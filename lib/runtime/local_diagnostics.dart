import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';

/// Bounded local developer evidence. Never records exception messages or inputs.
final class LocalDiagnostics {
  LocalDiagnostics(String dataRoot)
    : _file = File('$dataRoot/operation-diagnostics.json');
  final File _file;
  final List<Map<String, Object?>> _entries = [];

  void record(String stage, Object error, StackTrace stack) {
    try {
      final frames = RegExp(
        r'^#\d+\s+([A-Za-z0-9_.$<>]+)',
        multiLine: true,
      ).allMatches(stack.toString()).take(12).map((m) => m.group(1)!).toList();
      _entries.add({
        'stage': stage,
        'type': error.runtimeType.toString(),
        if (error is OperationFailure) 'code': error.code.name,
        'frames': frames,
      });
      if (_entries.length > 8) _entries.removeAt(0);
      _file.writeAsStringSync(jsonEncode(_entries), flush: true);
    } catch (_) {
      // Diagnostics must not replace the original operation outcome.
    }
  }
}
