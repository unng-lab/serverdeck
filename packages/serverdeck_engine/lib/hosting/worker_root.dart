import 'dart:async';
import 'dart:isolate';

import 'package:serverdeck_protocol/mcp/readiness.dart';

import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../platform/ports.dart';
import '../platform/vm_clock.dart';
import 'engine_host.dart';
import 'capability_snapshot.dart';
import 'in_process_gateway.dart';
import 'worker_power.dart';

/// Spawn-only VM metadata. It has no path, role, owner DTO or credential field.
final class EngineWorkerBoot {
  EngineWorkerBoot(this.control, this.replies, this.expiresAt);
  final Capability control;
  final SendPort replies;
  final int expiresAt;
}

/// Stateful root allocation, not a wire factory. close waits partial creation;
/// native resources transferred to Host must use disposeRuntime before lease.
abstract interface class EngineBootstrap {
  EnginePlatformKind get platformKind;
  Future<EngineHost> create(EngineClock clock);
  Future<void> close();
}

/// VM reply routing is separate from root control authority. The normal adapter
/// accepts SendPort only; RAM adapters use opaque addresses, never a test mode.
abstract interface class WorkerReplyPorts {
  bool accepts(Object? address);
  void send(Object address, Map<String, Object?> frame);
}

final class DartWorkerReplyPorts implements WorkerReplyPorts {
  @override
  bool accepts(Object? address) => address is SendPort;
  @override
  void send(Object address, Map<String, Object?> frame) =>
      (address as SendPort).send(frame);
}

final class _WorkerWindow {
  _WorkerWindow(this.capability, this.reply);
  final Capability capability;
  final Object reply;
  final Object binding = Object();
  final opening = Completer<void>();
  GatewayWorkerBinding? gateway;
  Future<void>? closing;
  bool retiring = false;
}

/// One trusted worker mailbox. Root control and bound calls share its arrival
/// order, but only the spawn-owned VM capability can attach/control the Host.
final class EngineWorkerRoot {
  EngineWorkerRoot({
    required Capability control,
    required EngineBootstrap bootstrap,
    required void Function(Map<String, Object?>) sendControl,
    WorkerReplyPorts? replies,
    EngineClock? clock,
    void Function() Function(Duration, void Function())? schedule,
    void Function()? closedAcknowledged,
  }) : _control = control,
       _bootstrap = bootstrap,
       _sendControl = sendControl,
       _replies = replies ?? DartWorkerReplyPorts(),
       _clock = clock ?? VmEngineClock(),
       _schedule = schedule ?? _timer,
       _closedAcknowledged = closedAcknowledged;
  final Capability _control;
  final EngineBootstrap _bootstrap;
  final void Function(Map<String, Object?>) _sendControl;
  final WorkerReplyPorts _replies;
  final EngineClock _clock;
  final void Function() Function(Duration, void Function()) _schedule;
  void Function()? _cancelPowerDeadline;
  static void Function() _timer(Duration duration, void Function() action) {
    final timer = Timer(duration, action);
    return timer.cancel;
  }

  final void Function()? _closedAcknowledged;
  final _windows = <Capability, _WorkerWindow>{};
  final _controlWork = <Future<void>>{};
  final _reservedControl = <String>{};
  final _detachingControl = <Capability>{};
  final _closeAcks = <int>{};
  EngineHost? _host;
  Future<void>? _startupPhysical;
  Future<Map<String, Object?>>? _starting;
  Completer<Map<String, Object?>>? _startReply;
  Future<HostCloseResult>? _shutdown, _waiting;
  bool _stopping = false,
      _ready = false,
      _closed = false,
      _pipeFailed = false,
      _closeBlocked = false;
  String? _failure;
  bool _workspaceBusy = false;
  int _lastControl = 0;
  final _hostAvailable = Completer<void>();
  WorkerPowerIntent? _power;
  HostPause? _powerPause;
  String? _powerPhase;
  Future<void>? _powerWork;
  bool _hostStarted = false;
  int _powerObserved = 0;

