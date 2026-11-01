import 'dart:async';
import 'dart:math';

import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../platform/ports.dart';
import 'capability_snapshot.dart';
import 'authority.dart';
import 'host_resources.dart';
import 'in_process_gateway.dart';
import 'sessions.dart';
import 'mcp_endpoint_pool.dart';
import '../api/mcp_server.dart';

enum HostStartResult { ready, workspaceBusy, startingFailure }

enum HostCloseResult { closed, closeBlocked }

/// One same-incarnation pause. A logical observer timeout never completes its
/// physical barrier or grants permission to replace/reopen the Host.
final class HostPause {
  HostPause._(this._epoch) {
    _completion.future.ignore();
  }
  final int _epoch;
  final _completion = Completer<void>(), _released = Completer<void>();
  Future<void>? _resuming;
  bool _expired = false;
  Duration? _ends;
  Future<void> get settled => _completion.future;
}

/// The composition root supplies retained platform objects, never decoded DTOs.
/// The Host owns the acquired attempt (including a busy attempt) and vault.
final class EnginePlatform {
  EnginePlatform({
    required this.kind,
    required this.runtime,
    required this.files,
    required this.vault,
    required this.storeRuntime,
    required this.acquireLease,
    this.disposeRuntime,
    this.externallyManagedShutdown = false,
    this.mcpPublication,
  });
  final VerifiedRuntime runtime;
  final EnginePlatformKind kind;
  final ProtectedFiles files;
  final SecureVault vault;
  final NativeStoreRuntime storeRuntime;
  final Future<WorkspaceLease> Function() acquireLease;

  /// Root-owned retained metadata closes after all runtime users/store/vault,
  /// before releasing the writer lease. An uncertain close keeps CloseBlocked.
  final Future<void> Function()? disposeRuntime;
  final bool externallyManagedShutdown;

  /// Creates only an owned, not-yet-bound pool. No I/O resource may precede it.
  final Future<McpEndpointPool> Function(
    McpApiServer server,
    String workspaceId,
  )?
  mcpPublication;
}

/// One generation, store and writer. This core owns startup/owner/exit; native
/// endpoint publication, desktop lifetime and suspend/resume bind separately.
final class EngineHost {
  EngineHost({
    required EnginePlatform platform,
    HostResources? resources,
    EngineClock? clock,
  }) : _platform = platform,
       _resources = resources ?? WorkspaceHostResources(),
       _clock = clock ?? SystemEngineClock() {
    _servicesReady.future.ignore();
  }

  final EnginePlatform _platform;
  final HostResources _resources;
  final EngineClock _clock;
  final String generation = _uuid();
  WorkspaceLease? _lease;
  HostAuthority? _authority;
  EngineSessions? _sessions;
  McpEndpointPool? _mcp;
  final _owners = Map<Object, InProcessGateway>.identity();
  final _opening = Map<Object, Future<EngineGateway>>.identity();
  final _ownerWork = <Future<EngineGateway>>{};
  final _gatewayDrains = <Future<void>>{};
  final _physicalClose = Completer<HostCloseResult>();
  Completer<HostStartResult>? _startReply;
  Future<HostStartResult>? _start;
  Future<void>? _startupWork;
  Future<HostCloseResult>? _shutdown, _waitForClose;
  final _releasePermission = Completer<void>();
  ReadinessState _state = ReadinessState.starting;
  bool _stopping = false, _closed = false, _gatewayCloseFailed = false;
  bool _admissionCloseFailed = false;
  bool _automaticReleaseBlocked = false;
  bool _workspaceBusy = false;
  String? _failure;
  Duration? _startupEnds;
  String? _workspaceId;
  final _servicesReady = Completer<void>();
  final _lifecycleWork = <Future<void>>{};
  HostPause? _pause;
  int _lifecycleEpoch = 0;
  bool _startupFinished = false;
  bool _servicesOpened = false;
  bool _storageValidated = false;
  VaultAccess? _vaultAccess;
  EnginePlatformKind get platformKind => _platform.kind;
  bool get _coreUsable =>
      _platform.kind == EnginePlatformKind.windows &&
      _state == ReadinessState.ready &&
      !_stopping &&
      _pause == null &&
      _storageValidated &&
      _vaultAccess == VaultAccess.available &&
      _lease?.isHeld == true &&
      _authority?.isStopping == false;
  EngineCapabilities get capabilities {
    if (!_coreUsable)
      return EngineCapabilities.unavailable(
        _platform.kind,
        reason: _failure ?? (_stopping ? 'SERVICE_UNAVAILABLE' : 'NOT_READY'),
        vaultStatus: _vaultAccess ?? VaultAccess.unavailable,
      );
    final epoch = _lifecycleEpoch;
    final features = _readyFeatures;
    if (!_coreUsable || epoch != _lifecycleEpoch) return capabilities;
    return EngineCapabilities(
      platform: _platform.kind,
      storageReady: true,
      vaultStatus: VaultAccess.available,
      directSsh: features.ssh,
      localMcpBridge: features.mcp,
      trayAvailable: false,
      backgroundPolicy: EngineBackgroundPolicy.desktopWhileRunning,
      reasonCodes: const [],
    );
  }

