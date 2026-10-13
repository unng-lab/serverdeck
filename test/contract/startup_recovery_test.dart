import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/startup_recovery.dart';
import 'package:serverdeck_protocol/models.dart';

import 'profile_controller_test.dart' as fixture;

class RecentClient extends fixture.ModelClient {
  int reads = 0;
  final replies = <Completer<ApiReply>>[];
  @override
  Future<ApiReply> read(
    ApiMethod method, [
    Map<String, Object?> params = const {},
  ]) {
    expect(method, ApiMethod.mutationsRecent);
    expect(params, {'limit': 20});
    reads++;
    final reply = Completer<ApiReply>();
    replies.add(reply);
    return reply.future;
  }
}

Map<String, Object?> recent({String revision = '1'}) => {
  'receipts': [
    {
      'requestId': '33333333-3333-4333-8333-333333333333',
      'operation': 'settings.update',
      'profileId': null,
      'result': {
        'entityId': null,
        'entityRevision': revision,
        'storeRevision': revision,
        'deleted': false,
      },
      'committedAt': '2026-10-11T00:00:00.000Z',
    },
  ],
  'truncated': false,
};

void main() {
  late RecentClient client;
  late fixture.ModelBootstrap bootstrap;
  late ProfileController model;
  late StartupRecovery recovery;
  setUp(() {
    client = RecentClient();
    bootstrap = fixture.ModelBootstrap(client)..show(ReadinessState.ready);
    model = ProfileController(bootstrap: bootstrap);
    recovery = StartupRecovery(model: model);
  });
  tearDown(() async {
    recovery.dispose();
    model.dispose();
    await bootstrap.close();
    await client.events.close();
    await client.readErrors.close();
  });
  test(
    'snapshot floor wait times out safely without a mutation or auto retry',
    () async {
      recovery.dispose();
      void Function()? timeout;
      recovery = StartupRecovery(
        model: model,
        schedule: (delay, action) {
          expect(delay, const Duration(seconds: 5));
          timeout = action;
          return () {};
        },
      );
      client.events.add(fixture.snapshot());
      client.replies.single.complete(
        ApiReply(fixture.fixtureGeneration, recent(revision: '2')),
      );
      await Future<void>.delayed(Duration.zero);
      timeout!();
      expect(recovery.error, ErrorCode.timeout);
      expect(recovery.receipts, isEmpty);
      expect(client.reads, 1);
    },
  );
  test(
    'malformed history is incompatible and late dispose cannot publish',
    () async {
      client.events.add(fixture.snapshot());
      client.replies.single.complete(
        ApiReply(fixture.fixtureGeneration, {
          'receipts': [
            {'private': 'must not display'},
          ],
          'truncated': false,
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(recovery.error, ErrorCode.incompatible);
      final retry = recovery.reload();
      recovery.dispose();
      client.replies.last.complete(
        ApiReply(fixture.fixtureGeneration, recent()),
      );
      await retry;
      expect(recovery.receipts, isEmpty);
      expect(recovery.loaded, false);
    },
  );
  test(
    'first coherent snapshot starts one bounded read and never a mutation',
    () async {
      expect(client.reads, 0);
      client.events.add(fixture.snapshot());
      expect(client.reads, 1);
      client.events.add(fixture.snapshot());
      expect(client.reads, 1);
      client.replies.single.complete(
        ApiReply(fixture.fixtureGeneration, recent()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(recovery.loaded, true);
      expect(recovery.receipts.single.operation, 'settings.update');
      expect(model.settings!.theme, ThemePreference.dark);
    },
  );
  test(
    'newer receipt requires current readback; receipt never replaces model',
    () async {
      client.events.add(fixture.snapshot());
      final before = client.refreshes;
      client.replies.single.complete(
        ApiReply(fixture.fixtureGeneration, recent(revision: '2')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(recovery.loaded, false);
      expect(client.refreshes, greaterThan(before));
      expect(model.storeRevision, '1');
      client.events.add(fixture.snapshot(revision: '2'));
      expect(recovery.loaded, true);
    },
  );
  test(
    'retired generation/epoch result cannot publish private history',
    () async {
      client.events.add(fixture.snapshot());
      bootstrap.show(ReadinessState.unavailable);
      bootstrap.show(ReadinessState.ready);
      client.events.add(fixture.snapshot());
      expect(client.reads, 2);
      client.replies.first.complete(
        ApiReply(fixture.fixtureGeneration, recent()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(recovery.loaded, false);
      expect(recovery.receipts, isEmpty);
      client.replies.last.complete(
        ApiReply(fixture.fixtureGeneration, {
          'receipts': <Object?>[],
          'truncated': false,
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(recovery.loaded, true);
    },
  );
  test(
    'safe failure does not auto-retry on snapshots; explicit retry reads only',
    () async {
      client.events.add(fixture.snapshot());
      client.replies.single.completeError(
        const LocalApiException(ErrorCode.timeout),
      );
      await Future<void>.delayed(Duration.zero);
      expect(recovery.error, ErrorCode.timeout);
      client.events.add(fixture.snapshot());
      expect(client.reads, 1);
      final retry = recovery.reload();
      expect(client.reads, 2);
      client.replies.last.complete(
        ApiReply(fixture.fixtureGeneration, {
          'receipts': <Object?>[],
          'truncated': false,
        }),
      );
      await retry;
      expect(recovery.loaded, true);
    },
  );
}