  Map<String, Object?> get status {
    final actual = _host?.readiness;
    final retired =
        _ready && actual?.state != ReadinessState.ready && _powerPhase == null;
    final failure = _failure ?? _host?.failureCode;
    final view = _powerPhase != null && actual?.state == ReadinessState.ready
        ? TrustedReadiness(
            state: ReadinessState.recovering,
            generation: actual!.generation,
          )
        : actual;
    final phase = _closed
        ? 'closed'
        : _stopping
        ? (_closeBlocked ? 'close-blocked' : 'stopping')
        : _workspaceBusy
        ? 'busy'
        : retired || failure != null
        ? 'failed'
        : _powerPhase != null
        ? _powerPhase!
        : _ready
        ? 'ready'
        : 'starting';
    final reason =
        failure ??
        (retired
            ? 'SERVICE_UNAVAILABLE'
            : _powerPhase != null
            ? 'NOT_READY'
            : null);
    final hosted = _host?.capabilities;
    final caps = hosted?.platform == _bootstrap.platformKind
        ? hosted!
        : EngineCapabilities.unavailable(
            _bootstrap.platformKind,
            reason: reason ?? 'NOT_READY',
          );
    return {
      'phase': phase,
      'reason': reason,
      'readiness': view?.toJson(),
      'capabilities':
          (phase == 'ready' ? caps : caps.withdraw(reason ?? 'NOT_READY'))
              .toJson(),
    };
  }

  static String _safe(Object error) {
    if (error is EngineCallFailure) return error.code;
    if (error is TimeoutException) return 'TIMEOUT';
    if (error is StateError &&
        const {
          'STORAGE_BLOCKED',
          'INCOMPATIBLE',
          'PREREQUISITE_UNAVAILABLE',
          'UNAUTHORIZED',
          'RESOURCE_LIMIT',
          'TIMEOUT',
          'NOT_READY',
          'SERVICE_UNAVAILABLE',
        }.contains(error.message))
      return error.message;
    return 'SERVICE_UNAVAILABLE';
  }

  Duration _remaining(int expiresAt, Duration maximum) {
    final remaining = Duration(microseconds: expiresAt) - _clock.elapsed;
    if (remaining <= Duration.zero) throw EngineCallFailure('TIMEOUT');
    if (remaining > maximum) throw EngineCallFailure('VALIDATION');
    return remaining;
  }

  bool _emit(Map<String, Object?> frame) {
    if (_pipeFailed) return false;
    try {
      _sendControl(frame);
      return true;
    } catch (_) {
      _pipeFailed = true;
      shutdown(_clock.elapsed.inMicroseconds + 10000000).ignore();
      return false;
    }
  }

  Future<Map<String, Object?>> start(int expiresAt) {
    if (_starting != null) return _starting!;
    if (_stopping) return Future.value(status);
    final reply = _startReply = Completer<Map<String, Object?>>();
    _starting = reply.future;
    final physical = Completer<void>();
    _startupPhysical = physical.future;
    physical.future.ignore();
    Duration remaining;
    try {
      remaining = _remaining(expiresAt, const Duration(seconds: 30));
    } catch (error) {
      _failure = _safe(error);
      if (!_hostAvailable.isCompleted) {
        _hostAvailable.future.ignore();
        _hostAvailable.completeError(error);
      }
      physical.complete();
      reply.complete(status);
      return reply.future;
    }
    physical.future
        .timeout(remaining)
        .then<void>(
          (_) {
            if (!reply.isCompleted) reply.complete(status);
          },
          onError: (Object error, StackTrace _) {
            _failure ??= _safe(error);
            if (!reply.isCompleted) reply.complete(status);
          },
        );
    Future<void>.sync(() async {
      if (_stopping) throw EngineCallFailure('SERVICE_UNAVAILABLE');
      _host = await _bootstrap.create(_clock);
      if (_host!.platformKind != _bootstrap.platformKind)
        throw EngineCallFailure('INCOMPATIBLE');
      if (!_host!.externallyManagedShutdown)
        throw EngineCallFailure('INCOMPATIBLE');
      if (_stopping) throw EngineCallFailure('SERVICE_UNAVAILABLE');
      _hostStarted = true;
      final starting = _host!.start(
        deadline: _remaining(expiresAt, const Duration(seconds: 30)),
      );
      if (_power != null) _powerPause = _host!.suspend();
      if (!_hostAvailable.isCompleted) _hostAvailable.complete();
      if (_power != null) {
        _emitPower();
        _pumpPower();
      }
      final ready = await starting;
      if (_stopping) throw EngineCallFailure('SERVICE_UNAVAILABLE');
      _remaining(expiresAt, const Duration(seconds: 30));
      if (ready == HostStartResult.workspaceBusy) {
        _workspaceBusy = true;
        _failure = 'STORAGE_BLOCKED';
        return;
      }
      if (ready != HostStartResult.ready)
        throw EngineCallFailure(_host!.failureCode ?? 'SERVICE_UNAVAILABLE');
      _ready = true;
      final power = _power;
      if (power != null &&
          !power.suspended &&
          _powerObserved == power.epoch &&
          _host!.readiness.state == ReadinessState.ready) {
        _powerPhase = null;
        _cancelPowerDeadline?.call();
        _cancelPowerDeadline = null;
        _emitPower();
      }
    }).then<void>(
      physical.complete,
      onError: (Object error, StackTrace _) {
        if (!_hostAvailable.isCompleted) {
          _hostAvailable.future.ignore();
          _hostAvailable.completeError(error);
        }
        physical.completeError(error);
      },
    );
    return reply.future;
  }

