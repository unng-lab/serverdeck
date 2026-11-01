part of 'ssh_transport.dart';

/// One finite typed SSH exec, retaining its slot until physical settlement.
final class _SshDirectOperation {
  _SshDirectOperation(
    this.owner,
    this.command,
    this.budget,
    this.beforeDispatch,
    this.dispatchFence,
    this.afterDispatch,
  ) {
    _result.future.ignore();
    _done.future.ignore();
  }
  final _SshOperation owner;
  final DirectSshCommand command;
  final Duration budget;
  final Future<void> Function()? beforeDispatch;
  final void Function()? dispatchFence;
  final void Function()? afterDispatch;
  final _result = Completer<DirectSshOutput>(), _done = Completer<void>();
  final _output = BytesBuilder(copy: false);
  SshIoSession? _session;
  Future<bool>? _sessionDone;
  bool _stopped = false, _drainFailed = false;
  Future<DirectSshOutput> get result => _result.future;
  Future<void> get done => _done.future;

  void _failDrain() {
    if (_drainFailed) return;
    _drainFailed = true;
    if (!_done.isCompleted) {
      _done.completeError(
        const SshTransportFailure(SshTransportCode.SERVICE_UNAVAILABLE),
      );
    }
    stop(SshTransportCode.SERVICE_UNAVAILABLE);
    owner._failIo();
  }

  Future<bool> _observe(Future<void> Function() work) =>
      Future<void>.sync(work).then(
        (_) => true,
        onError: (Object _, StackTrace __) {
          _failDrain();
          return false;
        },
      );

  void _close() {
    try {
      _session?.close();
    } catch (_) {
      _failDrain();
    }
  }

  void stop(SshTransportCode code) {
    if (_stopped) return;
    _stopped = true;
    if (!_result.isCompleted) {
      _result.completeError(SshTransportFailure(code));
    }
    _close();
  }

  Future<void> run() async {
    final timer = Timer(budget, () => stop(SshTransportCode.TIMEOUT));
    StreamSubscription<Uint8List>? output, errors;
    final outputDone = Completer<void>(), errorsDone = Completer<void>();
    var truncated = false;
    try {
      final session = _session = await owner._client!.execute(
        SshIoCommand.direct(command),
      );
      _sessionDone = _observe(() => session.done);
      if (_stopped || owner._stopped) _close();
      output = session.stdout.listen(
        (chunk) {
          final left = command.outputLimit - _output.length;
          if (left > 0) {
            _output.add(
              chunk.length > left
                  ? Uint8List.sublistView(chunk, 0, left)
                  : chunk,
            );
          }
          if (chunk.length > left) {
            truncated = true;
            _close();
          }
        },
        onDone: () {
          if (!outputDone.isCompleted) outputDone.complete();
        },
        onError: (Object _) {
          if (!outputDone.isCompleted) outputDone.complete();
          stop(SshTransportCode.CONNECTION_FAILED);
        },
      );
      errors = session.stderr.listen(
        (_) {},
        onDone: () {
          if (!errorsDone.isCompleted) errorsDone.complete();
        },
        onError: (Object _) {
          if (!errorsDone.isCompleted) errorsDone.complete();
          stop(SshTransportCode.CONNECTION_FAILED);
        },
      );
      if (!_stopped && !owner._stopped) await beforeDispatch?.call();
      if (!_stopped && !owner._stopped) dispatchFence?.call();
      if (!_stopped && !owner._stopped) {
        session.stdin.add(Uint8List.fromList(utf8.encode(command.script)));
        afterDispatch?.call();
      }
      if (!await _observe(() => session.stdin.close())) return;
      if (!await _sessionDone!) return;
      await Future.wait([outputDone.future, errorsDone.future]);
      if (!_result.isCompleted) {
        final captured = _output.takeBytes();
        final bytes =
            command.privileged &&
                !truncated &&
                captured.isEmpty &&
                session.exitCode == 1
            ? utf8.encode('SDSSH_ERROR\tFORBIDDEN\n')
            : captured;
        _result.complete(
          DirectSshOutput(
            bytes,
            exitCode: session.exitCode,
            truncated: truncated,
          ),
        );
      }
    } catch (_) {
      if (!_result.isCompleted) {
        _result.completeError(
          const SshTransportFailure(SshTransportCode.CONNECTION_FAILED),
        );
      }
    } finally {
      timer.cancel();
      _close();
      final drained = await _observe(() async {
        final results = await Future.wait<bool>([
          if (output != null) _observe(output.cancel),
          if (errors != null) _observe(errors.cancel),
          if (_sessionDone != null) _sessionDone!,
        ]);
        if (results.any((ok) => !ok)) {
          throw const SshTransportFailure(SshTransportCode.SERVICE_UNAVAILABLE);
        }
      });
      _output.clear();
      if (!drained || owner._ioFailed) {
        _failDrain();
        return;
      }
      owner._commands.remove(this);
      _done.complete();
    }
  }
}
