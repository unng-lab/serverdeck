import 'models.dart';

enum RetryAdvice { none, retrySameRequest, reload, reconnect, manualRecovery }

class LocalError {
  const LocalError(this.code, {this.field});
  final ErrorCode code;
  final String? field;
  static const fields = {
    'profileId',
    'expectedRevision',
    'name',
    'address',
    'port',
    'sshUser',
    'tags',
    'credential',
    'password',
    'privateKey',
    'passphrase',
    'theme',
    'reduceMotion',
    'selectedProfileId',
    'requestId',
    'limit',
  };
  RetryAdvice get retry => switch (code) {
    ErrorCode.revisionConflict => RetryAdvice.reload,
    ErrorCode.timeout => RetryAdvice.retrySameRequest,
    ErrorCode.unauthorized ||
    ErrorCode.serviceUnavailable => RetryAdvice.reconnect,
    ErrorCode.storageBlocked ||
    ErrorCode.internal => RetryAdvice.manualRecovery,
    _ => RetryAdvice.none,
  };
  Map<String, Object?> toJson() {
    if (field != null &&
        (code != ErrorCode.validation || !fields.contains(field))) {
      throw ArgumentError('INVALID_ERROR_FIELD');
    }
    return {
      'code': code.wireName,
      'boundary': 'local',
      'retry': switch (retry) {
        RetryAdvice.none => 'none',
        RetryAdvice.retrySameRequest => 'retry-same-request',
        RetryAdvice.reload => 'reload',
        RetryAdvice.reconnect => 'reconnect',
        RetryAdvice.manualRecovery => 'manual-recovery',
      },
      if (field != null) 'field': field,
    };
  }
}
