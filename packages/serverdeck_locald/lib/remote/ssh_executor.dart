part of 'ssh_transport.dart';

/// Locald-private typed root channel, never returned over owner/MCP wire.
/// Closing a channel does not cancel/kill an already committed root effect.
final class SshExecutorChannel {
  SshExecutorChannel._(this._operation);
  final _SshExecutorOperation _operation;
  Future<void> get done => _operation.done;
  Future<Map<String, Object?>> request(ExecutorRequest request) =>
      _operation.request(request);
  Future<void> close() {
    _operation.stop(SshTransportCode.CANCELLED);
    return done;
  }

  @override
  String toString() => 'SshExecutorChannel';
}

final class _ExecutorPending {
  _ExecutorPending(this.request) {
    result.future.ignore();
  }
  final ExecutorRequest request;
  final result = Completer<Map<String, Object?>>();
  Timer? timer;
}

final class _SshExecutorOperation {
  _SshExecutorOperation(this.owner) {
    _ready.future.ignore();
  }
  final _SshOperation owner;
  final _ready = Completer<SshExecutorChannel>(), _done = Completer<void>();
  SSHSession? _session;
  _ExecutorPending? _pending;
  bool _stopped = false;
  Uint8List _header = Uint8List(4);
  int _headerUsed = 0, _payloadUsed = 0;
  Uint8List? _payload;
  Future<SshExecutorChannel> get ready => _ready.future;
  Future<void> get done => _done.future;

  void stop(SshTransportCode code) {
    if (_stopped) return;
    _stopped = true;
    final error = SshTransportFailure(code);
    if (!_ready.isCompleted) _ready.completeError(error);
    final pending = _pending;
    _pending = null;
    pending?.timer?.cancel();
    if (pending != null && !pending.result.isCompleted)
      pending.result.completeError(error);
    _session?.close();
  }

  Future<Map<String, Object?>> request(ExecutorRequest request) {
    if (_stopped || owner._stopped || _session == null)
      throw const SshTransportFailure(SshTransportCode.SERVICE_UNAVAILABLE);
    if (_pending != null)
      throw const SshTransportFailure(SshTransportCode.RESOURCE_LIMIT);
    final pending = _pending = _ExecutorPending(request);
    pending.timer = Timer(
      const Duration(seconds: 5),
      () => stop(SshTransportCode.TIMEOUT),
    );
    final bytes = request.bytes;
    final header = Uint8List(4);
    ByteData.sublistView(header).setUint32(0, bytes.length, Endian.big);
    try {
      _session!.stdin.add(header);
      _session!.stdin.add(Uint8List.fromList(bytes));
    } catch (_) {
      stop(SshTransportCode.CONNECTION_FAILED);
    }
    return pending.result.future;
  }

  void _receive(Uint8List chunk) {
    if (_stopped) return;
    var offset = 0;
    try {
      while (offset < chunk.length) {
        if (_payload == null) {
          final amount = (4 - _headerUsed).clamp(0, chunk.length - offset);
          _header.setRange(_headerUsed, _headerUsed + amount, chunk, offset);
          _headerUsed += amount;
          offset += amount;
          if (_headerUsed < 4) continue;
          final count = ByteData.sublistView(_header).getUint32(0, Endian.big);
          if (count < 1 || count > 8 * 1024 * 1024)
            throw const FormatException();
          if (_pending == null) throw const FormatException();
          _payload = Uint8List(count);
          _payloadUsed = 0;
        }
        final payload = _payload!;
        final amount = (payload.length - _payloadUsed).clamp(
          0,
          chunk.length - offset,
        );
        payload.setRange(_payloadUsed, _payloadUsed + amount, chunk, offset);
        _payloadUsed += amount;
        offset += amount;
        if (_payloadUsed == payload.length) {
          final pending = _pending;
          if (pending == null) throw const FormatException();
          final document = StrictCodec().decode(
            payload,
            maxBytes: 8 * 1024 * 1024,
          );
          _payload = null;
          _headerUsed = _payloadUsed = 0;
          try {
            final result = captureExecutorResponse(pending.request, document);
            _pending = null;
            pending.timer?.cancel();
            pending.result.complete(result);
          } on ExecutorRemoteError catch (error) {
            _pending = null;
            pending.timer?.cancel();
            pending.result.completeError(error);
          }
        }
      }
    } catch (_) {
      // A malformed/uncorrelated result retires this stream. It is never
      // accepted as authority, raw diagnostic text or a retry instruction.
      stop(SshTransportCode.CONNECTION_FAILED);
    }
  }

  Future<void> run() async {
    final openTimer = Timer(
      const Duration(seconds: 5),
      () => stop(SshTransportCode.TIMEOUT),
    );
    StreamSubscription<Uint8List>? output, errors;
    final outDone = Completer<void>(), errDone = Completer<void>();
    try {
      final session = _session = await owner._client!.execute(
        'sudo -n /usr/libexec/serverdeck-executor-bridge',
      );
      if (_stopped || owner._stopped) session.close();
      output = session.stdout.listen(
        _receive,
        onError: (Object _) {
          if (!outDone.isCompleted) outDone.complete();
          stop(SshTransportCode.CONNECTION_FAILED);
        },
        onDone: () {
          if (!outDone.isCompleted) outDone.complete();
        },
      );
      errors = session.stderr.listen(
        (_) {
          // Never retain or return sudo/module stderr.
        },
        onError: (Object _) {
          if (!errDone.isCompleted) errDone.complete();
        },
        onDone: () {
          if (!errDone.isCompleted) errDone.complete();
        },
      );
      openTimer.cancel();
      if (!_stopped && !owner._stopped)
        _ready.complete(SshExecutorChannel._(this));
      await session.done;
      await Future.wait([outDone.future, errDone.future]);
    } catch (_) {
      stop(SshTransportCode.CONNECTION_FAILED);
    } finally {
      openTimer.cancel();
      stop(SshTransportCode.CONNECTION_FAILED);
      _session?.close();
      await output?.cancel();
      await errors?.cancel();
      if (_session != null) {
        try {
          await _session!.done;
        } catch (_) {}
      }
      _payload = null;
      owner._executors.remove(this);
      _done.complete();
    }
  }
}
