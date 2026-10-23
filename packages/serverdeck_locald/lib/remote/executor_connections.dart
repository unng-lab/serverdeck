part of 'connections.dart';

/// Native session/target-owned fixed helper stream. Admission/delegation/plan
/// checks remain owned by the job service; no channel or lease crosses the API.
final class ConnectionExecutorWork {
  ConnectionExecutorWork._(this.service, this.actor) {
    _ready.future.ignore();
  }
  final TrustedConnectionService service;
  final _ConnectionActor actor;
  final _ready = Completer<ConnectionExecutorWork>(),
      _done = Completer<void>(),
      _stoppedSignal = Completer<void>();
  _ConnectionEntry? _entry;
  SshAttempt<SshExecutorChannel>? _attempt;
  SshExecutorChannel? _channel;
  bool _stopped = false, _busy = false;
  final _calls = <Future<void>>{};
  Future<ConnectionExecutorWork> get ready => _ready.future;
  Future<void> get done => _done.future;
  Object get principal => actor.token;
  ConnectionIdentity get identity {
    _live();
    return _entry!.identity;
  }

  void stop(String code) {
    if (_stopped) return;
    _stopped = true;
    if (!_ready.isCompleted)
      _ready.completeError(ConnectionServiceFailure(code));
    if (!_stoppedSignal.isCompleted) _stoppedSignal.complete();
    _attempt?.cancel();
  }

  Future<void> close() {
    stop('CANCELLED');
    return done;
  }

  void _live() {
    if (_stopped) throw StateError('CANCELLED');
    actor.authorize();
    service._ready();
    final entry = _entry;
    if (entry == null ||
        entry.state != 'connected' ||
        !entry.attached.containsKey(actor.token))
      throw StateError('NOT_READY');
    service._current(entry);
  }

  Future<Map<String, Object?>> request(ExecutorRequest request) {
    _live();
    if (_channel == null) throw StateError('NOT_READY');
    if (_busy) throw StateError('RESOURCE_LIMIT');
    final scope = switch (request.method) {
      'preflight' || 'preflight_get' || 'recipes' => McpScope.plan,
      'submit' || 'authorize_step' || 'cancel' => McpScope.apply,
      _ => McpScope.read,
    };
    if (actor.mcp != null)
      actor.mcp!.authorize(scope: scope, serverId: actor.profile);
    // Catalog inspection is metadata only. Owner read contexts cannot authorize
    // changes or build plans. A distinct admitted
    // owner plan/job context must be issued by the corresponding owner API.
    if (actor.readOwner != null &&
        scope != McpScope.read &&
        request.method != 'recipes')
      throw StateError('FORBIDDEN');
    actor.automationOwner?.authorizeExecutorMethod(request.method);
    _busy = true;
    final result = _call(request);
    final tracked = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _calls.add(tracked);
    tracked.then<void>((_) {
      _calls.remove(tracked);
      _busy = false;
    }).ignore();
    return result;
  }

  Future<Map<String, Object?>> _call(ExecutorRequest request) async {
    await actor.proof();
    _live();
    Map<String, Object?>? result;
    Object? failure;
    StackTrace? trace;
    try {
      result = await _channel!.request(request);
    } catch (error, stack) {
      failure = error;
      trace = stack;
    }
    await actor.proof();
    _live();
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
    return result!;
  }

  Future<void> _run() async {
    Timer? timer;
    try {
      timer = Timer(actor.remaining, () => stop('TIMEOUT'));
      await actor.proof();
      actor.authorize();
      final entry = _entry = service._entries[actor.profile];
      _live();
      entry!.executors.add(this);
      final attempt = _attempt = entry.lease!.openExecutor();
      final channel = _channel = await attempt.result;
      await actor.proof();
      _live();
      _ready.complete(this);
      await Future.any([channel.done, _stoppedSignal.future]);
    } catch (error) {
      if (!_ready.isCompleted) _ready.completeError(_failure(error));
    } finally {
      timer?.cancel();
      stop('CANCELLED');
      _attempt?.cancel();
      await _attempt?.settled;
      await Future.wait(_calls.toList());
      await actor.settled;
      _entry?.executors.remove(this);
      service._executorWorks.remove(this);
      _done.complete();
    }
  }
}
