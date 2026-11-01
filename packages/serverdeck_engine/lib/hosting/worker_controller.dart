import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:isolate';

import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;
import 'package:serverdeck_protocol/validation.dart';

import 'engine_host.dart';
import 'capability_snapshot.dart';
import 'in_process_gateway.dart';
import 'worker_connection.dart';
import 'worker_power.dart';

final class WorkerStatus {
  WorkerStatus._(this.phase, this.reason, this.readiness, this.capabilities);
  factory WorkerStatus.fromJson(Object? input) {
    if (input is! Map<String, Object?>) throw EngineCallFailure('INCOMPATIBLE');
    requireFields(input, {'phase', 'reason', 'readiness', 'capabilities'});
    final phase = input['phase'], reason = input['reason'];
    if (!const {
          'starting',
          'busy',
          'ready',
          'suspending',
          'suspended',
          'resuming',
          'failed',
          'stopping',
          'close-blocked',
          'closed',
        }.contains(phase) ||
        (reason != null &&
            !const {
              'TIMEOUT',
              'STORAGE_BLOCKED',
              'INCOMPATIBLE',
              'PREREQUISITE_UNAVAILABLE',
              'UNAUTHORIZED',
              'RESOURCE_LIMIT',
              'NOT_READY',
              'SERVICE_UNAVAILABLE',
            }.contains(reason)))
      throw EngineCallFailure('INCOMPATIBLE');
    final view = input['readiness'] == null
        ? null
        : TrustedReadiness.fromJson(input['readiness']);
    if (phase == 'ready' &&
        (view?.state != ReadinessState.ready || reason != null))
      throw EngineCallFailure('INCOMPATIBLE');
    if (phase == 'busy' &&
        (reason != 'STORAGE_BLOCKED' ||
            view?.state != ReadinessState.storageBlocked ||
            view?.workspaceId != null)) {
      throw EngineCallFailure('INCOMPATIBLE');
    }
    if (const {'suspending', 'suspended', 'resuming'}.contains(phase) &&
        (reason != 'NOT_READY' ||
            view?.state == ReadinessState.ready ||
            view?.workspaceId != null)) {
      throw EngineCallFailure('INCOMPATIBLE');
    }
    final caps = EngineCapabilities.fromJson(input['capabilities']);
    if (phase == 'ready'
        ? !caps.coreUsable ||
              view!.features.ssh != caps.directSsh ||
              view.features.mcp != caps.localMcpBridge
        : caps.storageReady || caps.directSsh || caps.localMcpBridge)
      throw EngineCallFailure('INCOMPATIBLE');
    return WorkerStatus._(phase as String, reason as String?, view, caps);
  }
  final String phase;
  final String? reason;
  final TrustedReadiness? readiness;
  final EngineCapabilities capabilities;
  WorkerStatus withTray(bool available) => WorkerStatus._(
    phase,
    reason,
    readiness,
    capabilities.withTray(available),
  );
}

final class DesktopEngineStatus {
  DesktopEngineStatus(this.status, this.mcpSessions, this.unresolvedJobs);
  factory DesktopEngineStatus.fromJson(Object? input) {
    if (input is! Map<String, Object?>) throw EngineCallFailure('INCOMPATIBLE');
    requireFields(input, {'status', 'mcpSessions', 'unresolvedJobs'});
    final mcp = input['mcpSessions'], jobs = input['unresolvedJobs'];
    if (mcp is! int ||
        mcp < 0 ||
        mcp > 4 ||
        (jobs != null && (jobs is! int || jobs < 0 || jobs > 250)))
      throw EngineCallFailure('INCOMPATIBLE');
    return DesktopEngineStatus(
      WorkerStatus.fromJson(input['status']),
      mcp,
      jobs as int?,
    );
  }
  final WorkerStatus status;
  final int mcpSessions;
  final int? unresolvedJobs;
}

final class _Control {
  _Control(this.kind, this.expiresAt, this.powerEpoch);
  final String kind;
  final int? expiresAt;
  final int powerEpoch;
  final result = Completer<Object?>();
  void Function()? cancel;
}

