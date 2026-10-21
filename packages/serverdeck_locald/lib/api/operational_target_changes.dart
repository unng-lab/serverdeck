part of 'operational_auth.dart';

/// Internal owner-service synchronization; never a wire or authority capability.
final class _TargetChanges {
  _TargetChanges(this.registry, this.gate);
  final OperationalSessions registry;
  final OperationalPublicationGate gate;
  final _interests = <_TargetChangeInterest>{};
  Future<void>? _closeFuture;

  Future<T> runAuthority<T>(
    Future<T> Function() effect,
    Duration deadline,
  ) async {
    if (gate.isClosed) throw StateError('SERVICE_UNAVAILABLE');
    if (deadline <= Duration.zero) throw StateError('TIMEOUT');
    final budget = deadline < rpcDeadline ? deadline : rpcDeadline;
    final watch = Stopwatch()..start();
    OperationalPublicationLease? lease;
    try {
      lease = await gate.acquire(deadline: budget);
      if (watch.elapsed >= budget) throw StateError('TIMEOUT');
      if (registry._stopping) throw StateError('SERVICE_UNAVAILABLE');
      return await effect();
    } finally {
      await lease?.close();
    }
  }

  Future<OperationalTargetChangeLease> begin(Duration deadline) {
    if (gate.isClosed) return Future.error(StateError('SERVICE_UNAVAILABLE'));
    if (deadline <= Duration.zero) return Future.error(StateError('TIMEOUT'));
    if (_interests.length >= 16)
      return Future.error(StateError('RESOURCE_LIMIT'));
    final interest = _TargetChangeInterest(
      this,
      deadline < rpcDeadline ? deadline : rpcDeadline,
    );
    _interests.add(interest);
    interest.run().ignore();
    return interest.result.future;
  }

  void retireMcp() {
    var failed = false;
    for (final entry in registry._sessions.entries.toList()) {
      if (entry.value.role != OperationalRole.mcp) continue;
      try {
        registry.disconnect(entry.key);
      } catch (_) {
        failed = true;
      }
    }
    if (failed) throw StateError('UNAUTHORIZED');
  }

  void finish(_TargetChangeInterest interest) {
    _interests.remove(interest);
    if (!interest.done.isCompleted) interest.done.complete();
  }

  void stop() {
    gate.close().ignore();
  }

  Future<void> close() => _closeFuture ??= Future.wait<void>([
    gate.close(),
    for (final interest in _interests.toList()) interest.done.future,
  ]).then<void>((_) {});
}

final class _TargetChangeInterest {
  _TargetChangeInterest(this.owner, this.budget) {
    result.future.ignore();
    done.future.ignore();
  }
  final _TargetChanges owner;
  final Duration budget;
  final watch = Stopwatch()..start();
  final result = Completer<OperationalTargetChangeLease>();
  final done = Completer<void>();
  OperationalPublicationLease? native;
  Future<void>? _releaseFuture;

  Future<void> run() async {
    var transferred = false;
    try {
      native = await owner.gate.acquire(deadline: budget);
      if (watch.elapsed >= budget) throw StateError('TIMEOUT');
      if (owner.registry._stopping) throw StateError('SERVICE_UNAVAILABLE');
      owner.retireMcp();
      if (watch.elapsed >= budget) throw StateError('TIMEOUT');
      if (owner.registry._stopping) throw StateError('SERVICE_UNAVAILABLE');
      // No await between final retirement and transferring mutation ownership.
      result.complete(OperationalTargetChangeLease._(this));
      transferred = true;
    } catch (error) {
      final code =
          error is StateError &&
              const {
                'TIMEOUT',
                'RESOURCE_LIMIT',
                'UNAUTHORIZED',
                'SERVICE_UNAVAILABLE',
              }.contains(error.message)
          ? error.message
          : 'SERVICE_UNAVAILABLE';
      result.completeError(StateError(code));
      try {
        // A logical acquisition failure can precede its real worker cleanup.
        // This gate is private to this registry's bounded mutation interests.
        // Retain the fence/charge until all current native acquisition work ends.
        while (owner.gate.activeAcquisitions != 0) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        owner.retireMcp();
      } finally {
        await native?.close();
      }
    } finally {
      if (!transferred) owner.finish(this);
    }
  }

  Future<void> release() {
    if (_releaseFuture != null) return _releaseFuture!;
    final completion = Completer<void>();
    _releaseFuture = completion.future;
    completion.future.ignore();
    Future<void>(() async {
      try {
        await native!.close();
      } finally {
        owner.finish(this);
      }
    }).then(
      completion.complete,
      onError: (Object _) =>
          completion.completeError(StateError('SERVICE_UNAVAILABLE')),
    );
    return completion.future;
  }
}

/// Opaque, idempotent mutation lease. The last real release ends its open fence.
/// The service releases only after actual commit/rollback and invalidation.
final class OperationalTargetChangeLease {
  OperationalTargetChangeLease._(this._interest);
  final _TargetChangeInterest _interest;
  Future<void> close() => _interest.release();
}
