import 'dart:io';

import 'package:serverdeck_protocol/models.dart';

/// Acceptance only. Generic startup failure is conclusive only when the same
/// production safe-path check independently reports native access denial on
/// the bound owner's profile (the first operation in environment verification).
bool foreignAccessRefusalProved(
  ReadinessState state,
  ErrorCode? reason, {
  Object? ownerProfilePathFailure,
}) {
  if (!{
    ReadinessState.storageBlocked,
    ReadinessState.unavailable,
  }.contains(state)) {
    return false;
  }
  if ({
    ErrorCode.storageBlocked,
    ErrorCode.unauthorized,
    ErrorCode.forbidden,
  }.contains(reason)) {
    return true;
  }
  return reason == ErrorCode.serviceUnavailable &&
      ownerProfilePathFailure is FileSystemException &&
      ownerProfilePathFailure.message == 'UNSAFE_PATH' &&
      ownerProfilePathFailure.osError?.message == 'NT_ATTRIBUTES_STATUS' &&
      ownerProfilePathFailure.osError?.errorCode == 0xc0000022;
}
