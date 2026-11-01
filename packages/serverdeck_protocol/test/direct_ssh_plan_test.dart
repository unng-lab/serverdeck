import 'dart:convert';

import 'package:serverdeck_protocol/automation/plan_records.dart';
import 'package:serverdeck_protocol/direct_ssh_runtime.dart';
import 'package:test/test.dart';

Map<String, Object?> capsule({int format = 2}) => {
  'format': format,
  'operationId': '12345678-1234-4234-9234-123456789abc',
  'hostId': '22345678-1234-4234-9234-123456789abc',
  'environment': 'ubuntu24.04-amd64-systemd',
  'profileDigest': 'a' * 64,
  'inputDigest': 'b' * 64,
  'runtimeVersion': format == 2
      ? DirectSshRuntime.version
      : 'historical-executor-runtime',
  'runtimeLockDigest': format == 2
      ? DirectSshRuntime.prerequisiteDigest
      : 'c' * 64,
  'compilerDigest': format == 2 ? DirectSshRuntime.compilerDigest : 'd' * 64,
  'registryDigest': format == 2 ? DirectSshRuntime.registryDigest : 'e' * 64,
  'bootIdHash': 'f' * 64,
  'packageSnapshotDigest': '0' * 64,
  'expectedPackageSnapshotDigest': '0' * 64,
  'netbirdSnapshotDigest': '1' * 64,
  'aptIndexDigests': <Object?>[],
  'recipes': <Object?>[],
  'baseObservations': <Object?>[],
};

void main() {
  test(
    'direct capsule has a distinct immutable identity from legacy history',
    () async {
      final input = capsule();
      final captured = await AutomationPreflightCapsule.fromJson(input);
      input['hostId'] = null;
      expect(captured.isDirectSsh, isTrue);
      expect(captured.format, 2);
      expect(DirectSshRuntime.matches(captured.toJson()), isTrue);
      expect(captured.hostId, '22345678-1234-4234-9234-123456789abc');
    },
  );

  test(
    'legacy capsule retains exact JSON and digest without gaining authority',
    () async {
      final input = capsule(format: 1);
      final original = jsonEncode(input);
      final first = await AutomationPreflightCapsule.fromJson(input);
      final reloaded = await AutomationPreflightCapsule.fromJson(
        first.toJson(),
      );
      expect(first.isDirectSsh, isFalse);
      expect(jsonEncode(first.toJson()), original);
      expect(reloaded.digest, first.digest);
      expect(DirectSshRuntime.matches(first.toJson()), isFalse);
    },
  );

  test(
    'a format flag cannot turn arbitrary or legacy runtime into direct proof',
    () async {
      for (final patch in <Map<String, Object?>>[
        {'format': 3},
        {'format': 2.0},
        {'runtimeVersion': 'historical-executor-runtime'},
        {'runtimeLockDigest': 'c' * 64},
        {'compilerDigest': 'd' * 64},
        {'registryDigest': 'e' * 64},
        {'environment': 'other'},
        {'unexpected': true},
      ]) {
        await expectLater(
          AutomationPreflightCapsule.fromJson({...capsule(), ...patch}),
          throwsFormatException,
        );
      }
    },
  );
}
