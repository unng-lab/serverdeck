import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/native_attributes.dart';
import 'package:test/test.dart';

void _probe(List<Object> arguments) {
  final root = arguments[0] as String;
  final port = arguments[1] as SendPort;
  var failures = 0;
  for (var index = 0; index < 20000; index++) {
    try {
      requireSafePath(root, p.join(root, 'absent', 'child'));
    } on FileSystemException {
      failures++;
    }
  }
  port.send(failures);
}

void main() {
  test('native attributes distinguish ordinary existing and missing paths and reject NUL', () {
    final directory = Directory.systemTemp.createTempSync(
      'serverdeck-nt-attributes-',
    );
    final root = p.normalize(p.absolute(directory.path));
    if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root)) {
      throw StateError('UNSAFE_TEST_DIRECTORY');
    }
    try {
      final file = File(p.join(root, 'данные.txt'))
        ..writeAsStringSync('fixture');
      expect(queryLocalAttributes(root)! & 0x10, 0x10);
      expect(queryLocalAttributes(file.path)! & 0x10, 0);
      expect(queryLocalAttributes(p.join(root, 'absent')), isNull);
      expect(queryLocalAttributes(p.join(root, 'absent', 'child')), isNull);
      expect(
        () => queryLocalAttributes('$root\u0000'),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'safe code',
            'UNSAFE_PATH',
          ),
        ),
      );
    } finally {
      directory.deleteSync(recursive: true);
    }
  }, testOn: 'windows');
  test(
    'safe absent components remain valid under concurrent native queries',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'serverdeck-path-race-',
      );
      final root = p.normalize(p.absolute(directory.path));
      if (!p.isWithin(
        p.normalize(p.absolute(Directory.systemTemp.path)),
        root,
      )) {
        throw StateError('UNSAFE_TEST_DIRECTORY');
      }
      final port = ReceivePort();
      final workers = <Isolate>[];
      final results = port.take(8).cast<int>().toList();
      try {
        for (var index = 0; index < 8; index++) {
          workers.add(await Isolate.spawn(_probe, [root, port.sendPort]));
        }
        expect(
          await results.timeout(const Duration(seconds: 120)),
          everyElement(0),
        );
      } finally {
        for (final worker in workers) {
          worker.kill(priority: Isolate.immediate);
        }
        port.close();
        directory.deleteSync(recursive: true);
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 150)),
  );
}
