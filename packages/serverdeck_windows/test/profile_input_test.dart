import 'dart:io';
import 'dart:convert';

import 'package:serverdeck_windows/profile_input.dart';
import 'package:test/test.dart';

void main() {
  test('Windows IDN normalizes labels but does not accept address syntax', () {
    expect(domainToAscii('пример.рф'), 'xn--e1afmkfd.xn--p1ai');
    expect(domainToAscii('bücher.example'), 'xn--bcher-kva.example');
    expect(domainToAscii('Example.COM'), 'example.com');
    for (final invalid in [
      'a/b',
      '[::1]',
      '-x.example',
      'x .example',
      'a\u0000b',
      '\ud800',
    ]) {
      expect(() => domainToAscii(invalid), throwsFormatException);
    }
  });
  test('explicit file read is bounded, strict UTF8 and preserves secret bytes', () async {
    final root = await Directory.systemTemp.createTemp('serverdeck-key-input-');
    final file = File('${root.path}/input.txt');
    try {
      const text =
          '-----BEGIN PRIVATE KEY-----\r\nAQID\r\n-----END PRIVATE KEY-----\r\n';
      await file.writeAsBytes(utf8.encode(text));
      expect(await readSelectedPrivateKey(file.path), text);
      await file.writeAsBytes(List.filled(65536, 65));
      expect((await readSelectedPrivateKey(file.path)).length, 65536);
      await file.writeAsBytes(List.filled(65537, 65));
      await expectLater(
        readSelectedPrivateKey(file.path),
        throwsFormatException,
      );
      await file.writeAsBytes([0xff]);
      await expectLater(
        readSelectedPrivateKey(file.path),
        throwsFormatException,
      );
    } finally {
      await file.delete();
      await root.delete();
    }
  });
}