final class _Owner {
  final capability = Capability();
  final opening = Completer<EngineGateway>();
  WorkerWindowLink? link;
  WorkerGatewayProxy? proxy;
  bool retiring = false;
  Future<void>? closing;
}

/// UI-side root controller for exactly one worker incarnation. A logical timer
/// never cancels accepted work, returns control capacity or creates a replacement.
abstract interface class DesktopEngineControl {
  EnginePlatformKind get platformKind;
  Future<WorkerStatus> start();
  Future<DesktopEngineStatus> refreshDesktopStatus();
  Future<HostCloseResult> shutdown();
  Future<HostCloseResult> waitForClose();
  void setSuspended(bool suspended);
  void setTrayAvailable(bool available);
}

final class EngineWorkerController implements DesktopEngineControl {
  EngineWorkerController({
    required this.platformKind,
    required WorkerConnection connection,
    int Function()? nowMicros,
    GatewaySchedule? schedule,
  }) : _connection = connection,
       _now = nowMicros ?? (() => Timeline.now),
       _schedule = schedule ?? _timer,
       _status = WorkerStatus._(
         'starting',
         null,
         null,
         EngineCapabilities.unavailable(platformKind),
       );
  final EnginePlatformKind platformKind;
  bool _trayAvailable = false;
  final WorkerConnection _connection;
  final int Function() _now;
  final GatewaySchedule _schedule;
  final _pending = <int, _Control>{};
  final _owners = Map<Object, _Owner>.identity();
  StreamSubscription<Object?>? _subscription;
  Completer<WorkerStatus>? _starting;
  WorkerStatus _status;
  WorkerStatus? _busyStart;
  int _powerEpoch = 0;
  bool _powerPending = false;
  final _powerDetaches = <Future<void>>{};
  WorkerPowerIntent? _queuedPower;
  bool _powerFlushScheduled = false;
  String? _generation;
  int _sequence = 0;
  int? _startEnds;
  bool _lost = false,
      _stopping = false,
      _closed = false,
      _startedReceived = false;
  Future<HostCloseResult>? _shutdown, _waiting;
  void Function()? _cancelStart;
  WorkerStatus get status => _status;
  bool get isClosed => _closed;
  bool get isLost => _lost;
  WorkerStatus _localStatus(
    String phase,
    String? reason,
    TrustedReadiness? view,
  ) => WorkerStatus._(
    phase,
    reason,
    view,
    _status.capabilities.withdraw(reason ?? 'NOT_READY'),
  );
  @override
  void setTrayAvailable(bool available) {
    if (platformKind != EnginePlatformKind.windows && available)
      throw EngineCallFailure('INCOMPATIBLE');
    _trayAvailable = available;
    _status = _status.withTray(available);
  }

  static void Function() _timer(Duration d, void Function() action) {
    final timer = Timer(d, action);
    return timer.cancel;
  }

  Future<WorkerStatus> start() {
    // Historical startup outcome survives automatic contender cleanup. Current
    // status/isClosed still report actual physical cleanup, including failure.
    if (_busyStart != null) return _starting!.future;
    if (_lost || _stopping) return Future.value(_status);
    if (_starting != null) return _starting!.future;
    final done = _starting = Completer<WorkerStatus>();
    done.future.ignore();
    final end = _startEnds = _now() + 30000000;
    _subscription = _connection.messages.listen(
      _receive,
      onError: (Object _, StackTrace __) => _lose(),
      onDone: () {
        if (!_closed) _lose();
      },
    );
    _cancelStart = _schedule(const Duration(seconds: 30), () {
      if (done.isCompleted) return;
      _status = _localStatus('failed', 'TIMEOUT', _status.readiness);
      done.complete(_status);
      shutdown().ignore();
    });
    Future<void>.sync(() => _connection.start(end))
        .then<void>((_) {}, onError: (Object _, StackTrace __) => _lose());
    return done.future;
  }

