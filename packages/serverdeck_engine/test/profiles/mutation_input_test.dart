import 'package:serverdeck_engine/profiles/validation.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

void main() {
  test(
    'settings mutation retains CAS input and refuses unknown authority fields',
    () {
      final input = <String, Object?>{
        'expectedRevision': '3',
        'theme': 'system',
        'reduceMotion': true,
        'selectedProfileId': null,
      };
      final captured = validateMutationInput(ApiMethod.settingsUpdate, input);
      input['expectedRevision'] = '4';
      expect(captured['expectedRevision'], '3');
      expect(
        () => validateMutationInput(ApiMethod.settingsUpdate, {
          ...input,
          'owner': true,
        }),
        throwsFormatException,
      );
      expect(
        () => validateMutationInput(ApiMethod.settingsGet, {}),
        throwsFormatException,
      );
      expect(
        () => validateMutationInput(ApiMethod.settingsUpdate, {
          ...input,
          'expectedRevision': '0',
        }),
        throwsFormatException,
      );
    },
  );
}
