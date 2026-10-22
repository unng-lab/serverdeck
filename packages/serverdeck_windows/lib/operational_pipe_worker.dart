part of 'pipe_worker.dart';

/// Only this worker can issue an epoch-bound handle. It carries no native object
/// across isolates; every operation is checked inside its owning pipe worker.
final class OperationalPipePeer extends _EpochPipePeer {
  OperationalPipePeer._(
    super._worker,
    super._epoch,
    super.role,
    super.buildId,
    super.localRole,
  ) : super._();
}

/// Format3 native proof, with no conversion into a format2 operational peer.
final class TrustedPipePeer extends _EpochPipePeer {
  TrustedPipePeer._(
    super._worker,
    super._epoch,
    super.role,
    super.buildId,
    super.localRole,
  ) : super._();
}

sealed class _EpochPipePeer {
  _EpochPipePeer._(
    this._worker,
    this._epoch,
    this.role,
    this.buildId,
    this.localRole,
  );
  final PipeWorker _worker;
  final int _epoch;
  final BundlePeerRole role;

  /// Retained self-image role verified in the same native worker, not a claim
  /// supplied by the bootstrap client or a second process identity.
  final BundlePeerRole localRole;
  final String buildId;

  Future<OperationalNativeObservation> observeNextRevalidationForTest() async {
    if (!operationalNativeObservationEnabled) throw StateError('UNSUPPORTED');
    final token = await _worker._call('testPeerObservationArm', _epoch) as int;
    final reached = _worker
        ._call('testPeerObservationReached', [_epoch, token])
        .then<void>((_) {});
    return OperationalNativeObservation._(reached, () async {
      await _worker._call('testPeerObservationRelease', [_epoch, token]);
    });
  }

  /// Derive synchronization identity only from this actual verified endpoint.
  /// The gate itself grants no tool/session authority.
  Future<OperationalPublicationGate> publicationGate(String generation) async {
    requireUuid(generation);
    final identity =
        await _worker._call('peerPublicationIdentity', _epoch) as List;
    return OperationalPublicationGate._open(
      identity,
      generation,
      localRole,
      _worker._mode,
    );
  }

  Future<void> revalidate({
    void Function(Future<void>)? observeNativeCompletion,
  }) async {
    // _call may refuse before issuing work (for example the pipe3 quota).
    // Such a logical refusal is not a failed physical completion.
    final response = _worker._call('peerVerify', _epoch);
    final actual = () async {
      final result = (await response) as List;
      if (result[0] != _epoch ||
          result[1] != role.name ||
          result[2] != buildId ||
          result[3] != localRole.name)
        throw StateError('UNAUTHORIZED');
    }();
    actual.ignore();
    try {
      observeNativeCompletion?.call(actual);
    } catch (_) {
      try {
        await actual;
      } catch (_) {
        /* Actual failure remains observed. */
      }
      throw StateError('SERVICE_UNAVAILABLE');
    }
    await actual;
  }

  Future<Uint8List> read({
    int count = 65536,
    Duration deadline = const Duration(seconds: 5),
  }) async => (await _worker._call('peerRead', [
    _epoch,
    count,
    deadline.inMilliseconds,
  ])) as Uint8List;

  Future<void> write(
    List<int> bytes, {
    Duration deadline = const Duration(seconds: 5),
  }) async {
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024 + 4)
      throw StateError('RESOURCE_LIMIT');
    await _worker._call('peerWrite', [
      _epoch,
      Uint8List.fromList(bytes),
      deadline.inMilliseconds,
    ]);
  }

  Future<void> drainOutput({
    Duration deadline = const Duration(seconds: 5),
  }) async =>
      await _worker._call('peerDrain', [_epoch, deadline.inMilliseconds]);

  /// Cleanup is bound to this connection epoch even after identity failure.
  /// A late close must never disconnect a replacement accepted on the slot.
  Future<void> disconnect() async =>
      await _worker._call('peerDisconnect', _epoch);
}

enum _OperationalSlot {
  idle,
  listening,
  connected,
  needsDisconnect,
  disconnecting,
  failedDisconnect,
  closed,
}

// Private native-owner adapters reuse IO/epoch mechanics without converting
// either public proof type or accepting a claimed role/schema from a client.
final class _EndpointProof {
  _EndpointProof(this._role, this.revalidate);
  final BundlePeerRole Function() _role;
  BundlePeerRole get role => _role();
  final void Function() revalidate;
}

final class _EndpointBundle {
  _EndpointBundle._(this.appRoot, this.buildId, this.verifyPeer);
  factory _EndpointBundle.operational(McpBuildBundle bundle) =>
      _EndpointBundle._(bundle.manifest.appRoot, bundle.manifest.buildId, (
        identity,
        sid,
      ) {
        final proof = bundle.verifyPeer(identity, sid);
        return _EndpointProof(() => proof.role, proof.revalidate);
      });
  factory _EndpointBundle.trusted(TrustedBuildBundle bundle) =>
      _EndpointBundle._(bundle.manifest.appRoot, bundle.manifest.buildId, (
        identity,
        sid,
      ) {
        final proof = bundle.verifyPeer(identity, sid);
        return _EndpointProof(() => proof.role, proof.revalidate);
      });
  final String appRoot, buildId;
  final _EndpointProof Function(RetainedProcessIdentity, String) verifyPeer;
}

