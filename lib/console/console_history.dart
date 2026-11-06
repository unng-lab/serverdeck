import 'dart:convert';

import '../domain/models.dart';
import 'console_models.dart';
import 'terminal_engine.dart';

/// Projects only the requested live rows; no transcript or screen snapshot cache.
ConsoleHistoryValue consoleHistoryPage(
  String epoch,
  ConsoleSessionView session,
  ConsoleTerminalEngine engine, {
  String? cursor,
  int limit = 1000,
}) {
  if (limit < 1 || limit > 1000) {
    throw const OperationFailure(FailureCode.invalidArgument);
  }
  final scrollback = engine.terminal.mainBuffer.scrollBack;
  final screen =
      engine.terminal.buffer.height - engine.terminal.buffer.scrollBack;
  var section = 0, row = 0, offset = 0;
  var gap = false;
  if (cursor != null) {
    Map<String, dynamic> parts;
    try {
      if (cursor.length > 512 ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(cursor)) {
        throw const FormatException();
      }
      final decoded = base64Url.decode(base64Url.normalize(cursor));
      if (base64Url.encode(decoded).replaceAll('=', '') != cursor)
        throw const FormatException();
      final value = jsonDecode(utf8.decode(decoded));
      const keys = {
        'ownerEpoch',
        'sessionId',
        'generation',
        'historyVersion',
        'section',
        'row',
        'scalarOffset',
      };
      if (value is! Map<String, dynamic> ||
          value.length != 7 ||
          !value.keys.every(keys.contains) ||
          value['ownerEpoch'] is! String ||
          value['sessionId'] is! String ||
          !['scrollback', 'screen'].contains(value['section']) ||
          ['generation', 'historyVersion', 'row', 'scalarOffset'].any((key) {
            final v = value[key];
            return v is! int ||
                v < (key == 'generation' || key == 'historyVersion' ? 1 : 0) ||
                v > 9007199254740991;
          })) {
        throw const FormatException();
      }
      parts = value;
    } catch (_) {
      throw const OperationFailure(FailureCode.invalidArgument);
    }
    if (parts['ownerEpoch'] != epoch ||
        parts['sessionId'] != session.sessionId ||
        parts['generation'] != session.generation) {
      throw const OperationFailure(FailureCode.conflict);
    }
    gap = parts['historyVersion'] != engine.historyVersion;
    section = parts['section'] == 'scrollback' ? 0 : 1;
    row = parts['row'] as int;
    offset = parts['scalarOffset'] as int;
  }
  final rows = <ConsoleHistoryRow>[];
  String? next;
  if (!gap) {
    if (row >= (section == 0 ? scrollback : screen)) {
      if (cursor != null)
        throw const OperationFailure(FailureCode.invalidArgument);
      section = 1;
      row = 0;
    }
    var bytes = 0;
    while (section < 2 && rows.length < limit) {
      final count = section == 0 ? scrollback : screen;
      if (row >= count) {
        section++;
        row = 0;
        offset = 0;
        continue;
      }
      final source = engine.row(section == 1, row);
      final scalars = source.text.runes.toList(growable: false);
      if (offset > scalars.length)
        throw const OperationFailure(FailureCode.invalidArgument);
      final fragment = <int>[];
      var position = offset;
      while (position < scalars.length) {
        final scalar = scalars[position];
        final width = scalar <= 0x7f
            ? 1
            : scalar <= 0x7ff
            ? 2
            : scalar <= 0xffff
            ? 3
            : 4;
        // Reserve the separator even for a partial row, keeping every page bounded.
        if (bytes + width + 1 > 65536) break;
        fragment.add(scalar);
        bytes += width;
        position++;
      }
      if (position == offset && position < scalars.length) break;
      if (bytes + 1 > 65536) break;
      bytes++;
      rows.add(
        ConsoleHistoryRow(
          section: section == 0 ? 'scrollback' : 'screen',
          row: row,
          offset: offset,
          text: String.fromCharCodes(fragment),
          wrapped: source.wrapped,
        ),
      );
      if (position < scalars.length) {
        offset = position;
        break;
      }
      row++;
      offset = 0;
      if (row >= count) {
        section++;
        row = 0;
      }
    }
    if (section < 2) {
      next = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'ownerEpoch': epoch,
                'sessionId': session.sessionId,
                'generation': session.generation,
                'historyVersion': engine.historyVersion,
                'section': section == 0 ? 'scrollback' : 'screen',
                'row': row,
                'scalarOffset': offset,
              }),
            ),
          )
          .replaceAll('=', '');
    }
  }
  return ConsoleHistoryValue(
    session: session,
    activeBuffer: engine.isAlt ? 'alt' : 'main',
    cursorX: engine.cursorX,
    cursorY: engine.cursorY,
    historyVersion: engine.historyVersion,
    historyGap: gap,
    truncated: engine.truncated,
    partial: session.partial,
    rows: rows,
    nextCursor: next,
  );
}
