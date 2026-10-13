import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/pipe_worker.dart';

import '../api/auth.dart';
import '../api/channel.dart';
import '../api/server.dart';
import '../profiles/mutation_coordinator.dart';
import '../storage/key_custody.dart';
import '../storage/workspace.dart';
import 'discovery.dart';
import 'discovery_file.dart';
import 'entry.dart';
import 'lifecycle.dart';

/// Production resource owner. All callbacks close this generation's resources.
class LocaldBootstrap {
  LocaldBootstrap(this.environment, this.elapsed);
  final LocaldEnvironment environment;
  final Duration Function() elapsed;
  final _startupFinished = Completer<void>();
  final _channels = <String, ServerChannel>{};
  final _listeners = <Future<void>>[];
  PipeServerPool? _pipes;
  Workspace? _workspace;
  MutationCoordinator? _coordinator;
  late MutexLease _lease;
  late DiscoveryDescriptor _descriptor;
  late DiscoveryFile _discovery;
  late ServiceLifecycle _lifecycle;
  ReadinessState _state = ReadinessState.starting;
  ErrorCode? _reason;
  bool _published = false, _used = false;
  int _connection = 0;

  void _starting() {
    _lifecycle.checkStartupDeadline();
    if (!_lease.isHeld) throw StateError('OWNERSHIP_UNAVAILABLE');
  }

  Future<void> run() async {
    if (_used) throw StateError('SERVICE_UNAVAILABLE');
    _used = true;
    if (elapsed() >= startupDeadline) throw StateError('TIMEOUT');
    final sid = environment.sid;
    final namespace = await DiscoveryNamespace.forOwner(sid);
    _lease = await MutexLease.acquire(namespace.mutexName, sid);
    if (!_lease.isHeld) {
      try {
        await _waitForOwner(namespace);
      } finally {
        await _lease.close();
      }
      return;
    }
    try {
      _descriptor = await DiscoveryDescriptor.create(
        ownerSid: sid,
        buildId: environment.manifest.buildId,
        serverPid: pid,
      );
    } catch (_) {
      await _lease.close();
      rethrow;
    }
    final runtime = p.join(
      environment.localAppData,
      'ServerDeckNext',
      'v1',
      'runtime',
    );
    _discovery = DiscoveryFile(
      localAppData: environment.localAppData,
      runtimeDirectory: runtime,
      ownerSid: sid,
      custody: DiscoveryCustody(DpapiProtection(), sid),
    );
    _lifecycle = ServiceLifecycle(
      generation: _descriptor.generation,
      elapsed: elapsed,
      startupDeadlineAt: startupDeadline,
      onDetached: (id) => _coordinator?.detach(id),
      onExpiredChannel: (channel) => _channels[channel]?.close().ignore(),
      resources: ShutdownResources(
        cancelStartup: () => _startupFinished.future,
        drainMutations: () async {
          await _coordinator?.close();
        },
        closeStorage: () async {
          if (_workspace == null) Workspace.requireNoOpenReservation();
          await _workspace?.store.close();
        },
        closePipes: () async {
          await _pipes?.close();
          await Future.wait(_listeners);
        },
        removeDiscovery: () async {
          await _discovery.drained;
          if (_published) {
            await _discovery.remove(
              _descriptor.generation,
              environment.manifest.buildId,
              _lease,
            );
          }
        },
        clearKeys: () async {
          await _workspace?.close();
          _descriptor.close();
        },
        releaseMutex: _lease.close,
      ),
    );
    try {
      await _initialize(namespace, runtime);
    } catch (error) {
      if (elapsed() >= startupDeadline) {
        try {
          _lifecycle.checkStartupDeadline();
        } catch (_) {
          // The lifecycle now retains TIMEOUT even if Workspace mapped it.
        }
      }
      _reason = elapsed() >= startupDeadline
          ? ErrorCode.timeout
          : error is StateError && error.message == 'INCOMPATIBLE'
          ? ErrorCode.incompatible
          : ErrorCode.storageBlocked;
      _state = _reason == ErrorCode.incompatible
          ? ReadinessState.incompatible
          : ReadinessState.storageBlocked;
      if (!_published || _lifecycle.stopping || elapsed() >= startupDeadline) {
        unawaited(_lifecycle.close());
      } else {
        // The authenticated caller can inspect the failure without opening data.
        try {
          _lifecycle.bootstrapComplete();
        } catch (_) {
          unawaited(_lifecycle.close());
        }
      }
    } finally {
      _startupFinished.complete();
    }
    await _lifecycle.waitForExit();
    if (_reason != null) throw StateError(_reason!.wireName);
  }