  bool get isSuspended => _pause != null && !_stopping;

  String? get failureCode => _failure;
  bool get isClosed => _closed;
  int? get unresolvedJobs => _resources.unresolvedJobs;
  int get mcpSessionCount {
    _sessions?.expire();
    return _sessions?.mcpCount ?? 0;
  }

  bool get externallyManagedShutdown => _platform.externallyManagedShutdown;
  TrustedReadiness get readiness {
    if (_state == ReadinessState.ready &&
        (_authority?.isStopping == true || _lease?.isHeld != true)) {
      _beginShutdown(requireExplicitWait: _platform.externallyManagedShutdown);
    }
    final state = _state == ReadinessState.ready && !_coreUsable
        ? ReadinessState.recovering
        : _state;
    return TrustedReadiness(
      state: state,
      generation: generation,
      workspaceId: state == ReadinessState.ready
          ? _resources.workspaceId
          : null,
      features: state == ReadinessState.ready
          ? _readyFeatures
          : const OperationalFeatures(),
    );
  }

  OperationalFeatures get _readyFeatures {
    final base = _resources.features;
    return OperationalFeatures(
      profiles: base.profiles,
      ssh: base.ssh,
      jobs: base.jobs,
      backend: base.backend,
      mcp: _mcp?.isPublished == true,
    );
  }

  static String _safe(Object error) {
    if (error is EngineCallFailure) return error.code;
    if (error is TimeoutException) return 'TIMEOUT';
    return error is StateError &&
            const {
              'TIMEOUT',
              'STORAGE_BLOCKED',
              'INCOMPATIBLE',
              'PREREQUISITE_UNAVAILABLE',
              'UNAUTHORIZED',
              'RESOURCE_LIMIT',
              'SERVICE_UNAVAILABLE',
            }.contains(error.message)
        ? error.message
        : 'SERVICE_UNAVAILABLE';
  }

  void _checkStartup() {
    if (_stopping) throw StateError('SERVICE_UNAVAILABLE');
    if (_clock.elapsed >= _startupEnds!) throw StateError('TIMEOUT');
    final lease = _lease;
    if (lease != null &&
        (!lease.isHeld ||
            lease.ownerIdentity != _platform.runtime.ownerIdentity ||
            lease.workspaceSlot != 'default'))
      throw StateError('UNAUTHORIZED');
    if (_authority?.isStopping == true) throw StateError('SERVICE_UNAVAILABLE');
  }

