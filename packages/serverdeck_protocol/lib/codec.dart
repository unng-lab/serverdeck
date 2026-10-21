import 'dart:convert';
import 'dart:typed_data';

import 'package:unorm_dart/unorm_dart.dart' as unicode;

import 'protocol.dart';

class StrictCodec implements ProtocolCodec {
  @override
  Map<String, Object?> decode(
    List<int> bytes, {
    int maxBytes = maxRequestBytes,
  }) {
    final value = decodeValue(bytes, maxBytes: maxBytes);
    if (value is! Map<String, Object?>) {
      throw const FormatException('INVALID_FRAME');
    }
    return value;
  }

  /// Bounded JSON syntax parsing without the Local API's object-only envelope
  /// rule. External adapters can distinguish valid JSON from an invalid RPC
  /// shape, while existing [decode] callers retain exactly the same contract.
  Object? decodeValue(List<int> bytes, {int maxBytes = maxRequestBytes}) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('INVALID_FRAME');
    }
    try {
      final parser = _JsonParser(utf8.decode(bytes, allowMalformed: false));
      final value = parser.value(0);
      parser.space();
      if (parser.index != parser.text.length) {
        throw const FormatException('INVALID_FRAME');
      }
      return value;
    } on FormatException {
      // dart:convert exceptions can retain the private input as their source.
      throw const FormatException('INVALID_FRAME');
    }
  }

  @override
  List<int> encode(
    Map<String, Object?> document, {
    int maxBytes = maxResponseBytes,
  }) {
    final bytes = canonical(document);
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('INVALID_FRAME');
    }
    return bytes;
  }

  @override
  List<int> canonical(Object? value) =>
      utf8.encode(jsonEncode(_normalize(value, 0)));

  Object? _normalize(Object? value, int depth, {bool preserveText = false}) {
    if (depth > maxDepth) {
      throw const FormatException('INVALID_FRAME');
    }
    if (value is String) {
      _validUnicode(value);
      return preserveText ? value : unicode.nfc(value);
    }
    if (value is Map<String, Object?>) {
      final normalized = <String, Object?>{};
      for (final key in value.keys) {
        _validUnicode(key);
        final nfc = unicode.nfc(key);
        if (normalized.containsKey(nfc)) {
          throw const FormatException('INVALID_FRAME');
        }
        normalized[nfc] = _normalize(
          value[key],
          depth + 1,
          preserveText: const {
            'password',
            'privateKey',
            'passphrase',
          }.contains(nfc),
        );
      }
      final keys = normalized.keys.toList()..sort(_compareCodepoints);
      return {for (final key in keys) key: normalized[key]};
    }
    if (value is List) {
      return value.map((item) => _normalize(item, depth + 1)).toList();
    }
    if (value == null || value is bool || value is int) {
      return value;
    }
    throw const FormatException('INVALID_FRAME');
  }
}

int _compareCodepoints(String a, String b) {
  final left = a.runes.toList(), right = b.runes.toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final difference = left[i].compareTo(right[i]);
    if (difference != 0) {
      return difference;
    }
  }
  return left.length.compareTo(right.length);
}

void _validUnicode(String value) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= value.length ||
          value.codeUnitAt(i) < 0xdc00 ||
          value.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('INVALID_FRAME');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('INVALID_FRAME');
    }
  }
}

/// Parses before allocating business objects, including duplicate escaped keys.
class _JsonParser {
  _JsonParser(this.text);
  final String text;
  int index = 0;
  void space() {
    while (index < text.length &&
        const [9, 10, 13, 32].contains(text.codeUnitAt(index))) {
      index++;
    }
  }

  bool take(String character) {
    space();
    if (index < text.length && text[index] == character) {
      index++;
      return true;
    }
    return false;
  }

  Never invalid() => throw const FormatException('INVALID_FRAME');
  Object? value(int depth) {
    if (depth > maxDepth) {
      invalid();
    }
    space();
    if (index >= text.length) {
      invalid();
    }
    if (text[index] == '"') {
      return string();
    }
    if (take('{')) {
      final result = <String, Object?>{};
      if (take('}')) {
        return result;
      }
      do {
        space();
        if (index >= text.length || text[index] != '"') {
          invalid();
        }
        final key = string();
        if (result.containsKey(key) || !take(':')) {
          invalid();
        }
        result[key] = value(depth + 1);
        if (take('}')) {
          return result;
        }
      } while (take(','));
      invalid();
    }
    if (take('[')) {
      final result = <Object?>[];
      if (take(']')) {
        return result;
      }
      do {
        result.add(value(depth + 1));
        if (take(']')) {
          return result;
        }
      } while (take(','));
      invalid();
    }
    for (final literal in ['true', 'false', 'null']) {
      if (text.startsWith(literal, index)) {
        index += literal.length;
        return jsonDecode(literal);
      }
    }
    final match = RegExp(
      r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
    ).matchAsPrefix(text, index);
    if (match == null) {
      invalid();
    }
    index = match.end;
    final number = jsonDecode(match.group(0)!);
    if (number is! num || !number.isFinite) {
      invalid();
    }
    return number;
  }

  String string() {
    final start = index++;
    while (index < text.length) {
      final character = text[index++];
      if (character == '"') {
        final result = jsonDecode(text.substring(start, index)) as String;
        _validUnicode(result);
        return result;
      }
      if (character == r'\') {
        if (index >= text.length) {
          invalid();
        }
        index++;
      }
    }
    invalid();
  }
}

Uint8List frameBytes(List<int> payload, {int maxBytes = maxRequestBytes}) {
  if (payload.isEmpty || payload.length > maxBytes) {
    throw const FormatException('INVALID_FRAME');
  }
  final frame = Uint8List(payload.length + 4);
  ByteData.sublistView(frame).setUint32(0, payload.length, Endian.little);
  frame.setRange(4, frame.length, payload);
  return frame;
}

/// Bounded incremental framing. The pipe worker supplies the five-second timer.
class FrameDecoder {
  FrameDecoder({this.maxBytes = maxRequestBytes});
  final int maxBytes;
  final Uint8List _header = Uint8List(4);
  int _headerBytes = 0, _payloadBytes = 0;
  Uint8List? _payload;
  bool get hasPartialFrame => _headerBytes != 0 || _payload != null;
  List<Uint8List> add(List<int> chunk) {
    var offset = 0;
    final frames = <Uint8List>[];
    while (offset < chunk.length) {
      if (_payload == null) {
        final remaining = 4 - _headerBytes;
        final count = (chunk.length - offset).clamp(0, remaining);
        _header.setRange(_headerBytes, _headerBytes + count, chunk, offset);
        _headerBytes += count;
        offset += count;
        if (_headerBytes < 4) {
          continue;
        }
        final length = ByteData.sublistView(_header)
            .getUint32(0, Endian.little);
        if (length == 0 || length > maxBytes) {
          throw const FormatException('INVALID_FRAME');
        }
        _payload = Uint8List(length);
        _payloadBytes = 0;
      }
      final count = (chunk.length - offset).clamp(
        0,
        _payload!.length - _payloadBytes,
      );
      _payload!.setRange(_payloadBytes, _payloadBytes + count, chunk, offset);
      _payloadBytes += count;
      offset += count;
      if (_payloadBytes == _payload!.length) {
        frames.add(_payload!);
        _payload = null;
        _payloadBytes = 0;
        _headerBytes = 0;
      }
    }
    return frames;
  }
}
