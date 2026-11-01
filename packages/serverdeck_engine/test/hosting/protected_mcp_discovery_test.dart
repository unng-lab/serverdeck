import 'dart:async';
import 'dart:convert';

import 'package:serverdeck_engine/credentials/discovery_custody.dart';
import 'package:serverdeck_engine/hosting/protected_mcp_discovery.dart';
import 'package:serverdeck_protocol/discovery.dart';
import 'package:test/test.dart';

import '../support/memory_platform.dart' show Protection;
import '../credentials/discovery_custody_test.dart' as fixture;
import 'authority_test.dart' show settle;

final class File implements McpDiscoveryFile {
  List<int>? value;
  List<int>? lastWrite, lastRemoval;
  final readBuffers = <List<int>>[], events = <String>[];
  Completer<void>? writing;
  bool failWriteAfterCommit = false,
      corruptReadback = false,
      failClose = false,
      failRemove = false;
  int writes = 0;
  @override
  Future<List<int>?> read() async {
    events.add('read');
    if (value == null) return null;
    final result = List<int>.of(value!);
    if (corruptReadback && writes > 0) result[0] ^= 1;
    readBuffers.add(result);
    return result;
  }

  @override
  Future<void> replace(List<int> wrapped) async {
    events.add('write.begin');
    lastWrite = wrapped;
    await writing?.future;
    writes++;
    value = List.of(wrapped);
    events.add('write.commit');
    if (failWriteAfterCommit) throw StateError('private write diagnostic');
  }

  @override
  Future<void> removeExact(List<int> wrapped) async {
    events.add('remove');
    lastRemoval = wrapped;
    if (failRemove) throw StateError('private remove diagnostic');
    if (const ListEquality().equals(value, wrapped)) value = null;
  }

  @override
  Future<void> close() async {
    events.add('close');
    if (failClose) throw StateError('private unconfirmed handle');
  }
}

// Keep the unit port independent of real filesystem packages.
final class ListEquality {
  const ListEquality();
  bool equals(List<int>? a, List<int> b) =>
      a != null &&
      a.length == b.length &&
      List.generate(b.length, (i) => a[i] == b[i]).every((v) => v);
}

final class Setup {
  final protection = Protection(), file = File();
  late final custody = DiscoveryCustody(protection, fixture.sid);
  int checks = 0;
  bool live = true;
  void Function()? onCheck;
  late final publication = ProtectedMcpDiscovery(
    custody: custody,
    file: file,
    requireLive: () async {
      checks++;
      onCheck?.call();
      if (!live) throw StateError('NOT_READY');
    },
  );
  Future<void> close(DiscoveryDescriptor descriptor) async {
    await publication.removeOwned(descriptor);
    descriptor.close();
    protection.dispose();
  }
}

