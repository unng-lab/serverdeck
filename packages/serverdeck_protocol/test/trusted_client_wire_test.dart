import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_protocol/wire.dart';
import 'package:test/test.dart';

const id = '10000000-0000-4000-8000-000000000001';
const request = '10000000-0000-4000-8000-000000000002';
Map<String, Object?> receipt(String operation) => {
  'requestId': request,
  'operation': operation,
  'profileId': id,
  'result': {
    'entityId': id,
    'entityRevision': '2',
    'storeRevision': '2',
    'deleted': false,
  },
  'committedAt': '2026-10-22T00:00:00.000Z',
};
void main() {
  test('trusted readiness is exact3 and mutually closed to operational2', () {
    for (final state in ReadinessState.values) {
      final v = TrustedReadiness(
        state: state,
        generation: id,
        workspaceId: state == ReadinessState.ready ? id : null,
      );
      expect(v.toJson()['storageSchema'], 3);
      expect(TrustedReadiness.decode(v.encode()).toJson(), v.toJson());
      expect(
        () => OperationalReadiness.fromJson(v.toJson()),
        throwsFormatException,
      );
      final old = OperationalReadiness(
        state: state,
        generation: id,
        workspaceId: state == ReadinessState.ready ? id : null,
      );
      expect(
        () => TrustedReadiness.fromJson(old.toJson()),
        throwsFormatException,
      );
      expect(OperationalReadiness.decode(old.encode()).toJson(), old.toJson());
    }
  });
  test(
    'trusted readiness rejects wrong fields, types and capability claims',
    () {
      final v = TrustedReadiness(
        state: ReadinessState.ready,
        generation: id,
        workspaceId: id,
      ).toJson();
      for (final patch in <Map<String, Object?>>[
        {'storageSchema': 3.0},
        {'storageSchema': 4},
        {'extra': true},
        {'apiMinor': 0},
        {'generation': 'bad'},
        {'reason': 'NOT_READY'},
        {'workspaceId': null},
        {
          'features': {
            'profiles': false,
            'ssh': false,
            'jobs': false,
            'backend': false,
          },
        },
        {
          'features': {
            'profiles': false,
            'ssh': false,
            'jobs': false,
            'backend': false,
            'mcp': 1,
          },
        },
      ])
        expect(
          () => TrustedReadiness.fromJson({...v, ...patch}),
          throwsFormatException,
        );
      expect(
        () => TrustedReadiness(
          state: ReadinessState.starting,
          generation: id,
          features: const OperationalFeatures(ssh: true),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'trusted envelope accepts exactly21 code/retry pairs, old remains closed',
    () {
      expect(TrustedLocalError.codes.length, 21);
      for (final code in TrustedLocalError.codes) {
        final value = <String, Object?>{
          'v': 1,
          'id': request,
          'generation': id,
          'error': TrustedLocalError(code).toJson(),
        };
        validateTrustedResponseEnvelope(value);
        if (const {
          'TRUST_REQUIRED',
          'TRUST_CHANGED',
          'HOST_BUSY',
          'AUTHENTICATION_FAILED',
          'CONNECTION_FAILED',
          'CANCELLED',
        }.contains(code)) {
          expect(() => validateResponseEnvelope(value), throwsFormatException);
        } else {
          validateResponseEnvelope(value);
        }
        final error = value['error'] as Map<String, Object?>;
        expect(
          () => validateTrustedResponseEnvelope({
            ...value,
            'error': {...error, 'retry': 'invented'},
          }),
          throwsFormatException,
        );
        expect(
          () => validateTrustedResponseEnvelope({
            ...value,
            'error': {...error, 'secret': 'no'},
          }),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'trusted envelope refuses invalid correlation/version/result framing',
    () {
      final v = <String, Object?>{
        'v': 1,
        'id': request,
        'generation': id,
        'result': <String, Object?>{},
      };
      validateTrustedResponseEnvelope(v);
      for (final patch in <Map<String, Object?>>[
        {'v': true},
        {'v': 1.0},
        {'id': 'bad'},
        {'generation': null},
        {'result': []},
        {'extra': 1},
        {'error': TrustedLocalError('TIMEOUT').toJson()},
      ])
        expect(
          () => validateTrustedResponseEnvelope({...v, ...patch}),
          throwsFormatException,
        );
    },
  );
  test(
    'trusted receipt operations stay exact and do not mutate caller values',
    () {
      for (final operation in [
        'servers.trust.confirm',
        'servers.trust.revoke',
      ]) {
        final value = <String, Object?>{
          'receipts': [receipt(operation)],
          'truncated': false,
        };
        final got = captureTrustedMethodResult('mutations.recent', value);
        expect((got['receipts'] as List).single, receipt(operation));
        expect(
          () => validateMethodResult('mutations.recent', value),
          throwsFormatException,
        );
        expect((value['receipts'] as List).single, receipt(operation));
        expect(() => got.clear(), throwsUnsupportedError);
        final captured = got['receipts'] as List;
        expect(() => captured.clear(), throwsUnsupportedError);
        expect(() => (captured.single as Map).clear(), throwsUnsupportedError);
        expect(
          () => ((captured.single as Map)['result'] as Map).clear(),
          throwsUnsupportedError,
        );
        (value['receipts'] as List).clear();
        expect(captured.single, receipt(operation));
        for (final patch in <Map<String, Object?>>[
          {'operation': 'servers.trust.delete'},
          {'profileId': request},
          {
            'result': {
              'entityId': id,
              'entityRevision': '1',
              'storeRevision': '2',
              'deleted': false,
            },
          },
          {
            'result': {
              'entityId': id,
              'entityRevision': '3',
              'storeRevision': '2',
              'deleted': false,
            },
          },
          {
            'result': {
              'entityId': id,
              'entityRevision': '2',
              'storeRevision': '2',
              'deleted': true,
            },
          },
          {'committedAt': '2026-10-22'},
        ])
          expect(
            () => captureTrustedMethodResult('mutations.recent', {
              'receipts': [
                {...receipt(operation), ...patch},
              ],
              'truncated': false,
            }),
            throwsFormatException,
          );
        expect(
          () => captureTrustedMethodResult('mutations.recent', {
            'receipts': [receipt(operation), receipt(operation)],
            'truncated': false,
          }),
          throwsFormatException,
        );
      }
    },
  );
}
