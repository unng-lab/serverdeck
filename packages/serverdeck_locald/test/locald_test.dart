import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:serverdeck_locald/local_api.dart';
import 'package:serverdeck_locald/locald.dart';
import 'package:serverdeck_locald/src/records.dart';
import 'package:test/test.dart';

final library = File(
  '../../windows/flutter/ephemeral/.plugin_symlinks/'
  'isar_community_flutter_libs/windows/libisar.dll',
).absolute.path;
JsonMap profile(String id) => {
  'id': id,
  'name': 'Disposable Lab',
  'endpoint': '$id.invalid',
  'port': 22,
  'user': 'observer',
  'tags': ['fixture'],
  'state': 'unknown',
  'observedAt': '2026-10-05T00:00:00.000Z',
};
JobPlan plan({
  String host = 'lab',
  String version = '18.6-3.pgdg24.04+1',
  String recipe = 'postgresql',
  String mode = 'fresh',
}) => JobPlan(
  hostId: host,
  hostFingerprint: 'SHA256:${'A' * 43}',
  recipe: recipe,
  version: version,
  recipeDigest: 'sha256:${'a' * 64}',
  deviceId: 'test',
  mode: mode,
);
ProbeEvidence evidence({
  bool healthy = true,
  bool stopped = true,
  bool lockClear = true,
  String version = '18.6-3.pgdg24.04+1',
}) => ProbeEvidence(
  version: version,
  unitActive: true,
  applicationHealthy: healthy,
  executionStopped: stopped,
  remoteLockClear: lockClear,
);
Matcher code(String expected) =>
    isA<LocalApiException>().having((e) => e.code, 'code', expected);