  void _setStatus(Object? raw, {bool powerReady = false}) {
    final next = WorkerStatus.fromJson(raw);
    _checkGeneration(next);
    if (!_stopping &&
        !_lost &&
        (!_powerPending || next.phase != 'ready' || powerReady))
      _status = next.withTray(_trayAvailable);
  }

  void _checkGeneration(WorkerStatus next) {
    if (next.capabilities.platform != platformKind)
      throw EngineCallFailure('INCOMPATIBLE');
    final generation = _generation;
    final received = next.readiness?.generation;
    if (generation != null && received != null && received != generation)
      throw EngineCallFailure('INCOMPATIBLE');
    _generation ??= received;
  }

  void _receive(Object? input) {
    if (_lost) {
      discardWorkerFrame(input);
      return;
    }
    try {
      if (input is! Map<String, Object?>)
        throw EngineCallFailure('INCOMPATIBLE');
      if (input['kind'] == 'power') {
        requireFields(input, {'kind', 'epoch', 'status'});
        final epoch = input['epoch'];
        final next = WorkerStatus.fromJson(input['status']);
        if (epoch is! int || epoch < 1 || epoch > _powerEpoch)
          throw EngineCallFailure('INCOMPATIBLE');
        if (epoch != _powerEpoch || _closed || _stopping) return;
        if (next.phase == 'ready') {
          _checkGeneration(next);
          final raw = input['status'];
          Future.wait<void>(_powerDetaches.toList())
              .then<void>((_) {
                if (epoch != _powerEpoch ||
                    _stopping ||
                    _lost ||
                    const {
                      'failed',
                      'busy',
                      'closed',
                      'close-blocked',
                    }.contains(_status.phase))
                  return;
                _setStatus(raw, powerReady: true);
                _powerPending = false;
              })
              .catchError((Object _, StackTrace __) => _lose());
        } else {
          _setStatus(input['status']);
          if (next.phase == 'failed') shutdown().ignore();
        }
        return;
      }
      if (input['kind'] == 'started') {
        requireFields(input, {'kind', 'status'});
        if (_startedReceived || (_starting == null && !_stopping))
          throw EngineCallFailure('INCOMPATIBLE');
        _startedReceived = true;
        final initial = WorkerStatus.fromJson(input['status']);
        if (!(_powerEpoch > 0 &&
            !_powerPending &&
            _status.phase == 'ready' &&
            const {
              'starting',
              'suspending',
              'suspended',
              'resuming',
            }.contains(initial.phase))) {
          _setStatus(input['status']);
        }
        _cancelStart?.call();
        if (!_stopping && _startEnds != null && _now() >= _startEnds!) {
          _status = _localStatus('failed', 'TIMEOUT', _status.readiness);
        }
        final starting = _starting;
        if (!_stopping && !_lost && _status.phase == 'busy') {
          _busyStart = _status;
        }
        if (starting != null && !starting.isCompleted)
          starting.complete(_status);
        if (!const {
              'ready',
              'starting',
              'suspending',
              'suspended',
              'resuming',
            }.contains(_status.phase) &&
            !_stopping)
          shutdown().ignore();
        return;
      }
      final hasError = input.containsKey('error');
      requireFields(input, {
        'kind',
        'sequence',
        'operation',
        hasError ? 'error' : 'result',
      });
      final seq = input['sequence'];
      if (input['kind'] != 'reply' || seq is! int)
        throw EngineCallFailure('INCOMPATIBLE');
      final work = _pending[seq];
      if (work == null || input['operation'] != work.kind)
        throw EngineCallFailure('INCOMPATIBLE');
      Object? value;
      EngineCallFailure? failure;
      if (hasError) {
        if (input['error'] is! String) throw EngineCallFailure('INCOMPATIBLE');
        failure = EngineCallFailure(input['error'] as String);
      } else {
        value = input['result'];
        final stale =
            work.powerEpoch != _powerEpoch &&
            const {'desktopStatus', 'readiness', 'attach'}.contains(work.kind);
        switch (work.kind) {
          case 'desktopStatus':
            final desktop = DesktopEngineStatus.fromJson(value);
            if (!stale)
              _setStatus((input['result'] as Map<String, Object?>)['status']);
            value = desktop;
          case 'attach':
          case 'readiness':
            if (!stale) _setStatus(value);
            value = WorkerStatus.fromJson(value);
          case 'detach':
            if (value != true) throw EngineCallFailure('INCOMPATIBLE');
          case 'shutdown':
          case 'waitClose':
            if (value != 'closed' && value != 'closeBlocked')
              throw EngineCallFailure('INCOMPATIBLE');
            if (value == 'closed') {
              _recordPhysicalClose(seq);
            }
            value = value == 'closed'
                ? HostCloseResult.closed
                : HostCloseResult.closeBlocked;
        }
        if (stale) failure = EngineCallFailure('NOT_READY');
      }
      _pending.remove(seq);
      work.cancel?.call();
      if (!work.result.isCompleted) {
        if (work.expiresAt != null && _now() >= work.expiresAt!)
          work.result.completeError(EngineCallFailure('TIMEOUT'));
        else if (failure != null)
          work.result.completeError(failure);
        else
          work.result.complete(value);
      }
    } catch (_) {
      _lose();
    } finally {
      discardWorkerFrame(input);
    }
  }

