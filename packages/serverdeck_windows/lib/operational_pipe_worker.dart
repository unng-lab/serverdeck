part of 'pipe_worker.dart';

/// Only this worker can issue an epoch-bound handle. It carries no native object
/// across isolates; every operation is checked inside its owning pipe worker.
final class OperationalPipePeer {
  OperationalPipePeer._(
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

  Future<void> revalidate() async {
    final result = (await _worker._call('peerVerify', _epoch)) as List;
    if (result[0] != _epoch ||
        result[1] != role.name ||
        result[2] != buildId ||
        result[3] != localRole.name)
      throw StateError('UNAUTHORIZED');
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
  final McpBuildBundle bundle;
  final RetainedProcessIdentity self;
  final VerifiedBundlePeer selfProof;
  final BundlePeerRole localRole;
  final String sid;
  final bool server;
  _OperationalSlot state;
  int epoch;
  bool failed = false;
  VerifiedBundlePeer? peer;
  static const _maximumEpoch = 0x7fffffffffffffff;

  void advance(_OperationalSlot next) {
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
      case 'peerVerify':
        final role = verify(params as int?);
        return [epoch, role.name, bundle.manifest.buildId, localRole.name];
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

Future<void> _operationalWorker(List<Object> startup) async {
  final output = startup[0] as SendPort, input = ReceivePort();
  RetainedProcessIdentity? self;
  NativePipe? pipe;
  try {
    final config = startup[4] as Map,
        sid = startup[2] as String,
        server = startup[3] as bool;
    final bundle = await verifyMcpBuildBundle(
      config['appRoot'] as String,
      testOnly: config['testOnly'] as bool,
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
