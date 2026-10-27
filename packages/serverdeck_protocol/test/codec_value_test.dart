import 'dart:convert';

import 'package:serverdeck_protocol/codec.dart';
import 'package:test/test.dart';

void main() {
  test(
    'generic JSON syntax parsing does not loosen foundation object decoding',
    () {
      final codec = StrictCodec();
      for (final json in ['[]', '[1,2]', '42', 'null', '"text"', 'true']) {
        final bytes = utf8.encode(json);
        expect(codec.decodeValue(bytes), jsonDecode(json));
        expect(() => codec.decode(bytes), throwsFormatException);
      }
      expect(codec.decode(utf8.encode('{"v":1}')), {'v': 1});
    },
  );

  test('generic syntax API preserves all bounded strict parse guards', () {
    final codec = StrictCodec();
    for (final json in [
      '{"a":1,"a":2}',
      '[1,',
      'null trailing',
      '${'[' * 18}0${']' * 18}',
    ]) {
      expect(() => codec.decodeValue(utf8.encode(json)), throwsFormatException);
    }
    expect(() => codec.decodeValue([0xff]), throwsFormatException);
    expect(
      () => codec.decodeValue(utf8.encode('[]'), maxBytes: 1),
      throwsFormatException,
    );
  });
}
