part of 'sessions.dart';

sealed class _SessionPeer {
  OperationalRole get role;
  void requireCurrent();
  bool get isCurrent {
    try {
      requireCurrent();
      return true;
    } catch (_) {
      return false;
    }
  }

  String get buildId;
  Future<void> revalidate({
    void Function(Future<void>)? observeNativeCompletion,
  });
  Future<void> write(List<int> bytes, {required Duration deadline}) =>
      Future.error(StateError('FORBIDDEN'));
}

final class _OwnerPeer extends _SessionPeer {
  _OwnerPeer(this.host, this.capability);
  final HostAuthority host;
  final OwnerCapability capability;
  @override
  OperationalRole get role => OperationalRole.owner;
  @override
  String get buildId => host.runtime.buildId;
  @override
  void requireCurrent() {
    if (capability.isRevoked) throw StateError('UNAUTHORIZED');
    host.publicationGate;
  }

  @override
  Future<void> revalidate({
    void Function(Future<void>)? observeNativeCompletion,
  }) => host.validateOwner(
    capability,
    observeNativeCompletion: observeNativeCompletion,
  );
}

final class _McpPeer extends _SessionPeer {
  _McpPeer(this.registry, this.channel) : _epoch = registry._admissionEpoch {
    requireCurrent();
  }
  final EngineSessions registry;
  final int _epoch;
  HostAuthority get host => registry._host;
  final VerifiedMcpChannel channel;
  @override
  OperationalRole get role => OperationalRole.mcp;
  @override
  String get buildId => channel.buildId;
  @override
  void requireCurrent() {
    registry._requireAdmission(_epoch);
    host.publicationGate;
    if (channel.ownerIdentity != host.runtime.ownerIdentity ||
        channel.appRoot != host.runtime.appRoot ||
        channel.buildId != host.runtime.buildId)
      throw StateError('UNAUTHORIZED');
  }

  @override
  Future<void> revalidate({
    void Function(Future<void>)? observeNativeCompletion,
  }) {
    final physical = Completer<void>();
    final owned = <Future<void>>{};
    try {
      registry._ownPeerProof(physical.future);
      // Register ownership of the entire chain before the first phase starts.
      observeNativeCompletion?.call(physical.future);
    } catch (error, stack) {
      physical.complete();
      return Future.error(
        error is StateError && error.message == 'RESOURCE_LIMIT'
            ? error
            : StateError('SERVICE_UNAVAILABLE'),
        stack,
      );
    }
    void own(Future<void> actual, {bool publish = true}) {
      final tracked = actual.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      );
      owned.add(tracked);
      tracked.then<void>((_) {
        owned.remove(tracked);
      }).ignore();
      if (publish) observeNativeCompletion?.call(actual);
    }

    final work = _verify(own);
    work.ignore();
    () async {
      try {
        await work;
      } catch (_) {
        /* Logical result belongs to caller. */
      }
      while (owned.isNotEmpty) await Future.wait<void>(owned.toList());
      physical.complete();
    }().ignore();
    return work;
  }

  Future<void> _verify(void Function(Future<void>, {bool publish}) own) async {
    final watch = Stopwatch()..start();
    Duration remaining() {
      final left = rpcDeadline - watch.elapsed;
      if (left <= Duration.zero) throw StateError('TIMEOUT');
      return left;
    }

    requireCurrent();
    await host.validateRuntime(
      deadline: remaining(),
      observeNativeCompletion: own,
    );
    requireCurrent();
    final actual = channel.revalidate(observeNativeCompletion: own);
    actual.ignore();
    // A provider's logical result is lifetime bookkeeping, not evidence of a
    // physical/native failure. Its observed physical work is published above.
    own(actual, publish: false);
    await actual.timeout(remaining());
    requireCurrent();
    await host.validateRuntime(
      deadline: remaining(),
      observeNativeCompletion: own,
    );
    requireCurrent();
  }

  @override
  Future<void> write(List<int> bytes, {required Duration deadline}) =>
      channel.write(bytes, deadline: deadline);
}
