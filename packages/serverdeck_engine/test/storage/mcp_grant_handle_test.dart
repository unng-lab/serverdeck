import 'package:serverdeck_engine/credentials/mcp_credentials.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_engine/storage/workspace_snapshot.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

import '../support/schema3_fixture.dart' as fixture;
import 'workspace_snapshot_test.dart' as snapshotFixture;

// RAM repository boundary only. The graph, credential-file checks, custody and
// HMAC key are real; no native store/proof/session or write API is simulated.
final class Handle implements McpGrantKey {
  Handle(this.grant, this.key);
  @override
  final ClientGrantRecord grant;
  @override
  final McpClientKey key;
  int closes = 0;
  @override
  void close() {
    closes++;
    key.close();
  }
}

final class Store implements StateStore {
  Store(this.data, this.value)
    : current = value.automation.grants[fixture.grant]!;
  final snapshotFixture.Setup data;
  final WorkspaceSnapshot value;
  ClientGrantRecord current;
  final opened = <Handle>[];
  @override
  bool get isReady => true;
  @override
  WorkspaceSnapshot get snapshot => value;
  @override
  ClientGrantRecord currentMcpGrant(String id, {required DateTime at}) {
    if (id != current.id || !current.isCurrentAt(at))
      throw StateError('UNAUTHORIZED');
    return current;
  }

  @override
  Future<McpGrantKey> openMcpGrantKey(
    String id, {
    required DateTime Function() clock,
    Duration? publicationDeadline,
  }) async {
    final grant = currentMcpGrant(id, at: clock());
    final key = await data.artifacts.openReferenced(data.binding);
    final handle = Handle(grant, key);
    opened.add(handle);
    return handle;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('NO_UNDECLARED_REPOSITORY_EFFECT_IN_UNIT');
}

void main() {
  test(
    'repository interface transfers a real custody key and close destroys it',
    () async {
      final data = await snapshotFixture.Setup.create(populated: true);
      final StateStore store = Store(data, await data.load());
      final McpGrantKey handle = await store.openMcpGrantKey(
        fixture.grant,
        clock: () => DateTime.parse(fixture.second),
      );
      final peer = await data.artifacts.openReferenced(data.binding);
      try {
        expect(handle.grant.id, fixture.grant);
        final proof = await handle.key.mac([1, 3, 5]);
        expect(await peer.verify([1, 3, 5], proof), isTrue);
        expect(await peer.verify([1, 3, 6], proof), isFalse);
        handle.close();
        await expectLater(
          handle.key.mac([1]),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'code',
              'STORAGE_BLOCKED',
            ),
          ),
        );
        handle.close();
        expect((handle as Handle).closes, 2);
      } finally {
        handle.close();
        peer.close();
      }
    },
  );

  test('an owned key is independent of current grant authority', () async {
    final data = await snapshotFixture.Setup.create(populated: true);
    final store = Store(data, await data.load());
    final at = DateTime.parse(fixture.second);
    final handle = await store.openMcpGrantKey(fixture.grant, clock: () => at);
    try {
      store.current = ClientGrantRecord.fromJson({
        ...fixture.grantDocument(),
        'revision': 2,
        'revokedAt': fixture.second,
      });
      expect(
        () => store.currentMcpGrant(fixture.grant, at: at),
        throwsA(
          isA<StateError>().having((e) => e.message, 'code', 'UNAUTHORIZED'),
        ),
      );
      await expectLater(
        store.openMcpGrantKey(fixture.grant, clock: () => at),
        throwsA(isA<StateError>()),
      );
      expect(store.opened, hasLength(1));
      // Revocation is policy, not premature destruction of an in-flight key.
      expect(await handle.key.mac([1]), hasLength(32));
    } finally {
      handle.close();
    }
  });
}