  Future<void> _initialize(DiscoveryNamespace namespace, String runtime) async {
    _starting();
    final root = environment.localAppData;
    for (final path in [
      p.join(root, 'ServerDeckNext'),
      p.join(root, 'ServerDeckNext', 'v1'),
      runtime,
    ]) {
      _starting();
      createProtectedDirectory(root, path, environment.sid);
    }
    _pipes = await PipeServerPool.create(namespace.hash, environment.sid);
    _starting();
    final api = ApiServer(
      sessions: _lifecycle.sessions,
      coordinator: () => _coordinator,
      readiness: () => ReadinessView(
        state: _lifecycle.stopping ? ReadinessState.stopping : _state,
        reason: _reason,
        workspaceId: _descriptor.workspaceId,
        generation: _descriptor.generation,
      ),
    );
    for (final slot in _pipes!.slots) {
      final serving = _serve(slot, api);
      serving.ignore();
      _listeners.add(serving);
    }
    await _discovery.publish(_descriptor, _lease);
    _published = true;
    _starting();
    _state = _lease.abandoned
        ? ReadinessState.recovering
        : ReadinessState.starting;
    _workspace = await Workspace.open(
      localAppData: root,
      appRoot: environment.arguments.appRoot,
      lease: _lease,
      custody: KeyCustody(DpapiProtection(), environment.sid),
      checkStartup: _starting,
    );
    _starting();
    _coordinator = MutationCoordinator(
      _workspace!.store,
      KeyCustody(DpapiProtection(), environment.sid),
      _workspace!.receiptKey,
    );
    final promoted = _descriptor.withWorkspace(
      _workspace!.receiptKey.workspaceId,
    );
    try {
      await _discovery.publish(promoted, _lease);
    } catch (_) {
      promoted.close();
      rethrow;
    }
    _descriptor.close();
    _descriptor = promoted;
    _starting();
    _state = ReadinessState.ready;
    _lifecycle.bootstrapComplete();
  }

  Future<void> _serve(PipeWorker slot, ApiServer api) async {
    while (!_lifecycle.stopping) {
      try {
        await slot.accept();
        if (_lifecycle.stopping) return;
        final channelId = '${_descriptor.generation}:${++_connection}';
        final token = _descriptor.bootstrapToken;
        late final ServerChannel channel;
        try {
          channel = ServerChannel(
            handshake: ServerHandshake(
              token: token,
              generation: _descriptor.generation,
              buildId: environment.manifest.buildId,
              channel: channelId,
              sessions: _lifecycle.sessions,
              verifyPeer: () => slot.verifyPeer(
                environment.sid,
                p.join(environment.arguments.appRoot, 'serverdeck.exe'),
                environment.manifest.sha256['serverdeck.exe']!,
              ),
              elapsed: elapsed,
            ),
            server: api,
            read: (count, deadline) =>
                slot.read(count: count, deadline: deadline),
            write: (bytes, deadline) => slot.write(bytes, deadline: deadline),
            drainOutput: (deadline) => slot.drainOutput(deadline: deadline),
            disconnect: slot.disconnect,
            elapsed: elapsed,
          );
        } finally {
          token.fillRange(0, token.length, 0);
        }
        _channels[channelId] = channel;
        try {
          await channel.run();
        } finally {
          _channels.remove(channelId);
        }
      } catch (_) {
        if (!_lifecycle.stopping) {
          // A failed reusable listener cannot silently reduce the fixed pool.
          unawaited(_lifecycle.close(reason: ErrorCode.serviceUnavailable));
        }
        return;
      }
    }
  }

  Future<void> _waitForOwner(DiscoveryNamespace namespace) async {
    while (elapsed() < startupDeadline) {
      for (final name in namespace.pipeNames) {
        if (elapsed() >= startupDeadline) break;
        PipeWorker? probe;
        try {
          probe = await PipeWorker.openClient(name, environment.sid);
          await probe.verifyPeer(
            environment.sid,
            p.join(environment.arguments.appRoot, 'locald.exe'),
            environment.manifest.sha256['locald.exe']!,
          );
          return;
        } catch (_) {
          // A descriptor/PID alone is insufficient evidence of a live owner.
        } finally {
          await probe?.close();
        }
      }
      final remaining = startupDeadline - elapsed();
      if (remaining > Duration.zero) {
        await Future<void>.delayed(
          remaining < const Duration(milliseconds: 100)
              ? remaining
              : const Duration(milliseconds: 100),
        );
      }
    }
    throw StateError('TIMEOUT');
  }
}
