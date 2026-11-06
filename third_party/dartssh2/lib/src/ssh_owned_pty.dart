part of 'ssh_client.dart';

/// Only this callback may cross from a plaintext action to an encrypted packet.
/// The application checks current actor/channel/lease immediately before sending.
typedef SSHOwnedPacketSender = Future<void> Function(
  Uint8List payload,
  void Function() guard,
  void Function() committed,
  SSHOwnedPacketWait wait,
);

/// One action deadline and removable cancellation subscription across all waits.
class SSHOwnedPacketWait {
  const SSHOwnedPacketWait(
      {required this.remaining, required this.listenCancelled});
  final Duration Function() remaining;
  final void Function() Function(void Function()) listenCancelled;
}

class SSHOwnedPtyError implements Exception {
  const SSHOwnedPtyError(this.reason);
  final String reason;
  @override
  String toString() => 'Owned PTY $reason';
}

class SSHOwnedPtyCancellation {
  bool _cancelled = false;
  final _listeners = <void Function()>{};
  bool get isCancelled => _cancelled;
  void Function() listen(void Function() callback) {
    if (_cancelled) {
      callback();
      return () {};
    }
    _listeners.add(callback);
    return () => _listeners.remove(callback);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in List.of(_listeners)) {
      callback();
    }
    _listeners.clear();
  }

  void check() {
    if (_cancelled) throw const SSHOwnedPtyError('cancelled');
  }
}

class SSHOwnedPtyOptions {
  const SSHOwnedPtyOptions({
    required this.onData,
    required this.send,
    this.path,
    this.width = 80,
    this.height = 24,
    this.timeout = const Duration(seconds: 15),
    this.monotonicNow,
  });
  final void Function(Uint8List) onData;
  final SSHOwnedPacketSender send;
  final String? path;
  final int width, height;
  final Duration timeout;

  /// Optional synthetic clock for adapter units; production uses Stopwatch.
  final Duration Function()? monotonicNow;
}

enum SSHOwnedWriteStatus { complete, cancelledBeforeSend, outcomeUnknown }

class SSHOwnedWriteResult {
  const SSHOwnedWriteResult(this.acceptedBytes, this.status);
  final int acceptedBytes;
  final SSHOwnedWriteStatus status;
}

class SSHOwnedPtyOperation {
  SSHOwnedPtyOperation._(this._client, this._id, this.options) {
    _opened.future.ignore();
  }
  final SSHClient _client;
  final int _id;
  final SSHOwnedPtyOptions options;
  final _opened = Completer<SSHOwnedPtySession>();
  SSHChannelController? _channel;
  Timer? _timer;
  final _elapsed = Stopwatch();
  Duration _started = Duration.zero;
  Duration get _now => options.monotonicNow?.call() ?? _elapsed.elapsed;
  final _cancellation = SSHOwnedPtyCancellation();
  bool _stopped = false, _openSent = false;
  String? failure;
  int? exitCode;
  Future<SSHOwnedPtySession> get opened => _opened.future;

  void _start() {
    if (options.timeout <= Duration.zero ||
        options.timeout > const Duration(seconds: 15) ||
        options.width < 2 ||
        options.width > 512 ||
        options.height < 1 ||
        options.height > 200) {
      _stop('invalidArgument');
      return;
    }
    _timer = Timer(options.timeout, () => _stop('timeout'));
    _elapsed.start();
    _started = _now;
    unawaited(_open());
  }

  void _check() {
    if (_stopped || _client.isClosed) throw const SSHOwnedPtyError('cancelled');
  }

  Future<void> _send(SSHMessage message,
      {void Function()? guard,
      void Function()? committed,
      SSHOwnedPacketWait? wait}) {
    final payload = message.encode();
    final started = _opened.isCompleted ? _now : _started;
    final timeout =
        _opened.isCompleted ? const Duration(seconds: 15) : options.timeout;
    final control = wait ??
        SSHOwnedPacketWait(
            remaining: () => timeout - (_now - started),
            listenCancelled: _cancellation.listen);
    return options.send(payload, () {
      _check();
      if (control.remaining() <= Duration.zero)
        throw const SSHOwnedPtyError('timeout');
      guard?.call();
    }, committed ?? () {}, control);
  }

  Future<void> _open() async {
    final reply = _client._pendingChannelOpens.wait(_id);
    reply.ignore();
    try {
      await _send(
          SSH_Message_Channel_Open.session(
            senderChannel: _id,
            initialWindowSize: 65536,
            maximumPacketSize: 32768,
          ), committed: () {
        _openSent = true;
      });
      _check();
      final channel = await reply;
      _check();
      if (!await channel
          .ownedRequest(() => _send(SSH_Message_Channel_Request.pty(
                recipientChannel: channel.remoteId,
                termType: 'xterm-256color',
                termWidth: options.width,
                termHeight: options.height,
                termPixelWidth: 0,
                termPixelHeight: 0,
                termModes: Uint8List(0),
                wantReply: true,
              )))) throw const SSHOwnedPtyError('ptyDenied');
      _check();
      final path = options.path;
      final request = path == null
          ? SSH_Message_Channel_Request.shell(
              recipientChannel: channel.remoteId, wantReply: true)
          : SSH_Message_Channel_Request.exec(
              recipientChannel: channel.remoteId,
              wantReply: true,
              command: "exec '${path.replaceAll("'", "'\\''")}'");
      if (!await channel.ownedRequest(() => _send(request))) {
        throw const SSHOwnedPtyError('shellDenied');
      }
      _check();
      _timer?.cancel();
      _opened.complete(SSHOwnedPtySession._(this, channel));
    } catch (error) {
      _stop(error is SSHOwnedPtyError ? error.reason : 'unavailable');
    }
  }

