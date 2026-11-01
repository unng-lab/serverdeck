import 'package:serverdeck_engine/hosting/capability_snapshot.dart';

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/hosting/engine_host.dart';
import 'package:serverdeck_engine/hosting/host_resources.dart';
import 'package:serverdeck_engine/hosting/worker_connection.dart';
import 'package:serverdeck_engine/hosting/worker_controller.dart';
import 'package:serverdeck_engine/hosting/worker_root.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_engine/platform/vm_clock.dart';
import 'package:serverdeck_engine/credentials/discovery_custody.dart';
import 'package:serverdeck_engine/hosting/mcp_endpoint_pool.dart';
import 'package:serverdeck_engine/hosting/protected_mcp_discovery.dart';
import 'package:serverdeck_protocol/discovery.dart';

import 'embedded_build_bundle.dart';
import 'embedded_discovery.dart';
import 'embedded_pipe.dart';
import 'engine_platform.dart';
import 'paths.dart';
import 'security.dart';

EngineWorkerController? _desktopEngine;

/// One incarnation in the Flutter root isolate. Loss/close never clears this
/// reference; restarting the whole app is required to create another engine.
EngineWorkerController desktopEngineController() =>
    _desktopEngine ??= EngineWorkerController(
      platformKind: EnginePlatformKind.windows,
      connection: DartWorkerConnection(windowsEngineWorkerMain),
    );

/// Constructed inside the engine isolate. No native call runs in this object's
/// constructor; partial creation and its resources stay owned through close.
final class WindowsEngineBootstrap implements EngineBootstrap {
  @override
  EnginePlatformKind get platformKind => EnginePlatformKind.windows;
  RetainedProcessIdentity? _self;
  SecureVault? _vault;
  EngineHost? _host;
  Future<EngineHost>? _creating;
  Future<void>? _closing;
  bool _disposalAuthorized = false;
  bool _unconfirmedNative = false;