  /// Caller is the one ReceivePort installed before startup/provider callouts.
  void handle(Object? message) {
    Object? frame;
    try {
      if (message is! List || message.length != 2 || message[0] is! Capability)
        return;
      frame = message[1];
      if (message[0] == _control) {
        _handleControl(frame);
      } else {
        final window = _windows[message[0]];
        if (window == null || window.retiring || _stopping) return;
        if (frame is Map<String, Object?> &&
            frame.length == 2 &&
            frame['kind'] == 'close' &&
            frame['generation'] == _host?.generation) {
          _closeWindow(window).ignore();
          return;
        }
        window.gateway?.handle(frame);
      }
    } finally {
      if (frame != null)
        discardWorkerFrame(frame);
      else if (message is List && message.length > 1)
        discardWorkerFrame(message[1]);
    }
  }

  void _handleControl(Object? input) {
    if (input is Map<String, Object?> && input['kind'] == 'power') {
      _handlePower(input);
      return;
    }
    int? sequence;
    String? operation;
    try {
      if (input is! Map<String, Object?>) return;
      final seq = input['sequence'], kind = input['kind'];
      if (seq is! int || seq < 1 || seq > 0x7fffffffffffffff || kind is! String)
        return;
      sequence = seq;
      operation = kind;
      if (kind == 'ackClosed') {
        requireFields(input, {'kind', 'sequence'});
        if (_closed && _closeAcks.remove(seq)) _closedAcknowledged?.call();
        return;
      }
      if (seq <= _lastControl) throw EngineCallFailure('VALIDATION');
      _lastControl = seq;
      if (_controlWork.length >= 16 &&
          kind != 'shutdown' &&
          kind != 'waitClose' &&
          kind != 'detach')
        throw EngineCallFailure('RESOURCE_LIMIT');
      if ((kind == 'shutdown' || kind == 'waitClose') &&
          _reservedControl.contains(kind))
        throw EngineCallFailure('RESOURCE_LIMIT');
      if (_closed && _closeAcks.length >= 16 && kind != 'readiness')
        throw EngineCallFailure('RESOURCE_LIMIT');
      late Future<Object?> Function() action;
      Capability? detaching;
      switch (kind) {
        case 'desktopStatus':
          requireFields(input, {'kind', 'sequence'});
          action = () => Future.value({
            'status': status,
            'mcpSessions': _host?.mcpSessionCount ?? 0,
            'unresolvedJobs': _host?.unresolvedJobs,
          });
        case 'readiness':
          requireFields(input, {'kind', 'sequence'});
          action = () => Future.value(status);
        case 'attach':
          requireFields(input, {
            'kind',
            'sequence',
            'binding',
            'replies',
            'expiresAt',
          });
          final binding = input['binding'],
              replies = input['replies'],
              expires = input['expiresAt'];
          if (binding is! Capability ||
              binding == _control ||
              !_replies.accepts(replies) ||
              expires is! int)
            throw EngineCallFailure('VALIDATION');
          final budget = _remaining(expires, const Duration(seconds: 5));
          action = () => _attach(
            binding,
            replies!,
            expires,
          ).timeout(budget).then<Object?>((_) => status);
        case 'detach':
          requireFields(input, {'kind', 'sequence', 'binding'});
          final binding = input['binding'];
          if (binding is! Capability) throw EngineCallFailure('VALIDATION');
          if (_detachingControl.contains(binding) ||
              _detachingControl.length >= 8)
            throw EngineCallFailure('RESOURCE_LIMIT');
          detaching = binding;
          final window = _windows[binding];
          action = () =>
              (window == null ? Future<void>.value() : _closeWindow(window))
                  .then<Object?>((_) => true);
        case 'shutdown':
          requireFields(input, {'kind', 'sequence', 'expiresAt'});
          if (input['expiresAt'] is! int) throw EngineCallFailure('VALIDATION');
          action = () =>
              shutdown(input['expiresAt'] as int)
                  .then<Object?>((value) => value.name);
        case 'waitClose':
          requireFields(input, {'kind', 'sequence'});
          action = () => waitForClose().then<Object?>((value) => value.name);
        default:
          throw EngineCallFailure('UNSUPPORTED');
      }
      final owned = Completer<void>();
      _controlWork.add(owned.future);
      if (detaching != null) _detachingControl.add(detaching);
      if (kind == 'shutdown' || kind == 'waitClose') _reservedControl.add(kind);
      owned.future.then<void>((_) {
        _controlWork.remove(owned.future);
        _reservedControl.remove(kind);
        if (detaching != null) _detachingControl.remove(detaching);
      });
      Future<Object?>.sync(action).then<void>(
        (result) {
          if (result == 'closed') _closeAcks.add(seq);
          _emit({
            'kind': 'reply',
            'sequence': seq,
            'operation': kind,
            'result': result,
          });
          owned.complete();
        },
        onError: (Object error, StackTrace _) {
          _emit({
            'kind': 'reply',
            'sequence': seq,
            'operation': kind,
            'error': _safe(error),
          });
          owned.complete();
        },
      );
    } catch (error) {
      if (sequence != null)
        _emit({
          'kind': 'reply',
          'sequence': sequence,
          'operation': operation,
          'error': _safe(error),
        });
    }
  }