void main() {
  test('protected atomic write is read back before success; owned buffers are wiped', () async {
    final s = Setup(), descriptor = await fixture.create();
    await s.publication.publish(descriptor);
    expect(s.file.events, ['read', 'write.begin', 'write.commit', 'read']);
    final loaded = await s.custody.unprotect(s.file.value!, descriptor.buildId);
    expect(loaded.encode(), descriptor.encode());
    loaded.close();
    expect(s.file.lastWrite!.every((b) => b == 0), isTrue);
    expect(s.file.readBuffers.every((b) => b.every((v) => v == 0)), isTrue);
    await s.close(descriptor);
    expect(s.file.value, isNull);
    expect(s.file.events.sublist(4), ['remove', 'close']);
    expect(s.file.lastRemoval!.every((b) => b == 0), isTrue);
  });
  test(
    'valid stale descriptor of another build is inspected as data under lease',
    () async {
      final s = Setup(), descriptor = await fixture.create();
      final old = await DiscoveryDescriptor.create(
        ownerSid: fixture.sid,
        buildId: '${'c' * 40}+Release+${'d' * 64}',
        serverPid: 2,
        generation: fixture.generation,
        workspaceId: fixture.workspace,
      );
      s.file.value = await s.custody.protect(old);
      old.close();
      await s.publication.publish(descriptor);
      expect(s.file.writes, 1);
      await s.close(descriptor);
    },
  );
  test(
    'legacy or corrupt existing discovery is untouched and safely classified',
    () async {
      for (final legacy in [true, false]) {
        final s = Setup(), descriptor = await fixture.create();
        s.file.value = legacy
            ? await s.protection.protect(
                utf8.encode(
                  jsonEncode(
                    (jsonDecode(utf8.decode(descriptor.encode()))
                          as Map<String, dynamic>)
                      ..['format'] = 1
                      ..remove('hostKind'),
                  ),
                ),
                utf8.encode(
                  'ServerDeckNext\nv1\ndefault\n${fixture.sid}\nembedded-v1',
                ),
              )
            : [1, 2, 3];
        final before = List.of(s.file.value!);
        await expectLater(
          s.publication.publish(descriptor),
          fixture.failure(legacy ? 'INCOMPATIBLE' : 'STORAGE_BLOCKED'),
        );
        await s.close(descriptor);
        expect(s.file.value, before);
        expect(s.file.writes, 0);
        expect(s.file.events, ['read', 'close']);
      }
    },
  );
  test('not-ready guard rejects publication without touching a file', () async {
    final s = Setup()..live = false, descriptor = await fixture.create();
    await expectLater(
      s.publication.publish(descriptor),
      fixture.failure('NOT_READY'),
    );
    await s.close(descriptor);
    expect(s.file.events, ['close']);
  });
  test('readback corruption fails startup but exact committed descriptor is removed', () async {
    final s = Setup(), descriptor = await fixture.create();
    s.file.corruptReadback = true;
    await expectLater(s.publication.publish(descriptor), fixture.failure());
    await s.close(descriptor);
    expect(s.file.value, isNull);
  });
  test(
    'live proof loss after commit prevents ready but keeps cleanup ownership',
    () async {
      final s = Setup(), descriptor = await fixture.create();
      s.onCheck = () {
        if (s.checks == 4) s.live = false;
      };
      await expectLater(
        s.publication.publish(descriptor),
        fixture.failure('NOT_READY'),
      );
      expect(s.file.value, isNotNull);
      await s.close(descriptor);
      expect(s.file.value, isNull);
      expect(s.file.events, [
        'read',
        'write.begin',
        'write.commit',
        'remove',
        'close',
      ]);
    },
  );
  test('oversized existing protected bytes never reach replacement', () async {
    final s = Setup(), descriptor = await fixture.create();
    s.file.value = List.filled(16385, 1);
    await expectLater(s.publication.publish(descriptor), fixture.failure());
    await s.close(descriptor);
    expect(s.file.value, hasLength(16385));
    expect(s.file.writes, 0);
  });
  test(
    'write that commits then fails still owns exact descriptor removal',
    () async {
      final s = Setup(), descriptor = await fixture.create();
      s.file.failWriteAfterCommit = true;
      await expectLater(s.publication.publish(descriptor), fixture.failure());
      expect(s.file.value, isNotNull);
      await s.close(descriptor);
      expect(s.file.value, isNull);
    },
  );
  test(
    'remove waits real late write; stop prevents a readback and resurrection',
    () async {
      final s = Setup(), descriptor = await fixture.create();
      s.file.writing = Completer();
      final publish = s.publication.publish(descriptor);
      publish.ignore();
      await settle();
      final close = s.publication.removeOwned(descriptor);
      var closed = false;
      unawaited(close.then((_) => closed = true));
      await settle();
      expect(closed, isFalse);
      expect(s.file.events, ['read', 'write.begin']);
      s.file.writing!.complete();
      await expectLater(publish, fixture.failure('SERVICE_UNAVAILABLE'));
      await close;
      expect(s.file.value, isNull);
      expect(s.file.events, [
        'read',
        'write.begin',
        'write.commit',
        'remove',
        'close',
      ]);
      await s.close(descriptor);
    },
  );
  test('different file content is not removed as though owned', () async {
    final s = Setup(), descriptor = await fixture.create();
    await s.publication.publish(descriptor);
    s.file.value = [9, 8, 7];
    await s.close(descriptor);
    expect(s.file.value, [9, 8, 7]);
  });
  test(
    'unconfirmed file close remains sticky even without a published descriptor',
    () async {
      final s = Setup(), descriptor = await fixture.create();
      s.file.failClose = true;
      final first = s.publication.removeOwned(descriptor);
      await expectLater(first, fixture.failure());
      s.file.failClose = false;
      expect(identical(first, s.publication.removeOwned(descriptor)), isTrue);
      await expectLater(
        s.publication.removeOwned(descriptor),
        fixture.failure(),
      );
      descriptor.close();
      s.protection.dispose();
    },
  );
  test(
    'failed removal still drains file adapter; cannot be retried as success',
    () async {
      final s = Setup(), descriptor = await fixture.create();
      await s.publication.publish(descriptor);
      s.file.failRemove = true;
      await expectLater(
        s.publication.removeOwned(descriptor),
        fixture.failure(),
      );
      expect(s.file.events.last, 'close');
      expect(s.file.lastRemoval!.every((b) => b == 0), isTrue);
      s.file.failRemove = false;
      await expectLater(
        s.publication.removeOwned(descriptor),
        fixture.failure(),
      );
      expect(s.file.value, isNotNull);
      descriptor.close();
      s.protection.dispose();
    },
  );
  test(
    'one attempt cannot publish or remove another descriptor object',
    () async {
      final s = Setup(),
          descriptor = await fixture.create(),
          other = await fixture.create();
      final first = s.publication.publish(descriptor);
      expect(identical(first, s.publication.publish(descriptor)), isTrue);
      await first;
      await expectLater(
        s.publication.publish(other),
        fixture.failure('SERVICE_UNAVAILABLE'),
      );
      await expectLater(
        s.publication.removeOwned(other),
        fixture.failure('SERVICE_UNAVAILABLE'),
      );
      other.close();
      await s.close(descriptor);
      await expectLater(
        s.publication.publish(descriptor),
        fixture.failure('SERVICE_UNAVAILABLE'),
      );
    },
  );
}
