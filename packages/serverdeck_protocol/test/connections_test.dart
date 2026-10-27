import 'dart:convert';

import 'package:serverdeck_protocol/connections.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/wire.dart';
import 'package:test/test.dart';

const profile = '12345678-1234-4234-8234-123456789abc';
const operation = '22345678-1234-4234-8234-123456789abc';
Map<String, Object?> identity() => {
  'profileId': profile,
  'connectionRevision': '1',
  'credentialRevision': '3',
  'trustRevision': '2',
  'key': {
    'format': 'ssh-ed25519',
    'fingerprint':
        'SHA256:${base64.encode(List.filled(32, 7)).replaceAll('=', '')}',
  },
};
Map<String, Object?> connected() => {
  'profileId': profile,
  'state': 'connected',
  'interested': true,
  'identity': identity(),
};
void main() {
  test('connection identity retains independent schema3 counters and pin', () {
    final source = connected();
    final result = captureConnectionResult('servers.connection', source);
    (source['identity'] as Map)['trustRevision'] = '9';
    expect((result['identity'] as Map)['trustRevision'], '2');
    expect(() => result.clear(), throwsUnsupportedError);
    expect(
      () => (result['identity'] as Map)['key'] = {},
      throwsUnsupportedError,
    );
    expect(
      () => ((result['identity'] as Map)['key'] as Map).clear(),
      throwsUnsupportedError,
    );
    expect(captureTrustedMethodResult('servers.connection', result), result);
    expect(
      () => validateMethodResult('servers.connection', result),
      throwsFormatException,
    );
  });
  test('all five owner parameters are closed immutable UUID objects', () {
    for (final method in connectionOwnerMethods) {
      final field =
          method == 'servers.connectStatus' || method == 'servers.connectCancel'
          ? 'operationId'
          : 'profileId';
      final source = <String, Object?>{field: profile};
      final captured = captureConnectionParams(method, source);
      source[field] = operation;
      expect(captured[field], profile);
      expect(() => captured.clear(), throwsUnsupportedError);
      for (final invalid in <Map<String, Object?>>[
        {},
        {field: null},
        {field: 'bad'},
        {field: profile, 'secret': 'private'},
      ]) {
        expect(
          () => captureConnectionParams(method, invalid),
          throwsFormatException,
        );
      }
    }
    expect(
      () => captureConnectionParams('servers.trust.confirm', {}),
      throwsFormatException,
    );
  });
  test('snapshot state, ownership and nested identity cannot contradict', () {
    final invalid = <Map<String, Object?>>[
      {...connected(), 'identity': null},
      {...connected(), 'profileId': operation},
      {...connected(), 'state': 'future'},
      {...connected(), 'interested': 1},
      {...connected(), 'address': 'private'},
      {...connected(), 'state': 'disconnected'},
      {...connected(), 'state': 'closing'},
      {
        ...connected(),
        'identity': {...identity(), 'connectionRevision': '3'},
      },
      {
        ...connected(),
        'identity': {...identity(), 'credentialRevision': '0'},
      },
      {
        ...connected(),
        'identity': {...identity(), 'trustRevision': 2},
      },
      {
        ...connected(),
        'identity': {...identity(), 'trustRevision': '9223372036854775808'},
      },
      {
        ...connected(),
        'identity': {
          ...identity(),
          'key': {'format': 'bad', 'fingerprint': 'private'},
        },
      },
    ];
    for (final value in invalid) {
      expect(() => ConnectionSnapshot.fromJson(value), throwsFormatException);
    }
    for (final state in ['connecting', 'connected', 'closing']) {
      final value = {...connected(), 'state': state, 'interested': false};
      expect(ConnectionSnapshot.fromJson(value).toJson(), value);
    }
    final empty = {
      'profileId': profile,
      'state': 'disconnected',
      'interested': false,
      'identity': null,
    };
    expect(ConnectionSnapshot.fromJson(empty).toJson(), empty);
    expect(
      () => ConnectionSnapshot.fromJson({...empty, 'interested': true}),
      throwsFormatException,
    );
  });
  test('operation union is closed and success means attached connected', () {
    final running = {'operationId': operation, 'state': 'running'};
    expect(captureConnectionResult('servers.connect', running), running);
    expect(captureConnectionResult('servers.connectStatus', running), running);
    final done = {
      'operationId': operation,
      'state': 'succeeded',
      'connection': connected(),
    };
    expect(captureConnectionResult('servers.connectStatus', done), done);
    expect(
      () => captureConnectionResult('servers.connect', done),
      throwsFormatException,
    );
    for (final bad in <Map<String, Object?>>[
      {
        ...done,
        'connection': {...connected(), 'interested': false},
      },
      {
        ...done,
        'connection': {...connected(), 'state': 'connecting'},
      },
      {...running, 'code': 'TIMEOUT'},
      {'operationId': operation, 'state': 'failed', 'code': 'PRIVATE_ERROR'},
      {'operationId': operation, 'state': 'failed', 'code': null},
    ]) {
      expect(
        () => captureConnectionResult('servers.connectStatus', bad),
        throwsFormatException,
      );
    }
    for (final code in TrustedLocalError.codes) {
      final failed = {
        'operationId': operation,
        'state': 'failed',
        'code': code,
      };
      expect(captureConnectionResult('servers.connectStatus', failed), failed);
    }
    for (final cancelled in [true, false]) {
      final result = {'operationId': operation, 'cancelled': cancelled};
      expect(
        captureTrustedMethodResult('servers.connectCancel', result),
        result,
      );
    }
    expect(
      () => captureConnectionResult('servers.connectCancel', {
        'operationId': operation,
        'cancelled': 'true',
      }),
      throwsFormatException,
    );
  });
}
