import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_engine/storage/executor_enrollments.dart';
import 'package:serverdeck_engine/storage/key_custody.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/executor_enrollment.dart';
import 'package:test/test.dart';

import '../support/memory_platform.dart' show Files, Protection;
import '../support/schema3_fixture.dart' as fixture;

const host = '12345678-1234-4234-9234-123456789a10';
const challenge = '12345678-1234-4234-9234-123456789a11';
String id(int value) =>
    '12345678-1234-4234-9234-${value.toRadixString(16).padLeft(12, '0')}';
Matcher failure(String code) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', code));

Map<String, Object?> enrollment({
  String server = fixture.profile,
  String createdAt = fixture.first,
}) => {
  'format': 1,
  'workspaceId': fixture.workspace,
  'serverId': server,
  'connection': {
    'profileId': server,
    'connectionRevision': '1',
    'credentialRevision': '1',
    'trustRevision': '2',
    'key': fixture.trustDocument()['key'],
  },
  'hostId': host,
  'runtimeVersion': '1.0.0+${'a' * 64}',
  'lockDigest': 'b' * 64,
  'registryDigest': 'c' * 64,
  'compilerDigest': 'd' * 64,
  'bridgeDigest': 'e' * 64,
  'createdAt': createdAt,
};

final class Lease implements WorkspaceLease {
  @override
  String ownerIdentity = fixture.owner;
  @override
  String workspaceSlot = 'default';
  @override
  String get name => 'unit-only-memory-lease';
  @override
  bool isHeld = true;
  @override
  bool acquired = true;
  int closes = 0;
  @override
  Future<void> close() async {
    closes++;
    isHeld = false;
  }
}

final class FaultFiles extends Files {
  bool failBeforeReplace = false,
      failAfterReplace = false,
      corruptReadback = false;
  int reads = 0;
  bool replaced = false;
  Completer<void>? readGate;
  void Function()? afterRead;
  @override
  Future<void> replaceFile(String path, List<int> bytes) async {
    if (failBeforeReplace) throw StateError('private-before-replace');
    await super.replaceFile(path, bytes);
    replaced = true;
    if (failAfterReplace) throw StateError('private-after-commit');
  }

  @override
  Future<List<int>> readFile(String path, {required int maxBytes}) async {
    reads++;
    final value = await super.readFile(path, maxBytes: maxBytes);
    if (readGate != null) await readGate!.future;
    afterRead?.call();
    return corruptReadback && replaced ? [0] : value;
  }
}

final class Setup {
  Setup._(this.files, this.protection, this.custody, this.key);
  final FaultFiles files;
  final Protection protection;
  final KeyCustody custody;
  final ReceiptKeyMaterial key;
  final lease = Lease();
  int poisoned = 0;
  late final store = newStore();
  ExecutorEnrollmentStore newStore() => ExecutorEnrollmentStore(
    files: files,
    lease: lease,
    custody: custody,
    key: key,
    requireReady: () {},
    onStorageBlocked: () => poisoned++,
  );
  String get path => p.join(
    files.root,
    'ServerDeckNext',
    'v1',
    'workspaces',
    'default',
    'executor-enrollments.json',
  );
  static Future<Setup> create() async {
    final files = FaultFiles(), protection = Protection();
    final custody = KeyCustody(protection, fixture.owner);
    final key = await custody.createReceiptKey(
      fixture.workspace,
      fixture.receiptKey,
    );
    addTearDown(() {
      key.close();
      protection.dispose();
    });
    return Setup._(files, protection, custody, key);
  }

  Map<String, Object?> input(
    String method, {
    String server = fixture.profile,
  }) => {
    'profileId': server,
    if (method == 'executor.confirm') ...{
      'challengeId': challenge,
      'hostId': host,
    },
  };
  ExecutorEnrollmentMutation command(
    int request,
    String method, {
    String server = fixture.profile,
  }) => store.prepare(
    requestId: id(request),
    method: method,
    input: input(method, server: server),
  );
  Map<String, Object?> document({
    List<Object?> records = const [],
    List<Object?> receipts = const [],
  }) => {
    'format': 2,
    'workspaceId': fixture.workspace,
    'receiptKeyId': fixture.receiptKey,
    'records': records,
    'receipts': receipts,
  };
  void seed(Map<String, Object?> document, {bool badMac = false}) {
    final mac = custody.receiptDigestSync(key, {
      'purpose': 'executor-enrollments-v1',
      'document': document,
    });
    files.data[path] = StrictCodec().encode({
      'document': document,
      'mac': badMac ? base64.encode(List.filled(32, 0)) : mac,
    }, maxBytes: 64 * 1024 * 1024);
  }