  void _recordPhysicalClose(int sequence) {
    if (_closed) return;
    _closed = true;
    _status = _localStatus('closed', null, _status.readiness);
    // One physical proof covers every observer of this same incarnation. Finish
    // them before ACK permits onExit to close the control reply stream. Keep the
    // bounded correlations to absorb any already queued second close reply.
    for (final work in _pending.values) {
      if (work.kind != 'shutdown' && work.kind != 'waitClose') continue;
      work.cancel?.call();
      if (work.result.isCompleted) continue;
      if (work.expiresAt != null && _now() >= work.expiresAt!) {
        work.result.completeError(EngineCallFailure('TIMEOUT'));
      } else {
        work.result.complete(HostCloseResult.closed);
      }
    }
    try {
      _connection.acknowledgeClosed(sequence);
    } catch (_) {
      // Native closure was already proved. An uncertain ACK is not retried and
      // cannot strand observers or revoke that physical evidence.
    }
  }

  Future<Object?> _request(
    String kind,
    Map<String, Object?> fields, {
    int? expiresAt,
  }) {
    if (_lost || _closed)
      return Future.error(EngineCallFailure('SERVICE_UNAVAILABLE'));
    final ordinary =
        kind != 'shutdown' && kind != 'waitClose' && kind != 'detach';
    if ((ordinary &&
            _pending.values
                    .where(
                      (w) =>
                          w.kind != 'shutdown' &&
                          w.kind != 'waitClose' &&
                          w.kind != 'detach',
                    )
                    .length >=
                16) ||
        (!ordinary &&
            kind != 'detach' &&
            _pending.values.any((w) => w.kind == kind)) ||
        (kind == 'detach' &&
            _pending.values.where((w) => w.kind == kind).length >= 8))
      return Future.error(EngineCallFailure('RESOURCE_LIMIT'));
    if (_sequence == 0x7fffffffffffffff) {
      _lose();
      return Future.error(EngineCallFailure('SERVICE_UNAVAILABLE'));
    }
    final seq = ++_sequence, work = _Control(kind, expiresAt, _powerEpoch);
    work.result.future.ignore();
    _pending[seq] = work;
    if (expiresAt != null) {
      final remaining = expiresAt - _now();
      if (remaining <= 0) {
        _pending.remove(seq);
        work.result.completeError(EngineCallFailure('TIMEOUT'));
        return work.result.future;
      }
      work.cancel = _schedule(Duration(microseconds: remaining), () {
        if (!work.result.isCompleted)
          work.result.completeError(EngineCallFailure('TIMEOUT'));
        // Slot remains owned until actual control reply or authoritative loss.
      });
    }
    try {
      _connection.send({'kind': kind, 'sequence': seq, ...fields});
    } catch (_) {
      _lose();
    }
    return work.result.future;
  }

