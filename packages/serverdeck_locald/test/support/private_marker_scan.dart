import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Acceptance-only byte scanner; never imported by a normal entrypoint.
class PrivateMarkerScan {
  final _patterns = <Uint8List>[];
  bool _closed = false;
  int _longest = 0;

  void _live() {
    if (_closed) throw StateError('MARKER_SCAN_CLOSED');
  }

  static List<int> utf16le(String text) => [
    for (final unit in text.codeUnits) ...[unit & 255, unit >> 8],
  ];
  void addSecretBytes(List<int> bytes) {
    _live();
    if (bytes.isEmpty ||
        bytes.length > 8192 ||
        bytes.any((v) => v < 0 || v > 255))
      throw ArgumentError('INVALID_MARKER');
    final encoded = base64.encode(bytes);
    for (final value in [bytes, utf8.encode(encoded), utf16le(encoded)]) {
      final copy = Uint8List.fromList(value);
      _patterns.add(copy);
      if (copy.length > _longest) _longest = copy.length;
    }
  }

  void addSecretText(String text) {
    addSecretBytes(utf8.encode(text));
    addSecretBytes(utf16le(text));
  }

  void assertCleanBytes(List<int> bytes) {
    _live();
    if (_patterns.isEmpty) throw StateError('MARKER_SCAN_UNBOUND');
    for (final pattern in _patterns) {
      for (var at = 0; at <= bytes.length - pattern.length; at++) {
        if (bytes[at] != pattern[0]) continue;
        var equal = true;
        for (var index = 1; index < pattern.length; index++) {
          if (bytes[at + index] != pattern[index]) {
            equal = false;
            break;
          }
        }
        if (equal) throw StateError('PRIVATE_MARKER_FOUND');
      }
    }
  }

  Future<int> assertCleanFile(File file, {int chunkSize = 65536}) async {
    _live();
    if (chunkSize < 1 || chunkSize > 65536)
      throw ArgumentError('INVALID_CHUNK');
    final handle = await file.open();
    var count = 0;
    var tail = <int>[];
    try {
      while (true) {
        final chunk = await handle.read(chunkSize);
        if (chunk.isEmpty) break;
        count += chunk.length;
        final combined = [...tail, ...chunk];
        assertCleanBytes(combined);
        final retained = _longest - 1;
        tail = combined.sublist(
          combined.length > retained ? combined.length - retained : 0,
        );
      }
      // An empty file must still reject an unbound scanner.
      assertCleanBytes(const []);
      return count;
    } finally {
      await handle.close();
    }
  }

  void close() {
    _closed = true;
    for (final pattern in _patterns) {
      pattern.fillRange(0, pattern.length, 0);
    }
    _patterns.clear();
  }
}