  Map<String, Object?> receipt(int request, {String server = fixture.profile}) {
    final input = this.input('executor.revoke', server: server);
    return {
      'requestId': id(request),
      'method': 'executor.revoke',
      'requestDigest': custody.receiptDigestSync(key, {
        'purpose': 'executor-enrollment-mutation-v1',
        'workspaceId': fixture.workspace,
        'method': 'executor.revoke',
        'input': input,
      }),
      'result': {'profileId': server, 'revoked': false},
    };
  }
}

void main() {
  test('confirm/revoke/restart retain binding and stable ACK without replaying an effect', () async {
    final setup = await Setup.create();
    expect(await setup.store.read(), isEmpty);
    expect(setup.files.writes, 0);
    var proofs = 0;
    Future<void> prove() async {
      proofs++;
    }

    final confirm = setup.command(101, 'executor.confirm');
    final first = await setup.store.mutate(
      confirm,
      enrollment: ExecutorEnrollment.fromJson(enrollment()),
      revalidate: prove,
    );
    expect(proofs, 2);
    expect((await setup.store.read())[fixture.profile]!.toJson(), enrollment());
    final second = await setup.store.mutate(
      setup.command(102, 'executor.confirm'),
      enrollment: ExecutorEnrollment.fromJson(
        enrollment(createdAt: fixture.second),
      ),
      revalidate: prove,
    );
    expect(second, first);
    await setup.store.mutate(
      setup.command(103, 'executor.revoke'),
      enrollment: null,
      revalidate: prove,
    );
    expect(await setup.store.read(), isEmpty);
    final writes = setup.files.writes;
    final replay = await setup.store.mutate(
      confirm,
      enrollment: ExecutorEnrollment.fromJson(enrollment()),
      revalidate: prove,
    );
    expect(replay, first);
    expect(await setup.store.read(), isEmpty);
    expect(setup.files.writes, writes);
    final restarted = setup.newStore();
    final captured = restarted.prepare(
      requestId: id(101),
      method: 'executor.confirm',
      input: setup.input('executor.confirm'),
    );
    expect(await restarted.receipt(captured), first);
    expect(await restarted.read(), isEmpty);
    expect(setup.lease.closes, 0);
    expect(setup.poisoned, 0);
    final raw = StrictCodec().decode(
      setup.files.data[setup.path]!,
      maxBytes: 64 * 1024 * 1024,
    );
    expect((raw['document'] as Map)['format'], 2);
    expect((raw['document'] as Map)['receipts'], hasLength(3));
  });

  test(
    'captured commands cannot be mutated or moved to another repository',
    () async {
      final setup = await Setup.create();
      final input = setup.input('executor.confirm');
      final command = setup.store.prepare(
        requestId: id(101),
        method: 'executor.confirm',
        input: input,
      );
      input['profileId'] = host;
      await setup.store.mutate(
        command,
        enrollment: ExecutorEnrollment.fromJson(enrollment()),
        revalidate: () async {},
      );
      final other = setup.newStore();
      expect(() => other.receipt(command), failure('FORBIDDEN'));
      await expectLater(
        setup.store.receipt(setup.command(101, 'executor.revoke')),
        failure('IDEMPOTENCY_CONFLICT'),
      );
      expect(setup.poisoned, 0);
      expect(
        () => setup.store.prepare(
          requestId: id(102),
          method: 'executor.revoke',
          input: {...setup.input('executor.revoke'), 'role': 'owner'},
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'old/unknown sidecars and closed fields fail without writing or resetting',
    () async {
      for (final value in [1, 3, '2', 2.0]) {
        final setup = await Setup.create();
        final doc = setup.document()..['format'] = value;
        if (value == 1) doc.remove('receipts');
        if (value is double) {
          // The strict signer rejects doubles too; exercise raw on-disk JSON.
          setup.files.data[setup.path] = utf8.encode(
            jsonEncode({
              'document': doc,
              'mac': base64.encode(List.filled(32, 0)),
            }),
          );
        } else {
          setup.seed(doc);
        }
        final before = List.of(setup.files.data[setup.path]!);
        await expectLater(setup.store.read(), failure('STORAGE_BLOCKED'));
        expect(setup.files.data[setup.path], before);
        expect(setup.files.writes, 0);
        expect(setup.poisoned, 1);
        final reads = setup.files.reads;
        expect(() => setup.store.read(), failure('STORAGE_BLOCKED'));
        expect(setup.files.reads, reads);
      }
      for (final extra in [true, false]) {
        final setup = await Setup.create();
        final doc = setup.document();
        if (extra) {
          doc['unexpected'] = true;
        } else {
          doc.remove('receipts');
        }
        setup.seed(doc);
        await expectLater(setup.store.read(), failure('STORAGE_BLOCKED'));
      }
    },
  );

  test(
    'HMAC, workspace and key mismatches never become an empty repository',
    () async {
      for (final mode in ['mac', 'workspace', 'key', 'duplicate']) {
        final setup = await Setup.create();
        final doc = setup.document(
          records: mode == 'duplicate' ? [enrollment(), enrollment()] : [],
        );
        if (mode == 'workspace') doc['workspaceId'] = host;
        if (mode == 'key') doc['receiptKeyId'] = host;
        setup.seed(doc, badMac: mode == 'mac');
        await expectLater(setup.store.read(), failure('STORAGE_BLOCKED'));
        expect(setup.files.writes, 0);
        expect(setup.poisoned, 1);
      }
    },
  );

  test('capacity refuses new mutation; a full receipt history still permits replay', () async {
    final setup = await Setup.create();
    setup.seed(
      setup.document(
        receipts: [for (var i = 1; i <= 10000; i++) setup.receipt(i)],
      ),
    );
    expect(await setup.store.receipt(setup.command(1, 'executor.revoke')), {
      'profileId': fixture.profile,
      'revoked': false,
    });
    await expectLater(
      setup.store.mutate(
        setup.command(10001, 'executor.revoke'),
        enrollment: null,
        revalidate: () async {},
      ),
      failure('RESOURCE_LIMIT'),
    );
    expect(setup.files.writes, 0);
    expect(setup.poisoned, 0);
    final records = await Setup.create();
    records.seed(
      records.document(
        records: [for (var i = 1; i <= 250; i++) enrollment(server: id(i))],
      ),
    );
    await expectLater(
      records.store.mutate(
        records.command(10001, 'executor.confirm', server: id(251)),
        enrollment: ExecutorEnrollment.fromJson(enrollment(server: id(251))),
        revalidate: () async {},
      ),
      failure('RESOURCE_LIMIT'),
    );
    expect(records.files.writes, 0);
    expect(records.poisoned, 0);
  });

  test('failed replace/readback poisons ownership; restart reads actual committed file', () async {
    for (final mode in ['before', 'after', 'readback']) {
      final setup = await Setup.create();
      setup.files.failBeforeReplace = mode == 'before';
      setup.files.failAfterReplace = mode == 'after';
      setup.files.corruptReadback = mode == 'readback';
      await expectLater(
        setup.store.mutate(
          setup.command(101, 'executor.confirm'),
          enrollment: ExecutorEnrollment.fromJson(enrollment()),
          revalidate: () async {},
        ),
        failure('STORAGE_BLOCKED'),
      );
      expect(setup.poisoned, 1);
      expect(setup.lease.closes, 0);
      setup.files.failBeforeReplace = setup.files.failAfterReplace =
          setup.files.corruptReadback = false;
      final actual = await setup.newStore().read();
      expect(actual.length, mode == 'before' ? 0 : 1);
    }
  });

  test('owner/lease/path loss and physical read overlap fail closed without repair', () async {
    final setup = await Setup.create();
    setup.seed(setup.document());
    setup.files.afterRead = () => setup.lease.isHeld = false;
    await expectLater(setup.store.read(), failure('STORAGE_BLOCKED'));
    expect(setup.files.writes, 0);
    expect(setup.lease.closes, 0);
    for (final mode in ['owner', 'closed-key']) {
      final invalid = await Setup.create();
      if (mode == 'owner') {
        invalid.lease.ownerIdentity = 'another-owner';
      } else {
        invalid.key.close();
      }
      expect(() => invalid.store.read(), failure('STORAGE_BLOCKED'));
      expect(invalid.files.reads, 0);
      expect(invalid.files.writes, 0);
      expect(invalid.poisoned, 1);
    }
    final denied = await Setup.create();
    denied.files.denied.add(p.dirname(denied.path));
    await expectLater(denied.store.read(), failure('STORAGE_BLOCKED'));
    final pending = await Setup.create();
    pending.seed(pending.document());
    pending.files.readGate = Completer<void>();
    final physical = pending.store.read();
    expect(() => pending.store.read(), failure('NOT_READY'));
    await expectLater(
      physical.timeout(Duration.zero),
      throwsA(isA<TimeoutException>()),
    );
    expect(() => pending.store.read(), failure('NOT_READY'));
    pending.files.readGate!.complete();
    expect(await physical, isEmpty);
    expect(pending.poisoned, 0);
  });
}
