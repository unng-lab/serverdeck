import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/console/console_models.dart';
import 'package:serverdeck/console/console_replay.dart';
import 'package:serverdeck/domain/models.dart';

void main() {
  const epoch = '00000000-0000-4000-8000-000000000001';
  const result = ConsoleActionValue(
    sessionId: 'session',
    generation: 1,
    state: 'active',
    status: 'outcomeUnknown',
    acceptedBytes: 3,
    operationSequence: 1,
  );
  test(
    'pending duplicate conflicts; completed lost response replays metadata',
    () {
      final book = ConsoleReplayBook(epoch);
      expect(book.begin('client', 1, epoch, 1, {'text': 'private'}), isNull);
      expect(
        () => book.begin('client', 1, epoch, 1, {'text': 'private'}),
        throwsA(
          isA<OperationFailure>().having((e) => e.retryable, 'retryable', true),
        ),
      );
      book.complete('client', 1, 1, result);
      final replay = book.begin('client', 1, epoch, 1, {'text': 'private'});
      expect(replay!.replayed, isTrue);
      expect(replay.status, 'outcomeUnknown');
      expect(replay.acceptedBytes, 3);
      expect(book.next('client', 1), 2);
      expect(
        () => book.begin('client', 1, epoch, 1, {'text': 'different'}),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.code,
            'code',
            FailureCode.conflict,
          ),
        ),
      );
    },
  );
  test(
    'eviction retains high water and does not reaccept forgotten identity',
    () {
      final book = ConsoleReplayBook(epoch);
      for (var sequence = 1; sequence <= 65; sequence++) {
        book.begin('client', 1, epoch, sequence, {'sequence': sequence});
        book.complete('client', 1, sequence, result);
      }
      expect(
        () => book.begin('client', 1, epoch, 1, {'sequence': 1}),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.code,
            'code',
            FailureCode.consoleReplayExpired,
          ),
        ),
      );
      expect(book.next('client', 1), 66);
      expect(
        () => book.begin('client', 1, 'old', 66, {}),
        throwsA(isA<OperationFailure>()),
      );
      expect(
        () => book.begin('client', 1, epoch, 67, {}),
        throwsA(isA<OperationFailure>()),
      );
    },
  );
  test('principal cap cannot evict high water; failure is replayed', () {
    final book = ConsoleReplayBook(epoch);
    for (var i = 0; i < 64; i++) {
      book.begin('client$i', 1, epoch, 1, {});
      book.fail(
        'client$i',
        1,
        1,
        const OperationFailure(FailureCode.consoleInactive),
      );
    }
    expect(
      () => book.begin('new', 1, epoch, 1, {}),
      throwsA(
        isA<OperationFailure>().having(
          (e) => e.code,
          'code',
          FailureCode.resourceExhausted,
        ),
      ),
    );
    expect(
      () => book.begin('client0', 1, epoch, 1, {}),
      throwsA(
        isA<OperationFailure>().having(
          (e) => e.code,
          'code',
          FailureCode.consoleInactive,
        ),
      ),
    );
    expect(book.next('new', 1), 1);
  });
}