  Future<WorkerStatus> refreshReadiness() async {
    if (_stopping) return _status;
    await _request('readiness', {}, expiresAt: _now() + 5000000);
    return _status;
  }

  Future<DesktopEngineStatus> refreshDesktopStatus() async {
    if (_lost || _closed) return DesktopEngineStatus(_status, 0, null);
    final result = await _request(
      'desktopStatus',
      {},
      expiresAt: _now() + 5000000,
    ) as DesktopEngineStatus;
    return DesktopEngineStatus(
      _status,
      result.mcpSessions,
      result.unresolvedJobs,
    );
  }

  Future<EngineGateway> openOwner(Object binding) {
    if (_powerPending) return Future.error(EngineCallFailure('NOT_READY'));
    final prior = _owners[binding];
    if (prior != null && !prior.retiring && prior.proxy?.isClosed != true)
      return prior.opening.future;
    if (_stopping || _lost)
      return Future.error(EngineCallFailure('SERVICE_UNAVAILABLE'));
    if (prior != null || _owners.length >= 8)
      return Future.error(EngineCallFailure('RESOURCE_LIMIT'));
    final owner = _Owner();
    owner.opening.future.ignore();
    _owners[binding] = owner;
    Future<EngineGateway>.sync(() async {
      await start();
      if (_stopping ||
          owner.retiring ||
          _powerPending ||
          _status.phase != 'ready')
        throw EngineCallFailure('NOT_READY');
      final end = _now() + 5000000;
      final link = owner.link = _connection.openWindow(owner.capability);
      await _request('attach', {
        'binding': owner.capability,
        'replies': link.replyAddress,
        'expiresAt': end,
      }, expiresAt: end);
      if (_stopping || owner.retiring || _now() >= end)
        throw EngineCallFailure('SERVICE_UNAVAILABLE');
      final proxy = owner.proxy = WorkerGatewayProxy(
        generation: _generation!,
        channel: link.channel,
        nowMicros: _now,
        schedule: _schedule,
      );
      return proxy;
    }).then<void>(
      owner.opening.complete,
      onError: (Object error, StackTrace _) {
        _detach(binding, owner).ignore();
        owner.opening.completeError(
          error is EngineCallFailure
              ? error
              : EngineCallFailure('SERVICE_UNAVAILABLE'),
        );
      },
    );
    return owner.opening.future;
  }

  Future<void> detachOwner(Object binding) {
    final owner = _owners[binding];
    return owner == null ? Future.value() : _detach(binding, owner);
  }

  @override
  void setSuspended(bool suspended) {
    if (_lost || _closed || _stopping) return;
    if (_powerEpoch == 0x7fffffffffffffff) {
      _lose();
      return;
    }
    final intent = WorkerPowerIntent(
      ++_powerEpoch,
      suspended,
      _now() + 30000000,
    );
    _powerPending = true;
    final view = _status.readiness;
    _status = _localStatus(
      suspended ? 'suspending' : 'resuming',
      'NOT_READY',
      view == null
          ? null
          : TrustedReadiness(
              state: ReadinessState.recovering,
              generation: view.generation,
            ),
    );
    for (final entry in _owners.entries.toList()) {
      final work = _detach(entry.key, entry.value);
      if (_powerDetaches.add(work))
        work.then<void>(
          (_) => _powerDetaches.remove(work),
          onError: (Object _, StackTrace __) => _lose(),
        );
      work.ignore();
    }
    _queuedPower = intent;
    if (_powerFlushScheduled) return;
    _powerFlushScheduled = true;
    scheduleMicrotask(() {
      _powerFlushScheduled = false;
      final latest = _queuedPower;
      _queuedPower = null;
      if (latest == null || _lost || _stopping || _closed) return;
      try {
        _connection.send(latest.toFrame());
      } catch (_) {
        _lose();
      }
    });
  }

