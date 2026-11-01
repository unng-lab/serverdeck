import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/profile_validation.dart';
import 'package:serverdeck_protocol/validation.dart';

export 'package:serverdeck_protocol/profile_validation.dart';

Map<String, Object?> validateMutationInput(
  ApiMethod method,
  Map<String, Object?> input,
) {
  if (!method.isMutation) throw const FormatException('UNSUPPORTED');
  validateMethodShape(method.wireName, input);
  if (method == ApiMethod.settingsUpdate) {
    requireRevision(input['expectedRevision']);
    if (!ThemePreference.values.any((v) => v.name == input['theme']) ||
        input['reduceMotion'] is! bool)
      throw const FormatException('VALIDATION');
    if (input['selectedProfileId'] != null)
      requireUuid(input['selectedProfileId']);
    return Map.of(input);
  }
  requireUuid(input['profileId']);
  if (method != ApiMethod.profilesCreate)
    requireRevision(input['expectedRevision']);
  if (method == ApiMethod.profilesDelete) return Map.of(input);
  final creating = method == ApiMethod.profilesCreate;
  return {
    'profileId': input['profileId'],
    if (!creating) 'expectedRevision': input['expectedRevision'],
    ...normalizeProfileFields(input),
    'credential': normalizeCredential(
      input.containsKey('credential')
          ? Map<String, Object?>.from(input['credential'] as Map)
          : {'action': 'remove'},
      creating: creating,
    ),
  };
}
