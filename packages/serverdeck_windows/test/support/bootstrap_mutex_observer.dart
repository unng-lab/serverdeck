import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// Test-only observer, never waits on/acquires the mutex or enters the bundle.
// Layout/API: winsiderss/phnt ntexapi.h MUTANT_BASIC_INFORMATION/NtQueryMutant.
final class MutantInfo extends Struct {
  @Int32()
  external int count;
  @Uint8()
  external int owned;
  @Uint8()
  external int abandoned;
}

final query = DynamicLibrary.open('ntdll.dll')
    .lookupFunction<
      Int32 Function(
        Pointer,
        Uint32,
        Pointer<MutantInfo>,
        Uint32,
        Pointer<Uint32>,
      ),
      int Function(Pointer, int, Pointer<MutantInfo>, int, Pointer<Uint32>)
    >('NtQueryMutant');
final open = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<
      Pointer Function(Uint32, Int32, Pointer<Utf16>),
      Pointer Function(int, int, Pointer<Utf16>)
    >('OpenMutexW');

void check(bool condition) {
  if (!condition) throw StateError('MUTEX_OBSERVER_FAILED');
}

Future<void> main(List<String> args) async {
  check(
    args.length == 1 &&
        RegExp(r'^Global\\ServerDeckNext\.v1\.[a-f0-9]{64}$').hasMatch(args[0]),
  );
  final name = args.single.toNativeUtf16();
  final info = calloc<MutantInfo>();
  final length = calloc<Uint32>();
  HANDLE? handle;
  final commands = StreamIterator(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );
  try {
    handle = HANDLE(open(0x100001, 0, name));
    check(handle.isValid);
    void inspect(int count, int abandoned) {
      check(query(handle!, 0, info, sizeOf<MutantInfo>(), length) == 0);
      check(
        length.value == sizeOf<MutantInfo>() &&
            info.ref.count == count &&
            info.ref.owned == 0 &&
            info.ref.abandoned == abandoned,
      );
    }

    Future<void> command(String expected) async {
      check(await commands.moveNext().timeout(const Duration(seconds: 30)));
      check(commands.current == expected);
    }

    inspect(0, 0);
    stdout.writeln('MUTEX_OBSERVER_HELD');
    await stdout.flush();
    await command('abandoned');
    inspect(1, 1);
    stdout.writeln('MUTEX_ABANDONED_CONFIRMED');
    await stdout.flush();
    await command('acquired');
    inspect(0, 0);
    stdout.writeln('MUTEX_REACQUIRED_CONFIRMED');
    await stdout.flush();
    await command('close');
  } finally {
    await commands.cancel();
    if (handle != null && handle.isValid) CloseHandle(handle);
    calloc.free(name);
    calloc.free(info);
    calloc.free(length);
  }
}
