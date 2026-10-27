import 'package:serverdeck_protocol/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

const id = '12345678-1234-4234-9234-123456789abc';
const nonce = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
void main() {
  test(
    'handshake shapes, capabilities, integer versions and nonce encoding',
    () {
      final hello = ServerHello(generation: id, serverNonce: nonce).toJson();
      validateHello(hello);
      validateAuthenticate(
        const Authenticate(
          clientNonce: nonce,
          clientBuildId: 'build',
          requestedCapabilities: ['profiles.read', 'readiness.read'],
          proof: nonce,
        ).toJson(),
      );
      validateAuthenticated(
        const Authenticated(
          sessionId: nonce,
          capabilities: ['profiles.read'],
          proof: nonce,
        ).toJson(),
      );
      expect(
        () => validateHello({...hello, 'extra': true}),
        throwsFormatException,
      );
      final data = Map<String, Object?>.from(hello['hello'] as Map);
      for (final version in [1.0, '1', 2]) {
        expect(
          () => validateHello({
            'hello': {...data, 'apiMajor': version},
          }),
          throwsFormatException,
        );
      }
      expect(
        () => validateHello({
          'hello': {...data, 'serverNonce': 'a' * 43},
        }),
        throwsFormatException,
      );
      expect(
        () => validateAuthenticate(
          const Authenticate(
            clientNonce: nonce,
            clientBuildId: 'build',
            requestedCapabilities: ['ssh.execute'],
            proof: nonce,
          ).toJson(),
        ),
        throwsFormatException,
      );
    },
  );
  test('every method has a complete safe result schema', () {
    final mutation = const MutationResult(
      entityId: id,
      entityRevision: '1',
      storeRevision: '1',
      deleted: false,
    ).toJson();
    final profile = ProfileView(
      id: id,
      revision: '1',
      name: 'Host',
      address: 'example.test',
      port: 22,
      sshUser: 'user',
      tags: [],
      credentialRevision: '1',
      connectionRevision: '1',
      trustRevision: '1',
      createdAt: '2026-10-10T12:00:00.000Z',
      updatedAt: '2026-10-10T12:00:00.000Z',
      credentialKind: CredentialKind.none,
      credentialConfigured: false,
    ).toJson();
    final results = <String, Map<String, Object?>>{
      'readiness.get': const ReadinessView(
        state: ReadinessState.ready,
        reason: null,
        workspaceId: id,
        generation: id,
      ).toJson(),
      'session.ping': {'leaseSeconds': 60},
      'session.close': {'closed': true},
      'profiles.list': {
        'storeRevision': '0',
        'profiles': [profile],
      },
      'profiles.get': {'storeRevision': '0', 'profile': profile},
      'profiles.create': mutation,
      'profiles.update': mutation,
      'profiles.delete': {...mutation, 'deleted': true},
      'settings.get': {
        'storeRevision': '0',
        'settings': const SettingsView().toJson(),
      },
      'settings.update': {...mutation, 'entityId': null},
      'mutations.get': {'state': 'committed', 'result': mutation},
      'mutations.recent': {
        'receipts': [
          {
            'requestId': id,
            'operation': 'profiles.create',
            'profileId': id,
            'result': mutation,
            'committedAt': '2026-10-10T12:00:00.000Z',
          },
        ],
        'truncated': false,
      },
    };
    expect(
      results.keys.toSet(),
      ApiMethod.values.map((v) => v.wireName).toSet(),
    );
    for (final entry in results.entries) {
      validateMethodResult(entry.key, entry.value);
      expect(
        () => validateMethodResult(entry.key, {
          ...entry.value,
          'secret': 'marker',
        }),
        throwsFormatException,
      );
    }
    expect(
      () => validateMethodResult('profiles.get', {
        'storeRevision': '0',
        'profile': {...profile, 'credentialRef': id},
      }),
      throwsFormatException,
    );
    expect(
      () => validateMethodResult('mutations.get', {
        'state': 'running',
        'result': mutation,
      }),
      throwsFormatException,
    );
  });
  test('rejects malformed nested projections and result unions', () {
    final settings = const SettingsView().toJson();
    for (final change in <Map<String, Object?>>[
      {'revision': '0'},
      {'theme': 'sepia'},
      {'reduceMotion': 1},
      {'selectedProfileId': 'bad'},
      {'privateKey': 'marker'},
    ]) {
      expect(
        () => validateMethodResult('settings.get', {
          'storeRevision': '0',
          'settings': {...settings, ...change},
        }),
        throwsFormatException,
      );
    }
    for (final state in ['queued', 'running', 'not-found']) {
      validateMethodResult('mutations.get', {'state': state, 'result': null});
    }
    expect(
      () => validateMethodResult('mutations.get', {
        'state': 'committed',
        'result': null,
      }),
      throwsFormatException,
    );
    final ready = const ReadinessView(
      state: ReadinessState.ready,
      reason: null,
      workspaceId: id,
      generation: id,
    ).toJson();
    expect(
      () => validateMethodResult('readiness.get', {
        ...ready,
        'workspaceId': null,
      }),
      throwsFormatException,
    );
    expect(
      () => validateMethodResult('readiness.get', {
        ...ready,
        'features': {
          'profiles': true,
          'ssh': true,
          'jobs': false,
          'backend': false,
        },
      }),
      throwsFormatException,
    );
    expect(
      () => validateMethodResult('session.ping', {'leaseSeconds': 60.0}),
      throwsFormatException,
    );
    expect(
      () => validateMethodResult('profiles.list', {
        'storeRevision': '00',
        'profiles': [],
      }),
      throwsFormatException,
    );
    expect(
      () => validateMethodResult('mutations.recent', {
        'receipts': [],
        'truncated': null,
      }),
      throwsFormatException,
    );
    expect(() => validateMethodResult('unknown', {}), throwsFormatException);
  });
  test(
    'handshake capabilities must be sorted, unique and bounded by allowlist',
    () {
      for (final caps in [
        ['profiles.read', 'profiles.read'],
        ['settings.read', 'profiles.read'],
        [1],
      ]) {
        expect(
          () => validateAuthenticate({
            'authenticate': {
              'clientNonce': nonce,
              'clientBuildId': 'build',
              'requestedCapabilities': caps,
              'proof': nonce,
            },
          }),
          throwsFormatException,
        );
      }
      expect(
        () => validateAuthenticated({
          'authenticated': {
            'sessionId': nonce,
            'capabilities': [],
            'idleLeaseSeconds': 60.0,
            'proof': nonce,
          },
        }),
        throwsFormatException,
      );
    },
  );
}