  void _emitPower() {
    final power = _power;
    if (power != null && !_closed)
      _emit({'kind': 'power', 'epoch': power.epoch, 'status': status});
  }

  void _handlePower(Map<String, Object?> frame) {
    if (_stopping || _closed) return;
    try {
      final next = WorkerPowerIntent.fromFrame(frame);
      if (next.epoch <= (_power?.epoch ?? 0)) return;
      if (next.expiresAt - _clock.elapsed.inMicroseconds > 30000000)
        throw EngineCallFailure('VALIDATION');
      _power = next;
      _powerPhase = next.suspended ? 'suspending' : 'resuming';
      _cancelPowerDeadline?.call();
      _cancelPowerDeadline = null;
      if (!next.suspended) {
        final remaining = _remaining(
          next.expiresAt,
          const Duration(seconds: 30),
        );
        _cancelPowerDeadline = _schedule(remaining, () {
          if (_stopping || _closed || _power?.epoch != next.epoch) return;
          _failure ??= 'TIMEOUT';
          shutdown(_clock.elapsed.inMicroseconds + 10000000).ignore();
          _emitPower();
        });
      }
      // Intent bypasses ordinary quota; physical observation is coalesced below.
      if (_hostStarted) _powerPause = _host!.suspend();
      for (final window in _windows.values.toList())
        _closeWindow(window).ignore();
      _emitPower();
      _pumpPower();
    } catch (error) {
      _failure ??= _safe(error);
      shutdown(_clock.elapsed.inMicroseconds + 10000000).ignore();
      _emitPower();
    }
  }

