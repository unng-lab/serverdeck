import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/runtime/local_diagnostics.dart';

void main() {
  test('bounded local evidence omits error messages and stack paths', () {
    final directory = Directory.systemTemp.createTempSync('diagnostics-unit-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final diagnostics = LocalDiagnostics(directory.path);
    for (var i = 0; i < 12; i++) {
      diagnostics.record(
        'profile',
        StateError('SYNTHETIC_SECRET'),
        StackTrace.fromString(
          '#0      SyntheticAdapter.put (SYNTHETIC_PATH:1:2)',
        ),
      );
    }
    final text = File('${directory.path}/operation-diagnostics.json')
        .readAsStringSync();
    final entries = jsonDecode(text) as List;
    expect(entries, hasLength(8));
    expect(entries.last['frames'], ['SyntheticAdapter.put']);
    expect(text, isNot(contains('SYNTHETIC_SECRET')));
    expect(text, isNot(contains('SYNTHETIC_PATH')));
    diagnostics.record(
      'command',
      const OperationFailure(FailureCode.storageUnavailable),
      StackTrace.empty,
    );
    expect(
      File('${directory.path}/operation-diagnostics.json').readAsStringSync(),
      contains('storageUnavailable'),
    );
  });

  test('unavailable diagnostic directory does not throw', () {
    final directory = Directory.systemTemp.createTempSync('diagnostics-unit-');
    directory.deleteSync();
    expect(
      () => LocalDiagnostics(directory.path)
          .record('profile', StateError('SYNTHETIC_SECRET'), StackTrace.empty),
      returnsNormally,
    );
  });
}
