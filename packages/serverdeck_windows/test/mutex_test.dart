import 'dart:math';
import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;

import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

void main() {
  test('failed setup leaves no live ports in a child process', () async {
    final child = await Process.start(
      p.join(p.dirname(Platform.resolvedExecutable), 'dartvm.exe'),
      ['test/support/mutex_failure_child.dart'],
    );
    final ready = child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((line) => line == 'SETUP_REJECTED');
    final errors = child.stderr.drain<void>();
    try {
      // VM compilation is separate from the five-second shutdown assertion.
      await ready.timeout(const Duration(seconds: 30));
      expect(await child.exitCode.timeout(const Duration(seconds: 5)), 0);
      await errors.timeout(const Duration(seconds: 5));
    } finally {
      child.kill();
      await child.exitCode.timeout(const Duration(seconds: 10));
    }
  }, testOn: 'windows');
  test(
    'one owner across asynchronous Dart scheduling and contenders',
    () async {
      final suffix = List.generate(
        32,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final name = 'Global\\ServerDeckNext.v1.$suffix';
      final sid = currentUserSid();
      final first = await MutexLease.acquire(name, sid);
      try {
        expect(first.acquired, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final contender = await MutexLease.acquire(name, sid);
        try {
          expect(contender.acquired, isFalse);
        } finally {
          await contender.close();
        }
      } finally {
        await first.close();
      }
      await first.close();
      final next = await MutexLease.acquire(name, sid);
      expect(next.acquired, isTrue);
      await next.close();
    },
    testOn: 'windows',
  );
}
