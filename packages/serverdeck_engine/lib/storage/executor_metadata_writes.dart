part of 'state_store.dart';

extension ExecutorEnrollments on StateStore {
  Future<Map<String, Object?>?> readExecutorEnrollmentReceipt({
    required String requestId,
    required String method,
    required Map<String, Object?> input,
  }) {
    final command = _enrollmentStore.prepare(
      requestId: requestId,
      method: method,
      input: input,
    );
    return _queueMetadata(() => _enrollmentStore.receipt(command));
  }

  Future<Map<String, Object?>> mutateExecutorEnrollment({
    required String requestId,
    required String method,
    required Map<String, Object?> input,
    required ExecutorEnrollment? enrollment,
    required Future<void> Function() revalidate,
  }) {
    final command = _enrollmentStore.prepare(
      requestId: requestId,
      method: method,
      input: input,
    );
    return _queueMetadata(
      () => _enrollmentStore.mutate(
        command,
        enrollment: enrollment,
        revalidate: revalidate,
      ),
    );
  }

  Future<T> _queueMetadata<T>(Future<T> Function() action) {
    _ensure();
    snapshot;
    if (_closing) throw StateError('NOT_READY');
    if (_pendingAutomation.length + _pendingFoundation >= 32)
      throw StateError('RESOURCE_LIMIT');
    _pendingFoundation++;
    final run = _tail.then((_) async {
      _ensure();
      return action();
    });
    _tail = run.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return run.whenComplete(() => _pendingFoundation--);
  }
}
