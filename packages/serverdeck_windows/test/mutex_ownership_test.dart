import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';
import 'package:win32/win32.dart';

String _name() =>
    'Global\\ServerDeckNext.v1.${List.generate(32, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
String get _vm => p.join(p.dirname(Platform.resolvedExecutable), 'dartvm.exe');
final _openMutex = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<
      Pointer<Void> Function(Uint32, Int32, Pointer<Utf16>),
      Pointer<Void> Function(int, int, Pointer<Utf16>)
    >('OpenMutexW');

Future<List<int>> _contend(String name) async {
  final child = await Process.start(_vm, [
    'test/support/mutex_ownership_child.dart',
    name,
    'contend',
  ]);
  final output = child.stdout.transform(utf8.decoder).join();
  final errors = child.stderr.transform(utf8.decoder).join();
  try {
    final exit = await child.exitCode.timeout(const Duration(seconds: 120));
    expect(exit, 0, reason: await errors.timeout(const Duration(seconds: 5)));
    return (jsonDecode(
      await output.timeout(const Duration(seconds: 5)),
    ) as List).cast<int>();
  } finally {
    child.kill();
    await child.exitCode.timeout(const Duration(seconds: 10));
  }
}

void main() {
  test(
    'held owner excludes four processes across 4000 production acquisitions',
    () async {
      final name = _name(), sid = currentUserSid();
      final owner = await MutexLease.acquire(name, sid);
      expect(owner.isHeld, true);
      try {
        final results = await Future.wait(
          List.generate(4, (_) => _contend(name)),
        );
        expect(results, everyElement([0, 0]));
      } finally {
        await owner.close();
      }
      final successor = await MutexLease.acquire(name, sid);
      try {
        expect(successor.isHeld, true);
        expect(successor.abandoned, false);
      } finally {
        await successor.close();
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 150)),
  );

  test(
    'killed actual owner transfers an abandoned mutex to one successor',
    () async {
      final name = _name(), sid = currentUserSid();
      final child = await Process.start(_vm, [
        'test/support/mutex_ownership_child.dart',
        name,
        'hold',
      ]);
      final ready = child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line == 'MUTEX_HELD');
      final errors = child.stderr.drain<void>();
      HANDLE? retained;
      try {
        await ready.timeout(const Duration(seconds: 30));
        final pointer = name.toNativeUtf16();
        try {
          retained = HANDLE(_openMutex(0x100001, 0, pointer));
        } finally {
          calloc.free(pointer);
        }
        expect(retained.isValid, true);
        expect(child.kill(), true);
        await child.exitCode.timeout(const Duration(seconds: 10));
        await errors.timeout(const Duration(seconds: 5));
        final successor = await MutexLease.acquire(name, sid);
        try {
          expect(successor.isHeld, true);
          expect(successor.abandoned, true);
          final loser = await MutexLease.acquire(name, sid);
          try {
            expect(loser.isHeld, false);
          } finally {
            await loser.close();
          }
        } finally {
          await successor.close();
        }
      } finally {
        child.kill();
        await child.exitCode.timeout(const Duration(seconds: 10));
        if (retained != null && retained.isValid) CloseHandle(retained);
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