  Future<HostStartResult> start({
    Duration deadline = const Duration(seconds: 30),
  }) {
    if (_start != null) return _start!;
    if (_stopping) return Future.value(HostStartResult.startingFailure);
    if (deadline <= Duration.zero || deadline > const Duration(seconds: 30)) {
      return Future.error(ArgumentError('INVALID_DEADLINE'));
    }
    _startupEnds = _clock.elapsed + deadline;
    final reply = _startReply = Completer<HostStartResult>();
    _start = reply.future;
    final physical = Completer<void>();
    _startupWork = physical.future;
    _startupWork!
        .timeout(deadline)
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace _) {
            _failure ??= _safe(error);
            if (!_stopping) {
              _state = switch (_failure) {
                'INCOMPATIBLE' => ReadinessState.incompatible,
                'STORAGE_BLOCKED' => ReadinessState.storageBlocked,
                _ => ReadinessState.unavailable,
              };
            }
            if (!reply.isCompleted) {
              reply.complete(
                _workspaceBusy &&
                        !_stopping &&
                        _clock.elapsed < _startupEnds! &&
                        _failure == 'STORAGE_BLOCKED'
                    ? HostStartResult.workspaceBusy
                    : HostStartResult.startingFailure,
              );
            }
            // Cleanup waits actual startup, not this timeout wrapper. Retain failure
            // readiness while shutdown closes admission and all acquired resources.
            _beginShutdown(
              preserveFailure: true,
              requireExplicitWait: _platform.externallyManagedShutdown,
            );
          },
        );
    // Startup ownership and its logical observer must exist before lease or
    // another provider can synchronously reenter shutdown.
    Future<void>.sync(() async {
      await _initialize();
      while (true) {
        await _startupAdmission();
        // No await or provider call after this final admission/deadline check.
        // The physical wrapper still owns this commit until its completion.
        final now = _clock.elapsed;
        if (_stopping || reply.isCompleted) return;
        if (now >= _startupEnds!) throw StateError('TIMEOUT');
        if (_pause != null) continue;
        _startupFinished = true;
        _state = ReadinessState.ready;
        reply.complete(HostStartResult.ready);
        return;
      }
    }).then<void>(
      physical.complete,
      onError: (Object error, StackTrace stack) {
        if (!_servicesReady.isCompleted)
          _servicesReady.completeError(error, stack);
        physical.completeError(error, stack);
      },
    );
    return reply.future;
  }

  Future<void> _initialize() async {
    if (_platform.kind != EnginePlatformKind.windows)
      throw StateError('PREREQUISITE_UNAVAILABLE');
    _checkStartup();
    if (_resources.hasOpenReservation) throw StateError('STORAGE_BLOCKED');
    _lease = await _platform.acquireLease();
    // A late/retired attempt stays owned for cleanup, but cannot change the
    // startup outcome. Validate its binding before reporting a real conflict.
    if (_stopping) throw StateError('SERVICE_UNAVAILABLE');
    if (_clock.elapsed >= _startupEnds!) throw StateError('TIMEOUT');
    if (_lease!.ownerIdentity != _platform.runtime.ownerIdentity ||
        _lease!.workspaceSlot != 'default') {
      throw StateError('UNAUTHORIZED');
    }
    if (!_lease!.acquired) {
      if (_lease!.isHeld) throw StateError('SERVICE_UNAVAILABLE');
      _workspaceBusy = true;
      throw StateError('STORAGE_BLOCKED');
    }
    if (!_lease!.isHeld) throw StateError('STORAGE_BLOCKED');
    _checkStartup();
    if (_platform.files.ownerIdentity != _lease!.ownerIdentity) {
      throw StateError('UNAUTHORIZED');
    }
    _authority = HostAuthority.prepare(
      runtime: _platform.runtime,
      lease: _lease!,
      generation: generation,
      clock: _clock,
    );
    await _authority!.initialize(deadline: _startupEnds! - _clock.elapsed);
    _checkStartup();
    final access = await _platform.vault.accessStatus();
    _checkStartup();
    _vaultAccess = access;
    if (access != VaultAccess.available) throw StateError('STORAGE_BLOCKED');
    _state = ReadinessState.recovering;
    await _resources.openWorkspace(
      files: _platform.files,
      runtime: _platform.storeRuntime,
      lease: _lease!,
      vault: _platform.vault,
      checkStartup: _checkStartup,
    );
    _checkStartup();
    final workspaceId = _resources.workspaceId;
    requireUuid(workspaceId);
    _workspaceId = workspaceId;
    _sessions = EngineSessions.withAuthority(
      authority: _authority!,
      admissionBlocked: () =>
          _pause != null ||
          _stopping ||
          !_coreUsable ||
          (!_startupFinished && _clock.elapsed >= _startupEnds!),
      elapsed: () => _clock.elapsed,
    );
    await _resources.openServices(_sessions!);
    _checkStartup();
    _servicesOpened = true;
    _storageValidated = true;
    _servicesReady.complete();
    await _startupAdmission();
    await _authority!.validateRuntime();
    _checkStartup();
    requireUuid(_resources.workspaceId);
    if (_resources.workspaceId != _workspaceId)
      throw StateError('UNAUTHORIZED');
    final publish = _platform.mcpPublication;
    if (publish != null) {
      final server = _resources.mcpServer(_sessions!, () => readiness);
      if (!server.isActivated) throw StateError('NOT_READY');
      _mcp = await publish(server, _resources.workspaceId);
      if (!identical(_mcp!.server, server) ||
          _mcp!.descriptor.generation != generation ||
          _mcp!.descriptor.workspaceId != _resources.workspaceId)
        throw StateError('UNAUTHORIZED');
      _mcp!.failure
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace _) {
              _failure ??= _safe(error);
              _beginShutdown(
                requireExplicitWait: _platform.externallyManagedShutdown,
              );
            },
          )
          .ignore();
      _checkStartup();
      await _mcp!.bind();
      _checkStartup();
      await _authority!.validateRuntime();
      _checkStartup();
      // All services/endpoints are ready before advertising discovery. UI start
      // acknowledgement still waits publication/readback and the final proof.
      await _startupAdmission();
      _state = ReadinessState.ready;
      await _mcp!.activate(beforePublish: _publicationAdmission);
      _checkStartup();
      await _authority!.validateRuntime();
      _checkStartup();
    }
    await _startupAdmission();
  }

  Future<void> _startupAdmission() async {
    while (true) {
      final pause = _pause;
      if (pause != null) await pause._released.future;
      _checkStartup();
      if (_pause == null) return;
    }
  }

  Future<bool Function()> _publicationAdmission() async {
    await _startupAdmission();
    final epoch = _lifecycleEpoch;
    return () {
      final now = _clock.elapsed;
      return !_stopping &&
          _pause == null &&
          epoch == _lifecycleEpoch &&
          now < _startupEnds!;
    };
  }

  void _ownLifecycle(Future<void> physical) {
    _lifecycleWork.add(physical);
    physical.then<void>(
      (_) => _lifecycleWork.remove(physical),
      onError: (Object _, StackTrace __) => _lifecycleWork.remove(physical),
    );
    physical.ignore();
  }

  void _failLifecycle(HostPause pause, Object error) {
    if (_stopping || !identical(_pause, pause)) return;
    // A failed pre-services startup owns its original busy/failure outcome.
    // Its pause observes that failure, rather than preempting its classification.
    if (!_servicesOpened && !_startupFinished) return;
    _failure ??= _safe(error);
    _state = _failure == 'STORAGE_BLOCKED'
        ? ReadinessState.storageBlocked
        : ReadinessState.unavailable;
    _beginShutdown(
      preserveFailure: true,
      requireExplicitWait: _platform.externallyManagedShutdown,
    );
  }

  HostPause suspend() {
    if (_stopping) throw EngineCallFailure('SERVICE_UNAVAILABLE');
    if (_start == null) throw EngineCallFailure('NOT_READY');
    final previous = _pause;
    if (previous != null && previous._resuming == null) return previous;
    final preceding = _lifecycleWork.toList();
    final pause = _pause = HostPause._(++_lifecycleEpoch);
    _storageValidated = false;
    _vaultAccess = null;
    _ownLifecycle(pause.settled);
    // Supersede a resume without cancelling its retained platform work. Startup
    // moves to the newest pause checkpoint, never to a replacement Host.
    if (previous != null && !previous._released.isCompleted)
      previous._released.complete();
    Future<void>.sync(() async {
      final opening = _ownerWork.toList();
      final bindings = {..._owners.keys, ..._opening.keys};
      final owners = _owners.values.toList();
      _owners.clear();
      for (final binding in bindings) _authority?.detachOwner(binding);
      final drains = [for (final gateway in owners) _closeGateway(gateway)];
      Future<void> services;
      if (preceding.isEmpty && _servicesReady.isCompleted) {
        services = Future<void>.sync(_resources.suspendServices);
      } else {
        services = () async {
          for (final work in preceding) {
            try {
              await work;
            } catch (_) {
              /* Ownership, not old outcome. */
            }
          }
          await _servicesReady.future;
          await _resources.suspendServices();
        }();
      }
      await Future.wait<void>([
        services,
        ...drains,
        for (final work in opening)
          work.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
        if (_authority != null) _authority!.drainProofs(),
      ]);
      if (_gatewayCloseFailed) throw StateError('SERVICE_UNAVAILABLE');
    }).then<void>(
      pause._completion.complete,
      onError: (Object error, StackTrace stack) {
        pause._completion.completeError(EngineCallFailure(_safe(error)), stack);
        _failLifecycle(pause, error);
      },
    );
    return pause;
  }

  void _checkResume(HostPause pause) {
    if (_stopping) throw StateError('SERVICE_UNAVAILABLE');
    if (!identical(_pause, pause) || pause._epoch != _lifecycleEpoch)
      throw EngineCallFailure('NOT_READY');
    if (pause._expired ||
        _clock.elapsed >= pause._ends! ||
        !_startupFinished && _clock.elapsed >= _startupEnds!)
      throw StateError('TIMEOUT');
    if (_authority?.isStopping != false ||
        _lease?.isHeld != true ||
        _lease!.ownerIdentity != _platform.runtime.ownerIdentity ||
        _lease!.workspaceSlot != 'default')
      throw StateError('UNAUTHORIZED');
  }

  Future<void> resume(
    HostPause pause, {
    Duration deadline = const Duration(seconds: 30),
  }) {
    if (_stopping)
      return Future.error(EngineCallFailure('SERVICE_UNAVAILABLE'));
    if (!identical(_pause, pause))
      return Future.error(EngineCallFailure('NOT_READY'));
    if (pause._resuming != null) return pause._resuming!;
    if (deadline <= Duration.zero || deadline > const Duration(seconds: 30)) {
      return Future.error(ArgumentError('INVALID_DEADLINE'));
    }
    pause._ends = _clock.elapsed + deadline;
    final physical = Completer<void>();
    _ownLifecycle(physical.future);
    pause._resuming = physical.future.timeout(
      deadline,
      onTimeout: () {
        pause._expired = true;
        _failLifecycle(pause, StateError('TIMEOUT'));
        throw EngineCallFailure('TIMEOUT');
      },
    );
    pause._resuming!.ignore();
    Duration proofBudget() {
      _checkResume(pause);
      final left = pause._ends! - _clock.elapsed;
      return left < const Duration(seconds: 5)
          ? left
          : const Duration(seconds: 5);
    }

    Future<void>.sync(() async {
      await pause.settled;
      _checkResume(pause);
      await _authority!.validateRuntime(deadline: proofBudget());
      _checkResume(pause);
      final access = await _platform.vault.accessStatus();
      _checkResume(pause);
      if (access != VaultAccess.available) _vaultAccess = access;
      if (access != VaultAccess.available) throw StateError('STORAGE_BLOCKED');
      await _platform.storeRuntime.revalidate();
      _checkResume(pause);
      await _resources.revalidateServices();
      _checkResume(pause);
      if (_resources.workspaceId != _workspaceId)
        throw StateError('UNAUTHORIZED');
      await _authority!.validateRuntime(deadline: proofBudget());
      _checkResume(pause);
      _resources.resumeServices();
      _checkResume(pause);
      _storageValidated = true;
      _vaultAccess = access;
      _pause = null;
      if (!pause._released.isCompleted) pause._released.complete();
    }).then<void>(
      physical.complete,
      onError: (Object error, StackTrace stack) {
        physical.completeError(EngineCallFailure(_safe(error)), stack);
        _failLifecycle(pause, error);
      },
    );
    return pause._resuming!;
  }

  void _requireReady() {
    if (_stopping) throw EngineCallFailure('SERVICE_UNAVAILABLE');
    if (_state != ReadinessState.ready || _pause != null)
      throw EngineCallFailure('NOT_READY');
    if (_authority!.isStopping || _lease?.isHeld != true) {
      _beginShutdown(requireExplicitWait: _platform.externallyManagedShutdown);
      throw EngineCallFailure('SERVICE_UNAVAILABLE');
    }
    if (!_coreUsable) throw EngineCallFailure('NOT_READY');
  }

  Future<EngineGateway> openOwner(Object uiBinding) {
    try {
      _requireReady();
      final pending = _opening[uiBinding];
      if (pending != null) return pending;
      final prior = _owners[uiBinding];
      if (prior != null && !prior.isClosed) return Future.value(prior);
      final retired = _owners.entries
          .where((entry) => entry.value.isClosed)
          .toList();
      if (_owners.length - retired.length + _opening.length >= 8) {
        throw EngineCallFailure('RESOURCE_LIMIT');
      }
      final result = Completer<EngineGateway>();
      final work = result.future;
      _opening[uiBinding] = work;
      _ownerWork.add(work);
      work.then<void>(
        (_) => _finishOpen(uiBinding, work),
        onError: (Object _, StackTrace __) => _finishOpen(uiBinding, work),
      );
      // Reserve deduplication and physical ownership before any runtime proof
      // or retirement callback can synchronously reenter this Host.
      Future<EngineGateway>.sync(() {
        _retireClosedOwners(retired);
        _requireReady();
        return _openOwner(uiBinding, _lifecycleEpoch);
      }).then<void>(
        result.complete,
        onError: (Object error, StackTrace _) {
          result.completeError(
            error is EngineCallFailure
                ? error
                : EngineCallFailure(_safe(error)),
          );
        },
      );
      return work;
    } catch (error) {
      return Future.error(
        error is EngineCallFailure ? error : EngineCallFailure(_safe(error)),
      );
    }
  }

  void _finishOpen(Object binding, Future<EngineGateway> work) {
    if (identical(_opening[binding], work)) _opening.remove(binding);
    _ownerWork.remove(work);
  }

  void _retireClosedOwners(List<MapEntry<Object, InProcessGateway>> retired) {
    // Remove/revoke the complete old batch before any close listener runs.
    // Reentrant opens can then neither retire nor revoke a replacement slot.
    for (final entry in retired) {
      _owners.remove(entry.key);
      _authority!.detachOwner(entry.key);
    }
    for (final entry in retired) {
      // Logical retirement/expiry is not physical closure. Keep every old
      // dispatch and sticky cleanup error even when its UI slot is reused.
      _closeGateway(entry.value);
    }
  }

  Future<EngineGateway> _openOwner(Object binding, int epoch) async {
    try {
      final capability = await _authority!.bindOwner(binding);
      _requireReady();
      if (epoch != _lifecycleEpoch) throw EngineCallFailure('UNAUTHORIZED');
      final session = await _sessions!.openOwner(capability);
      _requireReady();
      if (epoch != _lifecycleEpoch) throw EngineCallFailure('UNAUTHORIZED');
      final gateway = InProcessGateway(
        owner: session,
        services: _resources.ownerApi,
        readiness: () => readiness,
      );
      _owners[binding] = gateway;
      return gateway;
    } catch (error) {
      _authority?.detachOwner(binding);
      throw EngineCallFailure(_safe(error));
    }
  }

  /// Window response interests only. The Host/store/MCP/jobs remain alive.
  Future<void> detachOwner(Object uiBinding) {
    _authority?.detachOwner(uiBinding);
    final gateway = _owners.remove(uiBinding);
    return gateway == null ? Future.value() : _closeGateway(gateway);
  }

  Future<void> _closeGateway(InProcessGateway gateway) {
    final actual = Future<void>.sync(gateway.close);
    _gatewayDrains.add(actual);
    actual.then<void>(
      (_) => _gatewayDrains.remove(actual),
      onError: (Object _, StackTrace __) {
        _gatewayCloseFailed = true;
        _gatewayDrains.remove(actual);
      },
    );
    return actual;
  }

  Future<HostCloseResult> shutdown(
    String reason, {
    Duration deadline = const Duration(seconds: 10),
    bool requireExplicitWait = false,
  }) {
    if (requireExplicitWait) _automaticReleaseBlocked = true;
    if (_shutdown != null) return _shutdown!;
    if (deadline <= Duration.zero || deadline > const Duration(seconds: 10)) {
      return Future.error(ArgumentError('INVALID_DEADLINE'));
    }
    return _beginShutdown(
      deadline: deadline,
      requireExplicitWait: requireExplicitWait,
    );
  }

  Future<HostCloseResult> _beginShutdown({
    Duration deadline = const Duration(seconds: 10),
    bool preserveFailure = false,
    bool requireExplicitWait = false,
  }) {
    if (requireExplicitWait) _automaticReleaseBlocked = true;
    if (_shutdown != null) return _shutdown!;
    final reply = Completer<HostCloseResult>();
    final ends = _clock.elapsed + deadline;
    _shutdown = reply.future;
    _stopping = true;
    _storageValidated = false;
    if (_vaultAccess == VaultAccess.available) _vaultAccess = null;
    final pause = _pause;
    if (pause != null && !pause._released.isCompleted)
      pause._released.complete();
    final startup = _startReply;
    if (startup != null && !startup.isCompleted) {
      startup.complete(HostStartResult.startingFailure);
    }
    if (!preserveFailure) _state = ReadinessState.stopping;
    _stopSessions();
    final drains = <Future<void>>[
      for (final gateway in _owners.values) _closeGateway(gateway),
    ];
    _owners.clear();
    final remaining = ends - _clock.elapsed;
    final timer = Timer(
      remaining > Duration.zero ? remaining : Duration.zero,
      () {
        if (!reply.isCompleted) reply.complete(HostCloseResult.closeBlocked);
      },
    );
    final actual = _drain(drains);
    actual.then<void>(
      (_) async {
        if (_clock.elapsed >= ends && !reply.isCompleted) {
          reply.complete(HostCloseResult.closeBlocked);
        }
        // Timeout keeps the lease even if resources finish later. Only explicit
        // continue-waiting grants release permission after CloseBlocked.
        if (_automaticReleaseBlocked &&
            !_releasePermission.isCompleted &&
            !reply.isCompleted) {
          reply.complete(HostCloseResult.closeBlocked);
          timer.cancel();
        }
        if (!_automaticReleaseBlocked &&
            !reply.isCompleted &&
            !_releasePermission.isCompleted) {
          _releasePermission.complete();
        }
        if (!_releasePermission.isCompleted) await _releasePermission.future;
        try {
          await _lease?.close();
          _closed = true;
          _physicalClose.complete(HostCloseResult.closed);
          if (!reply.isCompleted) reply.complete(HostCloseResult.closed);
        } catch (_) {
          _failure ??= 'SERVICE_UNAVAILABLE';
          _physicalClose.complete(HostCloseResult.closeBlocked);
          if (!reply.isCompleted) reply.complete(HostCloseResult.closeBlocked);
        }
        timer.cancel();
      },
      onError: (Object _, StackTrace __) {
        _failure ??= 'SERVICE_UNAVAILABLE';
        _physicalClose.complete(HostCloseResult.closeBlocked);
        timer.cancel();
        if (!reply.isCompleted) reply.complete(HostCloseResult.closeBlocked);
      },
    );
    return reply.future;
  }

  Future<void> _drain(List<Future<void>> gateways) async {
    // Physical startup owns any late acquired lease/workspace/services. No
    // release can race a provider future that has merely timed out logically.
    try {
      await _startupWork;
    } catch (_) {
      /* startup owns safe failure */
    }
    while (_lifecycleWork.isNotEmpty) {
      await Future.wait<void>([
        for (final work in _lifecycleWork.toList())
          work.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      ]);
    }
    _stopSessions();
    final ownerWork = _ownerWork.toList();
    await Future.wait(
      ownerWork.map(
        (f) => f.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      ),
    );
    final results = await Future.wait<bool>([
      for (final future in gateways) _settle(future),
      for (final future in _gatewayDrains.toList()) _settle(future),
      _settle(Future.sync(_resources.closeServices)),
      if (_sessions != null) _settle(_sessions!.close()),
      if (_mcp != null) _settle(_mcp!.close()),
      // Closing authority now revokes pending owners and drains late proofs.
      if (_authority != null) _settle(_authority!.close()),
    ]);
    if (_admissionCloseFailed ||
        _gatewayCloseFailed ||
        results.any((success) => !success)) {
      throw StateError('SERVICE_UNAVAILABLE');
    }
    await _resources.closeWorkspace();
    await _platform.vault.dispose();
    await _platform.disposeRuntime?.call();
    if (_resources.hasOpenReservation) throw StateError('STORAGE_BLOCKED');
  }

  /// The existing CloseBlocked UI's explicit "continue waiting" action. It
  /// resumes the same cleanup; no reopen, retries, replay or new generation.
  Future<HostCloseResult> waitForClose() {
    if (_shutdown == null) return Future.error(StateError('NOT_READY'));
    if (_waitForClose != null) return _waitForClose!;
    if (!_releasePermission.isCompleted) _releasePermission.complete();
    return _waitForClose = _physicalClose.future;
  }

  void _stopSessions() {
    try {
      _mcp?.stop();
      _sessions?.stop();
    } catch (_) {
      // A detach listener must not escape shutdown and strand its operation.
      _admissionCloseFailed = true;
    }
  }

  static Future<bool> _settle(Future<void> future) =>
      future.then((_) => true, onError: (Object _, StackTrace __) => false);
  static String _uuid() {
    final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
