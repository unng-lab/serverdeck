import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/error_presentation.dart';
import 'package:serverdeck/domain/models.dart';

void main() {
  test(
    'every public failure has fixed safe text and an actionable next step',
    () {
      for (final code in FailureCode.values) {
        final text = OperationPresentation.of(OperationFailure(code));
        expect(text.message, isNotEmpty, reason: code.name);
        expect(text.nextStep, isNotEmpty, reason: code.name);
        expect(text.message, isNot(code.wire));
      }
      for (final field in OperationField.values) {
        final text = OperationPresentation.of(
          OperationFailure(FailureCode.invalidArgument, field: field),
        );
        expect(text.message, contains(OperationPresentation.field(field)));
      }
    },
  );
  test(
    'clock rollback and grant cleanup point to their specific recovery action',
    () {
      expect(
        OperationPresentation.of(
          const OperationFailure(
            FailureCode.accessRevoked,
            reason: FailureReason.clockRollback,
          ),
        ).nextStep,
        contains('Обновите разрешение'),
      );
      expect(
        OperationPresentation.of(
          const OperationFailure(
            FailureCode.cleanupRequired,
            reason: FailureReason.grantCleanup,
          ),
        ).nextStep,
        contains('Повторить закрытие и сохранение'),
      );
    },
  );
}
