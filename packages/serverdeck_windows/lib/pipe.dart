import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'security.dart';
import 'kernel_security.dart';

final _kernel = DynamicLibrary.open('kernel32.dll');
final _queryPipe = DynamicLibrary.open('ntdll.dll')
    .lookupFunction<
      Int32 Function(
        Pointer,
        Pointer<_IoStatus>,
        Pointer<Uint32>,
        Uint32,
        Uint32,
      ),
      int Function(Pointer, Pointer<_IoStatus>, Pointer<Uint32>, int, int)
    >('NtQueryInformationFile');

final class _IoStatus extends Struct {
  @IntPtr()
  external int status;
  @UintPtr()
  external int information;
}

final _createPipe = _kernel
    .lookupFunction<
      Pointer Function(
        Pointer<Utf16>,
        Uint32,
        Uint32,
        Uint32,
        Uint32,
        Uint32,
        Uint32,
        Pointer<SECURITY_ATTRIBUTES>,
      ),
      Pointer Function(
        Pointer<Utf16>,
        int,
        int,
        int,
        int,
        int,
        int,
        Pointer<SECURITY_ATTRIBUTES>,
      )
    >('CreateNamedPipeW');
final _lastError = _kernel.lookupFunction<Uint32 Function(), int Function()>(
  'GetLastError',
);
typedef _NtIoNative = Int32 Function(
  Pointer,
  Pointer,
  Pointer,
  Pointer,
  Pointer<_IoStatus>,
  Pointer<Uint8>,
  Uint32,
  Pointer,
  Pointer,
);
typedef _NtIoDart = int Function(
  Pointer,
  Pointer,
  Pointer,
  Pointer,
  Pointer<_IoStatus>,
  Pointer<Uint8>,
  int,
  Pointer,
  Pointer,
);
final _ntdll = DynamicLibrary.open('ntdll.dll');
final _readIo = _ntdll.lookupFunction<_NtIoNative, _NtIoDart>('NtReadFile');
final _writeIo = _ntdll.lookupFunction<_NtIoNative, _NtIoDart>('NtWriteFile');
final _listenIo = _ntdll
    .lookupFunction<
      Int32 Function(
        Pointer,
        Pointer,
        Pointer,
        Pointer,
        Pointer<_IoStatus>,
        Uint32,
        Pointer,
        Uint32,
        Pointer,
        Uint32,
      ),
      int Function(
        Pointer,
        Pointer,
        Pointer,
        Pointer,
        Pointer<_IoStatus>,
        int,
        Pointer,
        int,
        Pointer,
        int,
      )
    >('NtFsControlFile');
final _waitMany = _kernel
    .lookupFunction<
      Uint32 Function(Uint32, Pointer<Pointer>, Int32, Uint32),
      int Function(int, Pointer<Pointer>, int, int)
    >('WaitForMultipleObjects');
final _serverPid = _kernel
    .lookupFunction<
      Int32 Function(Pointer, Pointer<Uint32>),
      int Function(Pointer, Pointer<Uint32>)
    >('GetNamedPipeServerProcessId');

const _clientRights =
    0x120083; // read/write data and attributes, READ_CONTROL, SYNCHRONIZE.
final _pipeName = RegExp(
  r'^\\\\\.\\pipe\\ServerDeckNext\.v1\.[a-f0-9]{64}\.[0-7]$',
);

/// Owned by a single Dart pipe worker. Never expose its handle to UI code.
class NativePipe {
  NativePipe._(this.handle, this.server);
  final HANDLE handle;
  final bool server;
  final Set<Future<void>> _active = {};
  final Set<int> _cancellations = {};
  bool _closing = false, _closed = false, _reading = false, _writing = false;
  bool _draining = false;
  RetainedProcessIdentity? _peer;
  Future<void>? _closeFuture;

