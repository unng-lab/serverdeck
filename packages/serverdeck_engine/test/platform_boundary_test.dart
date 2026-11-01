import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'domain library has no Flutter or native platform import dependency',
    () {
      final forbidden = RegExp(
        r'''(?:import|export)\s+['"](?:dart:ffi|package:(?:flutter|win32|ffi|serverdeck_windows)(?:/|['"]))''',
      );
      final sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      expect(sources, isNotEmpty);
      for (final source in sources) {
        expect(
          forbidden.hasMatch(source.readAsStringSync()),
          isFalse,
          reason: source.path,
        );
      }
    },
  );
}
