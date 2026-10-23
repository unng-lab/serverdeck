import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/mcp_build_bundle.dart'
    show VerifiedExecutorRelease;

import '../api/operational_auth.dart';
import '../api/trusted_server.dart';
import '../api/trusted_channel.dart';
import '../storage/key_custody.dart';
import '../storage/workspace.dart';
import 'discovery.dart';
import 'discovery_file.dart';
import 'lifecycle.dart' show ShutdownResources;
import 'trusted_entry.dart';
import 'trusted_lifecycle.dart';
import 'trusted_services.dart';

/// Production format3 generation owner. No legacy transport/store fallback.
final class TrustedLocaldBootstrap {
  TrustedLocaldBootstrap(this.environment, this.elapsed);
  final TrustedLocaldEnvironment environment;
  final Duration Function() elapsed;
  final _slots = <PipeWorker>[];
  final _listeners = <Future<void>>[];
  final _channels = <String, TrustedServerChannel>{};
  final _startupFinished = Completer<void>();
  late MutexLease _lease;
  late DiscoveryDescriptor _descriptor;
  late DiscoveryFile _discovery;
  late TrustedServiceLifecycle _lifecycle;
  late KeyCustody _custody;
  Workspace? _workspace;
  TrustedSessions? _sessions;
  TrustedApiServer? _server;
  TrustedControlServices? _services;
  Future<TrustedApiServer>? _binding;
  Future<void>? _activation;
  ReadinessState _state = ReadinessState.starting;
  ErrorCode? _startupFailure;
  bool _used = false, _published = false;
  int _connection = 0;

  void _starting() {
    _lifecycle.checkStartupDeadline();
    if (!_lease.isHeld) throw StateError('STORAGE_BLOCKED');
  }

  TrustedReadiness _readiness() => TrustedReadiness(
    state: _lifecycle.stopping ? ReadinessState.stopping : _state,
    generation: _descriptor.generation,
    workspaceId: _descriptor.workspaceId,
    features: !_lifecycle.stopping && _state == ReadinessState.ready
        ? OperationalFeatures(
            profiles: true,
            ssh: true,
            jobs: environment.bundle.manifest.sha256.containsKey(
              'executor-release.json',
            ),
            mcp: true,
          )
        : const OperationalFeatures(),
  );

  Future<void> run() async {
    if (_used) throw StateError('SERVICE_UNAVAILABLE');
    _used = true;
    if (elapsed() >= startupDeadline) throw StateError('TIMEOUT');
    final namespace = await DiscoveryNamespace.forOwner(environment.sid);
    _lease = await MutexLease.acquire(namespace.mutexName, environment.sid);
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
        ownerSid: environment.sid,
        buildId: environment.bundle.manifest.buildId,
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
    _custody = KeyCustody(DpapiProtection(), environment.sid);
    _discovery = DiscoveryFile(
      localAppData: environment.localAppData,
      runtimeDirectory: runtime,
      ownerSid: environment.sid,
      custody: DiscoveryCustody(DpapiProtection(), environment.sid),
    );
    _lifecycle = TrustedServiceLifecycle(
      generation: _descriptor.generation,
      elapsed: elapsed,
      resources: ShutdownResources(
        cancelStartup: () async {
          await _startupFinished.future;
          try {
            await _binding;
          } catch (_) {}
          try {
            await _activation;
          } catch (_) {}
        },
        drainMutations: () async {
          await _services?.close();
          await _sessions?.close();
        },
        closeStorage: () async {
          if (_workspace == null) Workspace.requireNoOpenReservation();
          await _workspace?.store.close();
        },
        closePipes: () async {
          await Future.wait([
            for (final channel in _channels.values.toList()) channel.close(),
          ]);
          await Future.wait([for (final slot in _slots) slot.close()]);
          await Future.wait(_listeners);
        },
        removeDiscovery: () async {
          await _discovery.drained;
          if (_published)
            await _discovery.remove(
              _descriptor.generation,
              environment.bundle.manifest.buildId,
              _lease,
            );
        },
        clearKeys: () async {
          await _workspace?.close();
          _descriptor.close();
        },
        releaseMutex: _lease.close,
      ),
    );
    try {
      for (final path in [
        p.join(environment.localAppData, 'ServerDeckNext'),
        p.join(environment.localAppData, 'ServerDeckNext', 'v1'),
        runtime,
      ]) {
        _starting();
        createProtectedDirectory(
          environment.localAppData,
          path,
          environment.sid,
        );
      }
      for (final name in namespace.pipeNames) {
        _starting();
        final slot = await PipeWorker.createTrustedServer(
          name,
          environment.sid,
          environment.arguments.appRoot,
        );
        _slots.add(slot);
        final serving = _serve(slot);
        serving.ignore();
        _listeners.add(serving);
      }
      _starting();
      await _discovery.publish(_descriptor, _lease);
      _published = true;
      _starting();
      _state = _lease.abandoned
          ? ReadinessState.recovering
          : ReadinessState.starting;
      _workspace = await Workspace.openTrusted(
        localAppData: environment.localAppData,
        appRoot: environment.arguments.appRoot,
        lease: _lease,
        custody: _custody,
        checkStartup: _starting,
      );
      _starting();
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
      await _activateIfPossible();
    } catch (error) {
      _failed(error);
      if (!_published || _lifecycle.stopping)
        _lifecycle.close(reason: _errorCode(error)).ignore();
      else {
        try {
          _lifecycle.bootstrapComplete();
        } catch (_) {}
      }
    } finally {
      _startupFinished.complete();
    }
    // Cleanup failure must surface first. Once physical cleanup succeeds, a
    // later authentication watchdog must not replace a known startup failure.
    await _lifecycle.finished;
    final failure = _startupFailure;
    if (failure != null) throw StateError(failure.wireName);
    await _lifecycle.waitForExit();
  }

