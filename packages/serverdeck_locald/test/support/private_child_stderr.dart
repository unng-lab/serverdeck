import 'dart:async';

/// Owns a private child stream and its bounded diagnostic prefix.
final class PrivateChildStderr {
  PrivateChildStderr(
    Stream<List<int>> stream,
    void Function(List<int>) forward,
  ) {
    _subscription = stream.listen(
      (chunk) {
        forward(chunk);
        final remaining = maximumCapturedBytes - _captured.length;
        if (remaining > 0) _captured.addAll(chunk.take(remaining));
      },
      onDone: _complete,
      onError: (Object error, StackTrace stack) {
        _error = error;
        _stack = stack;
        _complete();
      },
      cancelOnError: true,
    );
  }

  static const maximumCapturedBytes = 64 * 1024;
  final _captured = <int>[];
  final _done = Completer<void>();
  late final StreamSubscription<List<int>> _subscription;
  Object? _error;
  StackTrace? _stack;
  Future<List<int>>? _draining;

  void _complete() {
    if (!_done.isCompleted) _done.complete();
  }

  Future<List<int>> drain({Duration timeout = const Duration(seconds: 5)}) =>
      _draining ??= _drain(timeout);

  Future<List<int>> _drain(Duration timeout) async {
    try {
      await _done.future.timeout(timeout);
      if (_error case final error?) {
        Error.throwWithStackTrace(error, _stack!);
      }
      return List<int>.unmodifiable(_captured);
    } finally {
      await _subscription.cancel();
    }
  }
}
