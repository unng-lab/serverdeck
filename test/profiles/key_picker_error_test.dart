import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/error_presentation.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/theme/brand_theme.dart';

final class PickerOperations extends Fake implements AppOperations {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    return super.noSuchMethod(invocation);
  }
}

void main() {
  for (final code in ['INVALID_ARGUMENT', 'STORAGE_IO']) {
    testWidgets(
      'key picker $code keeps its category and never displays native details',
      (tester) async {
        final operations = PickerOperations(),
            expected = code == 'INVALID_ARGUMENT'
                ? FailureCode.invalidArgument
                : FailureCode.storageUnavailable;
        final c = ProfileController(
          operations: operations,
          actor: ActorAuthority('00000001-0000-4000-8000-000000000000').ui,
          newId: () => '00000002-0000-4000-8000-000000000000',
          poll: false,
        );
        addTearDown(c.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.dark,
            home: ProfileForm(
              controller: c,
              pickKey: () async {
                throw PlatformException(
                  code: code,
                  message: 'synthetic-sensitive-native-detail',
                  details: 'synthetic-secret',
                );
              },
            ),
          ),
        );
        await tester.tap(find.byType(DropdownButtonFormField<AuthKind>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Приватный ключ OpenSSH').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Выбрать файл ключа'));
        await tester.tap(find.text('Выбрать файл ключа'));
        await tester.pumpAndSettle();
        final presentation = OperationPresentation.of(
          OperationFailure(expected, field: OperationField.authentication),
        );
        expect(find.text(presentation.message), findsOneWidget);
        expect(find.text(presentation.nextStep), findsOneWidget);
        expect(
          find.textContaining('synthetic-sensitive-native-detail'),
          findsNothing,
        );
        expect(find.textContaining('synthetic-secret'), findsNothing);
        expect(operations.calls, 0);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
