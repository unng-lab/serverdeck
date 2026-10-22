import 'dart:async';
import 'dart:typed_data';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/protocol.dart';

import 'operational_auth.dart';
import 'trusted_server.dart';

/// One actual epoch-bound native channel. The pool may reuse its worker only
/// after run/close confirms the physical disconnect barrier.
final class TrustedServerChannel {
  TrustedServerChannel({
    required this.handshake,
    required this.server,
    Duration Function()? elapsed,
  }) {
    if (!identical(handshake.sessions, server.sessions)) {
      throw ArgumentError('INVALID_CHANNEL_CONFIGURATION');
    }
    _clock = elapsed ?? () => _watch.elapsed;
  }
  final TrustedServerHandshake handshake;
  final TrustedApiServer server;
  final _watch = Stopwatch()..start();
  late final Duration Function() _clock;
  final _active = <Future<void>>{};
  Future<void> _writeTail = Future.value();
  Future<void>? _closeFuture;
  TrustedReply? _terminal;
  Duration? _issuedUntil;
  bool _started = false, _accepting = true, _closing = false;
  int _publishing = 0;
  int get activeRequests => _active.length;
  int get pendingPublications => _publishing;

  Duration _remaining(Duration until) {
    if (_closing) throw StateError('SERVICE_UNAVAILABLE');
    final remaining = until - _clock();
    if (remaining <= Duration.zero) throw StateError('TIMEOUT');
    return remaining;
  }

  Future<void> run() async {
    if (_started || _closing) throw StateError('SERVICE_UNAVAILABLE');
    _started = true;
    final until = _clock() + rpcDeadline;
    try {
      await _bootstrapWrite((await handshake.hello()).toJson(), until);
      final authenticate = await _frame(maxHandshakeBytes, until);
      final response = await handshake.authenticate(authenticate);
      await _bootstrapWrite(response.toJson(), until);
      while (_accepting && !_closing) {
        while (_active.length >= maxPendingPerSession &&
            !_closing &&
            _accepting) {
          await Future.any(_active.toList());
        }
        if (!_accepting || _closing) break;
        final frame = await _frame(maxRequestBytes, _clock() + sessionLease);
        if (!_accepting || _closing) break;
        late final Future<void> work;
        work = _dispatch(frame).whenComplete(() => _active.remove(work));
        work.ignore();
        _active.add(work);
      }
      await Future.wait(_active.toList());
    } catch (_) {
      // Invalid/authentication/transport input never echoes or replays an effect.
    } finally {
      await close();
      await Future.wait(_active.toList());
    }
  }

  Future<void> _bootstrapWrite(
    Map<String, Object?> value,
    Duration until,
  ) async {
    final bytes = frameBytes(
      StrictCodec().encode(value, maxBytes: maxHandshakeBytes),
      maxBytes: maxHandshakeBytes,
    );
    final budget = _remaining(until);
    await handshake.peer.revalidate().timeout(budget);
    await handshake.peer.write(bytes, deadline: _remaining(until));
    _remaining(until);
  }

  Future<void> _dispatch(List<int> frame) async {
    final until = _clock() + rpcDeadline;
    TrustedReply? held;
    var abandoned = false;
    final work = server.handle(handshake.channel, frame);
    // Timeout does not cancel actual backend work. A late reply still releases
    // its original reserved request; durable operation ownership is elsewhere.
    work.then<void>((reply) {
      held = reply;
      if (abandoned) reply.release();
    }, onError: (Object _, StackTrace __) {}).ignore();
    try {
      final budget = _remaining(until);
      final reply = await work.timeout(
        budget,
        onTimeout: () {
          abandoned = true;
          held?.release();
          throw StateError('TIMEOUT');
        },
      );
      if (_closing) return;
      if (reply.closeChannel) _accepting = false;
      if (reply.terminal != null) _terminal = reply;
      final writing = _writeTail.then((_) => _publish(reply, until));
      writing.ignore();
      _writeTail = writing;
      _publishing++;
      try {
        await writing;
      } finally {
        _publishing--;
      }
      if (_terminal != null && !identical(_terminal, reply)) return;
      if (reply.closeChannel) {
        await handshake.peer.drainOutput(deadline: _remaining(until));
        await close();
      }
    } catch (error) {
      abandoned = true;
      held?.release();
      if (_terminal != null &&
          !identical(held, _terminal) &&
          error is StateError &&
          error.message == 'UNAUTHORIZED')
        return;
      await close();
    } finally {
      held?.release();
    }
  }

  Future<void> _publish(TrustedReply reply, Duration until) async {
    if (_terminal != null && !identical(_terminal, reply)) return;
    if (reply.terminal != null) {
      await reply.terminal!.write(reply.id, deadline: _remaining(until));
      return;
    }
    final bytes = frameBytes(reply.bytes!, maxBytes: maxResponseBytes);
    while (true) {
      final budget = _remaining(until);
      try {
        await reply.request.revalidate().timeout(budget);
      } catch (_) {
        if (_terminal != null && !identical(_terminal, reply)) return;
        rethrow;
      }
      if (_terminal != null && !identical(_terminal, reply)) return;
      late final Duration original;
      try {
        // This guard and issuing I/O are synchronous; only preparation retries.
        original = reply.request.rpcRemaining;
      } catch (error) {
        if (reply.request.isAuthorityPublicationPause(error)) continue;
        rethrow;
      }
      final outer = _remaining(until);
      _issuedUntil = until;
      await handshake.peer.write(
        bytes,
        deadline: original < outer ? original : outer,
      );
      break;
    }
    _remaining(until);
  }

  Future<Uint8List> _frame(int limit, Duration idleUntil) async {
    Duration? partialUntil;
    Future<Uint8List> fill(int count) async {
      final result = Uint8List(count);
      var offset = 0;
      while (offset < count) {
        final until = partialUntil == null || idleUntil < partialUntil!
            ? idleUntil
            : partialUntil!;
        final bytes = await handshake.peer.read(
          count: (count - offset).clamp(1, 65536),
          deadline: _remaining(until),
        );
        _remaining(until);
        if (bytes.isEmpty || bytes.length > count - offset)
          throw StateError('INVALID_FRAME');
        partialUntil ??= _clock() + rpcDeadline;
        result.setRange(offset, offset + bytes.length, bytes);
        offset += bytes.length;
      }
      return result;
    }

    final header = await fill(4);
    final size = ByteData.sublistView(header).getUint32(0, Endian.little);
    if (size == 0 || size > limit) throw StateError('INVALID_FRAME');
    return fill(size);
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
    Object? failure;
    try {
      handshake.close();
    } catch (error) {
      failure = error;
    }
    // Write completion may leave a committed frame tail in the kernel buffer.
    // Stop/detach eagerly, then allow only its original remaining budget for
    // consumption before disconnect. Ordinary replies do not each drain: a
    // continuously reading peer must still receive all bounded queued replies.
    final until = _issuedUntil;
    if (until != null && until > _clock()) {
      try {
        await handshake.peer.drainOutput(deadline: until - _clock());
      } catch (_) {
        // Abandoned/failed native output has no delivery guarantee. Physical
        // cancellation/disconnect below must still confirm the reuse barrier.
      }
    }
    try {
      await handshake.peer.disconnect();
    } catch (error) {
      failure ??= error;
    } finally {
      _watch.stop();
    }
    if (failure != null) throw StateError('SERVICE_UNAVAILABLE');
  }
}