  Future<void> _detach(Object binding, _Owner owner) {
    if (owner.closing != null) return owner.closing!;
    final done = Completer<void>();
    owner.closing = done.future;
    done.future.ignore();
    owner.retiring = true;
    // Stop this proxy synchronously; data close and reserved detach share mailbox.
    final proxyClose = owner.proxy?.close();
    proxyClose?.ignore();
    () async {
      if (owner.link != null && !_lost && !_closed) {
        await _request('detach', {'binding': owner.capability});
        if (proxyClose != null) await proxyClose;
      }
      if (_lost) throw EngineCallFailure('SERVICE_UNAVAILABLE');
      owner.link?.channel.dispose();
      if (identical(_owners[binding], owner)) _owners.remove(binding);
    }().then<void>(
      done.complete,
      onError: (Object _, StackTrace __) =>
          done.completeError(EngineCallFailure('SERVICE_UNAVAILABLE')),
    );
    return done.future;
  }

  Future<HostCloseResult> shutdown() {
    if (_shutdown != null) return _shutdown!;
    final end = _now() + 10000000;
    final done = Completer<HostCloseResult>();
    _shutdown = done.future;
    _stopping = true;
    if (_closed) {
      done.complete(HostCloseResult.closed);
      return done.future;
    }
    if (_lost) {
      done.complete(HostCloseResult.closeBlocked);
      return done.future;
    }
    _status = _localStatus('stopping', null, _status.readiness);
    final start = _starting;
    if (start != null && !start.isCompleted) start.complete(_status);
    _cancelStart?.call();
    for (final owner in _owners.values) {
      owner.retiring = true;
      owner.proxy?.close().ignore();
    }
    // Ensure bootstrap delivery exists even when exit precedes explicit start.
    if (_subscription == null) {
      _subscription = _connection.messages.listen(
        _receive,
        onError: (Object _, StackTrace __) => _lose(),
        onDone: () {
          if (!_closed) _lose();
        },
      );
      Future<void>.sync(() => _connection.start(_now() + 30000000))
          .then<void>((_) {}, onError: (Object _, StackTrace __) => _lose());
    }
    _request('shutdown', {'expiresAt': end}, expiresAt: end).then<void>(
      (value) {
        final result = value as HostCloseResult;
        if (!_closed && result != HostCloseResult.closed)
          _status = _localStatus('close-blocked', null, _status.readiness);
        done.complete(result);
      },
      onError: (Object _, StackTrace __) {
        if (!_closed)
          _status = _localStatus(
            'close-blocked',
            'SERVICE_UNAVAILABLE',
            _status.readiness,
          );
        done.complete(HostCloseResult.closeBlocked);
      },
    );
    return done.future;
  }

  Future<HostCloseResult> waitForClose() {
    if (_shutdown == null) return Future.error(EngineCallFailure('NOT_READY'));
    if (_closed) return Future.value(HostCloseResult.closed);
    if (_lost) return Future.value(HostCloseResult.closeBlocked);
    return _waiting ??= _request('waitClose', {}).then(
      (value) => value as HostCloseResult,
      onError: (Object _, StackTrace __) => HostCloseResult.closeBlocked,
    );
  }

  void _lose() {
    if (_lost || _closed) return;
    _lost = true;
    _stopping = true;
    _status = _localStatus(
      'close-blocked',
      'SERVICE_UNAVAILABLE',
      _status.readiness,
    );
    _cancelStart?.call();
    final start = _starting;
    if (start != null && !start.isCompleted) start.complete(_status);
    for (final work in _pending.values) {
      work.cancel?.call();
      if (!work.result.isCompleted)
        work.result.completeError(EngineCallFailure('SERVICE_UNAVAILABLE'));
    }
    for (final owner in _owners.values) {
      owner.retiring = true;
      owner.link?.workerLost();
    }
    _subscription?.cancel().ignore();
  }
}
