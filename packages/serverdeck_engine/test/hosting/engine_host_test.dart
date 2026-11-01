import 'package:serverdeck_engine/hosting/capability_snapshot.dart';

import 'dart:async';

import 'package:serverdeck_engine/api/mcp_server.dart';
import 'package:serverdeck_engine/hosting/mcp_endpoint_pool.dart';

import 'package:serverdeck_engine/api/owner_api.dart';
import 'package:serverdeck_engine/hosting/engine_host.dart';
import 'package:serverdeck_engine/hosting/host_resources.dart';
import 'package:serverdeck_engine/hosting/in_process_gateway.dart'
    show EngineGateway, EngineCallFailure;
import 'package:serverdeck_engine/hosting/sessions.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

import 'authority_test.dart' as ram;
import 'in_process_gateway_test.dart' as gateway;

// No platform calls: unmatched file/native access is an immediate test failure.
final class Files implements ProtectedFiles {
  @override
  String ownerIdentity = ram.owner;
  @override
  String get root => '/ram';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('NO_FILE_IO_IN_UNIT');
}

final class NativeRuntime implements NativeStoreRuntime {
  int validations = 0;
  Object? error;
  Completer<void>? validating;
  @override
  Future<void> initialize() => throw StateError('NO_NATIVE_IN_UNIT');
  @override
  Future<void> revalidate() async {
    validations++;
    await validating?.future;
    if (error != null) throw error!;
  }
}

final class Vault implements SecureVault {
  VaultAccess access = VaultAccess.available;
  int probes = 0, closes = 0;
  Object? error;
  Completer<void>? paused;
  @override
  Future<VaultAccess> accessStatus() async {
    probes++;
    await paused?.future;
    if (error != null) throw error!;
    return access;
  }

  @override
  Future<void> dispose() async {
    closes++;
  }

  @override
  Future<List<int>> protect(List<int> a, List<int> b) =>
      throw StateError('NO_SECRET_IO_IN_UNIT');
  @override
  Future<List<int>> unprotect(List<int> a, List<int> b) =>
      throw StateError('NO_SECRET_IO_IN_UNIT');
}

final class Resources implements HostResources {
  McpApiServer Function(EngineSessions, TrustedReadiness Function())? createMcp;
  @override
  McpApiServer mcpServer(
    EngineSessions sessions,
    TrustedReadiness Function() readiness,
  ) =>
      createMcp?.call(sessions, readiness) ??
      (throw StateError('NO_MCP_SERVICES_IN_HOST_FIXTURE'));
  @override
  int? unresolvedJobs = 0;
  final events = <String>[];
  final services = gateway.Services();
  Completer<void>? workspaceOpening,
      servicesOpening,
      servicesClosing,
      storeClosing;
  bool retainedReservation = false,
      failServicesClose = false,
      failStoreClose = false;
  Object? startupError;
  void Function()? beforeServices;
  EngineSessions? sessions;
  Completer<void>? servicesSuspending, servicesRevalidating;
  Object? suspendError, revalidationError, resumeError;
  void Function()? afterResume;
  SessionAdmissionPause? _pause;
  Future<void>? _suspending;
  @override
  Future<void> suspendServices() {
    if (_suspending != null) return _suspending!;
    events.add('services.suspend');
    _pause = sessions!.pauseAdmission();
    return _suspending = () async {
      await servicesSuspending?.future;
      if (suspendError != null) throw suspendError!;
      await sessions!.drainRetiredAdmissions();
    }();
  }

  @override
  Future<void> revalidateServices() async {
    events.add('services.revalidate');
    await servicesRevalidating?.future;
    if (revalidationError != null) throw revalidationError!;
  }

  @override
  void resumeServices() {
    events.add('services.resume');
    if (resumeError != null) throw resumeError!;
    sessions!.resumeAdmission(_pause!);
    _pause = null;
    _suspending = null;
    afterResume?.call();
  }

  @override
  bool get hasOpenReservation => retainedReservation;
  @override
  String workspaceId = gateway.workspace;
  @override
  TrustedOwnerApi get ownerApi => services;
  @override
  OperationalFeatures get features => const OperationalFeatures(profiles: true);
  @override
  Future<void> openWorkspace({
    required ProtectedFiles files,
    required NativeStoreRuntime runtime,
    required WorkspaceLease lease,
    required SecureVault vault,
    required void Function() checkStartup,
  }) async {
    events.add('workspace.open');
    expect(lease.isHeld, isTrue);
    await workspaceOpening?.future;
    if (startupError != null) throw startupError!;
    checkStartup();
  }

