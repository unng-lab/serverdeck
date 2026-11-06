import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/console/console_history.dart';
import 'package:serverdeck/console/console_models.dart';
import 'package:serverdeck/console/terminal_engine.dart';
import 'package:serverdeck/domain/models.dart';

void main() {
  const epoch = '00000000-0000-4000-8000-000000000001';
  ConsoleSessionView view(
    ConsoleTerminalEngine engine, {
    String id = 'session',
  }) => ConsoleSessionView(
    sessionId: id,
    profileId: 'profile',
    generation: 1,
    shellProfileId: 'login',
    shellName: 'shell',
    state: 'ended',
    partial: false,
    historyVersion: engine.historyVersion,
    inputOwner: const ConsoleInputView('free'),
  );
  test(
    'cursor is exact named object; unknown fields and types are rejected',
    () {
      final engine = ConsoleTerminalEngine();
      final first = consoleHistoryPage(epoch, view(engine), engine, limit: 1);
      final shape = {
        'ownerEpoch': epoch,
        'sessionId': 'session',
        'generation': 1,
        'historyVersion': engine.historyVersion,
        'section': 'screen',
        'row': 1,
        'scalarOffset': 0,
      };
      String encode(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      expect(
        jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(first.nextCursor!))),
        ),
        shape,
      );
      final next = consoleHistoryPage(
        epoch,
        view(engine),
        engine,
        cursor: encode(shape),
        limit: 1,
      );
      expect(next.rows.single.row, 1);
      for (final malformed in [
        {...shape, 'extra': 1},
        {...shape, 'section': 1},
        {...shape, 'row': '1'},
        {...shape, 'generation': 0},
        {...shape}..remove('scalarOffset'),
        shape.values.toList(),
      ]) {
        expect(
          () => consoleHistoryPage(
            epoch,
            view(engine),
            engine,
            cursor: encode(malformed),
          ),
          throwsA(
            isA<OperationFailure>().having(
              (e) => e.code,
              'code',
              FailureCode.invalidArgument,
            ),
          ),
        );
      }
    },
  );
  test(
    'pages share screen and scrollback; stale cursor is a successful gap',
    () {
      final engine = ConsoleTerminalEngine()..resize(10, 2);
      engine.feed(Uint8List.fromList(utf8.encode('one\r\ntwo\r\nthree')));
      final first = consoleHistoryPage(epoch, view(engine), engine, limit: 1);
      expect(first.rows.single.text.trimRight(), 'one');
      expect(first.rows.single.section, 'scrollback');
      final second = consoleHistoryPage(
        epoch,
        view(engine),
        engine,
        limit: 1,
        cursor: first.nextCursor,
      );
      expect(second.rows.single.text.trimRight(), 'two');
      expect(second.rows.single.section, 'screen');
      expect(
        () => consoleHistoryPage(
          epoch,
          view(engine, id: 'other'),
          engine,
          cursor: first.nextCursor,
        ),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.code,
            'code',
            FailureCode.conflict,
          ),
        ),
      );
      engine.feed(Uint8List.fromList(utf8.encode('!')));
      final gap = consoleHistoryPage(
        epoch,
        view(engine),
        engine,
        cursor: first.nextCursor,
      );
      expect(gap.historyGap, isTrue);
      expect(gap.rows, isEmpty);
      expect(gap.nextCursor, isNull);
    },
  );
  test('Unicode pages bounded by UTF8 budget preserve every row', () {
    final engine = ConsoleTerminalEngine()..resize(512, 1);
    engine.feed(
      Uint8List.fromList(
        utf8.encode(List.filled(180, '😀' * 250).join('\r\n')),
      ),
    );
    String? cursor;
    final physicalRows = <(String, int)>{};
    do {
      final page = consoleHistoryPage(
        epoch,
        view(engine),
        engine,
        cursor: cursor,
      );
      expect(page.rows.length, lessThanOrEqualTo(1000));
      expect(
        page.rows.fold<int>(
          0,
          (n, row) => n + utf8.encode(row.text).length + 1,
        ),
        lessThanOrEqualTo(65536),
      );
      expect(page.rows.every((row) => !row.text.contains('\uFFFD')), isTrue);
      physicalRows.addAll(page.rows.map((row) => (row.section, row.row)));
      cursor = page.nextCursor;
    } while (cursor != null);
    expect(physicalRows.length, 180);
    expect(
      () => consoleHistoryPage(epoch, view(engine), engine, cursor: 'invalid'),
      throwsA(isA<OperationFailure>()),
    );
    expect(
      () => consoleHistoryPage(epoch, view(engine), engine, limit: 0),
      throwsA(isA<OperationFailure>()),
    );
  });
}
