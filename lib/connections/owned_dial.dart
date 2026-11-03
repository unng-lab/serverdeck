import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../domain/models.dart';
import '../runtime/owned_work.dart';

abstract interface class SshDialTask {
  Future<SSHSocket> get socket;

  /// Requests cancellation; socket completion is the acknowledgment.
  void cancel();
}

/// A failed factory must have no live resource. Until it returns a task, the
/// factory owns any platform handle and must deliver it even after cancellation.
typedef BeginSshDial = Future<SshDialTask> Function(String host, int port);

/// Starts synchronously at construction: construct INSIDE the owner's guarded
/// connect-admission effect. Root reserves one of its64 live slots beforehand.
/// No timeout here abandons a pending factory/socket. Owner's30s budget cancels
/// admission and5s cleanup deadline may quarantine this exact object until close.
final class OwnedSshDial {
  OwnedSshDial(String host, int port, {BeginSshDial? begin}) {
    _result.future.ignore();
    Future.sync(() => (begin ?? beginNativeSshDial)(host, port)).then(
      (task) {
        _task = task;
        try {
          _attachSocket();
        } catch (_) {
          _reject();
        }
        _factoryReady.complete();
      },
      onError: (Object _, StackTrace __) {
        _reject();
        _factoryReady.complete();
      },
    );
  }
  final _result = Completer<SSHSocket>();
  final _factoryReady = Completer<void>(), _socketReady = Completer<void>();
  SshDialTask? _task;
  SSHSocket? _socket;
  bool _delivered = false,
      _attached = false,
      _cancelled = false,
      _transferred = false,
      _closed = false;
  Future<void>? _closing;
  Future<SSHSocket> get socket => _result.future;
  bool get transferred => _transferred;

  void _reject() {
    if (!_result.isCompleted)
      _result.completeError(
        const OperationFailure(FailureCode.networkError, retryable: true),
      );
  }

  void _attachSocket() {
    if (_attached) return;
    final future =
        _task!.socket; // A throwing getter retains the task for retry.
    _attached = true;
    future.then(
      (socket) {
        _socket = socket;
        if (!_cancelled && !_result.isCompleted) {
          _delivered = true;
          _result.complete(socket);
        }
        _socketReady.complete();
      },
      onError: (Object _, StackTrace __) {
        _reject();
        _socketReady.complete();
      },
    );
  }

  /// Caller must record the returned exact handle before constructing SSH. Once
  /// transferred, caller owns every close path, including constructor failures.
  SSHSocket takeSocket() {
    if (_cancelled || _transferred || !_delivered || _socket == null)
      throw const WorkCancelled();
    _transferred = true;
    return _socket!;
  }

  Future<void> close() {
    if (_transferred || _closed) return Future<void>.value();
    _cancelled = true;
    if (!_result.isCompleted) _result.completeError(const WorkCancelled());
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      await _factoryReady.future;
      final task = _task;
      if (task == null) {
        _closed = true;
        return;
      }
      if (!_socketReady.isCompleted) task.cancel();
      _attachSocket();
      await _socketReady.future;
      final socket = _socket;
      if (socket != null) {
        try {
          socket.destroy();
        } catch (_) {
          /* close may still confirm cleanup. */
        }
        await socket.close();
        // done confirms the consumer has closed even when it reports an error.
        final done =
            socket.done; // Getter failure is not an exit acknowledgment.
        try {
          await done;
        } catch (_) {}
      }
      _closed = true;
    } catch (_) {
      throw const OperationFailure(
        FailureCode.cleanupRequired,
        retryable: true,
        reason: FailureReason.connectionCleanup,
      );
    } finally {
      _closing = null;
    }
  }
}

Future<SshDialTask> beginNativeSshDial(String host, int port) async =>
    _NativeDialTask(await Socket.startConnect(host, port));

final class _NativeDialTask implements SshDialTask {
  _NativeDialTask(this.task) {
    socket = task.socket.then<SSHSocket>((value) => NativeSshSocket(value));
    socket.ignore();
  }
  final ConnectionTask<Socket> task;
  @override
  late final Future<SSHSocket> socket;
  @override
  void cancel() => task.cancel();
}

/// Thin native component. Tests inject fake DialTask/SSHSocket, never connect.
/// Public to allow a synthetic Socket unit to verify stream/sink/close semantics.
final class NativeSshSocket implements SSHSocket {
  NativeSshSocket(this.socket);
  final Socket socket;
  @override
  Stream<Uint8List> get stream => socket;
  @override
  StreamSink<List<int>> get sink => socket;
  @override
  Future<void> get done => socket.done;
  @override
  Future<void> flush() => socket.flush();
  @override
  Future<void> close() async {
    try {
      try {
        await socket.close();
      } catch (_) {
        // A returned, completed consumer Future can confirm close on reset.
        // A throwing getter provides no such acknowledgment and must propagate.
        final done = socket.done;
        try {
          await done;
        } catch (_) {}
      }
    } catch (_) {
      throw const OperationFailure(
        FailureCode.cleanupRequired,
        retryable: true,
        reason: FailureReason.connectionCleanup,
      );
    }
  }

  @override
  void destroy() => socket.destroy();
}
