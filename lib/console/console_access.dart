part of 'console_owner.dart';

final class _ConsoleLease {
  _ConsoleLease(this.token, this.binding, this.expires);
  final String token;
  final ConsoleMcpBinding? binding;
  Duration expires;
  void Function()? deadline;
}

extension _ConsoleAccess on ConsoleOwner {
  int _next(ConsoleCaller caller) => switch (caller.actor) {
    final McpActor mcp => _replay.next(mcp.clientId, mcp.grantVersion),
    _ => 1,
  };

  _ConsoleLease? _lease(_ConsoleSession session) {
    final lease = session.lease;
    if (lease != null &&
        (lease.expires <= now ||
            (lease.binding != null &&
                (lease.binding!.disconnected.isCancelled ||
                    !state.isAuthorizedNow(lease.binding!.actor))))) {
      _release(session);
      return null;
    }
    return lease;
  }

  ConsoleInputView _inputView(_ConsoleSession session) {
    final lease = _lease(session);
    if (lease == null) return const ConsoleInputView('free');
    final binding = lease.binding;
    if (binding == null) return const ConsoleInputView('ui');
    final name = repository.read((r) => r.grant(binding.actor.clientId)?.name);
    return ConsoleInputView(
      'mcp',
      clientId: binding.actor.clientId,
      name: name,
      expiresInMs: (lease.expires - now).inMilliseconds.clamp(0, 60000),
    );
  }

  void _release(_ConsoleSession session) {
    session.lease?.deadline?.call();
    session.lease = null;
    _cancelInput(session);
  }

  _ConsoleLease _issue(_ConsoleSession session, ConsoleCaller caller) {
    _release(session);
    final lease = _ConsoleLease(
      newId(),
      caller.binding,
      now + const Duration(seconds: 60),
    );
    session.lease = lease;
    _renew(session, lease);
    return lease;
  }

  void _renew(_ConsoleSession session, _ConsoleLease lease) {
    lease.expires = now + const Duration(seconds: 60);
    lease.deadline?.call();
    lease.deadline = _schedule(const Duration(seconds: 60), () {
      if (identical(session.lease, lease)) {
        _release(session);
        _notify();
      }
    });
  }

  _ConsoleLease _requireLease(
    _ConsoleSession session,
    ConsoleCaller caller,
    String? token, {
    bool keyboard = false,
  }) {
    var lease = _lease(session);
    if (keyboard && caller.actor is UiActor && lease == null)
      lease = _issue(session, caller);
    if (lease == null ||
        !identical(lease.binding, caller.binding) ||
        (!keyboard && lease.token != token)) {
      throw const OperationFailure(FailureCode.consoleInputBusy);
    }
    return lease;
  }

  Future<OperationResult<ConsoleValue>> _mutation(
    ConsoleCaller caller,
    String? epoch,
    int? sequence,
    Map<String, Object?> payload,
    FutureOr<ConsoleActionValue> Function() start,
  ) async {
    Future<ConsoleActionValue>? work;
    var reserved = false;
    final mcp = caller.actor is McpActor ? caller.actor as McpActor : null;
    final admitted = await gate.submit(
      caller.actor,
      (context) => context.linearize(() {
        _checkCaller(caller);
        if (mcp != null) {
          if (epoch == null || sequence == null)
            throw const OperationFailure(FailureCode.invalidArgument);
          final replay = _replay.begin(
            mcp.clientId,
            mcp.grantVersion,
            epoch,
            sequence,
            payload,
          );
          if (replay != null) return ConsoleValue(replay);
          reserved = true;
        }
        try {
          work = Future<ConsoleActionValue>.value(start());
          work!.ignore();
        } on OperationFailure catch (failure) {
          if (reserved)
            _replay.fail(mcp!.clientId, mcp.grantVersion, sequence!, failure);
          rethrow;
        } catch (_) {
          const failure = OperationFailure(FailureCode.networkError);
          if (reserved)
            _replay.fail(mcp!.clientId, mcp.grantVersion, sequence!, failure);
          throw failure;
        }
        return ConsoleValue(ConsoleSessionsValue(const [], _next(caller)));
      }),
    );
    if (work == null) return admitted;
    ConsoleActionValue? value;
    OperationFailure? failure;
    try {
      value = await work!;
      if (reserved)
        _replay.complete(mcp!.clientId, mcp.grantVersion, sequence!, value);
    } catch (error) {
      failure = error is OperationFailure
          ? error
          : const OperationFailure(FailureCode.networkError);
      if (reserved)
        _replay.fail(mcp!.clientId, mcp.grantVersion, sequence!, failure);
    }
    // Receipt completion is synchronous and precedes response authorization, even
    // if the response was lost, the pipe closed or the grant was revoked.
    if (!admitted.ok) return admitted;
    return gate.submit(
      caller.actor,
      (context) => context.read(() {
        _checkCaller(caller);
        if (failure != null) throw failure;
        return ConsoleValue(value!);
      }),
    );
  }

  void _sanitizeSessions() {
    for (final session in _sessions.values.toList()) {
      final current = state.versions(session.profileId);
      if (current == null) {
        _terminate(session, 'closed', 'contextChanged', clear: true);
        _sessions.remove(session.id);
        _visible.remove(session.id);
        _selectedSessions.remove(session.profileId);
        continue;
      }
      final fence = session.binding.fence;
      if ((fence.endpointId != null &&
              fence.endpointId != current.endpointId) ||
          (fence.credentialRevision != null &&
              fence.credentialRevision != current.credentialRevision) ||
          (fence.connectionRevision != null &&
              fence.connectionRevision != current.connectionRevision) ||
          (fence.trustRevision != null &&
              fence.trustRevision != current.trustRevision) ||
          current.quarantined) {
        if (session.reason != 'contextChanged')
          _terminate(session, 'disconnected', 'contextChanged', clear: true);
      }
    }
  }
}
