import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck_protocol/models.dart';

import '../integration_test/support/foreign_access_proof.dart';

void main() {
  test(
    'unrelated prerequisite or launch failure is not foreign access proof',
    () {
      for (final failure in <Object?>[
        null,
        StateError('PREREQUISITE_UNAVAILABLE'),
        StateError('SERVICE_UNAVAILABLE'),
        const FileSystemException('UNSAFE_PATH'),
        const FileSystemException(
          'UNSAFE_PATH',
          '',
          OSError('NT_ATTRIBUTES_STATUS', 0xc0000034),
        ),
        const FileSystemException(
          'UNSAFE_PATH',
          '',
          OSError('OTHER', 0xc0000022),
        ),
      ]) {
        expect(
          foreignAccessRefusalProved(
            ReadinessState.unavailable,
            ErrorCode.serviceUnavailable,
            ownerProfilePathFailure: failure,
          ),
          false,
        );
      }
    },
  );
  test(
    'native owner-profile path access denial supports early bootstrap refusal',
    () {
      const failure = FileSystemException(
        'UNSAFE_PATH',
        '',
        OSError('NT_ATTRIBUTES_STATUS', 0xc0000022),
      );
      expect(
        foreignAccessRefusalProved(
          ReadinessState.unavailable,
          ErrorCode.serviceUnavailable,
          ownerProfilePathFailure: failure,
        ),
        true,
      );
      expect(
        foreignAccessRefusalProved(
          ReadinessState.unavailable,
          ErrorCode.incompatible,
          ownerProfilePathFailure: failure,
        ),
        false,
      );
    },
  );
  test(
    'explicit storage or authorization refusal remains required otherwise',
    () {
      for (final reason in [
        ErrorCode.storageBlocked,
        ErrorCode.unauthorized,
        ErrorCode.forbidden,
      ]) {
        expect(
          foreignAccessRefusalProved(ReadinessState.storageBlocked, reason),
          true,
        );
      }
      expect(
        foreignAccessRefusalProved(
          ReadinessState.unavailable,
          ErrorCode.timeout,
        ),
        false,
      );
    },
  );
}
