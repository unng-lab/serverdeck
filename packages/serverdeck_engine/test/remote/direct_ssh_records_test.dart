import 'dart:convert';
import 'dart:typed_data';

import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:serverdeck_engine/remote/direct_ssh_records.dart';
import 'package:test/test.dart';

String id(int value) =>
    '12345678-1234-4234-9234-' + value.toString().padLeft(12, '0');
Map<String, String> identity() => {
  'workspaceId': id(1),
  'jobId': id(2),
  'attemptId': id(3),
  'planDigest': 'a' * 64,
  'hostId': id(4),
  'bootIdHash': 'b' * 64,
};
Map<String, String> step({String state = 'reserved'}) => {
  'attemptId': id(3),
  'planDigest': 'a' * 64,
  'stepId': 'e1',
  'stepDigest': 'c' * 64,
  'token': id(5),
  'bootIdHash': 'b' * 64,
  'issuedUptimeMs': '1000',
  'expiresUptimeMs': '6000',
  'authorityBindingDigest': 'd' * 64,
  'targetBindingDigest': 'e' * 64,
  'state': state,
  'exitCode': 'unknown',
  'checkDigest': 'unknown',
};

void main() {
  test('all durable host record kinds have one immutable exact encoding', () {
    final cases = <String, Map<String, String>>{
      'owner': identity(),
      'admission': identity(),
      'plan': {
        'planDigest': 'a' * 64,
        'attemptId': id(3),
        'terminal': 'pending',
      },
      'step': step(),
      'stop': {'attemptId': id(3), 'planDigest': 'a' * 64},
      'policy': {
        'attemptId': id(3),
        'planDigest': 'a' * 64,
        'ownership': 'created',
        'fixedBytesDigest': 'f' * 64,
      },
      'terminal': {
        ...identity(),
        'state': 'succeeded',
        'checksDigest': 'f' * 64,
      },
      'resource': {
        'hostId': id(4),
        'resourceId': 'postgresql.settings',
        'product': 'postgresql16',
        'version': '16.10-0ubuntu0.24.04.1',
        'recipeDigest': 'a' * 64,
        'registryDigest': 'b' * 64,
        'compilerDigest': 'c' * 64,
        'installAttemptId': id(3),
        'installStepId': 'e1',
        'installStepDigest': 'd' * 64,
        'lastConfigAttemptId': id(3),
        'lastConfigStepId': 'e1',
        'unitParentDigest': 'e' * 64,
        'managedFileDigest': 'f' * 64,
      },
    };
    for (final example in cases.entries) {
      final input = {...example.value};
      final record = DirectHostRecord.create(example.key, input);
      input.clear();
      final encoded = record.encode();
      expect(
        ascii.decode(encoded),
        startsWith('SDSSH1\n' + example.key + '\n'),
      );
      final parsed = DirectHostRecord.parse(encoded, expectedKind: example.key);
      expect(parsed.fields, example.value);
      expect(parsed.encode(), encoded);
      expect(() => parsed.fields.clear(), throwsUnsupportedError);
      expect(record.toString(), isNot(contains(id(3))));
    }
  });

  test(
    'partial, foreign, malformed and overlarge records are never empty success',
    () {
      final valid = DirectHostRecord.create('owner', identity()).encode();
      for (final data in <List<int>>[
        [],
        valid.sublist(0, valid.length - 1),
        [...valid, 10],
        ascii.encode(ascii.decode(valid).replaceFirst('SDSSH1', 'SDSSH2')),
        ascii.encode(ascii.decode(valid).replaceFirst(id(3), '../attempt')),
        ascii.encode(ascii.decode(valid).replaceAll('\n', '\r\n')),
        [0xff, ...valid],
        Uint8List(16385),
      ]) {
        expect(
          () => DirectHostRecord.parse(data),
          throwsA(isA<DirectSshFailure>()),
        );
      }
      expect(
        () => DirectHostRecord.parse(valid, expectedKind: 'admission'),
        throwsA(isA<DirectSshFailure>()),
      );
    },
  );

  test(
    'host data cannot carry paths, unknown fields or renewed step windows',
    () {
      for (final value in [
        {...identity(), 'attemptId': '../attempt'},
        {...identity(), 'extra': 'value'},
        {...identity()}..remove('bootIdHash'),
        {...identity(), 'planDigest': 'x' * 64},
      ]) {
        expect(
          () => DirectHostRecord.create('owner', value),
          throwsA(isA<DirectSshFailure>()),
        );
      }
      for (final value in [
        {...step(), 'expiresUptimeMs': '6001'},
        {...step(), 'issuedUptimeMs': '0' * 1000},
        {...step(), 'issuedUptimeMs': '01000'},
        {...step(), 'state': 'succeeded'},
        {...step(), 'state': 'failed', 'exitCode': '0'},
      ]) {
        expect(
          () => DirectHostRecord.create('step', value),
          throwsA(isA<DirectSshFailure>()),
        );
      }
      final success = DirectHostRecord.create('step', {
        ...step(state: 'succeeded'),
        'exitCode': '0',
        'checkDigest': 'f' * 64,
      });
      expect(
        DirectHostRecord.parse(success.encode()).fields['state'],
        'succeeded',
      );
      final failedCheck = DirectHostRecord.create('step', {
        ...step(state: 'failed'),
        'exitCode': '0',
        'checkDigest': 'f' * 64,
      });
      expect(
        DirectHostRecord.parse(failedCheck.encode()).fields['state'],
        'failed',
      );
    },
  );
}