final class _OperationalEndpoint {
  _OperationalEndpoint(
    this.pipe,
    this.bundle,
    this.self,
    this.selfProof,
    this.sid,
    this.server,
  ) : localRole = selfProof.role,
      state = server ? _OperationalSlot.idle : _OperationalSlot.connected,
      epoch = server ? 0 : 1;
  final NativePipe pipe;
  final _EndpointBundle bundle;
  final RetainedProcessIdentity self;
  final _EndpointProof selfProof;
  final BundlePeerRole localRole;
  final String sid;
  final bool server;
  _OperationalSlot state;
  int epoch;
  bool failed = false;
  _EndpointProof? peer;
  _NativeObservationPause? _proofPause;
  bool _proofPauseConsumed = false;
  int _proofObservationToken = 0;
  static const _maximumEpoch = 0x7fffffffffffffff;

  void advance(_OperationalSlot next) {
    _proofPause?.retire();
    _proofPause = null;
    _proofPauseConsumed = false;
    if (epoch >= _maximumEpoch) {
      failed = true;
      peer = null;
      state = _OperationalSlot.failedDisconnect;
      throw StateError('SERVICE_UNAVAILABLE');
    }
    epoch++;
    peer = null;
    failed = false;
    state = next;
  }

  BundlePeerRole verify(int? expected) {
    // A stale or raw caller must not poison a healthy replacement connection.
    if (state != _OperationalSlot.connected ||
        failed ||
        expected != null && expected != epoch)
      throw StateError('UNAUTHORIZED');
    try {
      selfProof.revalidate();
      if (peer == null) {
        if (expected != null) throw StateError('UNAUTHORIZED');
        peer = bundle.verifyPeer(pipe.peerIdentity(), sid);
      }
      final role = peer!.role;
      if (server
          ? role == BundlePeerRole.locald
          : role != BundlePeerRole.locald)
        throw StateError('UNAUTHORIZED');
      return role;
    } catch (_) {
      failed = true;
      peer = null;
      throw StateError('UNAUTHORIZED');
    }
  }

  Future<Object?> io(int expected, Future<Object?> Function() run) async {
    verify(expected);
    try {
      final result = await run();
      verify(expected);
      return result;
    } catch (error) {
      if (expected == epoch &&
          state == _OperationalSlot.connected &&
          !(error is StateError && error.message == 'RESOURCE_LIMIT')) {
        failed = true;
        peer = null;
      }
      rethrow;
    }
  }

