import 'codec.dart';
import 'executor_enrollment.dart';
import 'validation.dart';

const executorOwnerMethods = {
  'executor.enrollment',
  'executor.confirm',
  'executor.revoke',
};

Map<String, Object?> captureExecutorOwnerResult(
  String method,
  Map<String, Object?> value,
) {
  StrictCodec().encode(value, maxBytes: 16 * 1024);
  if (!executorOwnerMethods.contains(method))
    throw const FormatException('UNSUPPORTED');
  final profile = requireUuid(value['profileId']);
  if (method == 'executor.revoke') {
    requireFields(value, {'profileId', 'revoked'});
    if (value['revoked'] is! bool) throw const FormatException('VALIDATION');
    return Map.unmodifiable(value);
  }
  requireFields(value, {'profileId', 'enrollment'});
  final raw = value['enrollment'];
  if (raw == null && method == 'executor.enrollment')
    return Map.unmodifiable(value);
  if (raw is! Map<String, Object?>) throw const FormatException('VALIDATION');
  final enrollment = ExecutorEnrollment.fromJson(raw);
  if (enrollment.serverId != profile) throw const FormatException('VALIDATION');
  return Map.unmodifiable({...value, 'enrollment': enrollment.toJson()});
}