  void _accept(SSHChannelController channel) {
    _channel = channel;
    if (channel.remoteMaximumPacketSize <= 0) {
      _stop('invalidPacketSize');
      return;
    }
    if (_stopped) {
      channel.destroy();
      return;
    }
    channel.channel.setRequestHandler((request) {
      if (request.requestType == SSHChannelRequestType.exitStatus) {
        exitCode = request.exitStatus;
        return true;
      }
      return false;
    });
  }

  void _data(SSHChannelData data) {
    if (_stopped) return;
    try {
      options.onData(data.bytes);
    } catch (_) {
      _stop('outputLimit');
    }
  }

  void cancel() => _stop('cancelled');
  void _stop(String reason) {
    if (_stopped) return;
    _stopped = true;
    _cancellation.cancel();
    failure = reason;
    _timer?.cancel();
    if (!_opened.isCompleted) _opened.completeError(SSHOwnedPtyError(reason));
    _channel?.destroy();
    if (!_openSent && _channel == null) {
      _client._pendingChannelOpens.fail(_id, SSHOwnedPtyError(reason));
      _client._channelIdAllocator.release(_id);
      _client._ownedPtys.remove(_id);
    }
  }
}

/// Intentionally has no stdin, raw channel, exec or legacy upload sink.
class SSHOwnedPtySession {
  SSHOwnedPtySession._(this._operation, this._channel);
  final SSHOwnedPtyOperation _operation;
  final SSHChannelController _channel;
  bool _writing = false;
  int? get exitCode => _operation.exitCode;
  String? get failure => _operation.failure;
  Future<void> get streamsDone => _channel.channel.done;
  bool get isClosed => _operation._stopped || _channel.ownedClosed;
  void abort() => _operation.cancel();

  Future<SSHOwnedWriteResult> sendGuardedData(
    Uint8List bytes, {
    required void Function() guard,
    required SSHOwnedPtyCancellation cancellation,
  }) async {
    if (bytes.isEmpty || bytes.length > 65536)
      throw const SSHOwnedPtyError('inputLimit');
    if (_writing) throw const SSHOwnedPtyError('inputBusy');
    _writing = true;
    var accepted = 0;
    final started = _operation._now;
    Duration elapsed() => _operation._now - started;
    void check() {
      cancellation.check();
      if (elapsed() >= const Duration(seconds: 15))
        throw const SSHOwnedPtyError('timeout');
      _operation._check();
      if (_channel.ownedClosed) throw const SSHOwnedPtyError('closed');
      guard();
    }

    final wait = SSHOwnedPacketWait(
        remaining: () => const Duration(seconds: 15) - elapsed(),
        listenCancelled: (wake) {
          final offAction = cancellation.listen(wake);
          final offChannel = _operation._cancellation.listen(wake);
          return () {
            offAction();
            offChannel();
          };
        });

    try {
      while (accepted < bytes.length) {
        check();
        if (elapsed() >= const Duration(seconds: 15)) {
          throw const SSHOwnedPtyError('timeout');
        }
        if (_channel.ownedRemoteWindow <= 0) {
          await _waitCredit(
              cancellation, const Duration(seconds: 15) - elapsed());
          continue;
        }
        final count = [
          bytes.length - accepted,
          _channel.ownedRemoteWindow,
          _channel.remoteMaximumPacketSize,
          32768
        ].reduce((a, b) => a < b ? a : b);
        if (count <= 0) throw const SSHOwnedPtyError('invalidPacketSize');
        final chunk = Uint8List.sublistView(bytes, accepted, accepted + count);
        await _operation._send(
            SSH_Message_Channel_Data(
              recipientChannel: _channel.remoteId,
              data: chunk,
            ),
            guard: check,
            wait: wait, committed: () {
          _channel.commitOwnedWindow(count);
          accepted += count;
        });
      }
      return SSHOwnedWriteResult(accepted, SSHOwnedWriteStatus.complete);
    } catch (_) {
      return SSHOwnedWriteResult(
          accepted,
          accepted == 0
              ? SSHOwnedWriteStatus.cancelledBeforeSend
              : SSHOwnedWriteStatus.outcomeUnknown);
    } finally {
      _writing = false;
    }
  }

  Future<void> _waitCredit(
      SSHOwnedPtyCancellation cancellation, Duration remaining) async {
    if (remaining <= Duration.zero) throw const SSHOwnedPtyError('timeout');
    final result = Completer<void>();
    void wake() {
      if (!result.isCompleted) result.complete();
    }

    final off = _channel.listenOwnedWindow(wake);
    final cancel = cancellation.listen(wake);
    final timer = Timer(remaining, () {
      if (!result.isCompleted)
        result.completeError(const SSHOwnedPtyError('timeout'));
    });
    try {
      if (_channel.ownedRemoteWindow > 0 ||
          _channel.ownedClosed ||
          cancellation.isCancelled) wake();
      await result.future;
    } finally {
      off();
      cancel();
      timer.cancel();
    }
  }

  Future<void> resizeGuarded(
      int width, int height, void Function() guard) async {
    if (width < 2 || width > 512 || height < 1 || height > 200) {
      throw const SSHOwnedPtyError('invalidArgument');
    }
    await _operation._send(
        SSH_Message_Channel_Request.windowChange(
          recipientChannel: _channel.remoteId,
          termWidth: width,
          termHeight: height,
          termPixelWidth: 0,
          termPixelHeight: 0,
        ),
        guard: guard);
  }
}
