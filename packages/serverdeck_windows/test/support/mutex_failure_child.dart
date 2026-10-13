import 'dart:io';

import 'package:serverdeck_windows/mutex.dart';

Future<void> main() async {
  try {
    await MutexLease.acquire(
      'Global\\ServerDeckNext.v1.${'a' * 64}',
      'invalid',
    );
    throw StateError('EXPECTED_REJECTION');
  } on StateError catch (error) {
    if (error.message == 'EXPECTED_REJECTION') rethrow;
  }
  // Normal Dart shutdown must complete without orphan ReceivePorts.
  stdout.writeln('SETUP_REJECTED');
  await stdout.flush();
}