void main() {
  test(
    'atomic preferences survive reopen and authenticated stop closes storage',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'serverdeck-update-settings-',
      );
      var server = await LocaldServer.start(
        directory: root.path,
        nativeLibraryPath: library,
      );
      var client = LocalApiClient(port: server.port, proof: server.proof);
      try {
        await Future.wait([
          client.call('settings/set', {'theme': 'light'}),
          client.call('settings/set', {'updateAutoCheck': false}),
        ]);
        expect(await client.call('settings/get'), {
          'theme': 'light',
          'updateAutoCheck': false,
        });
        await expectLater(
          client.call('settings/set', {'updateAutoCheck': 'false'}),
          throwsA(isA<LocalApiException>()),
        );
        await client.call('service/stop');
        await server.done.timeout(const Duration(seconds: 10));
        expect(await File('${root.path}/endpoint.json').exists(), false);
        client.close();
        server = await LocaldServer.start(
          directory: root.path,
          nativeLibraryPath: library,
        );
        client = LocalApiClient(port: server.port, proof: server.proof);
        expect(await client.call('settings/get'), {
          'theme': 'light',
          'updateAutoCheck': false,
        });
      } finally {
        client.close();
        await server.close();
        await root.delete(recursive: true);
      }
    },
  );

  group('Durable Isar application store', () {
    late Directory root;
    late LocalStore store;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('serverdeck-store-test-');
      store = await LocalStore.open(
        directory: root.path,
        nativeLibraryPath: library,
      );
    });
    tearDown(() async {
      await store.close();
      await root.delete(recursive: true);
    });
    Future<void> reopen() async {
      await store.close();
      store = await LocalStore.open(
        directory: root.path,
        nativeLibraryPath: library,
      );
    }

    Future<String> runningFixture() async {
      final id = await store.submit(plan(), 'historical');
      await store.preflight(id);
      await store.reviewed(id);
      // Historical state only. No production launch path is enabled by this fixture.
      final isar = Isar.getInstance('serverdeck')!;
      await isar.writeTxn(() async {
        final record = (await isar.jobRecords.getByJobId(id))!;
        record.phase = 'running';
        record.containerId = 'fixture-container';
        await isar.jobRecords.put(record);
      });
      return id;
    }

    test(
      'profile edit/delete survives reopen and seed cannot resurrect deletion',
      () async {
        await store.initializeProfiles([profile('a'), profile('b')]);
        await store.saveProfile({...profile('a'), 'name': 'Renamed'});
        await store.removeProfile('b');
        await reopen();
        await store.initializeProfiles([profile('a'), profile('b')]);
        expect((await store.profiles()).single['name'], 'Renamed');
        await expectLater(
          store.removeProfile('a'),
          throwsA(code('LastProfile')),
        );
      },
    );
    test(
      'profile contract rejects credential fields and non-demo endpoints',
      () async {
        await expectLater(
          store.saveProfile({...profile('a'), 'password': 'synthetic'}),
          throwsA(code('InvalidProfile')),
        );
        await expectLater(
          store.saveProfile({...profile('a'), 'endpoint': '127.0.0.1'}),
          throwsA(code('InvalidProfile')),
        );
        expect(await store.profiles(), isEmpty);
      },
    );
    test('duplicate input is idempotent, changed input conflicts', () async {
      final id = await store.submit(plan(), 'duplicate');
      expect(await store.submit(plan(), 'duplicate'), id);
      expect(await store.events(id), hasLength(1));
      await expectLater(
        store.submit(plan(host: 'alias'), 'duplicate'),
        throwsA(code('IdempotencyConflict')),
      );
    });
    test('fingerprint lock survives reopen, aliases cannot bypass, terminal releases', () async {
      final id = await store.submit(plan(), 'one');
      await reopen();
      await expectLater(
        store.submit(plan(host: 'alias'), 'two'),
        throwsA(code('HostLocked')),
      );
      await store.requestCancel(id);
      expect(await store.submit(plan(host: 'alias'), 'two'), isNot(id));
    });
    test('concurrent transactions claim exactly one host writer', () async {
      final outcomes = await Future.wait(
        ['one', 'two'].map((key) async {
          try {
            await store.submit(plan(), key);
            return 'claimed';
          } on LocalApiException catch (e) {
            return e.code;
          }
        }),
      );
      expect(outcomes, unorderedEquals(['claimed', 'HostLocked']));
    });
    test('running identity survives restart, uncertainty retains lock until verified', () async {
      final id = await runningFixture();
      await reopen();
      expect((await store.getJob(id))['containerId'], 'fixture-container');
      await store.lostExecution(id);
      await store.beginReconcile(id);
      await store.finish(id, evidence(stopped: false));
      expect((await store.getJob(id))['phase'], 'unknown');
      await expectLater(
        store.submit(plan(), 'retry'),
        throwsA(code('HostLocked')),
      );
      await store.beginReconcile(id);
      await store.finish(id, evidence());
      expect((await store.getJob(id))['phase'], 'succeeded');
    });
    test(
      'wrong version or failed application probe cannot report success',
      () async {
        final id = await runningFixture();
        await store.finish(id, evidence(healthy: false));
        expect((await store.getJob(id))['phase'], 'failed');
      },
    );
    test(
      'cancel records request, uncertain remote lock prevents terminal result',
      () async {
        final id = await runningFixture();
        await store.requestCancel(id);
        await store.requestCancel(id);
        expect((await store.getJob(id))['phase'], 'cancel-requested');
        await store.lostExecution(id);
        await store.beginReconcile(id);
        await store.confirmCancelled(id, evidence(lockClear: false));
        expect((await store.getJob(id))['phase'], 'unknown');
        await store.beginReconcile(id);
        await store.confirmCancelled(id, evidence());
        expect((await store.getJob(id))['phase'], 'cancelled');
        expect(
          (await store.events(id)).last['code'],
          contains('not-rolled-back'),
        );
      },
    );
    test(
      'launch always denied and event pages are bounded and resumable',
      () async {
        final id = await store.submit(plan(), 'gate');
        await store.preflight(id);
        await store.reviewed(id);
        await expectLater(
          store.approveAndLaunch(id),
          throwsA(code('ExecutionDisabled')),
        );
        expect((await store.getJob(id))['phase'], 'awaiting-approval');
        expect(
          (await store.events(id, after: 1, limit: 1)).single['sequence'],
          2,
        );
        await expectLater(
          store.events(id, limit: 1001),
          throwsA(code('InvalidPage')),
        );
      },
    );
    test(
      'invalid version, recipe, shell parameters and adoption fail closed',
      () async {
        for (final p in [
          plan(version: 'latest'),
          plan(recipe: 'netbird'),
          plan(host: 'host; whoami'),
          plan(mode: 'adopt'),
        ]) {
          await expectLater(
            store.submit(p, 'bad'),
            throwsA(code('InvalidPlan')),
          );
        }
        expect(await store.jobs(), isEmpty);
      },
    );
    test(
      'event uniqueness failure rolls back phase and lock changes together',
      () async {
        final id = await store.submit(plan(), 'atomic');
        final isar = Isar.getInstance('serverdeck')!;
        await isar.writeTxn(() async {
          await isar.eventRecords.put(
            EventRecord()
              ..jobId = id
              ..sequence = 2
              ..phase = 'fixture'
              ..code = 'collision'
              ..at = DateTime.now(),
          );
        });
        await expectLater(store.requestCancel(id), throwsA(isA<IsarError>()));
        expect((await store.getJob(id))['phase'], 'queued');
        await expectLater(
          store.submit(plan(), 'other'),
          throwsA(code('HostLocked')),
        );
      },
    );
    test('unsupported schema fails without deleting existing data', () async {
      final isar = Isar.getInstance('serverdeck')!;
      await isar.writeTxn(() async {
        final meta = (await isar.metadataRecords.get(1))!;
        meta.schemaVersion = 99;
        await isar.metadataRecords.put(meta);
      });
      await store.close();
      await expectLater(
        LocalStore.open(directory: root.path, nativeLibraryPath: library),
        throwsA(code('UnsupportedSchema')),
      );
      // Restore only the fixture's version so tearDown can close a real store.
      final original = await Isar.open(
        [
          ProfileRecordSchema,
          JobRecordSchema,
          HostLockRecordSchema,
          EventRecordSchema,
          MetadataRecordSchema,
        ],
        directory: root.path,
        name: 'serverdeck',
        inspector: false,
      );
      await original.writeTxn(() async {
        final meta = (await original.metadataRecords.get(1))!;
        expect(meta.schemaVersion, 99);
        meta.schemaVersion = 1;
        await original.metadataRecords.put(meta);
      });
      await original.close();
      store = await LocalStore.open(
        directory: root.path,
        nativeLibraryPath: library,
      );
    });
  });

  group('Authenticated loopback API', () {
    late Directory root;
    late LocaldServer server;
    late LocalApiClient client;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('serverdeck-api-test-');
      server = await LocaldServer.start(
        directory: root.path,
        nativeLibraryPath: library,
      );
      client = LocalApiClient(port: server.port, proof: server.proof);
    });
    tearDown(() async {
      client.close();
      await server.close();
      await root.delete(recursive: true);
    });
    test(
      'profile writes survive service reopen and client disconnect',
      () async {
        await client.initializeProfiles([profile('a'), profile('b')]);
        await client.saveProfile({...profile('a'), 'name': 'Persisted'});
        await client.removeProfile('b');
        client.close();
        await server.close();
        server = await LocaldServer.start(
          directory: root.path,
          nativeLibraryPath: library,
        );
        client = LocalApiClient(port: server.port, proof: server.proof);
        expect((await client.profiles()).single['name'], 'Persisted');
        final discovered = await discoverLocald(root.path);
        expect(discovered, isNotNull);
        discovered!.close();
      },
    );
    test(
      'wrong proof, browser Origin, malformed and oversized requests rejected',
      () async {
        final wrong = LocalApiClient(port: server.port, proof: 'wrong');
        await expectLater(wrong.health(), throwsA(code('Unauthenticated')));
        wrong.close();
        final http = HttpClient();
        addTearDown(() => http.close(force: true));
        Future<int> post(String body, {String? origin}) async {
          final request = await http.postUrl(
            Uri.parse('http://127.0.0.1:${server.port}/v1/health'),
          );
          request.headers.set('authorization', 'Bearer ${server.proof}');
          if (origin != null) {
            request.headers.set('origin', origin);
          }
          request.write(body);
          final response = await request.close();
          await response.drain<void>();
          return response.statusCode;
        }

        expect(await post('{}', origin: 'https://example.invalid'), 401);
        expect(await post('['), 400);
        // An oversized unread body can also be rejected by disconnecting it.
        try {
          expect(await post('x' * (1024 * 1024 + 1)), 400);
        } on HttpException {
          // Dart HttpServer closes the incomplete request stream.
        }
        await client.health();
      },
    );
    test('caller cannot supply probe outcome or enable execution', () async {
      final id = await client.call('jobs/submit', {
        'plan': plan().toJson(),
        'idempotencyKey': 'api-job',
      }) as String;
      await expectLater(
        client.call('jobs/launch', {'id': id}),
        throwsA(code('ExecutionDisabled')),
      );
      await expectLater(
        client.call('jobs/finish', {'id': id, 'evidence': evidence().toJson()}),
        throwsA(code('UnknownOperation')),
      );
      expect((await client.call('jobs/get', {'id': id}))['phase'], 'queued');
    });
    test(
      'private Windows process lock prevents a second service owner',
      () async {
        await expectLater(
          LocaldServer.start(directory: root.path, nativeLibraryPath: library),
          throwsA(code('ServiceAlreadyRunning')),
        );
        await client.health();
      },
    );
  });
}
