import 'dart:convert';

import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

const workspace = '10000000-0000-4000-8000-000000000001';
const server = '10000000-0000-4000-8000-000000000002';
const host = '10000000-0000-4000-8000-000000000003';
const hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const stamp = '2026-10-21T10:00:00.000Z';

Map<String, Object?> observation({String resource = 'system.motd'}) => {
  'workspaceId': workspace,
  'serverId': server,
  'resourceId': resource,
  'targetRevision': '9223372036854775807',
  'connectionRevision': '2',
  'accessRevision': '1',
  'trustRevision': '2',
  'hostId': host,
  'resourceRegistryDigest': hash,
  'observedAt': stamp,
  'status': 'known',
  'value': resource.endsWith('.service')
      ? <String, Object?>{
          'activeState': 'active',
          'unitFileState': 'enabled',
          'mainPid': 42,
          'startMonotonicUs': '9223372036854775807',
          'baselineDigest': hash,
        }
      : <String, Object?>{
          'exists': true,
          'fileDigest': hash,
          'baselineDigest': hash,
          'values': <String, Object?>{
            'text': 'e\u0301 {{public}}\u0000\u0085\n',
          },
        },
};

Map<String, Object?> copy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

void main() {
  test('verbatim data, immutable snapshots and independent serialization', () {
    final input = observation();
    final record = ManagedResourceObservationRecord.fromJson(input);
    expect(record.toJson(), input);
    (input['value'] as Map)['values'] = {'text': 'changed'};
    final output = record.toJson();
    ((output['value'] as Map)['values'] as Map)['text'] = 'changed again';
    expect(record.toJson(), observation());
    expect(record.targetRevision, '9223372036854775807');
  });

  test('quality unions and absent configuration never invent values', () {
    for (final status in [
      'unknown',
      'unsupported',
      'denied',
      'incomplete',
      'error',
    ]) {
      final input = observation()..['status'] = status;
      expect(
        () => ManagedResourceObservationRecord.fromJson(input),
        throwsFormatException,
      );
      input['value'] = null;
      input['hostId'] = null;
      input['resourceRegistryDigest'] = null;
      final record = ManagedResourceObservationRecord.fromJson(input);
      expect(record.toJson(), input);
      expect(record.fingerprint(), throwsFormatException);
    }
    for (final status in ['known', 'stale']) {
      final input = observation()..['status'] = status;
      (input['value'] as Map).addAll(<String, Object?>{
        'exists': false,
        'fileDigest': null,
        'values': null,
      });
      expect(ManagedResourceObservationRecord.fromJson(input).toJson(), input);
      input['hostId'] = null;
      expect(
        () => ManagedResourceObservationRecord.fromJson(input),
        throwsFormatException,
      );
    }
  });

  test(
    'freshness has exact 15 second inclusive boundary and rejects future',
    () {
      final record = ManagedResourceObservationRecord.fromJson(observation());
      final now = DateTime.parse(stamp);
      expect(record.isFreshAt(now), isTrue);
      expect(record.isFreshAt(now.add(const Duration(seconds: 15))), isTrue);
      expect(
        record.isFreshAt(now.add(const Duration(milliseconds: 15001))),
        isFalse,
      );
      expect(
        record.isFreshAt(now.subtract(const Duration(milliseconds: 1))),
        isFalse,
      );
      final stale = ManagedResourceObservationRecord.fromJson(
        observation()..['status'] = 'stale',
      );
      expect(stale.isFreshAt(now), isFalse);
    },
  );

  test(
    'fingerprints exclude only quality/time and bind all captured facts',
    () async {
      final input = observation();
      final original = await ManagedResourceObservationRecord.fromJson(input)
          .fingerprint();
      final later = copy(input)
        ..['status'] = 'stale'
        ..['observedAt'] = '2026-10-21T10:01:00.000Z';
      expect(
        await ManagedResourceObservationRecord.fromJson(later).fingerprint(),
        original,
      );
      for (final key in ['workspaceId', 'serverId', 'hostId']) {
        final changed = copy(input)
          ..[key] = '10000000-0000-4000-8000-000000000004';
        expect(
          await ManagedResourceObservationRecord.fromJson(changed)
              .fingerprint(),
          isNot(original),
        );
      }
      final changed = copy(input);
      (changed['value'] as Map)['fileDigest'] = 'b' * 64;
      expect(
        await ManagedResourceObservationRecord.fromJson(changed).fingerprint(),
        isNot(original),
      );
    },
  );

  test('closed schema, decimal counters, Unicode and document bounds', () {
    final mutations = <void Function(Map<String, Object?>)>[
      (v) => v['extra'] = true,
      (v) => v.remove('value'),
      (v) => v['resourceId'] = 'netbird.service',
      (v) => v['targetRevision'] = 1,
      (v) => v['targetRevision'] = '01',
      (v) => v['targetRevision'] = '9223372036854775808',
      (v) => v['targetRevision'] = '0',
      (v) => v['trustRevision'] = '1',
      (v) => v['accessRevision'] = '9223372036854775808',
      (v) => v['targetRevision'] = '1',
      (v) => v['observedAt'] = '2026-02-30T10:00:00.000Z',
      (v) => v['status'] = 'fresh',
      (v) => ((v['value'] as Map)['values'] as Map)['text'] = '\ud800',
      (v) => ((v['value'] as Map)['values'] as Map)['text'] = 'é' * 32769,
      (v) => ((v['value'] as Map)['values'] as Map)['text'] = '\u0000' * 65536,
      (v) => (v['value'] as Map)['exists'] = false,
      (v) => (v['value'] as Map)['fileDigest'] = null,
      (v) => (v['value'] as Map)['baselineDigest'] = hash.toUpperCase(),
    ];
    for (final mutate in mutations) {
      final input = observation();
      mutate(input);
      expect(
        () => ManagedResourceObservationRecord.fromJson(input),
        throwsFormatException,
      );
    }
    final boundary = observation();
    ((boundary['value'] as Map)['values'] as Map)['text'] = 'é' * 32768;
    expect(
      () => ManagedResourceObservationRecord.fromJson(boundary),
      returnsNormally,
    );
  });

  test('service states and decimal monotonic start are exact closed types', () {
    final input = observation(resource: 'postgresql.service');
    expect(ManagedResourceObservationRecord.fromJson(input).toJson(), input);
    for (final pair in <String, Object?>{
      'activeState': 'maintenance',
      'unitFileState': 'future-enabled',
      'mainPid': 2147483648,
      'startMonotonicUs': 0,
      'baselineDigest': null,
      'extra': true,
    }.entries) {
      final changed = copy(input);
      (changed['value'] as Map)[pair.key] = pair.value;
      expect(
        () => ManagedResourceObservationRecord.fromJson(changed),
        throwsFormatException,
      );
    }
    (input['value'] as Map)['startMonotonicUs'] = '0';
    (input['value'] as Map)['mainPid'] = 0;
    expect(
      () => ManagedResourceObservationRecord.fromJson(input),
      returnsNormally,
    );
  });

  test(
    'observed DB settings reuse exact literal field types without parameters',
    () {
      for (final entry in {
        'postgresql.settings': {'max_connections': 10, 'shared_buffers_mb': 16},
        'clickhouse.settings': {
          'max_connections': 10000,
          'max_server_memory_usage_mb': 1048576,
        },
      }.entries) {
        final input = observation(resource: entry.key);
        (input['value'] as Map)['values'] = entry.value;
        expect(
          ManagedResourceObservationRecord.fromJson(input).toJson(),
          input,
        );
        final bad = copy(input);
        ((bad['value'] as Map)['values'] as Map)['max_connections'] = {
          'param': 'connections',
        };
        expect(
          () => ManagedResourceObservationRecord.fromJson(bad),
          throwsFormatException,
        );
        ((bad['value'] as Map)['values'] as Map)['max_connections'] = 9;
        expect(
          () => ManagedResourceObservationRecord.fromJson(bad),
          throwsFormatException,
        );
      }
    },
  );
}
