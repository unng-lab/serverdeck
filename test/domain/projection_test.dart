import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';

void main() {
  test('public projection serializes only public fields and is detached', () {
    const profile = ProfileView(
      profileId: '3456789a-3456-4456-8456-3456789abcde',
      revision: 1,
      connectionRevision: 1,
      displayName: 'Public name',
      host: 'example.test',
      port: 22,
      username: 'user',
      authKind: AuthKind.privateKey,
      hasCredential: true,
      endpointId: 'endpoint',
    );
    final inputs = [profile];
    final page = ProfilesPage(items: inputs, snapshotRevision: 3);
    inputs.clear();
    expect(page.items, [profile]);
    expect(() => page.items.clear(), throwsUnsupportedError);
    final response = OperationResult.success(
      page,
      const OperationMeta(
        dataRevision: 3,
        ownerEpoch: '12345678-1234-4234-8234-123456789abc',
      ),
    );
    final detached = response.toJson();
    (detached['value'] as Map)['items'] = [];
    expect(((response.toJson()['value'] as Map)['items'] as List).length, 1);
    final json = jsonEncode(response.toJson());
    expect(json, isNot(contains('protectedBytes')));
    expect(json, isNot(contains('passphrase')));
    expect(json, contains('"hasCredential":true'));
  });

  test(
    'secret input retains exact password without a public serialization',
    () {
      final input = PasswordInput('  synthetic pass word  ');
      expect(input.password, '  synthetic pass word  ');
      expect(input.toString(), isNot(contains('synthetic')));
      expect(input, isNot(isA<PublicValue>()));
      input.dispose();
      expect(() => input.password, throwsStateError);
    },
  );

  test('private key input owns its bytes, exposes no writable view, clears on disposal', () {
    final original = Uint8List.fromList([1, 2, 3]);
    final input = PrivateKeyInput(original, passphrase: 'synthetic passphrase');
    original[0] = 9;
    final view = input.bytes;
    expect(view, [1, 2, 3]);
    expect(() => view[0] = 5, throwsUnsupportedError);
    expect(input.toString(), isNot(contains('synthetic')));
    expect(input, isNot(isA<PublicValue>()));
    input.dispose();
    expect(view, everyElement(0));
    expect(original, [9, 2, 3]);
    expect(() => input.bytes, throwsStateError);
    expect(() => input.passphrase, throwsStateError);
  });

  test('secret size guard counts UTF8 bytes, not just code units', () {
    expect(
      () => PasswordInput(List.filled(40000, 'я').join()),
      throwsA(isA<OperationFailure>()),
    );
    expect(
      () => PrivateKeyInput(Uint8List(1024 * 1024 + 1)),
      throwsA(isA<OperationFailure>()),
    );
  });

  test('revision exhaustion fails before producing an unsafe increment', () {
    expect(nextRevision(1), 2);
    expect(
      () => nextRevision(9007199254740991),
      throwsA(isA<OperationFailure>()),
    );
    expect(() => nextRevision(0), throwsA(isA<OperationFailure>()));
  });

  test('error detail is a fixed field/reason, never remote exception text', () {
    const error = OperationFailure(
      FailureCode.cleanupRequired,
      field: OperationField.profileId,
      retryable: true,
      reason: FailureReason.connectionCleanup,
    );
    expect(error.toJson()['field'], 'profileId');
    expect(error.toJson()['messageKey'], 'connection.cleanupRequired');
    expect(error.toString(), 'CLEANUP_REQUIRED');
  });
}
