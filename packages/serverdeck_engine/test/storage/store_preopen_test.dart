import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_engine/storage/key_custody.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_engine/storage/workspace.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:test/test.dart';

import '../support/memory_platform.dart' show Files, Protection;
import '../support/schema3_fixture.dart' as fixture;

Matcher failure(String code) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', code));

final class Lease implements WorkspaceLease {
  @override
  String ownerIdentity = fixture.owner;
  @override
  String workspaceSlot = 'default';
  @override
  String get name => 'unit-memory-lease';
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

/// No native library is loaded: these cases terminate before Isar.open. The
/// only Isar API reached is its in-memory getInstance map, inspected in source.
final class Runtime implements NativeStoreRuntime {
  int initializes = 0, validations = 0;
  bool failInitialize = false;
  int? failValidation;
  Completer<void>? initializeGate;
  void Function()? afterInitialize;
  @override
  Future<void> initialize() async {
    initializes++;
    if (initializeGate != null) await initializeGate!.future;
    afterInitialize?.call();
    if (failInitialize) throw StateError('PREREQUISITE_UNAVAILABLE');
  }

  @override
  Future<void> revalidate() async {
    validations++;
    if (validations == failValidation)
      throw StateError('PREREQUISITE_UNAVAILABLE');
  }
}

final class Setup {
  Setup._(this.files, this.protection, this.custody, this.key);
  final Files files;
  final Protection protection;
  final KeyCustody custody;
  final ReceiptKeyMaterial key;
  final lease = Lease(), runtime = Runtime();
  String get active =>
      p.join(files.root, 'ServerDeckNext', 'v1', 'workspaces', 'default');
  static Future<Setup> create() async {
    final files = Files(), protection = Protection();
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

  Future<StateStore> store() => StateStore.open(
    files: files,
    runtime: runtime,
    lease: lease,
    custody: custody,
    receiptKey: key,
  );
  Future<Workspace> workspace() => Workspace.open(
    files: files,
    runtime: runtime,
    lease: lease,
    custody: custody,
  );
  Future<void> manifest({int schema = 3}) async {
    final doc = await custody.createWorkspaceManifest(key);
    doc['schema'] = schema;
    files.data[p.join(active, 'workspace.manifest.json')] = StrictCodec()
        .encode(doc, maxBytes: 4096);
    files.data[p.join(active, 'receipt-key.dpapi')] = List.of(key.wrapper);
    files.data[p.join(active, 'workspace.isar')] = [
      0,
    ]; // Invalid geometry: never native-open.
    files.data[p.join(active, 'workspace.isar-lck')] = [];
  }
}

void main() {
  tearDown(() {
    expect(StateStore.hasOpenReservation, isFalse);
    expect(Workspace.hasOpenReservation, isFalse);
  });

  test('runtime failure releases only preopen reservation and never closes caller lease', () async {
    final setup = await Setup.create();
    setup.runtime.failInitialize = true;
    await expectLater(setup.store(), failure('PREREQUISITE_UNAVAILABLE'));
    expect(setup.files.writes, 0);
    expect(setup.lease.closes, 0);
    expect(StateStore.hasOpenReservation, isFalse);
    await expectLater(setup.workspace(), failure('PREREQUISITE_UNAVAILABLE'));
    expect(setup.lease.closes, 0);
  });

  test('pending initialization excludes a second writer after logical timeout until physical completion', () async {
    final setup = await Setup.create();
    setup.runtime.initializeGate = Completer<void>();
    setup.runtime.failInitialize = true;
    final physical = setup.store();
    await expectLater(
      physical.timeout(Duration.zero),
      throwsA(isA<TimeoutException>()),
    );
    expect(StateStore.hasOpenReservation, isTrue);
    await expectLater(setup.store(), failure('STORAGE_BLOCKED'));
    await expectLater(setup.workspace(), failure('STORAGE_BLOCKED'));
    expect(setup.runtime.initializes, 1);
    setup.runtime.initializeGate!.complete();
    await expectLater(physical, failure('PREREQUISITE_UNAVAILABLE'));
    expect(setup.files.writes, 0);
    expect(setup.lease.closes, 0);
  });

  test(
    'unknown schema and malformed native bytes refuse before any writable open',
    () async {
      for (final schema in [1, 2, 4, 3]) {
        final setup = await Setup.create();
        await setup.manifest(schema: schema);
        final before = {
          for (final e in setup.files.data.entries) e.key: List.of(e.value),
        };
        await expectLater(
          setup.store(),
          failure(schema == 3 ? 'STORAGE_BLOCKED' : 'INCOMPATIBLE'),
        );
        expect(setup.files.data, before);
        expect(setup.files.writes, 0);
        expect(setup.lease.closes, 0);
      }
    },
  );

  test('wrong owner/slot, lost lease and unsafe path never reach native open or create keys', () async {
    for (final mode in ['owner', 'slot', 'loss', 'path']) {
      final setup = await Setup.create();
      await setup.manifest();
      if (mode == 'owner') setup.lease.ownerIdentity = 'another-owner';
      if (mode == 'slot') setup.lease.workspaceSlot = 'another-slot';
      if (mode == 'loss')
        setup.runtime.afterInitialize = () => setup.lease.isHeld = false;
      if (mode == 'path') setup.files.denied.add(setup.files.root);
      final keyCount = setup.protection.records.length;
      await expectLater(setup.store(), failure('STORAGE_BLOCKED'));
      expect(setup.files.writes, 0);
      expect(setup.protection.records.length, keyCount);
      expect(setup.lease.closes, 0);
    }
  });

  test(
    'legacy residue and unsupported active workspace remain inert',
    () async {
      final unsupported = await Setup.create();
      await unsupported.manifest(schema: 1);
      final before = List.of(
        unsupported.files.data[p.join(
          unsupported.active,
          'workspace.manifest.json',
        )]!,
      );
      await expectLater(unsupported.workspace(), failure('INCOMPATIBLE'));
      expect(
        unsupported.files.data[p.join(
          unsupported.active,
          'workspace.manifest.json',
        )],
        before,
      );
      expect(unsupported.files.writes, 0);
      final residue = await Setup.create();
      await residue.manifest();
      residue.files.dirs.add('${residue.active}.upgrading-2-3');
      await expectLater(residue.store(), failure('STORAGE_BLOCKED'));
      expect(residue.files.writes, 0);
    },
  );

  test('creation failure before native attempt retains inert stage but no false native reservation', () async {
    final setup = await Setup.create();
    setup.files.dirs.remove(setup.active);
    setup.runtime.failValidation = 2;
    await expectLater(setup.workspace(), failure('PREREQUISITE_UNAVAILABLE'));
    expect(setup.files.data.keys, hasLength(4));
    expect(
      setup.files.data.keys.every(
        (path) => p.isWithin('${setup.active}.creating', path),
      ),
      isTrue,
    );
    expect(setup.files.dirs.contains(setup.active), isFalse);
    expect(Workspace.hasOpenReservation, isFalse);
    expect(setup.lease.closes, 0);
  });
}