  factory NativePipe.createServer(String name, String sid) {
    if (!_pipeName.hasMatch(name)) {
      throw StateError('UNSAFE_ENDPOINT');
    }
    final attributes = SecurityAttributes(
      'O:${sid}D:P(A;;0x120083;;;$sid)(A;;0x120083;;;SY)',
    );
    final input = name.toNativeUtf16();
    final getError = _lastError;
    HANDLE? created;
    try {
      // Exactly one instance under each of eight separate names.
      created = HANDLE(
        _createPipe(
          input,
          3 | 0x40000000 | 0x80000,
          8,
          1,
          65536,
          65536,
          0,
          attributes.pointer,
        ),
      );
      getError();
      if (!created.isValid) {
        throw StateError('UNSAFE_ENDPOINT');
      }
      requireKernelOwnerAcl(created, sid, '0x120083');
      return NativePipe._(created, true);
    } catch (_) {
      if (created != null && created.isValid) {
        CloseHandle(created);
      }
      rethrow;
    } finally {
      attributes.close();
      calloc.free(input);
    }
  }

  factory NativePipe.openClient(String name, String sid) {
    if (!_pipeName.hasMatch(name)) {
      throw StateError('UNSAFE_ENDPOINT');
    }
    final input = name.toNativeUtf16();
    HANDLE? opened;
    try {
      final result = CreateFile(
        PCWSTR(input),
        _clientRights,
        FILE_SHARE_MODE(0),
        null,
        OPEN_EXISTING,
        FILE_FLAGS_AND_ATTRIBUTES(0x40000000),
        null,
      );
      opened = result.value;
      if (!opened.isValid) {
        throw StateError('SERVICE_UNAVAILABLE');
      }
      requireKernelOwnerAcl(opened, sid, '0x120083');
      return NativePipe._(opened, false);
    } catch (_) {
      if (opened != null && opened.isValid) {
        CloseHandle(opened);
      }
      rethrow;
    } finally {
      calloc.free(input);
    }
  }

  Future<void> accept({Duration? deadline}) async {
    if (!server) {
      throw StateError('UNSAFE_ENDPOINT');
    }
    await _operation('connect', const [], 0, deadline);
  }

  Future<Uint8List> read({
    int count = 65536,
    Duration deadline = const Duration(seconds: 5),
  }) async {
    if (count < 1 || count > 65536 || _reading) {
      throw StateError('RESOURCE_LIMIT');
    }
    _reading = true;
    try {
      return await _operation('read', const [], count, deadline);
    } finally {
      _reading = false;
    }
  }