  @override
  Future<void> openServices(EngineSessions sessions) async {
    this.sessions = sessions;
    events.add('services.open');
    expect(sessions.hasPublicationGate, isTrue);
    beforeServices?.call();
    await servicesOpening?.future;
  }

  @override
  Future<void> closeServices() async {
    events.add('services.close');
    await servicesClosing?.future;
    if (failServicesClose) throw StateError('private cleanup error');
  }

  @override
  Future<void> closeWorkspace() async {
    events.add('workspace.close');
    await storeClosing?.future;
    if (failStoreClose) throw StateError('private store error');
  }
}

final class Setup {
  EnginePlatformKind platformKind = EnginePlatformKind.windows;
  final runtime = ram.Runtime(), lease = ram.Lease(), vault = Vault();
  final storeRuntime = NativeRuntime();
  final files = Files(), resources = Resources(), clock = ram.ManualClock();
  int acquisitions = 0;
  void Function()? onAcquire;
  Future<void> Function()? disposeRuntime;
  bool externallyManagedShutdown = false;
  Future<McpEndpointPool> Function(McpApiServer, String)? mcpPublication;
  Completer<WorkspaceLease>? acquiring;
  late final host = EngineHost(
    platform: EnginePlatform(
      kind: platformKind,
      runtime: runtime,
      files: files,
      vault: vault,
      storeRuntime: storeRuntime,
      disposeRuntime: () => disposeRuntime?.call() ?? Future<void>.value(),
      externallyManagedShutdown: externallyManagedShutdown,
      mcpPublication: mcpPublication,
      acquireLease: () {
        acquisitions++;
        onAcquire?.call();
        return acquiring?.future ?? Future.value(lease);
      },
    ),
    resources: resources,
    clock: clock,
  );
  Future<HostStartResult> start({
    Duration deadline = const Duration(seconds: 30),
  }) {
    runtime.gate.generation = host.generation;
    return host.start(deadline: deadline);
  }
}