  ErrorCode _errorCode(Object error) =>
      elapsed() >= startupDeadline ||
          error is StateError && error.message == 'TIMEOUT'
      ? ErrorCode.timeout
      : error is StateError && error.message == 'INCOMPATIBLE'
      ? ErrorCode.incompatible
      : error is StateError && error.message == 'SERVICE_UNAVAILABLE'
      ? ErrorCode.serviceUnavailable
      : ErrorCode.storageBlocked;
  void _failed(Object error) {
    final code = _startupFailure ??= _errorCode(error);
    _state = code == ErrorCode.incompatible
        ? ReadinessState.incompatible
        : ReadinessState.storageBlocked;
  }

  Future<void> _activateIfPossible() {
    if (_workspace == null ||
        _server == null ||
        _state == ReadinessState.storageBlocked ||
        _state == ReadinessState.incompatible ||
        _lifecycle.stopping)
      return Future.value();
    return _activation ??= () async {
      try {
        _starting();
        VerifiedExecutorRelease? release;
        if (environment.bundle.manifest.sha256.containsKey(
          'executor-release.json',
        ))
          release = environment.bundle.loadExecutorRelease();
        final work = _workspace!;
        _services = await TrustedControlServices.create(
          store: work.store,
          custody: _custody,
          receiptKey: work.receiptKey,
          sessions: _sessions!,
          bundle: environment.bundle,
          executorRelease: release,
        );
        _starting();
        _server!.activate(
          authority: _services!.authority,
          router: _services!.router,
          owner: _services!,
        );
        _state = ReadinessState.ready;
        _lifecycle.bootstrapComplete();
      } catch (error) {
        _failed(error);
        _lifecycle.close(reason: _errorCode(error)).ignore();
        rethrow;
      }
    }();
  }

  Future<TrustedApiServer> _bind(TrustedPipePeer peer) {
    if (peer.localRole != BundlePeerRole.locald ||
        peer.role == BundlePeerRole.locald)
      return Future.error(StateError('FORBIDDEN'));
    return _binding ??= () async {
      _starting();
      _sessions = await TrustedSessions.withNativePublicationGate(
        generation: _descriptor.generation,
        peer: peer,
        elapsed: elapsed,
        onChanged: () => _lifecycle.changed(),
        onExpiredChannel: (id) => _channels[id]?.close().ignore(),
      );
      _lifecycle.attach(_sessions!);
      _server = TrustedApiServer.starting(
        sessions: _sessions!,
        readiness: _readiness,
      );
      _activateIfPossible().ignore();
      return _server!;
    }();
  }

