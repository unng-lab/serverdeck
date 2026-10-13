import 'dart:ffi';

import 'package:serverdeck_windows/security.dart';
import 'package:win32/win32.dart';

import 'thread_identity_probe.dart';

/// Acceptance-only invalid inputs exercise actual OpenProcess/OpenProcessToken.
/// Returns the original safe failure so the real handshake can propagate it.
StateError identityQueryFailure(String mode) {
  final before = currentUserSid();
  StateError? failure;
  try {
    observeThreadIdentity(() {
      if (mode == 'process') {
        // UINT32_MAX is not a valid Windows process ID; unlike PID0, this reaches
        // the native OpenProcess call rather than the wrapper's input guard.
        final unexpected = RetainedProcessIdentity.open(0xffffffff);
        unexpected.close();
      } else if (mode == 'token') {
        processUserSid(HANDLE(nullptr));
      } else {
        throw StateError('INVALID_IDENTITY_PROBE');
      }
    });
  } on StateError catch (error) {
    if (error.message != 'IDENTITY_UNAVAILABLE') rethrow;
    failure = error;
  }
  if (failure == null || currentUserSid() != before) {
    throw StateError('IDENTITY_FAILURE_NOT_PROVED');
  }
  return failure;
}