void main() {
  for (final kind in EnginePlatformKind.values.where(
    (v) => v != EnginePlatformKind.windows,
  )) {
    test(
      'unsupported ${kind.name} rejects before provider startup, cleanup retained',
      () async {
        final s = Setup()..platformKind = kind;
        expect(await s.start(), HostStartResult.startingFailure);
        expect(s.host.failureCode, 'PREREQUISITE_UNAVAILABLE');
        expect(s.acquisitions, 0);
        expect(s.vault.probes, 0);
        expect(s.storeRuntime.validations, 0);
        expect(s.resources.events, isNot(contains('workspace.open')));
        expect(s.host.capabilities.platform, kind);
        expect(s.host.capabilities.coreUsable, isFalse);
        expect(await s.host.shutdown('finish'), HostCloseResult.closed);
        expect(s.vault.closes, 1);
      },
    );
  }
  test(
    'actual Host capabilities track unknown, current restore and stop proofs',
    () async {
      final s = Setup();
      expect(s.host.capabilities.coreUsable, isFalse);
      final physical = s.vault.paused = Completer<void>();
      final starting = s.start();
      await ram.settle();
      expect(s.host.capabilities.vaultStatus, VaultAccess.unavailable);
      s.vault.paused = null;
      physical.complete();
      expect(await starting, HostStartResult.ready);
      expect(s.host.capabilities.coreUsable, isTrue);
      final pause = s.host.suspend();
      expect(s.host.capabilities.coreUsable, isFalse);
      expect(s.host.capabilities.vaultStatus, VaultAccess.unavailable);
      await pause.settled;
      await s.host.resume(pause);
      expect(s.host.capabilities.coreUsable, isTrue);
      expect(s.resources.events.where((e) => e == 'workspace.open').length, 1);
      final closing = s.host.shutdown('finish');
      expect(s.host.capabilities.coreUsable, isFalse);
      expect(await closing, HostCloseResult.closed);
    },
  );
  for (final access in [VaultAccess.locked, VaultAccess.unavailable]) {
    test(
      'observed vault $access on resume withdraws Host admission and remains negative',
      () async {
        final s = Setup();
        await s.start();
        final pause = s.host.suspend();
        s.vault.access = access;
        await expectLater(
          s.host.resume(pause),
          throwsA(isA<EngineCallFailure>()),
        );
        expect(s.host.capabilities.coreUsable, isFalse);
        expect(s.host.capabilities.vaultStatus, access);
        await expectLater(
          s.host.openOwner(Object()),
          throwsA(isA<EngineCallFailure>()),
        );
        expect(await s.host.shutdown('finish'), HostCloseResult.closed);
      },
    );
  }
  test(
    'runtime metadata close follows store and vault, before lease release',
    () async {
      final s = Setup(), metadata = Completer<void>();
      s.disposeRuntime = () {
        expect(s.resources.events, contains('workspace.close'));
        expect(s.vault.closes, 1);
        expect(s.lease.closes, 0);
        return metadata.future;
      };
      await s.start();
      final close = s.host.shutdown('exit');
      await ram.settle();
      expect(s.lease.closes, 0);
      metadata.complete();
      expect(await close, HostCloseResult.closed);
      expect(s.lease.closes, 1);
    },
  );

  test(
    'failed runtime metadata close permanently holds the writer lease',
    () async {
      final s = Setup();
      s.disposeRuntime = () =>
          Future.error(StateError('private metadata failure'));
      await s.start();
      expect(await s.host.shutdown('exit'), HostCloseResult.closeBlocked);
      expect(await s.host.waitForClose(), HostCloseResult.closeBlocked);
      expect(s.lease.closes, 0);
      expect(s.host.failureCode, 'SERVICE_UNAVAILABLE');
    },
  );

  test('managed automatic startup failure drains but holds lease for root decision', () async {
    final s = Setup()..externallyManagedShutdown = true;
    s.resources.startupError = StateError('private workspace failure');
    expect(await s.start(), HostStartResult.startingFailure);
    await ram.settle();
    expect(s.vault.closes, 1);
    expect(s.lease.closes, 0);
    expect(await s.host.shutdown('root-exit'), HostCloseResult.closeBlocked);
    expect(await s.host.waitForClose(), HostCloseResult.closed);
    expect(s.lease.closes, 1);
  });

  test(
    'one startup operation; readiness waits workspace and recovered services',
    () async {
      final s = Setup();
      s.resources.servicesOpening = Completer();
      final starting = s.start();
      expect(identical(starting, s.start()), isTrue);
      await ram.settle();
      expect(s.host.readiness.state, ReadinessState.recovering);
      expect(s.host.readiness.features.any, isFalse);
      await expectLater(
        s.host.openOwner(Object()),
        gateway.failure('NOT_READY'),
      );
      s.resources.servicesOpening!.complete();
      expect(await starting, HostStartResult.ready);
      expect(s.host.readiness.workspaceId, gateway.workspace);
      expect(s.acquisitions, 1);
      expect(s.resources.events, ['workspace.open', 'services.open']);
      expect(await s.host.shutdown('exit'), HostCloseResult.closed);
      expect(s.resources.events, [
        'workspace.open',
        'services.open',
        'services.close',
        'workspace.close',
      ]);
      expect(s.vault.closes, 1);
      expect(s.lease.closes, 1);
      expect(
        await s.host.start(),
        HostStartResult.ready,
      ); // Same past operation, no reopen.
      await expectLater(
        s.host.openOwner(Object()),
        gateway.failure('SERVICE_UNAVAILABLE'),
      );
    },
  );

  test(
    'two windows share store; one detached window leaves engine alive',
    () async {
      final s = Setup();
      await s.start();
      final a = Object(), b = Object();
      final opening = s.host.openOwner(a);
      expect(identical(opening, s.host.openOwner(a)), isTrue);
      final first = await opening, second = await s.host.openOwner(b);
      expect(identical(first, second), isFalse);
      expect(identical(first, await s.host.openOwner(a)), isTrue);
      await s.host.detachOwner(a);
      expect(first.isClosed, isTrue);
      expect(second.isClosed, isFalse);
      expect(s.host.readiness.state, ReadinessState.ready);
      expect(s.lease.closes, 0);
      final reopened = await s.host.openOwner(a);
      expect(identical(reopened, first), isFalse);
      expect(
        (await second.call(
          'readiness.get',
          {},
          requestId: gateway.id,
        ))['generation'],
        s.host.generation,
      );
      expect(s.acquisitions, 1);
      await s.host.shutdown('exit');
    },
  );

  test(
    'confirmed contender reports busy without opening domain resources',
    () async {
      final s = Setup();
      s.lease.acquired = false;
      s.lease.isHeld = false;
      var publications = 0;
      s.mcpPublication = (_, __) async {
        publications++;
        throw StateError('NO_PUBLICATION_FOR_CONTENDER');
      };
      final starting = s.start();
      expect(await starting, HostStartResult.workspaceBusy);
      expect(s.host.failureCode, 'STORAGE_BLOCKED');
      expect(s.host.readiness.state, ReadinessState.storageBlocked);
      expect(s.host.readiness.features.toJson().values, everyElement(false));
      expect(s.host.readiness.workspaceId, isNull);
      expect(s.host.mcpSessionCount, 0);
      expect(s.vault.probes, 0);
      expect(s.resources.events, isNot(contains('workspace.open')));
      expect(s.resources.events, isNot(contains('services.open')));
      expect(publications, 0);
      expect(await s.host.shutdown('exit'), HostCloseResult.closed);
      expect(s.lease.closes, 1);
      expect(s.vault.closes, 1);
      // A historic outcome is not authority to retry or open this incarnation.
      expect(identical(s.start(), starting), isTrue);
      expect(await s.start(), HostStartResult.workspaceBusy);
      expect(s.acquisitions, 1);
      expect(s.host.isClosed, isTrue);
    },
  );

  test(
    'contender does not open a second store while owner is starting',
    () async {
      final owner = Setup(), contender = Setup();
      owner.resources.workspaceOpening = Completer<void>();
      contender.lease.acquired = false;
      contender.lease.isHeld = false;
      final startingOwner = owner.start();
      final startingContender = contender.start();
      expect(await startingContender, HostStartResult.workspaceBusy);
      await ram.settle();
      expect(owner.host.readiness.state, isNot(ReadinessState.ready));
      expect(owner.resources.events, contains('workspace.open'));
      expect(contender.resources.events, isNot(contains('workspace.open')));
      expect(contender.resources.events, isNot(contains('services.open')));
      expect(await contender.host.shutdown('exit'), HostCloseResult.closed);
      expect(owner.lease.isHeld, isTrue);
      expect(owner.lease.closes, 0);
      owner.resources.workspaceOpening!.complete();
      expect(await startingOwner, HostStartResult.ready);
      await owner.host.shutdown('exit');
    },
  );

  test(
    'foreign or inconsistent lease evidence cannot report workspace busy',
    () async {
      for (final defect in ['owner', 'slot', 'held']) {
        final s = Setup();
        s.lease.acquired = false;
        s.lease.isHeld = defect == 'held';
        if (defect == 'owner') s.lease.ownerIdentity = 'foreign';
        if (defect == 'slot') s.lease.workspaceSlot = 'foreign';
        expect(await s.start(), HostStartResult.startingFailure);
        expect(
          s.host.failureCode,
          defect == 'held' ? 'SERVICE_UNAVAILABLE' : 'UNAUTHORIZED',
        );
        expect(s.vault.probes, 0);
        expect(s.resources.events, isNot(contains('workspace.open')));
        await s.host.shutdown('exit');
        expect(s.lease.closes, 1);
      }
    },
  );

  test('busy lease arriving after original deadline stays a timeout', () async {
    final s = Setup();
    s.acquiring = Completer<WorkspaceLease>();
    s.lease.acquired = false;
    s.lease.isHeld = false;
    final starting = s.start();
    await ram.settle();
    s.clock.elapsed = const Duration(seconds: 30);
    s.acquiring!.complete(s.lease);
    expect(await starting, HostStartResult.startingFailure);
    expect(s.host.failureCode, 'TIMEOUT');
    expect(await s.host.shutdown('exit'), HostCloseResult.closed);
    expect(s.lease.closes, 1);
    expect(s.vault.probes, 0);
  });

  test(
    'exit owns late busy attempt without changing retired startup',
    () async {
      final s = Setup();
      s.acquiring = Completer<WorkspaceLease>();
      s.lease.acquired = false;
      s.lease.isHeld = false;
      final starting = s.start();
      await ram.settle();
      final closing = s.host.shutdown('exit');
      expect(await starting, HostStartResult.startingFailure);
      expect(s.lease.closes, 0);
      s.acquiring!.complete(s.lease);
      expect(await closing, HostCloseResult.closed);
      expect(await s.start(), HostStartResult.startingFailure);
      expect(s.lease.closes, 1);
      expect(s.vault.probes, 0);
    },
  );

  test('busy outcome does not hide unconfirmed physical cleanup', () async {
    final s = Setup();
    s.lease.acquired = false;
    s.lease.isHeld = false;
    s.disposeRuntime = () async => throw StateError('PRIVATE_METADATA_CLOSE');
    expect(await s.start(), HostStartResult.workspaceBusy);
    expect(await s.host.shutdown('exit'), HostCloseResult.closeBlocked);
    expect(s.host.isClosed, isFalse);
    expect(s.lease.closes, 0);
    expect(s.acquisitions, 1);
  });

  test(
    'lost acquired lease is a failure rather than a busy contender',
    () async {
      final s = Setup();
      s.lease.isHeld = false;
      expect(await s.start(), HostStartResult.startingFailure);
      expect(s.host.failureCode, 'STORAGE_BLOCKED');
      expect(await s.host.shutdown('exit'), HostCloseResult.closed);
      expect(s.lease.closes, 1);
      expect(s.vault.probes, 0);
      expect(s.resources.events, isNot(contains('workspace.open')));
    },
  );

  test('wrong owner and unavailable vault never open storage', () async {
    for (final access in [VaultAccess.locked, VaultAccess.unavailable, null]) {
      final s = Setup();
      if (access == null) {
        s.files.ownerIdentity = 'foreign';
      } else {
        s.vault.access = access;
      }
      expect(await s.start(), HostStartResult.startingFailure);
      expect(s.resources.events, isNot(contains('workspace.open')));
      expect(await s.host.shutdown('exit'), HostCloseResult.closed);
      expect(s.lease.closes, 1);
    }
  });

  test('provider diagnostics are not published in startup failure', () async {
    final s = Setup();
    s.vault.error = StateError('SECRET provider path');
    expect(await s.start(), HostStartResult.startingFailure);
    expect(s.host.failureCode, 'SERVICE_UNAVAILABLE');
    expect(s.host.readiness.toJson().toString(), isNot(contains('SECRET')));
    await s.host.shutdown('exit');
  });

  test('startup deadline retains late work and cannot publish Ready', () async {
    final s = Setup();
    s.resources.workspaceOpening = Completer();
    final starting = s.start(deadline: const Duration(milliseconds: 20));
    await ram.settle();
    expect(await starting, HostStartResult.startingFailure);
    expect(s.host.failureCode, 'TIMEOUT');
    expect(s.lease.closes, 0);
    s.resources.workspaceOpening!.complete();
    expect(await s.host.shutdown('exit'), HostCloseResult.closed);
    expect(s.resources.events, isNot(contains('services.open')));
    expect(s.host.readiness.state, isNot(ReadinessState.ready));
  });

  test('monotonic budget covers service recovery and final proof', () async {
    final s = Setup();
    s.resources.beforeServices = () =>
        s.clock.elapsed = const Duration(seconds: 31);
    expect(await s.start(), HostStartResult.startingFailure);
    expect(s.host.failureCode, 'TIMEOUT');
    expect(await s.host.shutdown('exit'), HostCloseResult.closed);
  });

  test(
    'exit during acquisition drains late lease before releasing it',
    () async {
      final s = Setup();
      s.acquiring = Completer();
      final starting = s.start();
      final closing = s.host.shutdown(
        'exit',
        deadline: const Duration(milliseconds: 10),
      );
      expect(await starting, HostStartResult.startingFailure);
      expect(await closing, HostCloseResult.closeBlocked);
      expect(identical(closing, s.host.shutdown('again')), isTrue);
      s.acquiring!.complete(s.lease);
      await ram.settle();
      expect(s.lease.closes, 0);
      expect(await s.host.waitForClose(), HostCloseResult.closed);
      expect(s.lease.closes, 1);
      expect(s.resources.events, isNot(contains('workspace.open')));
    },
  );

  test(
    'CloseBlocked keeps lease after late store close until explicit waiting',
    () async {
      final s = Setup();
      await s.start();
      s.resources.storeClosing = Completer();
      final close = s.host.shutdown(
        'exit',
        deadline: const Duration(milliseconds: 10),
      );
      expect(await close, HostCloseResult.closeBlocked);
      expect(s.lease.isHeld, isTrue);
      await expectLater(
        s.host.openOwner(Object()),
        gateway.failure('SERVICE_UNAVAILABLE'),
      );
      s.resources.storeClosing!.complete();
      await ram.settle();
      expect(s.lease.closes, 0);
      expect(s.host.isClosed, isFalse);
      final waiting = s.host.waitForClose();
      expect(identical(waiting, s.host.waitForClose()), isTrue);
      expect(await waiting, HostCloseResult.closed);
      expect(s.lease.closes, 1);
      expect(identical(close, s.host.shutdown('again')), isTrue);
      expect(await close, HostCloseResult.closeBlocked);
    },
  );

  test('unconfirmed service/store close never releases the lease', () async {
    for (final phase in ['services', 'store', 'reservation']) {
      final s = Setup();
      await s.start();
      s.resources.failServicesClose = phase == 'services';
      s.resources.failStoreClose = phase == 'store';
      s.resources.retainedReservation = phase == 'reservation';
      expect(await s.host.shutdown('exit'), HostCloseResult.closeBlocked);
      expect(await s.host.waitForClose(), HostCloseResult.closeBlocked);
      expect(s.lease.closes, 0);
      expect(s.lease.isHeld, isTrue);
      if (phase == 'services')
        expect(s.resources.events, isNot(contains('workspace.close')));
    }
  });

  test('detached gateway work remains owned by shutdown', () async {
    final s = Setup();
    await s.start();
    final binding = Object(), effect = Completer<Map<String, Object?>>();
    s.resources.services.effect = (_, __) => effect.future;
    final owner = await s.host.openOwner(binding);
    final call = owner.call('settings.get', {}, requestId: gateway.id);
    call.ignore();
    await ram.settle();
    final detached = s.host.detachOwner(binding);
    final close = s.host.shutdown(
      'exit',
      deadline: const Duration(milliseconds: 10),
    );
    expect(await close, HostCloseResult.closeBlocked);
    expect(s.lease.closes, 0);
    effect.complete(gateway.settings());
    await detached;
    expect(await s.host.waitForClose(), HostCloseResult.closed);
    expect(s.lease.closes, 1);
  });

  test(
    'observed lease loss retires readiness and all existing gateways',
    () async {
      final s = Setup();
      await s.start();
      final owner = await s.host.openOwner(Object());
      s.lease.isHeld = false;
      expect(s.host.readiness.state, ReadinessState.stopping);
      expect(owner.isClosed, isTrue);
      expect(await s.host.shutdown('exit'), HostCloseResult.closed);
    },
  );

  test(
    'throwing detach callback cannot strand the shutdown operation',
    () async {
      final s = Setup();
      await s.start();
      await s.host.openOwner(Object());
      s.resources.sessions!.onSessionDetached(
        (_) => throw StateError('private callback'),
      );
      expect(await s.host.shutdown('exit'), HostCloseResult.closeBlocked);
      expect(await s.host.waitForClose(), HostCloseResult.closeBlocked);
      expect(s.runtime.gate.isClosed, isTrue);
      expect(s.lease.closes, 0);
      expect(s.resources.events, isNot(contains('workspace.close')));
    },
  );

  test(
    'synchronous runtime reentry shares one pending owner and gateway',
    () async {
      final s = Setup();
      await s.start();
      final binding = Object();
      Future<EngineGateway>? nested;
      s.runtime.onProof = () {
        nested ??= s.host.openOwner(binding);
      };
      final outer = s.host.openOwner(binding);
      expect(identical(outer, nested), isTrue);
      final owner = await outer;
      expect(identical(owner, await nested), isTrue);
      s.runtime.onProof = null;
      await owner.close();
      expect(await s.host.shutdown('exit'), HostCloseResult.closed);
      expect(s.lease.closes, 1);
    },
  );

  test('expired gateway detach callback cannot revoke replacement', () async {
    final s = Setup();
    await s.start();
    final a = Object(), b = Object();
    await s.host.openOwner(a);
    await s.host.openOwner(b);
    s.clock.elapsed = const Duration(seconds: 61);
    Future<EngineGateway>? nestedA, nestedB;
    s.resources.sessions!.onSessionDetached((_) {
      nestedA ??= s.host.openOwner(a);
      nestedB ??= s.host.openOwner(b);
    });
    final outer = s.host.openOwner(a);
    expect(identical(outer, nestedA), isTrue);
    final nextA = await outer, nextB = await nestedB!;
    expect(nextA.isClosed, isFalse);
    expect(nextB.isClosed, isFalse);
    expect(identical(nextA, await nestedA!), isTrue);
    expect(identical(nextB, await s.host.openOwner(b)), isTrue);
    expect(await s.host.shutdown('exit'), HostCloseResult.closed);
  });

  test(
    'shutdown reentry from retirement callback cannot issue late owner',
    () async {
      final s = Setup();
      await s.start();
      final binding = Object();
      await s.host.openOwner(binding);
      s.clock.elapsed = const Duration(seconds: 61);
      Future<HostCloseResult>? closing;
      s.resources.sessions!.onSessionDetached((_) {
        closing ??= s.host.shutdown('exit');
      });
      await expectLater(
        s.host.openOwner(binding),
        gateway.failure('SERVICE_UNAVAILABLE'),
      );
      expect(await closing, HostCloseResult.closed);
      expect(s.lease.closes, 1);
    },
  );

  for (final lateFailure in [false, true]) {
    test(
      'acquireLease shutdown reentry retains ${lateFailure ? 'failing' : 'successful'} late startup',
      () async {
        final s = Setup();
        s.acquiring = Completer();
        Future<HostCloseResult>? closing;
        s.onAcquire = () {
          closing = s.host.shutdown(
            'exit',
            deadline: const Duration(milliseconds: 10),
          );
        };
        expect(await s.start(), HostStartResult.startingFailure);
        expect(await closing, HostCloseResult.closeBlocked);
        expect(s.host.isClosed, isFalse);
        expect(s.vault.closes, 0);
        expect(s.lease.closes, 0);
        expect(s.resources.events, isEmpty);
        if (lateFailure) {
          s.acquiring!.completeError(StateError('private acquisition error'));
        } else {
          s.acquiring!.complete(s.lease);
        }
        await ram.settle();
        expect(s.lease.closes, 0);
        expect(await s.host.waitForClose(), HostCloseResult.closed);
        expect(s.vault.closes, 1);
        expect(s.lease.closes, lateFailure ? 0 : 1);
        expect(s.resources.events, isNot(contains('workspace.open')));
        expect(s.host.failureCode, isNot(contains('private')));
      },
    );
  }

  for (final prune in [false, true]) {
    test(
      '${prune ? 'slot pruning' : 'same-binding replacement'} retains self-retired cleanup failure',
      () async {
        final s = Setup();
        await s.start();
        final binding = Object();
        final first = await s.host.openOwner(binding);
        if (prune) {
          for (var i = 0; i < 7; i++) {
            await s.host.openOwner(Object());
          }
        }
        s.resources.services.failClose = true;
        await expectLater(
          first.call('settings.get', {}, requestId: gateway.id),
          gateway.failure('SERVICE_UNAVAILABLE'),
        );
        expect(first.isClosed, isTrue);
        final next = await s.host.openOwner(prune ? Object() : binding);
        expect(next.isClosed, isFalse);
        expect(identical(first, next), isFalse);
        expect(await s.host.shutdown('exit'), HostCloseResult.closeBlocked);
        expect(await s.host.waitForClose(), HostCloseResult.closeBlocked);
        expect(s.lease.closes, 0);
        expect(s.resources.events, isNot(contains('workspace.close')));
      },
    );

    test(
      '${prune ? 'slot pruning' : 'same-binding replacement'} retains old physical dispatch',
      () async {
        final s = Setup();
        await s.start();
        final binding = Object(), effect = Completer<Map<String, Object?>>();
        final first = await s.host.openOwner(binding);
        if (prune) {
          for (var i = 0; i < 7; i++) {
            await s.host.openOwner(Object());
          }
        }
        s.resources.services.effect = (_, __) => effect.future;
        final call = first.call('settings.get', {}, requestId: gateway.id);
        call.ignore();
        await ram.settle();
        final retired = first.close();
        retired.ignore();
        final next = await s.host.openOwner(prune ? Object() : binding);
        expect(next.isClosed, isFalse);
        expect(
          await s.host.shutdown(
            'exit',
            deadline: const Duration(milliseconds: 10),
          ),
          HostCloseResult.closeBlocked,
        );
        expect(s.lease.closes, 0);
        effect.complete(gateway.settings());
        await retired;
        expect(await s.host.waitForClose(), HostCloseResult.closed);
        expect(s.lease.closes, 1);
        expect(s.acquisitions, 1);
      },
    );
  }
}