  void _pumpPower() {
    if (_powerWork != null || _stopping || _power == null) return;
    final done = Completer<void>();
    _powerWork = done.future;
    done.future.ignore();
    () async {
          while (!_stopping && _powerObserved != _power!.epoch) {
            final intent = _power!;
            try {
              await _hostAvailable.future;
              if (_stopping) return;
              if (intent.epoch != _power!.epoch) continue;
              final pause = _powerPause!;
              await pause.settled;
              await Future.wait<void>([
                for (final window in _windows.values.toList())
                  _closeWindow(window),
              ]);
              if (_stopping) return;
              if (intent.epoch != _power!.epoch) continue;
              if (intent.suspended) {
                _powerPhase = 'suspended';
              } else {
                await _host!.resume(
                  pause,
                  deadline: _remaining(
                    intent.expiresAt,
                    const Duration(seconds: 30),
                  ),
                );
                if (_stopping) return;
                if (intent.epoch != _power!.epoch) continue;
                // Startup can still be publishing. Do not block the intent pump on
                // start: another suspend must be able to hold that same startup.
                if (!_ready) {
                  _powerObserved = intent.epoch;
                  _emitPower();
                  continue;
                }
                if (_host!.readiness.state != ReadinessState.ready)
                  throw EngineCallFailure(_host!.failureCode ?? 'NOT_READY');
                _powerPhase = null;
                _cancelPowerDeadline?.call();
                _cancelPowerDeadline = null;
              }
              _powerObserved = intent.epoch;
              _emitPower();
            } catch (error) {
              if (_stopping) return;
              if (intent.epoch != _power!.epoch) continue;
              if (!_ready && _starting != null && _safe(error) != 'TIMEOUT')
                await _starting;
              if (_workspaceBusy) {
                _powerPhase = null;
                _powerObserved = intent.epoch;
                _emitPower();
                return;
              }
              _failure ??= _safe(error);
              shutdown(_clock.elapsed.inMicroseconds + 10000000).ignore();
              _emitPower();
              return;
            }
          }
        }()
        .then<void>(
          done.complete,
          onError: (Object error, StackTrace _) {
            _failure ??= _safe(error);
            shutdown(_clock.elapsed.inMicroseconds + 10000000).ignore();
            done.complete();
          },
        )
        .whenComplete(() {
          _powerWork = null;
          if (!_stopping && _power != null && _powerObserved != _power!.epoch)
            _pumpPower();
        });
  }

  Future<void> _attach(Capability capability, Object replies, int expiresAt) {
    if (_stopping)
      return Future.error(EngineCallFailure('SERVICE_UNAVAILABLE'));
    if (!_ready ||
        _powerPhase != null ||
        _host?.readiness.state != ReadinessState.ready)
      return Future.error(EngineCallFailure('NOT_READY'));
    final prior = _windows[capability];
    if (prior != null) {
      if (prior.retiring || prior.reply != replies)
        return Future.error(EngineCallFailure('UNAUTHORIZED'));
      return prior.opening.future;
    }
    if (_windows.length >= 8)
      return Future.error(EngineCallFailure('RESOURCE_LIMIT'));
    final window = _WorkerWindow(capability, replies);
    window.opening.future.ignore();
    _windows[capability] = window;
    Future<void>.sync(() async {
      try {
        final gateway = await _host!.openOwner(window.binding);
        if (_stopping || window.retiring)
          throw EngineCallFailure('SERVICE_UNAVAILABLE');
        _remaining(expiresAt, const Duration(seconds: 5));
        if (gateway is! InProcessGateway) throw EngineCallFailure('INTERNAL');
        window.gateway = GatewayWorkerBinding(
          gateway: gateway,
          send: (frame) {
            try {
              _replies.send(replies, frame);
            } finally {
              if (frame['kind'] == 'closed') {
                window.retiring = true;
                if (frame['ok'] == true &&
                    identical(_windows[capability], window))
                  _windows.remove(capability);
              }
            }
          },
          detach: () => _host!.detachOwner(window.binding),
        );
      } catch (error) {
        window.retiring = true;
        await _host!.detachOwner(window.binding);
        if (identical(_windows[capability], window))
          _windows.remove(capability);
        rethrow;
      }
    }).then<void>(
      window.opening.complete,
      onError: (Object error, StackTrace _) =>
          window.opening.completeError(error),
    );
    return window.opening.future;
  }