  Future<void> write(
    List<int> bytes, {
    Duration deadline = const Duration(seconds: 5),
  }) async {
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024 + 4 || _writing) {
      throw StateError('RESOURCE_LIMIT');
    }
    _writing = true;
    try {
      await _operation('write', bytes, bytes.length, deadline);
    } finally {
      _writing = false;
    }
  }

  /// Waits for the peer to consume buffered replies without a synchronous
  /// FlushFileBuffers call that would block this worker's cancellation loop.
  Future<void> drainOutput({Duration deadline = const Duration(seconds: 5)}) {
    if (!server || _closing || _closed || deadline <= Duration.zero) {
      throw StateError('SERVICE_UNAVAILABLE');
    }
    if (_draining || _active.length >= 3) throw StateError('RESOURCE_LIMIT');
    _draining = true;
    final operation = _drainOutput(deadline)
        .whenComplete(() => _draining = false);
    final guard = operation.then<void>((_) {}, onError: (Object _) {});
    _active.add(guard);
    unawaited(guard.then((_) => _active.remove(guard)));
    return operation;
  }

  Future<void> _drainOutput(Duration deadline) async {
    final watch = Stopwatch()..start();
    while (true) {
      if (_closing || _closed) throw StateError('SERVICE_UNAVAILABLE');
      if (watch.elapsed >= deadline) throw StateError('TIMEOUT');
      final io = calloc<_IoStatus>();
      final info = calloc<Uint32>(10);
      try {
        io.ref.status = 0x103;
        // FilePipeLocalInformation (24), ten ULONG fields. Server end's
        // WriteQuotaAvailable == OutboundQuota means no unread output remains.
        final status = _queryPipe(handle, io, info, 40, 24) & 0xffffffff;
        if (status == 0x103) {
          // Unexpected asynchronous metadata query: cancel and retain buffers
          // until its IO_STATUS_BLOCK is terminal, never free pending native I/O.
          CancelIoEx(handle, null);
          while ((io.ref.status & 0xffffffff) == 0x103) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          throw StateError('SERVICE_UNAVAILABLE');
        }
        if (status != 0 ||
            io.ref.information < 40 ||
            info[9] != 1 ||
            info[8] != 3 ||
            info[7] > info[6]) {
          throw StateError('SERVICE_UNAVAILABLE');
        }
        if (info[7] == info[6]) return;
      } finally {
        calloc.free(info);
        calloc.free(io);
      }
      final remaining = deadline - watch.elapsed;
      if (remaining <= Duration.zero) throw StateError('TIMEOUT');
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 10)
            ? remaining
            : const Duration(milliseconds: 10),
      );
    }
  }

  RetainedProcessIdentity peerIdentity() {
    if (_closing || _closed) {
      throw StateError('IDENTITY_UNAVAILABLE');
    }
    if (_peer != null) {
      _peer!.revalidate();
      return _peer!;
    }
    final processId = calloc<Uint32>();
    try {
      final success = server
          ? GetNamedPipeClientProcessId(handle, processId).value
          : _serverPid(handle, processId) != 0;
      if (!success || processId.value == 0) {
        throw StateError('IDENTITY_UNAVAILABLE');
      }
      return _peer = RetainedProcessIdentity.open(processId.value);
    } finally {
      calloc.free(processId);
    }
  }

  Future<Uint8List> _operation(
    String kind,
    List<int> bytes,
    int count,
    Duration? deadline,
  ) {
    if (_closing || _closed || _active.length >= 3) {
      throw StateError('SERVICE_UNAVAILABLE');
    }
    final operation = _perform(kind, bytes, count, deadline);
    final guard = operation.then<void>((_) {}, onError: (Object _) {});
    _active.add(guard);
    unawaited(
      guard.then((_) {
        _active.remove(guard);
      }),
    );
    return operation;
  }

  Future<Uint8List> _perform(
    String kind,
    List<int> bytes,
    int count,
    Duration? deadline,
  ) async {
    final overlapped = calloc<OVERLAPPED>();
    final transferred = calloc<Uint32>();
    final buffer = calloc<Uint8>(count == 0 ? 1 : count);
    HANDLE? event, cancellation;
    Timer? timer;
    var timedOut = false;
    try {
      final created = CreateEvent(null, true, false, null);
      if (!created.value.isValid) throw StateError('SERVICE_UNAVAILABLE');
      event = created.value;
      final cancel = CreateEvent(null, true, false, null);
      if (!cancel.value.isValid) throw StateError('SERVICE_UNAVAILABLE');
      cancellation = cancel.value;
      _cancellations.add(cancellation.address);
      overlapped.ref.hEvent = event;
      if (bytes.isNotEmpty) buffer.asTypedList(count).setAll(0, bytes);
      if (deadline != null) {
        timer = Timer(deadline, () {
          timedOut = true;
          SetEvent(cancellation!);
        });
      }
      try {
        await _runNativeIo(
          kind,
          handle.address,
          overlapped.address,
          buffer.address,
          count,
          transferred.address,
          event.address,
          cancellation.address,
        );
      } on StateError {
        if (timedOut) throw StateError('TIMEOUT');
        rethrow;
      }
      if (timedOut) throw StateError('TIMEOUT');
      if (transferred.value > count ||
          (kind == 'write' && transferred.value != count)) {
        throw StateError('SERVICE_UNAVAILABLE');
      }
      return kind == 'read'
          ? Uint8List.fromList(buffer.asTypedList(transferred.value))
          : Uint8List(0);
    } finally {
      timer?.cancel();
      if (cancellation != null) {
        _cancellations.remove(cancellation.address);
        CloseHandle(cancellation);
      }
      if (event != null) CloseHandle(event);
      buffer
          .asTypedList(count == 0 ? 1 : count)
          .fillRange(0, count == 0 ? 1 : count, 0);
      calloc.free(buffer);
      calloc.free(overlapped);
      calloc.free(transferred);
    }
  }

  // Keep issuance and completion on one uninterrupted native call stack.
  // Windows cancels I/O when an issuing VM pool thread retires. The caller
  // remains asynchronous and can signal cancellation even before issuance.
  static Future<void> _runNativeIo(
    String kind,
    int handleAddress,
    int overlappedAddress,
    int bufferAddress,
    int count,
    int transferredAddress,
    int eventAddress,
    int cancellationAddress,
  ) => Isolate.run(
    () => _nativeIo(
      kind,
      handleAddress,
      overlappedAddress,
      bufferAddress,
      count,
      transferredAddress,
      eventAddress,
      cancellationAddress,
    ),
  );

  static void _nativeIo(
    String kind,
    int handleAddress,
    int overlappedAddress,
    int bufferAddress,
    int count,
    int transferredAddress,
    int eventAddress,
    int cancellationAddress,
  ) {
    final nativeHandle = HANDLE(Pointer.fromAddress(handleAddress));
    final overlapped = Pointer<OVERLAPPED>.fromAddress(overlappedAddress);
    final buffer = Pointer<Uint8>.fromAddress(bufferAddress);
    final transferred = Pointer<Uint32>.fromAddress(transferredAddress);
    final cancellation = HANDLE(Pointer.fromAddress(cancellationAddress));
    final events = calloc<Pointer>(2);
    var pending = false;
    try {
      if (WaitForSingleObject(cancellation, 0).value == 0)
        throw StateError('SERVICE_UNAVAILABLE');
      final ioStatus = overlapped.cast<_IoStatus>();
      // NT calls may leave IOSB untouched until completion. Win32's drain
      // waits only when Internal is STATUS_PENDING, so initialize it before
      // issuance. The returned NTSTATUS alone still decides whether to wait.
      ioStatus.ref.status = 0x103;
      final event = Pointer.fromAddress(eventAddress);
      // Native NTSTATUS distinguishes queued I/O from immediate failure or
      // an already connected pipe without a second TLS GetLastError call.
      final status = switch (kind) {
        'read' => _readIo(
          nativeHandle,
          event,
          nullptr,
          nullptr,
          ioStatus,
          buffer,
          count,
          nullptr,
          nullptr,
        ),
        'write' => _writeIo(
          nativeHandle,
          event,
          nullptr,
          nullptr,
          ioStatus,
          buffer,
          count,
          nullptr,
          nullptr,
        ),
        _ => _listenIo(
          nativeHandle,
          event,
          nullptr,
          nullptr,
          ioStatus,
          0x110008,
          nullptr,
          0,
          nullptr,
          0,
        ), // FSCTL_PIPE_LISTEN
      };
      if (kind == 'connect' && (status & 0xffffffff) == 0xc00000b2) return;
      if (status == 0x103) {
        pending = true;
        events[0] = event;
        events[1] = Pointer.fromAddress(cancellationAddress);
        final waited = _waitMany(2, events, 0, 0xffffffff);
        if (waited != 0) {
          CancelIoEx(nativeHandle, overlapped);
          GetOverlappedResult(nativeHandle, overlapped, transferred, true);
          pending = false;
          throw StateError('SERVICE_UNAVAILABLE');
        }
        pending =
            false; // The completion event confirms native ownership ended.
        if (ioStatus.ref.status != 0) throw StateError('SERVICE_UNAVAILABLE');
      } else if (status != 0) {
        throw StateError('SERVICE_UNAVAILABLE');
      }
      transferred.value = ioStatus.ref.information;
    } finally {
      if (pending) {
        CancelIoEx(nativeHandle, overlapped);
        GetOverlappedResult(nativeHandle, overlapped, transferred, true);
      }
      calloc.free(events);
    }
  }

  Future<void> disconnect() async {
    if (!server || _closed || _closing) {
      throw StateError('SERVICE_UNAVAILABLE');
    }
    _closing = true;
    for (final address in _cancellations) {
      SetEvent(HANDLE(Pointer.fromAddress(address)));
    }
    CancelIoEx(handle, null);
    await Future.wait(_active.toList());
    _peer?.close();
    _peer = null;
    final result = DisconnectNamedPipe(handle);
    if (!result.value && result.error.toInt() != 233) {
      throw StateError('SERVICE_UNAVAILABLE');
    }
    _closing = false;
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    if (_closed) {
      return;
    }
    _closing = true;
    for (final address in _cancellations) {
      SetEvent(HANDLE(Pointer.fromAddress(address)));
    }
    CancelIoEx(handle, null);
    await Future.wait(_active.toList());
    _peer?.close();
    _peer = null;
    _closed = true;
    CloseHandle(handle);
  }
}
