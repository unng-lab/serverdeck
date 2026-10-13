import 'dart:convert';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  final codec = StrictCodec();
  for (final (name, limit) in [
    ('handshake', maxHandshakeBytes),
    ('request', maxRequestBytes),
    ('response', maxResponseBytes),
  ]) {
    test(
      'actual $name byte limit accepts boundary and rejects one-byte excess',
      () {
        // JSON envelope is8 ASCII bytes; the Cyrillic scalar is2 UTF8 bytes.
        final text = 'я' + 'x' * (limit - 10);
        final exact = codec.encode({'x': text}, maxBytes: limit);
        expect(exact.length, limit);
        final decoded = codec.decode(exact, maxBytes: limit);
        expect((decoded['x'] as String).length, text.length);
        final framed = frameBytes(exact, maxBytes: limit);
        final decoder = FrameDecoder(maxBytes: limit);
        expect(decoder.add(framed.sublist(0, 3)), isEmpty);
        expect(decoder.add(framed.sublist(3)).single.length, limit);
        expect(decoder.hasPartialFrame, false);
        final excess = codec.canonical({'x': '$text!'});
        expect(excess.length, limit + 1);
        for (final operation in <void Function()>[
          () {
            codec.encode({'x': '$text!'}, maxBytes: limit);
          },
          () {
            codec.decode(excess, maxBytes: limit);
          },
          () {
            frameBytes(excess, maxBytes: limit);
          },
          () {
            FrameDecoder(
              maxBytes: limit,
            ).add([for (var i = 0; i < 4; i++) ((limit + 1) >> (i * 8)) & 255]);
          },
        ]) {
          expect(
            operation,
            throwsA(
              isA<FormatException>().having(
                (error) => error.source,
                'safe source',
                isNull,
              ),
            ),
          );
        }
      },
    );
  }
  test('NFC and Unicode codepoint key ordering', () {
    expect(
      utf8.decode(
        codec.canonical({'e': 'e\u0301', '\u{10000}': 1, '\ue000': 2}),
      ),
      '{"e":"é","\ue000":2,"\u{10000}":1}',
    );
    expect(
      () => codec.canonical({'é': 1, 'e\u0301': 2}),
      throwsFormatException,
    );
    expect(
      () => codec.decode(utf8.encode(r'{"a":"\ud800"}')),
      throwsFormatException,
    );
  });
  test('bounded little endian partial and consecutive framing', () {
    final decoder = FrameDecoder(maxBytes: 20);
    final frame = frameBytes(utf8.encode('{"a":1}'), maxBytes: 20);
    expect(decoder.add(frame.sublist(0, 2)), isEmpty);
    expect(decoder.hasPartialFrame, isTrue);
    expect(decoder.add(frame.sublist(2)).single, utf8.encode('{"a":1}'));
    expect(decoder.hasPartialFrame, isFalse);
    expect(decoder.add([...frame, ...frame]).length, 2);
    expect(
      () => FrameDecoder(maxBytes: 1).add([2, 0, 0, 0]),
      throwsFormatException,
    );
    expect(() => FrameDecoder().add([0, 0, 0, 0]), throwsFormatException);
  });
  test('concatenated stream is independent of chunk boundaries', () {
    final first = frameBytes(utf8.encode('{"value":123}'), maxBytes: 20);
    final second = frameBytes(utf8.encode('{"value":456}'), maxBytes: 20);
    final stream = [...first, ...second];
    final expected = FrameDecoder(maxBytes: 20).add(stream);
    expect(expected.length, 2);
    for (var cut = 1; cut < stream.length; cut++) {
      final decoder = FrameDecoder(maxBytes: 20);
      expect([
        ...decoder.add(stream.sublist(0, cut)),
        ...decoder.add(stream.sublist(cut)),
      ], expected);
      expect(decoder.hasPartialFrame, isFalse);
    }
  });
  test('canonical bytes preserve array order and sort object keys', () {
    expect(
      utf8.decode(
        codec.canonical({
          'z': [2, 1],
          'a': 'тест',
        }),
      ),
      '{"a":"тест","z":[2,1]}',
    );
  });
  test('UTF8 object decode', () {
    expect(codec.decode(utf8.encode('{"a":[true,null,1]}')), {
      'a': [true, null, 1],
    });
  });
  for (final input in [
    '{"a":1,"a":2}',
    '{"a":1,"\\u0061":2}',
    '{"nested":{"x":1,"x":2}}',
    '[]',
    '{"a":01}',
    '{"a":1} trailing',
  ]) {
    test('reject malformed/duplicate input $input', () {
      expect(() => codec.decode(utf8.encode(input)), throwsFormatException);
    });
  }
  test('invalid UTF8 and oversize/depth rejected', () {
    expect(() => codec.decode([123, 255, 125]), throwsFormatException);
    expect(
      () => codec.decode(utf8.encode('{"a":1}'), maxBytes: 2),
      throwsFormatException,
    );
    final nested =
        List.filled(17, '[').join() + '0' + List.filled(17, ']').join();
    expect(
      () => codec.decode(utf8.encode('{"a":$nested}')),
      throwsFormatException,
    );
  });
  test('malformed JSON errors never retain private source bytes or text', () {
    for (final bytes in [
      utf8.encode('{"password":"synthetic-marker\n"}'),
      [123, 255, 125],
    ]) {
      expect(
        () => codec.decode(bytes),
        throwsA(
          isA<FormatException>()
              .having((e) => e.source, 'source', isNull)
              .having((e) => e.message, 'message', 'INVALID_FRAME'),
        ),
      );
    }
  });
}