  Future<void> _serve(PipeWorker slot) async {
    while (!_lifecycle.stopping) {
      try {
        await slot.accept();
      } catch (_) {
        if (!_lifecycle.stopping)
          _lifecycle.close(reason: ErrorCode.serviceUnavailable).ignore();
        return;
      }
      if (_lifecycle.stopping) return;
      final id = '${_descriptor.generation}:${++_connection}';
      TrustedServerChannel? ownedChannel;
      var eligibleBinding = false;
      try {
        final peer = await slot.verifyTrustedPeer();
        if (peer.localRole == BundlePeerRole.locald &&
            peer.role == BundlePeerRole.locald) {
          // A contender receives only a bounded native ownership proof. It
          // never binds services, obtains a bootstrap token or opens a session.
          final watch = Stopwatch()..start();
          Duration remaining() {
            final left = rpcDeadline - watch.elapsed;
            if (left <= Duration.zero) throw StateError('TIMEOUT');
            return left;
          }

          await TrustedHandshakeIo(peer).write({
            'serverdeckOwnerProbeV1': environment.bundle.manifest.buildId,
          }, remaining);
          // Keep the native endpoint alive until the contender has actually
          // read the proof, avoiding a disconnect-versus-peer-verification race.
          await peer.drainOutput(deadline: remaining());
          continue;
        }
        eligibleBinding =
            peer.localRole == BundlePeerRole.locald &&
            peer.role != BundlePeerRole.locald;
        final api = await _bind(peer);
        if (_lifecycle.stopping) return;
        final token = _descriptor.bootstrapToken;
        late final TrustedServerChannel channel;
        try {
          channel = TrustedServerChannel(
            handshake: TrustedServerHandshake(
              peer: peer,
              token: token,
              channel: id,
              sessions: _sessions!,
              elapsed: elapsed,
            ),
            server: api,
            elapsed: elapsed,
          );
        } finally {
          token.fillRange(0, token.length, 0);
        }
        ownedChannel = channel;
        _channels[id] = channel;
        try {
          await channel.run();
        } finally {
          _channels.remove(id);
        }
      } catch (_) {
        // Invalid peer/bootstrap input retires this connection, not the pool.
        if (eligibleBinding &&
            _binding != null &&
            _server == null &&
            !_lifecycle.stopping)
          _lifecycle.close(reason: ErrorCode.serviceUnavailable).ignore();
      } finally {
        if (!_lifecycle.stopping) {
          try {
            if (ownedChannel == null)
              await slot.disconnect();
            else
              await ownedChannel.close();
          } catch (_) {
            _lifecycle.close(reason: ErrorCode.serviceUnavailable).ignore();
          }
        }
      }
    }
  }

  Future<void> _waitForOwner(DiscoveryNamespace namespace) async {
    while (elapsed() < startupDeadline) {
      for (final name in namespace.pipeNames) {
        if (elapsed() >= startupDeadline) break;
        PipeWorker? probe;
        try {
          probe = await PipeWorker.openTrustedClient(
            name,
            environment.sid,
            environment.arguments.appRoot,
          );
          final peer = await probe.verifyTrustedPeer();
          if (peer.role != BundlePeerRole.locald ||
              peer.localRole != BundlePeerRole.locald)
            throw StateError('INCOMPATIBLE');
          final attempt = Stopwatch()..start();
          Duration remaining() {
            final startupLeft = startupDeadline - elapsed(),
                rpcLeft = rpcDeadline - attempt.elapsed;
            final left = startupLeft < rpcLeft ? startupLeft : rpcLeft;
            if (left <= Duration.zero) throw StateError('TIMEOUT');
            return left;
          }

          final response = StrictCodec().decode(
            await TrustedHandshakeIo(peer).read(remaining),
          );
          if (response.length != 1 ||
              response['serverdeckOwnerProbeV1'] !=
                  environment.bundle.manifest.buildId)
            throw StateError('INCOMPATIBLE');
          if (elapsed() >= startupDeadline) throw StateError('TIMEOUT');
          return;
        } on StateError catch (error) {
          if (error.message == 'INCOMPATIBLE') rethrow;
        } finally {
          await probe?.close();
        }
      }
      final left = startupDeadline - elapsed();
      if (left > Duration.zero)
        await Future<void>.delayed(
          left < const Duration(milliseconds: 100)
              ? left
              : const Duration(milliseconds: 100),
        );
    }
    throw StateError('TIMEOUT');
  }
}
