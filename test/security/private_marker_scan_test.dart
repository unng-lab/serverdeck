import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../packages/serverdeck_locald/test/support/private_marker_scan.dart';

void main() {
  const marker = 'synthetic-only-marker-Q05-123456789';
  test('byte marker capture survives clearing the producer buffer', () {
    final bytes = List.generate(32, (index) => index + 1);
    final saved = List<int>.from(bytes);
    final scanner = PrivateMarkerScan()..addSecretBytes(bytes);
    bytes.fillRange(0, bytes.length, 0);
    try {
      expect(() => scanner.assertCleanBytes(saved), throwsStateError);
      scanner.assertCleanBytes(bytes);
    } finally {
      scanner.close();
    }
  });
  test(
    'scanner detects UTF8/UTF16/base64 secret representations without echo',
    () {
      final scanner = PrivateMarkerScan()..addSecretText(marker);
      try {
        for (final bytes in [
          utf8.encode(marker),
          PrivateMarkerScan.utf16le(marker),
          utf8.encode(base64.encode(utf8.encode(marker))),
          utf8.encode(base64.encode(PrivateMarkerScan.utf16le(marker))),
        ]) {
          expect(
            () => scanner.assertCleanBytes([1, ...bytes, 2]),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'safe code',
                'PRIVATE_MARKER_FOUND',
              ),
            ),
          );
        }
        scanner.assertCleanBytes(utf8.encode('ordinary readable metadata'));
      } finally {
        scanner.close();
      }
      expect(() => scanner.assertCleanBytes([]), throwsStateError);
    },
  );
  test(
    'stream scanner catches a marker spanning many chunk boundaries',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'serverdeck-marker-scan-',
      );
      final absolute = p.normalize(p.absolute(root.path));
      if (!p.isWithin(
        p.normalize(p.absolute(Directory.systemTemp.path)),
        absolute,
      ))
        throw StateError('UNSAFE_FIXTURE');
      final scanner = PrivateMarkerScan()..addSecretText(marker);
      try {
        final file = File(p.join(absolute, 'synthetic.bin'));
        await file.writeAsBytes([
          ...List.filled(31, 0),
          ...utf8.encode(marker),
          ...List.filled(70, 0),
        ]);
        await expectLater(
          scanner.assertCleanFile(file, chunkSize: 8),
          throwsStateError,
        );
        await file.writeAsBytes(List.filled(100, 0));
        expect(await scanner.assertCleanFile(file, chunkSize: 8), 100);
      } finally {
        scanner.close();
        root.deleteSync(recursive: true);
      }
    },
  );
}
