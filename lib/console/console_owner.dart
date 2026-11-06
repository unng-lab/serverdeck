import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/actor.dart';
import '../domain/app_operations.dart';
import '../domain/models.dart';
import '../runtime/capability.dart';
import '../runtime/owned_work.dart';
import '../storage/domain_repository.dart';
import 'console_models.dart';
import 'console_port.dart';
import 'console_operations.dart';
import 'console_replay.dart';
import 'console_history.dart';
import 'terminal_engine.dart';

part 'session.dart';
part 'console_access.dart';

/// Application-owned sessions survive renderer detach, navigation and tray.
final class ConsoleOwner
    implements Listenable, RuntimeCapability, ConsoleOperations {
  ConsoleOwner({
    required this.actors,
    required this.gate,
    required this.state,
    required this.repository,
    required this.connections,
    required this.configuration,
    required this.newId,
    Duration Function()? monotonicNow,
    ScheduleOwnedDeadline? schedule,
  }) : _monotonic = monotonicNow,
       _schedule = schedule ?? _timer {
    _subscription = connections.consoleInvalidations.listen(_invalidated);
  }
  final ActorAuthority actors;
  final DomainCommandGate gate;
  final OperationState state;
  final DomainRepository repository;
  final ConsoleConnectionPort connections;
  final ConsoleConfiguration Function() configuration;
  final String Function() newId;
  final Duration Function()? _monotonic;
  final ScheduleOwnedDeadline _schedule;
  final _clock = Stopwatch()..start();
  late final _replay = ConsoleReplayBook(actors.ownerEpoch);
  final _notifier = _ConsoleNotifier();
  final _sessions = <String, _ConsoleSession>{};
  final _selectedSessions = <String, String>{};
  final _visible = <String>{};
  final _pending = <Future<void>>{};
  StreamSubscription<ConsoleInvalidation>? _subscription;
  bool _stopped = false, _disposed = false, _keyboardActive = true;
  OperationFailure? lastFailure;
  Duration get now => _monotonic?.call() ?? _clock.elapsed;
  @override
  String get id => 'console';
  @override
  void addListener(VoidCallback listener) => _notifier.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      _notifier.removeListener(listener);
  void _notify() {
    if (!_disposed) _notifier.changed();
  }

  void configurationChanged() => _notify();
  static void Function() _timer(Duration duration, void Function() callback) {
    final timer = Timer(duration, callback);
    return timer.cancel;
  }

  void _track(Future<void> pending) {
    final handled = pending.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _pending.add(handled);
    handled.whenComplete(() => _pending.remove(handled));
  }

  void _checkCaller(ConsoleCaller caller) {
    if (_stopped) throw const OperationFailure(FailureCode.shuttingDown);
    if (!actors.owns(caller.actor) || !state.isAuthorizedNow(caller.actor)) {
      throw const OperationFailure(FailureCode.authRequired);
    }
    if (caller.actor case final McpActor mcp) {
      final binding = caller.binding;
      if (binding == null ||
          binding.disconnected.isCancelled ||
          mcp.requestCancelled) {
        throw const OperationFailure(FailureCode.authRequired);
      }
    }
  }

  void _checkBase(_ConsoleSession session) {
    if (_stopped ||
        !identical(_sessions[session.id], session) ||
        !session.acceptsOutput) {
      throw const OperationFailure(FailureCode.consoleInactive);
    }
    session.binding.check();
    session.binding.fence.check(state.versions(session.profileId));
  }

  ConsoleSessionView _view(_ConsoleSession session) => ConsoleSessionView(
    sessionId: session.id,
    profileId: session.profileId,
    generation: session.generation,
    shellProfileId: session.shell.id,
    shellName: session.shell.name,
    state: session.state,
    partial: session.partial,
    historyVersion: session.engine.historyVersion,
    reason: session.reason,
    exitCode: session.exitCode,
    inputOwner: _inputView(session),
  );
  List<ConsoleSessionView> sessionsFor(String profileId) => [
    for (final session in _sessions.values)
      if (session.profileId == profileId) _view(session),
  ];
  ConsoleTerminalEngine? engine(String sessionId) =>
      _sessions[sessionId]?.engine;
  OperationFailure? inputFailure(String sessionId) =>
      _sessions[sessionId]?.inputFailure;
  String? inputOutcome(String sessionId) => _sessions[sessionId]?.inputOutcome;
  String? selectedSession(String profileId) {
    final selected = _selectedSessions[profileId];
    if (selected != null && _sessions[selected]?.profileId == profileId)
      return selected;
    for (final session in _sessions.values) {
      if (session.profileId == profileId)
        return _selectedSessions[profileId] = session.id;
    }
    _selectedSessions.remove(profileId);
    return null;
  }

  void selectSession(String profileId, String? sessionId) {
    if (sessionId != null && _sessions[sessionId]?.profileId == profileId) {
      _selectedSessions[profileId] = sessionId;
    }
  }

  void setKeyboardActive(bool active) {
    _keyboardActive = active;
  }

  void setVisible(String sessionId, bool visible) {
    if (visible)
      _visible.add(sessionId);
    else
      _visible.remove(sessionId);
  }

  Future<OperationResult<ConsoleValue>> listConsoles(
    ConsoleCaller caller,
    String profileId,
  ) => gate.submit(
    caller.actor,
    (context) => context.read(() {
      _checkCaller(caller);
      _sanitizeSessions();
      if (repository.read((r) => r.profile(profileId)) == null) {
        throw const OperationFailure(FailureCode.profileNotFound);
      }
      return ConsoleValue(
        ConsoleSessionsValue(sessionsFor(profileId), _next(caller)),
      );
    }),
  );

  Future<OperationResult<ConsoleValue>> openConsole(
    ConsoleCaller caller,
    String profileId, {
    String? shellProfileId,
    String? ownerEpoch,
    int? operationSequence,
  }) => _mutation(
    caller,
    ownerEpoch,
    operationSequence,
    {'kind': 'open', 'profileId': profileId, 'shellProfileId': shellProfileId},
    () {
      _sanitizeSessions();
      if (!isCanonicalUuid(profileId))
        throw const OperationFailure(FailureCode.invalidArgument);
      if (_sessions.length >= 16 ||
          _sessions.values.where((s) => s.profileId == profileId).length >= 4) {
        throw const OperationFailure(FailureCode.resourceExhausted);
      }
      final settings = configuration();
      final shell = settings.profile(shellProfileId ?? settings.defaultId);
      if (shell == null)
        throw const OperationFailure(FailureCode.invalidArgument);
      final binding = connections.bindConsole(caller.actor, profileId);
      final sessionId = newId();
      final model = ConsoleTerminalEngine(
        onResponse: (text) => _deviceResponse(sessionId, text),
      );
      final session = _ConsoleSession(
        id: sessionId,
        profileId: profileId,
        binding: binding,
        shell: shell,
        creator: caller,
        engine: model,
      );
      _sessions[sessionId] = session;
      final lease = _issue(session, caller);
      model.terminal.onOutput = (text) => _keyboard(session, text);
      session.deadline = _schedule(const Duration(seconds: 15), () {
        if (session.state == 'opening') _terminate(session, 'error', 'timeout');
      });
      session.offCreator = caller.binding?.disconnected.listen(() {
        if (session.state == 'opening')
          _terminate(session, 'error', 'cancelled');
      });
      _track(Future<void>.microtask(() => _start(session)));
      _notify();
      return ConsoleActionValue(
        sessionId: sessionId,
        generation: 1,
        state: 'opening',
        leaseToken: lease.token,
        operationSequence: operationSequence ?? 0,
      );
    },
  );

  Future<void> _start(_ConsoleSession session) async {
    try {
      _checkBase(session);
      _checkCaller(session.creator);
      final opening = session.binding.open(
        path: session.shell.path,
        onData: (bytes) => _output(session, bytes),
        guard: () {
          _checkBase(session);
          if (session.state == 'opening') _checkCaller(session.creator);
        },
      );
      session.opening = opening;
      final channel = await opening.opened;
      if (!identical(_sessions[session.id], session) ||
          session.state != 'opening' ||
          _stopped) {
        channel.abort();
        return;
      }
      _checkBase(session);
      _checkCaller(session.creator);
      session.channel = channel;
      session.state = 'active';
      if (!session.ready.isCompleted) session.ready.complete();
      resizeConsole(
        session.id,
        session.engine.terminal.viewWidth,
        session.engine.terminal.viewHeight,
      );
      session.deadline?.call();
      session.deadline = null;
      session.offCreator?.call();
      session.offCreator = null;
      _track(
        channel.done.then((_) {
          if (!identical(_sessions[session.id], session) ||
              !session.acceptsOutput)
            return;
          session.pendingDone = true;
          _release(session);
          _finishOutput(session);
        }),
      );
      _notify();
    } catch (error) {
      if (session.state == 'opening')
        _terminate(session, 'error', switch (error) {
          ConsoleOpenFailure(:final code) => code.name,
          TimeoutException() => 'timeout',
          OperationFailure(code: FailureCode.authRequired) ||
          WorkCancelled() => 'cancelled',
          _ => 'networkError',
        });
    }
  }

  void _output(_ConsoleSession session, Uint8List bytes) {
    if (!session.acceptsOutput || !identical(_sessions[session.id], session))
      return;
    try {
      _checkBase(session);
    } catch (_) {
      return;
    }
    if (bytes.length > 1048576 - session.rawBytes) {
      _terminate(session, 'error', 'outputLimit');
      return;
    }
    session.raw.addLast(Uint8List.fromList(bytes));
    session.rawBytes += bytes.length;
    if (!session.outputScheduled) {
      session.outputScheduled = true;
      _track(Future<void>.microtask(() => _drainOutput(session)));
    }
  }

  void _drainOutput(_ConsoleSession session) {
    session.outputScheduled = false;
    if (!session.acceptsOutput) return;
    try {
      _checkBase(session);
      var budget = 16384;
      while (session.raw.isNotEmpty && budget > 0) {
        final data = session.raw.removeFirst();
        final take = data.length < budget ? data.length : budget;
        session.engine.feed(Uint8List.sublistView(data, 0, take));
        session.rawBytes -= take;
        budget -= take;
        if (take < data.length)
          session.raw.addFirst(Uint8List.sublistView(data, take));
      }
      if (session.raw.isNotEmpty) {
        session.outputScheduled = true;
        _track(Future<void>.microtask(() => _drainOutput(session)));
      } else
        _finishOutput(session);
      _notify();
    } catch (_) {
      _terminate(session, 'error', 'outputLimit');
    }
  }

  void _finishOutput(_ConsoleSession session) {
    if (!session.pendingDone || session.raw.isNotEmpty) return;
    try {
      session.engine.finish();
    } catch (_) {
      session.partial = true;
    }
    session.exitCode = session.channel?.exitCode;
    session.reason = session.channel?.failure;
    session.state = session.reason == null ? 'ended' : 'error';
    session.partial |= session.reason != null;
    _notify();
  }

  void _cancelInput(_ConsoleSession session) {
    for (final token in List.of(session.inputJobs)) {
      token.cancel();
    }
  }

  void _terminate(
    _ConsoleSession session,
    String status,
    String reason, {
    bool clear = false,
  }) {
    session.state = status;
    session.reason = reason;
    session.partial = true;
    if (!session.ready.isCompleted)
      session.ready.completeError(const WorkCancelled());
    session.deadline?.call();
    session.deadline = null;
    session.offCreator?.call();
    session.offCreator = null;
    _release(session);
    session.raw.clear();
    session.rawBytes = 0;
    session.opening?.cancel();
    session.channel?.abort();
    if (clear) session.engine.clear();
    _notify();
  }

  void _invalidated(ConsoleInvalidation event) {
    for (final session
        in _sessions.values
            .where((s) => s.profileId == event.profileId)
            .toList()) {
      _terminate(
        session,
        'disconnected',
        event.clear ? 'contextChanged' : 'connectionLost',
        clear: event.clear,
      );
    }
  }

  void _keyboard(_ConsoleSession session, String text) {
    if (!_keyboardActive || !_visible.contains(session.id)) return;
    _track(_sendUi(session, Uint8List.fromList(utf8.encode(text))));
  }

  Future<void> _sendUi(_ConsoleSession session, Uint8List bytes) async {
    final caller = ConsoleCaller.ui(actors.ui);
    _ConsoleLease? lease;
    try {
      await gate.prepare(
        caller.actor,
        (context) => context.read(() {
          _checkCaller(caller);
          _checkBase(session);
          if (!session.active ||
              !_keyboardActive ||
              !_visible.contains(session.id)) {
            throw const OperationFailure(FailureCode.consoleInactive);
          }
          lease = _requireLease(session, caller, null, keyboard: true);
        }),
      );
      final work = _enqueueInput(session, bytes, () {
        _checkCaller(caller);
        _checkBase(session);
        _requireLease(session, caller, lease!.token);
        if (!_keyboardActive || !_visible.contains(session.id))
          throw const OperationFailure(FailureCode.conflict);
      });
      _renew(session, lease!);
      final outcome = await work;
      session.inputFailure = null;
      session.inputOutcome = outcome.status;
      _notify();
    } catch (error) {
      session.inputFailure = error is OperationFailure
          ? error
          : const OperationFailure(FailureCode.networkError);
      _notify();
    }
  }

  Future<ConsoleWriteOutcome> _enqueueInput(
    _ConsoleSession session,
    Uint8List bytes,
    void Function() guard,
  ) {
    if (bytes.isEmpty || bytes.length > 65536 - session.inputBytes) {
      throw const OperationFailure(FailureCode.resourceExhausted);
    }
    final token = WorkCancellation();
    final cancelDeadline = _schedule(const Duration(seconds: 15), token.cancel);
    final result = Completer<ConsoleWriteOutcome>();
    session.inputJobs.add(token);
    session.inputBytes += bytes.length;
    session.inputTail = session.inputTail.then((_) async {
      try {
        token.check();
        guard();
        if (session.state == 'opening') await session.ready.future;
        token.check();
        guard();
        final channel = session.channel;
        if (channel == null || !session.active)
          throw const OperationFailure(FailureCode.consoleInactive);
        final outcome = await channel.write(
          bytes,
          guard: () {
            token.check();
            guard();
          },
          cancellation: token,
        );
        result.complete(outcome);
      } catch (_) {
        result.complete(const ConsoleWriteOutcome(0, 'cancelledBeforeSend'));
      } finally {
        cancelDeadline();
        session.inputJobs.remove(token);
        session.inputBytes -= bytes.length;
        bytes.fillRange(0, bytes.length, 0);
      }
    });
    _track(session.inputTail);
    return result.future;
  }

  void _deviceResponse(String sessionId, String text) {
    final session = _sessions[sessionId];
    if (session == null || !session.acceptsOutput) return;
    _track(
      _enqueueInput(
        session,
        Uint8List.fromList(utf8.encode(text)),
        () => _checkBase(session),
      ).then<void>((_) {}),
    );
  }

  @override
  Future<OperationResult<ConsoleValue>> consoleProfiles(ConsoleCaller caller) =>
      gate.submit(
        caller.actor,
        (context) => context.read(() {
          _checkCaller(caller);
          return ConsoleValue(
            ConsoleProfilesValue(configuration(), _next(caller)),
          );
        }),
      );

  @override
  Future<OperationResult<ConsoleValue>> readConsole(
    ConsoleCaller caller,
    String profileId,
    String sessionId, {
    required int generation,
    String? cursor,
    int limit = 1000,
  }) => gate.submit(
    caller.actor,
    (context) => context.read(() {
      _checkCaller(caller);
      final session = _target(profileId, sessionId, generation);
      return ConsoleValue(
        consoleHistoryPage(
          actors.ownerEpoch,
          _view(session),
          session.engine,
          cursor: cursor,
          limit: limit,
        ),
      );
    }),
  );

  @override
  Future<OperationResult<ConsoleValue>> acquireConsole(
    ConsoleCaller caller,
    String profileId,
    String sessionId, {
    required int generation,
    String? ownerEpoch,
    int? operationSequence,
  }) => _mutation(
    caller,
    ownerEpoch,
    operationSequence,
    {
      'kind': 'acquire',
      'profileId': profileId,
      'sessionId': sessionId,
      'generation': generation,
    },
    () {
      final session = _target(profileId, sessionId, generation);
      _checkBase(session);
      if (!session.active && session.state != 'opening')
        throw const OperationFailure(FailureCode.consoleInactive);
      var lease = _lease(session);
      if (lease != null &&
          !identical(lease.binding, caller.binding) &&
          caller.actor is! UiActor) {
        throw const OperationFailure(FailureCode.consoleInputBusy);
      }
      if (lease == null || !identical(lease.binding, caller.binding))
        lease = _issue(session, caller);
      _notify();
      return ConsoleActionValue(
        sessionId: sessionId,
        generation: generation,
        state: session.state,
        leaseToken: lease.token,
        operationSequence: operationSequence ?? 0,
      );
    },
  );

  @override
  Future<OperationResult<ConsoleValue>> releaseConsole(
    ConsoleCaller caller,
    String profileId,
    String sessionId, {
    required int generation,
    required String leaseToken,
    String? ownerEpoch,
    int? operationSequence,
  }) => _mutation(
    caller,
    ownerEpoch,
    operationSequence,
    {
      'kind': 'release',
      'profileId': profileId,
      'sessionId': sessionId,
      'generation': generation,
      'leaseToken': leaseToken,
    },
    () {
      final session = _target(profileId, sessionId, generation);
      _requireLease(session, caller, leaseToken);
      _release(session);
      _notify();
      return ConsoleActionValue(
        sessionId: sessionId,
        generation: generation,
        state: session.state,
        status: 'complete',
        operationSequence: operationSequence ?? 0,
      );
    },
  );

  @override
  void disconnectBinding(ConsoleMcpBinding binding) {
    binding.close();
    for (final session in _sessions.values.toList()) {
      if (identical(session.creator.binding, binding) &&
          session.state == 'opening') {
        _terminate(session, 'error', 'cancelled');
      } else if (identical(session.lease?.binding, binding)) {
        _release(session);
      }
    }
    _notify();
  }

  @override
  void invalidateClient(String clientId) {
    for (final session in _sessions.values.toList()) {
      if (session.creator.binding?.actor.clientId == clientId &&
          session.state == 'opening') {
        _terminate(session, 'error', 'cancelled');
      } else if (session.lease?.binding?.actor.clientId == clientId) {
        _release(session);
      }
    }
    _notify();
  }

  String? uiLeaseToken(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) return null;
    final lease = _lease(session);
    return lease?.binding == null ? lease?.token : null;
  }

  Future<String> claimUiInput(String sessionId) => gate.prepare(
    actors.ui,
    (context) => context.read(() {
      final caller = ConsoleCaller.ui(actors.ui);
      _checkCaller(caller);
      final session = _sessions[sessionId];
      if (session == null ||
          !session.active ||
          !_visible.contains(sessionId) ||
          !_keyboardActive) {
        throw const OperationFailure(FailureCode.consoleInactive);
      }
      return _requireLease(session, caller, null, keyboard: true).token;
    }),
  );

  Future<OperationResult<ConsoleValue>> closeConsole(
    ConsoleCaller caller,
    String profileId,
    String sessionId, {
    required int generation,
    bool confirmed = false,
    String? leaseToken,
    String? ownerEpoch,
    int? operationSequence,
  }) => _mutation(
    caller,
    ownerEpoch,
    operationSequence,
    {
      'kind': 'close',
      'profileId': profileId,
      'sessionId': sessionId,
      'generation': generation,
      'leaseToken': leaseToken,
      'confirmed': confirmed,
    },
    () {
      final session = _target(profileId, sessionId, generation);
      if (session.active || session.state == 'opening') {
        _requireLease(session, caller, leaseToken);
        if (!confirmed)
          throw const OperationFailure(FailureCode.invalidArgument);
      }
      _terminate(session, 'closed', 'closed', clear: true);
      _sessions.remove(sessionId);
      _visible.remove(sessionId);
      _notify();
      return ConsoleActionValue(
        sessionId: sessionId,
        generation: generation,
        state: 'closed',
        status: 'complete',
        operationSequence: operationSequence ?? 0,
      );
    },
  );
  _ConsoleSession _target(String profileId, String sessionId, int generation) {
    _sanitizeSessions();
    final session = _sessions[sessionId];
    if (session == null || session.profileId != profileId)
      throw const OperationFailure(FailureCode.consoleNotFound);
    if (session.generation != generation)
      throw const OperationFailure(FailureCode.conflict);
    return session;
  }

  @override
  Future<OperationResult<ConsoleValue>> writeConsole(
    ConsoleCaller caller,
    String profileId,
    String sessionId, {
    required int generation,
    String? leaseToken,
    String? text,
    String? key,
    bool confirmedMultiline = false,
    String? ownerEpoch,
    int? operationSequence,
  }) => _mutation(
    caller,
    ownerEpoch,
    operationSequence,
    {
      'kind': 'write',
      'profileId': profileId,
      'sessionId': sessionId,
      'generation': generation,
      'leaseToken': leaseToken,
      'text': text,
      'key': key,
      'confirmedMultiline': confirmedMultiline,
    },
    () {
      final session = _target(profileId, sessionId, generation);
      _checkBase(session);
      if (!session.active)
        throw const OperationFailure(FailureCode.consoleInactive);
      final lease = _requireLease(session, caller, leaseToken);
      if (caller.actor is UiActor &&
          (!_keyboardActive || !_visible.contains(sessionId))) {
        throw const OperationFailure(FailureCode.conflict);
      }
      if ((text == null) == (key == null))
        throw const OperationFailure(FailureCode.invalidArgument);
      if (text != null &&
          (text.isEmpty ||
              !_validInputUnicode(text) ||
              utf8.encode(text).length > 65536 ||
              ((text.contains('\n') || text.contains('\r')) &&
                  !confirmedMultiline))) {
        throw const OperationFailure(FailureCode.invalidArgument);
      }
      Uint8List bytes;
      try {
        bytes = text != null
            ? session.engine.encodeText(text)
            : session.engine.encodeKey(key!);
      } catch (_) {
        throw const OperationFailure(FailureCode.invalidArgument);
      }
      final work = _enqueueInput(session, bytes, () {
        _checkCaller(caller);
        _checkBase(session);
        _requireLease(session, caller, lease.token);
        if (caller.actor is UiActor &&
            (!_keyboardActive || !_visible.contains(sessionId))) {
          throw const OperationFailure(FailureCode.conflict);
        }
      });
      _renew(session, lease);
      return work.then(
        (outcome) => ConsoleActionValue(
          sessionId: sessionId,
          generation: generation,
          state: _sessions[sessionId]?.state ?? 'closed',
          status: outcome.status,
          acceptedBytes: outcome.acceptedBytes,
          operationSequence: operationSequence ?? 0,
        ),
      );
    },
  );

  static bool _validInputUnicode(String text) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= text.length) return false;
        final low = text.codeUnitAt(i);
        if (low < 0xdc00 || low > 0xdfff) return false;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        return false;
      }
    }
    return true;
  }

  void resizeConsole(String sessionId, int columns, int rows) {
    final session = _sessions[sessionId];
    if (session == null ||
        !session.active ||
        !_visible.contains(sessionId) ||
        !_keyboardActive)
      return;
    session.pendingResize = (columns.clamp(2, 512), rows.clamp(1, 200));
    if (session.resizing) return;
    session.resizing = true;
    _track(() async {
      try {
        while (session.pendingResize != null) {
          final size = session.pendingResize!;
          session.pendingResize = null;
          await session.channel!.resize(size.$1, size.$2, () {
            _checkBase(session);
            if (!_visible.contains(sessionId) || !_keyboardActive) {
              throw const OperationFailure(FailureCode.conflict);
            }
          });
        }
      } catch (_) {
        session.pendingResize = null;
      } finally {
        session.resizing = false;
      }
    }());
  }

  @override
  Future<void> stopAdmission() async {
    _stopped = true;
    for (final s in _sessions.values) _cancelInput(s);
  }

  @override
  Future<void> cancelPending() async {
    for (final s
        in _sessions.values.where((s) => s.state == 'opening').toList())
      _terminate(s, 'error', 'cancelled');
  }

  @override
  Future<void> closeSessions() async {
    for (final s in _sessions.values.toList())
      _terminate(s, 'disconnected', 'shutdown', clear: true);
  }

  @override
  Future<void> drain() async {
    while (_pending.isNotEmpty) await Future.wait(List.of(_pending));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stopAdmission();
    await cancelPending();
    await closeSessions();
    await drain();
    await _subscription?.cancel();
    _disposed = true;
    _notifier.dispose();
  }
}

final class _ConsoleNotifier extends ChangeNotifier {
  void changed() => notifyListeners();
}
