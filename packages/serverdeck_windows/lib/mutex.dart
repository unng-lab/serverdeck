import 'dart:ffi';
import 'dart:isolate';
import 'dart:io';

import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart';

import 'security.dart';
import 'kernel_security.dart';

final _kernel = DynamicLibrary.open('kernel32.dll');
const _nativeObservationEnabled = bool.fromEnvironment(
  'SERVERDECK_TEST_NATIVE_OBSERVATION',
);
final _createMutex = _kernel
    .lookupFunction<
      Pointer Function(Pointer<SECURITY_ATTRIBUTES>, Int32, Pointer<Utf16>),
      Pointer Function(Pointer<SECURITY_ATTRIBUTES>, int, Pointer<Utf16>)
    >('CreateMutexW');
final _releaseMutex = _kernel
    .lookupFunction<Int32 Function(Pointer), int Function(Pointer)>(
      'ReleaseMutex',
    );

/// A worker holds ownership on one uninterrupted native call stack.
/// Dart await boundaries must never separate native mutex acquire/release.
class MutexLease {
  MutexLease._(
    this.name,
    this.acquired,
    this.abandoned,
    this._event,
    this._exit,
    this._testMutex,
  );
  final String name;
  final bool acquired, abandoned;
  final int _event;
  final Future<void> _exit;
  final int? _testMutex;
  bool _closed = false;
  bool get isHeld => acquired && !_closed;
  static Future<MutexLease> acquire(
    String name,
    String sid, {
    bool testWrongThreadRelease = false,
  }) async {
    if (testWrongThreadRelease && !_nativeObservationEnabled)
      throw StateError('UNSUPPORTED');
    if (!RegExp(r'^Global\\ServerDeckNext\.v1\.[a-f0-9]{64}$').hasMatch(name)) {
      throw StateError('UNSAFE_ENDPOINT');
    }
    final security = SecurityAttributes(ownerOnlySddl(sid));
    late final HANDLE event;
    try {
      final created = CreateEvent(security.pointer, true, false, null);
      if (!created.value.isValid) {
        throw StateError('OWNERSHIP_UNAVAILABLE');
      }
      event = created.value;
    } finally {
      security.close();
    }
    final reply = ReceivePort();
    final done = ReceivePort();
    final completion = ReceivePort();
    final exit = done.first.then<void>((_) async {
      done.close();
      try {
        final status = await completion.first.timeout(
          const Duration(seconds: 5),
        );
        if (status != true) {
          throw StateError('OWNERSHIP_UNAVAILABLE');
        }
      } finally {
        completion.close();
      }
    });
    var spawned = false;
    try {
      await Isolate.spawn(_worker, [
        reply.sendPort,
        name,
        sid,
        event.address,
        completion.sendPort,
        testWrongThreadRelease,
      ], onExit: done.sendPort);
      spawned = true;
      final message = await reply.first.timeout(const Duration(seconds: 5));
      if (message is! List ||
          message.length != (testWrongThreadRelease ? 4 : 3) ||
          message[0] is! bool ||
          message[1] is! bool ||
          message[2] is! int ||
          testWrongThreadRelease && message[3] is! int) {
        throw StateError('OWNERSHIP_UNAVAILABLE');
      }
      return MutexLease._(
        name,
        message[0] as bool,
        message[1] as bool,
        message[2] as int,
        exit,
        testWrongThreadRelease && message[0] == true ? message[3] as int : null,
      );
    } catch (_) {
      SetEvent(event);
      if (!spawned) {
        completion.sendPort.send(true);
        done.sendPort.send(null);
      }
      try {
        await exit;
      } finally {
        CloseHandle(event);
      }
      rethrow;
    } finally {
      reply.close();
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    // Negative fixture only: the genuine owner worker is still blocked in its
    // native wait, so this caller cannot own the mutex. Cleanup never delegates
    // to this attempt; always signal and await the real owner's release below.
    final wrongThreadDenied = _nativeObservationEnabled && _testMutex != null
        ? _releaseMutex(Pointer.fromAddress(_testMutex)) == 0
        : null;
    if (acquired && !SetEvent(HANDLE(Pointer.fromAddress(_event))).value) {
      throw StateError('OWNERSHIP_UNAVAILABLE');
    }
    _closed = true;
    var eventClosed = false;
    try {
      await _exit;
    } finally {
      eventClosed = CloseHandle(HANDLE(Pointer.fromAddress(_event))).value;
    }
    if (_nativeObservationEnabled && _testMutex != null) {
      if (wrongThreadDenied == true && eventClosed)
        stdout.writeln(
          'ACTUAL_WRONG_THREAD_MUTEX_RELEASE_DENIED_OWNER_CLEANUP_PROVED',
        );
      throw StateError('OWNERSHIP_UNAVAILABLE');
    }
  }

  static void _worker(List<Object> message) {
    final reply = message[0] as SendPort;
    final name = message[1] as String, sid = message[2] as String;
    final input = name.toNativeUtf16();
    SecurityAttributes? security;
    HANDLE? mutex;
    final event = HANDLE(Pointer.fromAddress(message[3] as int));
    final testRelease = _nativeObservationEnabled && message[5] == true;
    var owned = false;
    try {
      security = SecurityAttributes(ownerOnlySddl(sid));
      // Opening/creating a handle never proves ownership. Always acquire via
      // the native wait result, avoiding a separate TLS GetLastError call.
      final opened = HANDLE(_createMutex(security.pointer, 0, input));
      if (!opened.isValid) {
        throw StateError('OWNERSHIP_UNAVAILABLE');
      }
      mutex = opened;
      requireKernelOwnerAcl(opened, sid, '0x1f0001');
      final waited = WaitForSingleObject(opened, 0).value;
      if (waited == 258) {
        reply.send([false, false, event.address, if (testRelease) 0]);
        return;
      }
      if (waited != 0 && waited != 128) {
        throw StateError('OWNERSHIP_UNAVAILABLE');
      }
      final abandoned = waited == 128;
      owned = true;
      reply.send([
        true,
        abandoned,
        event.address,
        if (testRelease) opened.address,
      ]);
      if (WaitForSingleObject(event, 0xffffffff).value != 0) {
        throw StateError('OWNERSHIP_UNAVAILABLE');
      }
    } catch (_) {
      reply.send('OWNERSHIP_UNAVAILABLE');
    } finally {
      var cleaned = true;
      if (owned && mutex != null) {
        cleaned = _releaseMutex(mutex) != 0;
      }
      if (mutex != null) {
        cleaned = CloseHandle(mutex).value && cleaned;
      }
      security?.close();
      calloc.free(input);
      (message[4] as SendPort).send(cleaned);
    }
  }
}