  Future<Object?> call(String method, Object? params) async {
    switch (method) {
      case 'accept':
        // Native STATUS_PIPE_CONNECTED is not a new connection. Never clear a
        // failed binding or epoch before checking the physical reuse barrier.
        if (!server || state != _OperationalSlot.idle)
          throw StateError('SERVICE_UNAVAILABLE');
        advance(_OperationalSlot.listening);
        final attempt = epoch;
        try {
          await pipe.accept(
            deadline: params == null
                ? null
                : Duration(milliseconds: params as int),
          );
          if (epoch != attempt || state != _OperationalSlot.listening)
            throw StateError('SERVICE_UNAVAILABLE');
          state = _OperationalSlot.connected;
        } catch (_) {
          if (epoch == attempt && state == _OperationalSlot.listening)
            state = _OperationalSlot.needsDisconnect;
          rethrow;
        }
        return null;
      case 'peerPublicationIdentity':
        verify(params as int);
        return [sid, p.normalize(bundle.appRoot).toLowerCase(), localRole.name];
      case 'peerVerify':
        var role = verify(params as int?);
        if (operationalNativeObservationEnabled &&
            _proofPause != null &&
            !_proofPauseConsumed) {
          final pause = _proofPause!;
          _proofPauseConsumed = true;
          await pause.hit();
          role = verify(params);
        }
        return [epoch, role.name, bundle.buildId, localRole.name];
      case 'testPeerObservationArm':
        if (!operationalNativeObservationEnabled)
          throw StateError('UNAUTHORIZED');
        verify(params as int);
        if (_proofPause != null) throw StateError('RESOURCE_LIMIT');
        _proofPause = _NativeObservationPause();
        _proofPauseConsumed = false;
        return ++_proofObservationToken;
      case 'testPeerObservationReached' || 'testPeerObservationRelease':
        if (!operationalNativeObservationEnabled)
          throw StateError('UNAUTHORIZED');
        final probe = params as List;
        if (probe[0] != epoch ||
            probe[1] != _proofObservationToken ||
            _proofPause == null)
          throw StateError('UNAUTHORIZED');
        final pause = _proofPause!;
        if (method == 'testPeerObservationReached') {
          await pause.reached.future;
        } else {
          _proofPause = null;
          _proofPauseConsumed = false;
          pause.retire();
        }
        return null;
      case 'peerRead':
        final values = params as List, count = values[1] as int;
        if (count < 1 || count > 65536) throw StateError('RESOURCE_LIMIT');
        return io(
          values[0] as int,
          () => pipe.read(
            count: count,
            deadline: Duration(milliseconds: values[2] as int),
          ),
        );
      case 'peerWrite':
        final values = params as List, bytes = values[1] as Uint8List;
        if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024 + 4)
          throw StateError('RESOURCE_LIMIT');
        return io(values[0] as int, () async {
          await pipe.write(
            bytes,
            deadline: Duration(milliseconds: values[2] as int),
          );
          return null;
        });
      case 'peerDrain':
        if (!server) throw StateError('UNSAFE_ENDPOINT');
        final values = params as List;
        return io(values[0] as int, () async {
          await pipe.drainOutput(
            deadline: Duration(milliseconds: values[1] as int),
          );
          return null;
        });
      case 'peerDisconnect':
        if (!server) throw StateError('UNSAFE_ENDPOINT');
        if (params != epoch || state != _OperationalSlot.connected)
          throw StateError('UNAUTHORIZED');
        return call('disconnect', null);
      case 'disconnect':
        if (!server ||
            state == _OperationalSlot.closed ||
            state == _OperationalSlot.failedDisconnect ||
            state == _OperationalSlot.disconnecting)
          throw StateError('SERVICE_UNAVAILABLE');
        advance(_OperationalSlot.disconnecting);
        final attempt = epoch;
        try {
          await pipe.disconnect();
          if (epoch != attempt || state != _OperationalSlot.disconnecting)
            throw StateError('SERVICE_UNAVAILABLE');
          state = _OperationalSlot.idle;
        } catch (_) {
          if (epoch == attempt) state = _OperationalSlot.failedDisconnect;
          rethrow;
        }
        return null;
      case 'close':
        _proofPause?.retire();
        _proofPause = null;
        if (epoch < _maximumEpoch) epoch++;
        failed = true;
        peer = null;
        state = _OperationalSlot.closed;
        try {
          await pipe.close();
        } finally {
          self.close();
        }
        return null;
      default:
        // Raw read/write/drain and arbitrary legacy sid/image/hash verification
        // are never a substitute for the connection-bound operational handle.
        throw StateError('UNAUTHORIZED');
    }
  }
}

Future<void> _operationalWorker(List<Object> startup) =>
    _bundleWorker(startup, trusted: false);

Future<void> _trustedWorker(List<Object> startup) =>
    _bundleWorker(startup, trusted: true);

Future<void> _bundleWorker(
  List<Object> startup, {
  required bool trusted,
}) async {
  final output = startup[0] as SendPort, input = ReceivePort();
  RetainedProcessIdentity? self;
  NativePipe? pipe;
  try {
    final config = startup[4] as Map,
        sid = startup[2] as String,
        server = startup[3] as bool;
    final root = config['appRoot'] as String,
        testOnly = config['testOnly'] as bool;
    final bundle = trusted
        ? _EndpointBundle.trusted(
            await verifyTrustedBuildBundle(root, testOnly: testOnly),
          )
        : _EndpointBundle.operational(
            await verifyMcpBuildBundle(root, testOnly: testOnly),
          );
    self = RetainedProcessIdentity.open(pid);
    final selfProof = bundle.verifyPeer(self, sid), role = selfProof.role;
    if (server ? role != BundlePeerRole.locald : role == BundlePeerRole.locald)
      throw StateError('UNAUTHORIZED');
    pipe = server
        ? NativePipe.createServer(startup[1] as String, sid)
        : NativePipe.openClient(startup[1] as String, sid);
    final endpoint = _OperationalEndpoint(
      pipe,
      bundle,
      self,
      selfProof,
      sid,
      server,
    );
    input.listen((message) async {
      if (message is! List || message.length != 3 || message[0] is! int) return;
      final id = message[0] as int, method = message[1] as String;
      try {
        final result = await endpoint.call(method, message[2]);
        output.send([id, true, result]);
      } catch (error) {
        output.send([
          id,
          false,
          PipeWorker._safeCode(error is StateError ? error.message : null),
        ]);
      } finally {
        if (method == 'close') input.close();
      }
    });
    output.send(input.sendPort);
  } catch (error) {
    try {
      await pipe?.close();
    } finally {
      self?.close();
      input.listen((message) {
        if (message == 'startupErrorAck') input.close();
      });
      output.send([
        'startupError',
        PipeWorker._safeCode(error is StateError ? error.message : null),
        input.sendPort,
      ]);
    }
  }
}
