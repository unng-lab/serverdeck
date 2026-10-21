import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:io';

import 'pipe.dart';
import 'process.dart';
import 'security.dart';
import 'mcp_build_bundle.dart';
export 'mcp_build_bundle.dart' show BundlePeerRole;

part 'operational_pipe_worker.dart';

/// Only messages cross isolates; native pipe and process handles stay in worker.
class PipeWorker {
  PipeWorker._(
    this._input,
    this._output,
    this._exited,
    this._pending,
    this._operational,
  );
  final SendPort _input;
  final ReceivePort _output;
  final Future<void> _exited;
  final Map<int, Completer<Object?>> _pending;
  final bool _operational;
  int _next = 0;
  bool _closing = false;
  Future<void>? _closeFuture;
  Future<void>? _disconnectFuture;

  static Future<PipeWorker> createServer(String name, String sid) =>
      _start(name, sid, true);
  static Future<PipeWorker> openClient(String name, String sid) =>
      _start(name, sid, false);
  static Future<PipeWorker> createOperationalServer(
    String name,
    String sid,
    String appRoot, {
    bool testOnly = false,
  }) => _start(name, sid, true, appRoot: appRoot, testOnly: testOnly);
  static Future<PipeWorker> openOperationalClient(
    String name,
    String sid,
    String appRoot, {
    bool testOnly = false,
  }) => _start(name, sid, false, appRoot: appRoot, testOnly: testOnly);
  static Future<PipeWorker> _start(
    String name,
    String sid,
    bool server, {
    String? appRoot,
    bool testOnly = false,
  }) async {
    final output = ReceivePort(), done = ReceivePort();
    final pending = <int, Completer<Object?>>{};
    final ready = Completer<SendPort>();
    ready.future.ignore();
    final exited = Completer<void>();
    var spawned = false;
    output.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is List &&
          message.length == 3 &&
          message[0] == 'startupError' &&
          message[2] is SendPort) {
        // Acknowledge the classified failure before the worker exits; separate
        // onExit/output ports must not race away the safe startup error code.
        (message[2] as SendPort).send('startupErrorAck');
        if (!ready.isCompleted)
          ready.completeError(StateError(_safeCode(message[1])));
        return;
      }
      if (message is! List || message.length != 3 || message[0] is! int) return;
      final target = pending.remove(message[0]);
      if (target == null) return;
      if (message[1] == true) {
        target.complete(message[2]);
      } else {
        target.completeError(StateError(_safeCode(message[2])));
      }
    });
    done.listen((_) {
      if (!ready.isCompleted)
        ready.completeError(StateError('SERVICE_UNAVAILABLE'));
      for (final target in pending.values) {
        target.completeError(StateError('SERVICE_UNAVAILABLE'));
      }
      pending.clear();
      output.close();
      done.close();
      if (!exited.isCompleted) exited.complete();
    });
    try {
      await Isolate.spawn(_worker, [
        output.sendPort,
        name,
        sid,
        server,
        if (appRoot != null) {'appRoot': appRoot, 'testOnly': testOnly},
      ], onExit: done.sendPort);
      spawned = true;
      return PipeWorker._(
        await ready.future,
        output,
        exited.future,
        pending,
        appRoot != null,
      );
    } catch (_) {
      if (spawned && appRoot != null) await exited.future;
      output.close();
      done.close();
      rethrow;
    }
  }

  Future<Object?> _call(String method, Object? params) {
    if (_closing && method != 'close') throw StateError('SERVICE_UNAVAILABLE');
    if (_disconnectFuture != null &&
        method != 'disconnect' &&
        method != 'close')
      throw StateError('SERVICE_UNAVAILABLE');
    if (_pending.length >= 3 &&
        method != 'close' &&
        method != 'disconnect' &&
        method != 'peerDisconnect')
      throw StateError('RESOURCE_LIMIT');
    final id = ++_next;
    final result = Completer<Object?>();
    _pending[id] = result;
    _input.send([id, method, params]);
    return result.future;
  }

  Future<void> accept({Duration? deadline}) async =>
      await _call('accept', deadline?.inMilliseconds);
  Future<Uint8List> read({
    int count = 65536,
    Duration deadline = const Duration(seconds: 5),
  }) async =>
      (await _call('read', [count, deadline.inMilliseconds])) as Uint8List;
  Future<void> write(
    List<int> bytes, {
    Duration deadline = const Duration(seconds: 5),
  }) async {
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024 + 4) {
      throw StateError('RESOURCE_LIMIT');
    }
    await _call('write', [Uint8List.fromList(bytes), deadline.inMilliseconds]);
  }

  Future<void> verifyPeer(String sid, String image, String sha256) async =>
      await _call('verify', [sid, image, sha256]);
  Future<OperationalPipePeer> verifyOperationalPeer() async {
    if (!_operational) throw StateError('UNAUTHORIZED');
    final result = (await _call('peerVerify', null)) as List;
    return OperationalPipePeer._(
      this,
      result[0] as int,
      BundlePeerRole.values.singleWhere((r) => r.name == result[1]),
      result[2] as String,
      BundlePeerRole.values.singleWhere((r) => r.name == result[3]),
    );
  }

  Future<void> disconnect() => _disconnectFuture ??= _disconnect();
  Future<void> _disconnect() async {
    // Teardown is admitted independently of the ordinary I/O quota. Repeated
    // callers share one operation; reuse starts only after cancellation drains.
    await _call('disconnect', null);
    _disconnectFuture = null;
  }

  Future<void> drainOutput({
    Duration deadline = const Duration(seconds: 5),
  }) async => await _call('drain', deadline.inMilliseconds);
  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closing = true;
    try {
      await _call('close', null);
    } finally {
      await _exited;
      _output.close();
    }
  }

  static String _safeCode(Object? code) =>
      const {
        'SERVICE_UNAVAILABLE',
        'UNSAFE_ENDPOINT',
        'IDENTITY_UNAVAILABLE',
        'TIMEOUT',
        'RESOURCE_LIMIT',
        'UNAUTHORIZED',
        'INCOMPATIBLE',
        'PREREQUISITE_UNAVAILABLE',
      }.contains(code)
      ? code as String
      : 'SERVICE_UNAVAILABLE';

  static void _worker(List<Object> startup) {
    if (startup.length == 5) {
      _operationalWorker(startup).ignore();
      return;
    }
    final output = startup[0] as SendPort;
    final input = ReceivePort();
    late final NativePipe pipe;
    try {
      pipe = startup[3] == true
          ? NativePipe.createServer(startup[1] as String, startup[2] as String)
          : NativePipe.openClient(startup[1] as String, startup[2] as String);
    } catch (_) {
      input.close();
      return;
    }
    input.listen((message) async {
      if (message is! List || message.length != 3 || message[0] is! int) return;
      final id = message[0] as int, method = message[1];
      final params = message[2];
      try {
        Object? result;
        switch (method) {
          case 'accept':
            await pipe.accept(
              deadline: params == null
                  ? null
                  : Duration(milliseconds: params as int),
            );
          case 'read':
            result = await pipe.read(
              count: params[0] as int,
              deadline: Duration(milliseconds: params[1] as int),
            );
          case 'write':
            await pipe.write(
              params[0] as Uint8List,
              deadline: Duration(milliseconds: params[1] as int),
            );
          case 'verify':
            verifyProcessImage(
              pipe.peerIdentity(),
              params[0] as String,
              params[1] as String,
              params[2] as String,
            );
          case 'disconnect':
            await pipe.disconnect();
          case 'drain':
            await pipe.drainOutput(
              deadline: Duration(milliseconds: params as int),
            );
          case 'close':
            await pipe.close();
          default:
            throw StateError('UNSAFE_ENDPOINT');
        }
        output.send([id, true, result]);
      } catch (error) {
        output.send([
          id,
          false,
          _safeCode(error is StateError ? error.message : null),
        ]);
      } finally {
        if (method == 'close') input.close();
      }
    });
    output.send(input.sendPort);
  }
}

class PipeServerPool {
  PipeServerPool._(this.names, this.slots);
  final List<String> names;
  final List<PipeWorker> slots;
  static Future<PipeServerPool> create(String hash, String sid) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))
      throw StateError('UNSAFE_ENDPOINT');
    final names = List.generate(
      8,
      (slot) => '\\\\.\\pipe\\ServerDeckNext.v1.$hash.$slot',
    );
    final slots = <PipeWorker>[];
    try {
      for (final name in names) {
        slots.add(await PipeWorker.createServer(name, sid));
      }
      return PipeServerPool._(
        List.unmodifiable(names),
        List.unmodifiable(slots),
      );
    } catch (_) {
      await Future.wait(slots.map((slot) => slot.close()));
      rethrow;
    }
  }

  Future<void> close() => Future.wait(slots.map((slot) => slot.close()));
}
