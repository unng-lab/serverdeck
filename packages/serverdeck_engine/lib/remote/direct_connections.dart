part of 'connections.dart';

/// Finite typed execution through the existing session/target registry. The
/// job service separately owns selected consent, durable dispatch and the
/// native authority gate through first SSH write. A command is never authority.
extension DirectConnections on TrustedConnectionService {
  ConnectionDirectWork executeDirectOwner(
    TrustedOwnerReadContext context,
    String profile,
    DirectSshCommand command, {
    void Function()? beforeDispatch,
  }) {
    if (!context.belongsTo(sessions) || command.mutates)
      throw StateError('FORBIDDEN');
    context.remaining;
    return _executeDirect(
      _ConnectionActor.readOwner(context, requireUuid(profile)),
      command,
      beforeDispatch,
    );
  }

  ConnectionDirectWork executeDirectAutomationOwner(
    TrustedOwnerAutomationContext context,
    String profile,
    DirectSshCommand command, {
    void Function()? beforeDispatch,
  }) {
    if (!context.belongsTo(sessions)) throw StateError('FORBIDDEN');
    context.authorizeDirectCommand(command.kind);
    final scope = command.requiresApply ? McpScope.apply : McpScope.read;
    return _executeDirect(
      _ConnectionActor.automation(context, requireUuid(profile), scope),
      command,
      beforeDispatch,
    );
  }

  ConnectionDirectWork executeDirectMcp(
    TrustedMcpContext context,
    String profile,
    DirectSshCommand command, {
    void Function()? beforeDispatch,
  }) {
    if (!context.belongsTo(sessions, authority)) throw StateError('FORBIDDEN');
    requireUuid(profile);
    final scope = command.requiresApply ? McpScope.apply : McpScope.read;
    context.authorize(scope: scope, serverId: profile);
    return _executeDirect(
      _ConnectionActor.read(context, profile, scope),
      command,
      beforeDispatch,
    );
  }

  ConnectionDirectWork _executeDirect(
    _ConnectionActor actor,
    DirectSshCommand command,
    void Function()? beforeDispatch,
  ) {
    _ready();
    if (_workCount >= 48) throw StateError('RESOURCE_LIMIT');
    final work = ConnectionDirectWork._(this, actor, command, beforeDispatch);
    _directWorks.add(work);
    work._run().ignore();
    return work;
  }
}

final class ConnectionDirectValue {
  ConnectionDirectValue._(this.identity, this.output);
  final ConnectionIdentity identity;
  final DirectSshOutput output;
}

/// Actual byte lifetime stays owned through SSH and native proof settlement,
/// including cancellation, detach, target retirement and failed shutdown.
final class ConnectionDirectWork {
  ConnectionDirectWork._(
    this.service,
    this.actor,
    this.command,
    this.beforeDispatch,
  ) {
    _result.future.ignore();
    _done.future.ignore();
    _dispatched.future.ignore();
  }
  final TrustedConnectionService service;
  final _ConnectionActor actor;
  final DirectSshCommand command;
  final void Function()? beforeDispatch;
  final _result = Completer<ConnectionDirectValue>(), _done = Completer<void>();
  final _dispatched = Completer<void>();
  _ConnectionEntry? _entry;
  SshAttempt<DirectSshOutput>? _attempt;
  Object? _dispatchFailure;
  bool _stopped = false;
  Future<ConnectionDirectValue> get result => _result.future;
  Future<void> get done => _done.future;

  /// Only the synchronous first stdin.add boundary, not remote ACK or success.
  /// Physical/native work remains owned by done after this handoff.
  Future<void> get dispatched => _dispatched.future;

  void stop(String code) {
    if (_result.isCompleted) return;
    _stopped = true;
    _attempt?.cancel();
    if (!_dispatched.isCompleted)
      _dispatched.completeError(ConnectionServiceFailure(code));
    _result.completeError(
      ConnectionServiceFailure(
        code,
        boundary: _attempt == null ? 'local' : 'remote',
      ),
    );
  }

  Future<void> cancelInterest() {
    stop('CANCELLED');
    return done;
  }

  void _failedDrain() {
    service._poisoned = true;
    stop('SERVICE_UNAVAILABLE');
    if (!_done.isCompleted) {
      _done.completeError(ConnectionServiceFailure('SERVICE_UNAVAILABLE'));
    }
  }

  void _live() {
    if (_stopped) throw StateError('CANCELLED');
    actor.authorize();
    actor.automationOwner?.authorizeDirectCommand(command.kind);
    if (actor.readOwner != null && command.mutates)
      throw StateError('FORBIDDEN');
    service._ready();
    final entry = _entry;
    if (entry != null) {
      if (entry.state != 'connected' ||
          !entry.attached.containsKey(actor.token)) {
        throw StateError('NOT_READY');
      }
      service._current(entry);
    }
  }

  Future<void> _dispatchProof() async {
    try {
      // The channel may have opened asynchronously since the earlier proof.
      // Revalidate here, then run the exact job/permit continuation immediately
      // before the transport's synchronous stdin.add.
      await actor.proof();
      _live();
    } catch (error) {
      _dispatchFailure = _failure(error);
      rethrow;
    }
  }

  void _dispatchFence() {
    try {
      _live();
      beforeDispatch?.call();
      _live();
    } catch (error) {
      _dispatchFailure = _failure(error);
      rethrow;
    }
  }

  Future<void> _run() async {
    Timer? timer;
    try {
      final left = actor.remaining;
      timer = Timer(
        left < command.maximumDuration ? left : command.maximumDuration,
        () => stop('TIMEOUT'),
      );
      await actor.proof();
      _live();
      service._profile(actor.profile, mcp: actor.mcp != null);
      final entry = _entry = service._entries[actor.profile];
      if (entry == null) throw StateError('NOT_READY');
      _live();
      entry.directs.add(this);
      final attempt = _attempt = entry.lease!.execute(
        command,
        deadline: actor.remaining,
        beforeDispatch: _dispatchProof,
        dispatchFence: _dispatchFence,
        afterDispatch: () {
          if (!_dispatched.isCompleted) _dispatched.complete();
        },
      );
      attempt.settled
          .then<void>(
            (_) {},
            onError: (Object _, StackTrace __) => _failedDrain(),
          )
          .ignore();
      final output = await attempt.result;
      await actor.proof();
      _live();
      _result.complete(ConnectionDirectValue._(entry.identity, output));
    } catch (error) {
      if (!_dispatched.isCompleted)
        _dispatched.completeError(_failure(_dispatchFailure ?? error));
      if (!_result.isCompleted) {
        final failure = _failure(_dispatchFailure ?? error);
        _result.completeError(
          ConnectionServiceFailure(
            failure.message,
            boundary: _attempt == null ? failure.boundary : 'remote',
          ),
        );
      }
    } finally {
      timer?.cancel();
      _attempt?.cancel();
      try {
        await drainOwned([() => _attempt?.settled, () => actor.settled]);
        if (!_done.isCompleted) {
          _entry?.directs.remove(this);
          service._directWorks.remove(this);
          _done.complete();
        }
      } catch (_) {
        _failedDrain();
      }
    }
  }
}
