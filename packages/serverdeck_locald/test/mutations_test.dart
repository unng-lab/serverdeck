import 'package:serverdeck_locald/profiles/validation.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

import 'models_test.dart' as fixture;
import 'state_store_test.dart' as native;

void main() {
  test(
    'mutation input applies create-only defaults and preserves access secrets',
    () {
      final params = {
        'profileId': fixture.profileId,
        'name': ' Synthetic ',
        'address': ' example.invalid ',
        'sshUser': ' synthetic ',
        'credential': {
          'action': 'replace',
          'kind': 'password',
          'password': ' e\u0301 ',
        },
      };
      final normalized = validateMutationInput(
        ApiMethod.profilesCreate,
        params,
      );
      expect(normalized['name'], 'Synthetic');
      expect(normalized['port'], 22);
      expect(normalized['tags'], isEmpty);
      expect((normalized['credential'] as Map)['password'], ' e\u0301 ');
      expect(
        () => validateMutationInput(ApiMethod.profilesUpdate, {
          ...params,
          'expectedRevision': '1',
        }),
        throwsFormatException,
      );
    },
  );
  native.registerRepositoryTest(mode: 'mutations');
}
