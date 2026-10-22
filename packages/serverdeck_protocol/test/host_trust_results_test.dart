import 'package:serverdeck_protocol/host_trust.dart';
import 'package:test/test.dart';

import 'host_trust_test.dart' as fixture;

Map<String, Object?> challenge() => {
  'challengeId': fixture.request,
  'profileId': fixture.profile,
  'expectedRevision': '2',
  'connectionRevision': '1',
  'credentialRevision': '1',
  'trustRevision': '2',
  'key': fixture.key(),
  'expiresAt': '2026-10-22T00:05:00.000Z',
};

Map<String, Object?> snapshot() => {
  'profileId': fixture.profile,
  'profileRevision': '2',
  'connectionRevision': '1',
  'credentialRevision': '1',
  'trustRevision': '2',
  'trust': fixture.record()..remove('workspaceId'),
};

void main() {
  test('public trust snapshot is exact immutable and checks graph epochs', () {
    final input = snapshot();
    final parsed = HostTrustSnapshot.fromJson(input);
    expect(parsed.toJson(), input);
    expect(parsed.trust!.key, SshHostPin.fromJson(fixture.key()));
    (input['trust'] as Map)['key'] = fixture.key()..['format'] = 'ssh-rsa';
    expect(parsed.toJson(), snapshot());
    final exported = parsed.toJson();
    (exported['trust'] as Map).clear();
    expect(parsed.toJson(), snapshot());
    for (final change in <Map<String, Object?>>[
      {'credentialRevision': '3'},
      {'connectionRevision': '3'},
      {'trustRevision': '3'},
      {'trust': null},
      {'trust': fixture.record()},
      {
        'trust': {
          ...(snapshot()['trust'] as Map<String, Object?>),
          'profileId': fixture.request,
        },
      },
      {
        'trust': {
          ...(snapshot()['trust'] as Map<String, Object?>),
          'revision': '1',
        },
      },
      {
        'trust': {
          ...(snapshot()['trust'] as Map<String, Object?>),
          'connectionRevision': '2',
        },
      },
      {'workspaceId': fixture.workspace},
    ]) {
      expect(
        () => HostTrustSnapshot.fromJson({...snapshot(), ...change}),
        throwsFormatException,
      );
    }
    expect(
      HostTrustSnapshot.fromJson({
        ...snapshot(),
        'trustRevision': '1',
        'trust': null,
      }).trust,
      isNull,
    );
    expect(
      HostTrustSnapshot.fromJson({
        ...snapshot(),
        'connectionRevision': '2',
        'trust': {
          ...(snapshot()['trust'] as Map<String, Object?>),
          'status': 'revoked',
        },
      }).trust!.status,
      HostTrustStatus.revoked,
    );
  });

  test('challenge metadata preserves fields without claiming session or TTL authority', () {
    final input = challenge();
    final parsed = HostTrustChallenge.fromJson(input);
    expect(parsed.toJson(), input);
    (input['key'] as Map).clear();
    expect(parsed.toJson(), challenge());
    for (final change in <Map<String, Object?>>[
      {'expectedRevision': '0'},
      {'connectionRevision': '3'},
      {'credentialRevision': '3'},
      {'trustRevision': '0'},
      {'connectionRevision': '2', 'trustRevision': '1'},
      {'expiresAt': '2026-10-22T00:05:00Z'},
      {'challengeId': 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA'},
      {'owner': true},
    ]) {
      expect(
        () => HostTrustChallenge.fromJson({...challenge(), ...change}),
        throwsFormatException,
      );
    }
  });

  test('six owner results have closed unions and deeply immutable capture', () {
    final mutation = <String, Object?>{
      'entityId': fixture.profile,
      'entityRevision': '2',
      'storeRevision': '2',
      'deleted': false,
    };
    final successes = <String, Map<String, Object?>>{
      'servers.trust.get': snapshot(),
      'servers.trust.probe': {
        'operationId': fixture.request,
        'state': 'running',
      },
      'servers.trust.probeStatus': {
        'operationId': fixture.request,
        'state': 'succeeded',
        'challenge': challenge(),
      },
      'servers.trust.probeCancel': {
        'operationId': fixture.request,
        'cancelled': true,
      },
      'servers.trust.confirm': mutation,
      'servers.trust.revoke': mutation,
    };
    for (final entry in successes.entries) {
      final captured = captureHostTrustResult(entry.key, entry.value);
      expect(captured, entry.value);
      expect(() => captured.clear(), throwsUnsupportedError);
      expect(
        () =>
            captureHostTrustResult(entry.key, {...entry.value, 'extra': null}),
        throwsFormatException,
      );
    }
    final captured = captureHostTrustResult(
      'servers.trust.probeStatus',
      successes['servers.trust.probeStatus']!,
    );
    expect(
      () => (captured['challenge'] as Map).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => ((captured['challenge'] as Map)['key'] as Map).clear(),
      throwsUnsupportedError,
    );
    for (final code in TrustedLocalError.codes) {
      final failed = {
        'operationId': fixture.request,
        'state': 'failed',
        'code': code,
      };
      expect(
        captureHostTrustResult('servers.trust.probeStatus', failed),
        failed,
      );
    }
    for (final failed in <Map<String, Object?>>[
      {'operationId': fixture.request, 'state': 'unknown'},
      {'operationId': fixture.request, 'state': 'failed', 'code': 'RAW_ERROR'},
      {'operationId': fixture.request, 'state': 'succeeded'},
      {
        'operationId': fixture.request,
        'state': 'running',
        'challenge': challenge(),
      },
    ]) {
      expect(
        () => captureHostTrustResult('servers.trust.probeStatus', failed),
        throwsFormatException,
      );
    }
    expect(
      () => captureHostTrustResult('servers.trust.probe', {
        'operationId': fixture.request,
        'state': 'succeeded',
      }),
      throwsFormatException,
    );
    expect(
      () => captureHostTrustResult('servers.trust.confirm', {
        ...mutation,
        'deleted': true,
      }),
      throwsFormatException,
    );
  });
}
