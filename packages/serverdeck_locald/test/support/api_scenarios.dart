import 'dart:convert';
import 'dart:io';

import 'package:serverdeck_locald/api/server.dart';
import 'package:serverdeck_locald/api/sessions.dart';
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/wire.dart';

import '../models_test.dart' as fixture;
import 'state_store_child.dart' show check;

Future<void> verifyApi(
  StateStore store,
  KeyCustody custody,
  ReceiptKeyMaterial key,
) async {
  final backend = MutationCoordinator(store, custody, key);
  const generation = '82345678-1234-4234-8234-123456789abc';
  final session = base64Url.encode(List.filled(32, 42)).replaceAll('=', '');
  final sessions = SessionRegistry(
    generation: generation,
    onDetached: backend.detach,
  )..register('owned', session, Capability.values.toSet());
  final server = ApiServer(
    sessions: sessions,
    readiness: () => const ReadinessView(
      state: ReadinessState.ready,
      reason: null,
      workspaceId: fixture.workspace,
      generation: generation,
    ),
    coordinator: () => backend,
  );
  var number = 0;
  String id() =>
      '92345678-1234-4234-8234-${(++number).toRadixString(16).padLeft(12, '0')}';
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params, {
    String? requestId,
    String? error,
  }) async {
    final dispatch = await server.handle(
      'owned',
      StrictCodec().encode(
        ApiRequest(
          id: requestId ?? id(),
          sessionId: session,
          method: method,
          params: params,
        ).toJson(),
      ),
    );
    check(!utf8.decode(dispatch.bytes).contains('synthetic-router-secret'));
    final response = StrictCodec().decode(dispatch.bytes);
    check(response['generation'] == generation);
    if (error != null) {
      check((response['error'] as Map)['code'] == error);
      return response;
    }
    check(response['error'] == null);
    final result = response['result'] as Map<String, Object?>;
    validateMethodResult(method, result);
    return result;
  }

  try {
    await call('readiness.get', {});
    await call('session.ping', {});
    check((await call('profiles.list', {}))['profiles'] is List);
    final original = id();
    final create = <String, Object?>{
      'profileId': fixture.profileId,
      'name': 'Router',
      'address': 'example.invalid',
      'sshUser': 'synthetic',
      'credential': {
        'action': 'replace',
        'kind': 'password',
        'password': 'synthetic-router-secret',
      },
    };
    final created = await call('profiles.create', create, requestId: original);
    check(created['storeRevision'] == '1');
    check(
      (await call(
            'profiles.create',
            create,
            requestId: original,
          ))['storeRevision'] ==
          '1',
    );
    await call(
      'profiles.create',
      {...create, 'name': 'Different'},
      requestId: original,
      error: 'IDEMPOTENCY_CONFLICT',
    );
    final view =
        (await call('profiles.get', {
              'profileId': fixture.profileId,
            }))['profile']
            as Map;
    check(
      !view.containsKey('credentialRef') && !view.containsKey('protectedBlob'),
    );
    check((view['credential'] as Map)['kind'] == 'password');
    check(
      (await call('mutations.get', {'requestId': original}))['state'] ==
          'committed',
    );
    check(
      (await call('mutations.get', {'requestId': id()}))['state'] ==
          'not-found',
    );
    check(
      ((await call('mutations.recent', {}))['receipts'] as List).length == 1,
    );
    await call('mutations.recent', {'limit': 0}, error: 'VALIDATION');
    final updated = await call('profiles.update', {
      'profileId': fixture.profileId,
      'expectedRevision': '1',
      'name': 'Updated',
      'address': 'example.invalid',
      'port': 22,
      'sshUser': 'synthetic',
      'tags': <String>[],
      'credential': {'action': 'keep'},
    });
    check(updated['entityRevision'] == '2');
    await call('profiles.delete', {
      'profileId': fixture.profileId,
      'expectedRevision': '1',
    }, error: 'REVISION_CONFLICT');
    final settings = (await call('settings.get', {}))['settings'] as Map;
    await call('settings.update', {
      'expectedRevision': settings['revision'],
      'theme': 'dark',
      'reduceMotion': true,
      'selectedProfileId': fixture.profileId,
    });
    await call('profiles.delete', {
      'profileId': fixture.profileId,
      'expectedRevision': '2',
    });
    check(
      ((await call('settings.get', {}))['settings']
              as Map)['selectedProfileId'] ==
          null,
    );
    await call('profiles.get', {
      'profileId': fixture.profileId,
    }, error: 'NOT_FOUND');
    check(
      (await call(
            'profiles.create',
            create,
            requestId: original,
          ))['storeRevision'] ==
          '1',
    );
    check(((await call('profiles.list', {}))['profiles'] as List).isEmpty);
    check((await call('mutations.recent', {'limit': 1}))['truncated'] == true);
    await call('jobs.start', {
      'privateKey': 'synthetic-router-secret',
    }, error: 'UNSUPPORTED');
    await call('profiles.list', {'unknown': true}, error: 'VALIDATION');
    await store.close();
    final blocked = await call('readiness.get', {});
    check(
      blocked['state'] == 'storage-blocked' &&
          blocked['reason'] == 'STORAGE_BLOCKED',
    );
    await call('profiles.list', {}, error: 'STORAGE_BLOCKED');
    await call('mutations.get', {
      'requestId': original,
    }, error: 'STORAGE_BLOCKED');
    await call('session.close', {});
    check(sessions.count == 0);
    stdout.writeln('NATIVE_ROUTER_METHODS_PROVED');
  } finally {
    sessions.stop();
    await backend.close();
    await store.close();
  }
}
