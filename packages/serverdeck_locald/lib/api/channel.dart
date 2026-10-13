import 'dart:async';
import 'dart:typed_data';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/protocol.dart';

import 'auth.dart';
import 'server.dart';

typedef ChannelRead = Future<Uint8List> Function(int count, Duration deadline);
typedef ChannelWrite = Future<void> Function(
  List<int> bytes,
  Duration deadline,
);

/// One accepted connection; the owner retains the reusable native pipe slot.
class ServerChannel {
  ServerChannel({
    required this.handshake,
    required this.server,
    required ChannelRead read,
    required ChannelWrite write,
    required Future<void> Function(Duration deadline) drainOutput,
    required Future<void> Function() disconnect,
    Duration Function()? elapsed,
  }) : _read = read,
       _write = write,
       _drainOutput = drainOutput,
       _disconnect = disconnect {
    if (!identical(handshake.sessions, server.sessions)) {
      throw ArgumentError('INVALID_CHANNEL_CONFIGURATION');
    }
    _clock = elapsed ?? () => _watch.elapsed;
  }
  final ServerHandshake handshake;
  final ApiServer server;
  final ChannelRead _read;
  final ChannelWrite _write;
  final Future<void> Function(Duration deadline) _drainOutput;
  final Future<void> Function() _disconnect;
  final _watch = Stopwatch()..start();
  late final Duration Function() _clock;
  final _active = <Future<void>>{};
  Future<void> _writeTail = Future.value();
  Future<void>? _closeFuture;
  bool _started = false, _accepting = true, _closing = false;

  Future<void> run() async {
    if (_started || _closing) throw StateError('SERVICE_UNAVAILABLE');
    _started = true;
    final authenticationDeadline = _clock() + rpcDeadline;
    try {
      final hello = await handshake.hello();
      await _send(
        StrictCodec().encode(hello.toJson()),
        until: authenticationDeadline,
      );
      final authentication = await _frame(
        maxHandshakeBytes,
        authenticationDeadline,
      );
      final grant = await handshake.authenticate(authentication);
      await _send(
        StrictCodec().encode(grant.toJson()),
        until: authenticationDeadline,
      );
      while (_accepting && !_closing) {
        // Includes replies waiting for the single native writer. Backpressure
        // prevents a fast reader from accumulating unbounded response buffers.
        while (_active.length >= maxPendingPerSession && !_closing) {
          await Future.any(_active.toList());
        }
        if (!_accepting || _closing) break;
        final frame = await _frame(maxRequestBytes, _clock() + sessionLease);
        if (!_accepting || _closing) break;
        late final Future<void> operation;
        operation = _dispatch(frame)
            .whenComplete(() => _active.remove(operation));
        operation.ignore();
        _active.add(operation);
      }
      await Future.wait(_active.toList());
    } catch (_) {
      // Framing, authentication, peer, I/O and timeout failures revoke the
      // connection without echo. Durable mutation draining belongs to its owner.
    } finally {
      await close();
      await Future.wait(_active.toList());
    }
  }

  Future<void> _dispatch(List<int> frame) async {
    try {
      final response = await server.handle(handshake.channel, frame);
      if (response.closeChannel) _accepting = false;
      if (!_closing) await _send(response.bytes);
      if (response.closeChannel) {
        if (!_closing) await _drainOutput(rpcDeadline);
        await close();
      }
    } catch (_) {
      await close();
    }
  }

  Future<void> _send(List<int> payload, {Duration? until}) {
    final bytes = frameBytes(payload, maxBytes: maxResponseBytes);
    final operation = _writeTail.then((_) async {
      if (_closing) throw StateError('SERVICE_UNAVAILABLE');
      final remaining = until == null ? rpcDeadline : until - _clock();
      if (remaining <= Duration.zero) throw StateError('TIMEOUT');
      await _write(bytes, remaining);
      if (until != null && _clock() >= until) throw StateError('TIMEOUT');
    });
    operation.ignore();
    _writeTail = operation;
    return operation;
  }

  Future<Uint8List> _frame(int limit, Duration idleDeadline) async {
    final header = Uint8List(4);
    Duration? partialDeadline;
    Future<void> fill(Uint8List target) async {
      var offset = 0;
      while (offset < target.length) {
        if (_closing) throw StateError('SERVICE_UNAVAILABLE');
        final deadline =
            partialDeadline == null || idleDeadline < partialDeadline!
            ? idleDeadline
            : partialDeadline!;
        final remaining = deadline - _clock();
        if (remaining <= Duration.zero) throw StateError('TIMEOUT');
        final count = (target.length - offset).clamp(1, 65536);
        final bytes = await _read(count, remaining);
        if (_clock() >= deadline) throw StateError('TIMEOUT');
        if (bytes.isEmpty || bytes.length > count)
          throw StateError('INVALID_FRAME');
        partialDeadline ??= _clock() + rpcDeadline;
        target.setRange(offset, offset + bytes.length, bytes);
        offset += bytes.length;
      }
    }

    await fill(header);
    final length = ByteData.sublistView(header).getUint32(0, Endian.little);
    if (length == 0 || length > limit) throw StateError('INVALID_FRAME');
    final payload = Uint8List(length);
    await fill(payload);
    return payload;
  }

  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    completion.future.ignore();
    _close().then(completion.complete, onError: completion.completeError);
    return completion.future;
  }

  Future<void> _close() async {
    _closing = true;
    _accepting = false;
    handshake.close();
    server.sessions.disconnect(handshake.channel);
    try {
      // Native disconnect cancels and drains the outstanding overlapped read.
      await _disconnect();
    } catch (_) {
      throw StateError('SERVICE_UNAVAILABLE');
    } finally {
      _watch.stop();
    }
  }
}