  Future<void> _closeWindow(_WorkerWindow window) {
    if (window.closing != null) return window.closing!;
    final done = Completer<void>();
    window.closing = done.future;
    done.future.ignore();
    window.retiring = true;
    final detach = Future<void>.sync(() => _host!.detachOwner(window.binding));
    () async {
      try {
        await window.opening.future;
      } catch (_) {
        /* opening owns error */
      }
      await Future.wait<void>([
        detach,
        if (window.gateway != null) window.gateway!.close(),
      ]);
      if (identical(_windows[window.capability], window))
        _windows.remove(window.capability);
    }().then<void>(
      done.complete,
      onError: (Object _, StackTrace __) =>
          done.completeError(EngineCallFailure('SERVICE_UNAVAILABLE')),
    );
    return done.future;
  }

  Future<HostCloseResult> shutdown(int expiresAt) {
    if (_shutdown != null) return _shutdown!;
    final remaining = Duration(microseconds: expiresAt) - _clock.elapsed;
    if (remaining > const Duration(seconds: 10))
      return Future.error(EngineCallFailure('VALIDATION'));
    final done = Completer<HostCloseResult>();
    _shutdown = done.future;
    _stopping = true;
    _cancelPowerDeadline?.call();
    _cancelPowerDeadline = null;
    _ready = false;
    if (!_hostAvailable.isCompleted) {
      _hostAvailable.future.ignore();
      _hostAvailable.completeError(EngineCallFailure('SERVICE_UNAVAILABLE'));
    }
    final host = _host;
    if (host != null) {
      final left = Duration(microseconds: expiresAt) - _clock.elapsed;
      host
          .shutdown(
            'root-exit',
            deadline: left > Duration.zero
                ? left
                : const Duration(microseconds: 1),
            requireExplicitWait: left <= Duration.zero,
          )
          .ignore();
    }
    final starting = _startReply;
    if (starting != null && !starting.isCompleted) starting.complete(status);
    final budget = remaining > const Duration(seconds: 10)
        ? const Duration(seconds: 10)
        : remaining;
    final timer = Timer(budget > Duration.zero ? budget : Duration.zero, () {
      _closeBlocked = true;
      if (!done.isCompleted) done.complete(HostCloseResult.closeBlocked);
    });
    _drain(expiresAt, false).then<void>(
      (result) {
        timer.cancel();
        _closeBlocked = result == HostCloseResult.closeBlocked;
        if (!done.isCompleted) done.complete(result);
      },
      onError: (Object _, StackTrace __) {
        timer.cancel();
        _failure ??= 'SERVICE_UNAVAILABLE';
        _closeBlocked = true;
        if (!done.isCompleted) done.complete(HostCloseResult.closeBlocked);
      },
    );
    return done.future;
  }

  Future<HostCloseResult> waitForClose() {
    if (_shutdown == null) return Future.error(EngineCallFailure('NOT_READY'));
    return _waiting ??= _drain(_clock.elapsed.inMicroseconds + 10000000, true);
  }

  Future<HostCloseResult> _drain(int expiresAt, bool continued) async {
    try {
      await _startupPhysical;
    } catch (_) {
      /* startup failure */
    }
    final windows = _windows.values.toList();
    final closures = [for (final window in windows) _closeWindow(window)];
    final host = _host;
    HostCloseResult result;
    if (host == null)
      result = HostCloseResult.closed;
    else {
      var remaining = Duration(microseconds: expiresAt) - _clock.elapsed;
      if (remaining > const Duration(seconds: 10))
        remaining = const Duration(seconds: 10);
      if (remaining <= Duration.zero)
        remaining = const Duration(microseconds: 1);
      final held =
          _closeBlocked ||
          _clock.elapsed.inMicroseconds >= expiresAt ||
          _pipeFailed;
      result = await host.shutdown(
        'root-exit',
        deadline: remaining,
        requireExplicitWait: held,
      );
      if ((continued || (!held && _clock.elapsed.inMicroseconds < expiresAt)) &&
          result == HostCloseResult.closeBlocked)
        result = await host.waitForClose();
    }
    await Future.wait<void>(
      closures.map(
        (future) =>
            future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      ),
    );
    if (result != HostCloseResult.closed) return HostCloseResult.closeBlocked;
    await _bootstrap.close();
    _closed = true;
    return HostCloseResult.closed;
  }
}