  @override
  Future<EngineHost> create(EngineClock clock) {
    if (_creating != null) return _creating!;
    if (_closing != null)
      return Future.error(StateError('SERVICE_UNAVAILABLE'));
    final done = Completer<EngineHost>();
    _creating = done.future;
    Future<EngineHost>.sync(() async {
      if (!Platform.isWindows) throw StateError('PREREQUISITE_UNAVAILABLE');
      final root = p.dirname(Platform.resolvedExecutable);
      final bundle = await verifyEmbeddedBuildBundle(root);
      final local = Platform.environment['LOCALAPPDATA'];
      if (local == null || !p.isAbsolute(local))
        throw StateError('PREREQUISITE_UNAVAILABLE');
      requireSafePath(local, local);
      final owner = currentUserSid();
      late final RetainedProcessIdentity identity;
      try {
        identity = _self = RetainedProcessIdentity.open(pid);
      } catch (e) {
        if (e is StateError && e.message == 'PHYSICAL_CLOSE_UNCONFIRMED')
          _unconfirmedNative = true;
        rethrow;
      }
      final self = bundle.verifyPeer(identity, owner);
      self.requireCurrentProcess(bundle);
      final vault = _vault = createWindowsVault(ownerIdentity: owner);
      final runtime = WindowsVerifiedRuntime(
        bundle: bundle,
        self: self,
        onUnconfirmedClose: () {
          _unconfirmedNative = true;
        },
      );
      final files = WindowsProtectedFiles(
        root: local,
        ownerIdentity: owner,
        onUnconfirmedClose: () {
          _unconfirmedNative = true;
        },
      );
      WindowsWorkspaceLease? lease;
      void requireOwner() {
        self.requireCurrentProcess(bundle);
        if (currentUserSid() != owner || lease?.isHeld != true) {
          throw StateError('UNAUTHORIZED');
        }
      }

      final resources = WorkspaceHostResources(
        bundle: bundle,
        executorRelease:
            bundle.manifest.sha256.containsKey('executor-release.json')
            ? bundle.loadExecutorRelease()
            : null,
      );
      return _host = EngineHost(
        clock: clock,
        resources: resources,
        platform: EnginePlatform(
          kind: EnginePlatformKind.windows,
          runtime: runtime,
          files: files,
          vault: vault,
          storeRuntime: WindowsNativeStoreRuntime(bundle: bundle, self: self),
          acquireLease: () async =>
              lease = await WindowsWorkspaceLease.acquire(ownerIdentity: owner),
          mcpPublication: (server, workspace) async {
            requireOwner();
            final descriptor = await DiscoveryDescriptor.create(
              ownerSid: owner,
              buildId: bundle.buildId,
              serverPid: pid,
              generation: server.sessions.generation,
              workspaceId: workspace,
            );
            try {
              requireOwner();
              return McpEndpointPool(
                descriptor: descriptor,
                server: server,
                createListener: EmbeddedPipeListener.bind,
                checkLive: requireOwner,
                elapsed: () => clock.elapsed,
                discovery: ProtectedMcpDiscovery(
                  custody: DiscoveryCustody(vault, owner),
                  file: WindowsMcpDiscoveryFile(
                    files: files,
                    requireOwner: requireOwner,
                  ),
                  requireLive: () async {
                    requireOwner();
                    await runtime.revalidate(lease!);
                    requireOwner();
                    // Admission/epoch is committed by the pool before accepting
                    // publication. This async proof owns accepted I/O even if
                    // the same Host subsequently suspends; never replace native
                    // lease/identity evidence with transient readiness.
                    if (server.sessions.generation != descriptor.generation ||
                        !server.isActivated)
                      throw StateError('UNAUTHORIZED');
                  },
                ),
              );
            } catch (_) {
              descriptor.close();
              rethrow;
            }
          },
          externallyManagedShutdown: true,
          disposeRuntime: () {
            _disposalAuthorized = true;
            return close();
          },
        ),
      );
    }).then<void>(
      done.complete,
      onError: (Object error, StackTrace stack) =>
          done.completeError(error, stack),
    );
    return done.future;
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!;
    final done = Completer<void>();
    _closing = done.future;
    done.future.ignore();
    () async {
      try {
        await _creating;
      } catch (_) {
        /* partial resources still owned */
      }
      if (_host != null && !_disposalAuthorized && !_host!.isClosed)
        throw StateError('STORAGE_BLOCKED');
      var failed = _unconfirmedNative;
      try {
        await _vault?.dispose();
      } catch (_) {
        failed = true;
      }
      try {
        if (_self != null && !_self!.close()) failed = true;
      } catch (_) {
        failed = true;
      }
      if (failed) throw StateError('SERVICE_UNAVAILABLE');
    }().then<void>(
      done.complete,
      onError: (Object _, StackTrace __) =>
          done.completeError(StateError('SERVICE_UNAVAILABLE')),
    );
    return done.future;
  }
}

/// Top-level entry for Isolate.spawn in normal desktop mode only. The stdio
/// mode never invokes this function or constructs an EngineHost/domain worker.
void windowsEngineWorkerMain(EngineWorkerBoot boot) {
  final mailbox = ReceivePort();
  final root = EngineWorkerRoot(
    control: boot.control,
    bootstrap: WindowsEngineBootstrap(),
    clock: VmEngineClock(),
    sendControl: boot.replies.send,
    closedAcknowledged: mailbox.close,
  );
  var begun = false;
  mailbox.listen((message) {
    if (message is List &&
        message.length == 2 &&
        message[0] == boot.control &&
        message[1] is Map<String, Object?> &&
        (message[1] as Map<String, Object?>)['kind'] == 'begin') {
      final frame = message[1] as Map<String, Object?>;
      if (begun || frame.length != 1) return;
      begun = true;
      root.start(boot.expiresAt).then<void>((status) {
        boot.replies.send({'kind': 'started', 'status': status});
      });
      return;
    }
    root.handle(message);
  });
  boot.replies.send({'kind': 'mailbox', 'mailbox': mailbox.sendPort});
}
