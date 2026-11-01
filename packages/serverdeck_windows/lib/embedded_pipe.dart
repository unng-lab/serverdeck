import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_engine/hosting/mcp_endpoint_pool.dart';

import 'embedded_build_bundle.dart';
import 'embedded_pipe_policy.dart';
import 'pipe.dart';
import 'publication_gate.dart';
import 'security.dart';

String _safe(Object error) =>
    error is StateError &&
        const {
          'UNAUTHORIZED',
          'INCOMPATIBLE',
          'SERVICE_UNAVAILABLE',
          'TIMEOUT',
          'RESOURCE_LIMIT',
          'PREREQUISITE_UNAVAILABLE',
          'VALIDATION',
          'UNSAFE_ENDPOINT',
        }.contains(error.message)
    ? error.message
    : 'SERVICE_UNAVAILABLE';

/// Own the attempt before awaiting ready. One listener accepts one peer only;
/// rebinding a slot requires this listener/channel's confirmed physical close.
final class EmbeddedPipeListener implements McpListener {
  EmbeddedPipeListener.bind(String name)
    : _driver = _PipeDriver(name, true, null);
  final _PipeDriver _driver;
  Future<EmbeddedPipeChannel>? _accepting;
  Future<void> get ready => _driver.ready.then<void>((_) {});
  Future<EmbeddedPipeChannel> accept() {
    if (_accepting != null) return _accepting!;
    final done = Completer<EmbeddedPipeChannel>();
    _accepting = done.future;
    done.future.ignore();
    () async {
      await ready;
      await _driver.call('accept', null);
      return EmbeddedPipeChannel._(_driver);
    }().then<void>(
      done.complete,
      onError: (Object error, StackTrace _) => done.completeError(error),
    );
    return done.future;
  }

  Future<void> close() => _driver.close();
}

/// Native proof is issued only by this dedicated worker after verifying both
/// actual retained processes against its own bundle4. No role, owner DTO or
/// raw transport factory can construct a channel. It never creates a store.
final class EmbeddedPipeChannel implements VerifiedMcpChannel {
  EmbeddedPipeChannel._(this._driver);
  final _PipeDriver _driver;
  factory EmbeddedPipeChannel.connecting(
    String name, {
    required int serverPid,
  }) {
    requireEmbeddedPeerPid(serverPid);
    return EmbeddedPipeChannel._(_PipeDriver(name, false, serverPid));
  }

  /// Own the attempt before awaiting this future; disconnect also owns failures.
  Future<void> get ready => _driver.ready.then<void>((_) {});

  @override
  String get ownerIdentity => _driver.metadata[0];
  @override
  String get appRoot => _driver.metadata[1];
  @override
  String get buildId => _driver.metadata[2];
  @override
  Future<void> revalidate({
    void Function(Future<void>)? observeNativeCompletion,
  }) {
    final actual = _driver
        .call('proof', Timeline.now + 5000000)
        .then<void>((_) {});
    actual.ignore();
    observeNativeCompletion?.call(actual);
    return actual;
  }

  int _end(Duration deadline, {bool reading = false}) {
    if (deadline <= Duration.zero ||
        deadline > Duration(seconds: reading ? 60 : 5))
      throw StateError('VALIDATION');
    return Timeline.now + deadline.inMicroseconds;
  }

  @override
  Future<Uint8List> read({
    required int count,
    required Duration deadline,
  }) async {
    if (count < 1 || count > 65536) throw StateError('RESOURCE_LIMIT');
    return await _driver.call('read', [count, _end(deadline, reading: true)])
        as Uint8List;
  }

  @override
  Future<void> write(List<int> bytes, {required Duration deadline}) async {
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024 + 4)
      throw StateError('RESOURCE_LIMIT');
    final owned = Uint8List.fromList(bytes);
    try {
      await _driver.call('write', [owned, _end(deadline)]);
    } finally {
      owned.fillRange(0, owned.length, 0);
    }
  }

  @override
  Future<void> drainOutput({required Duration deadline}) async {
    await _driver.call('drain', _end(deadline));
  }

  @override
  Future<void> disconnect() => _driver.close();

  /// Synchronization only, not a role/grant. The caller supplies the generation
  /// from its authenticated handshake; own identity is always retained natively.
  Future<WindowsPublicationGate> publicationGate(String generation) async {
    await revalidate();
    final root = appRoot, sid = ownerIdentity;
    final bundle = await verifyEmbeddedBuildBundle(root);
    VerifiedApplicationPeer? actualSelf;
    final gate = await WindowsPublicationGate.open(
      ownerIdentity: sid,
      appRoot: root,
      generation: generation,
      verifyCurrentProcess: (identity) {
        actualSelf ??= bundle.verifyPeer(identity, sid);
        actualSelf!.requireCurrentProcess(bundle);
      },
    );
    try {
      if (gate.isClosed) throw StateError('SERVICE_UNAVAILABLE');
      await revalidate();
      return gate;
    } catch (_) {
      await gate.close();
      rethrow;
    }
  }
}

/// One private VM route; capacity is retained until actual native replies. A
/// reserved close is not an ordinary-slot request. Exit alone is not close ACK.
final class _PipeDriver {
  _PipeDriver(String name, bool server, int? expectedPid) {
    _ready.future.ignore();
    _input.future.ignore();
    _output.listen(_receive);
    _exit.listen((_) => _lost());
    _errors.listen((_) => _lost());
    Isolate.spawn(
          _pipeMain,
          [_output.sendPort, name, server, expectedPid],
          onExit: _exit.sendPort,
          onError: _errors.sendPort,
          errorsAreFatal: true,
        )
        .then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {
            _lost();
          },
        )
        .ignore();
  }
  final _output = ReceivePort(), _exit = ReceivePort(), _errors = ReceivePort();
  final _ready = Completer<List<String>>(), _input = Completer<SendPort>();
  final _pending = <int, Completer<Object?>>{};
  List<String>? _metadata;
  int _sequence = 0;
  bool _closing = false, _failed = false, _physicalClosed = false;
  Future<void>? _close;
  Future<List<String>> get ready => _ready.future;
  List<String> get metadata {
    if (_metadata == null || _closing || _failed)
      throw StateError('UNAUTHORIZED');
    return _metadata!;
  }

  void _receive(Object? message) {
    if (message is! List || message.length != 3) return _lost();
    if (message[0] == 'input' &&
        message[1] == true &&
        message[2] is SendPort &&
        !_input.isCompleted) {
      _input.complete(message[2] as SendPort);
      return;
    }
    if (message[0] == 'ready' && !_ready.isCompleted) {
      if (message[1] == true &&
          message[2] is List &&
          (message[2] as List).length == 3 &&
          (message[2] as List).every((v) => v is String)) {
        _metadata = List<String>.unmodifiable(
          (message[2] as List).cast<String>(),
        );
        _ready.complete(_metadata!);
      } else if (message[1] == false && message[2] is String) {
        _ready.completeError(StateError(_safe(StateError(message[2]))));
      } else {
        _lost();
      }
      return;
    }
    if (message[0] is! int ||
        message[1] is! bool ||
        (message[1] == false && message[2] is! String))
      return _lost();
    final id = message[0] as int, pending = _pending.remove(message[0]);
    if (pending == null) return _lost();
    if (message[1] == true) {
      if (_closing && id == _closeSequence) {
        _physicalClosed = true;
        pending.complete(message[2]);
        _input.future
            .then<void>((port) => port.send([0, 'ackClose', null]))
            .ignore();
        _dispose();
      } else
        pending.complete(message[2]);
    } else
      pending.completeError(StateError(_safe(StateError(message[2]))));
  }

  int? _closeSequence;
  Future<Object?> call(String method, Object? params) {
    if (_closing || _failed)
      return Future.error(StateError('SERVICE_UNAVAILABLE'));
    if (_pending.length >= 16)
      return Future.error(StateError('RESOURCE_LIMIT'));
    return _send(method, params);
  }

  Future<Object?> _send(String method, Object? params) {
    if (_sequence == 0x7fffffffffffffff) {
      _lost();
      return Future.error(StateError('SERVICE_UNAVAILABLE'));
    }
    final id = ++_sequence, done = Completer<Object?>();
    done.future.ignore();
    _pending[id] = done;
    if (method == 'close') _closeSequence = id;
    _input.future
        .then<void>(
          (port) {
            try {
              port.send([id, method, params]);
            } catch (_) {
              _lost();
            }
          },
          onError: (Object _, StackTrace __) {
            _lost();
          },
        )
        .ignore();
    return done.future;
  }

  Future<void> close() {
    if (_close != null) return _close!;
    _closing = true;
    if (_failed)
      return _close = Future.error(StateError('SERVICE_UNAVAILABLE'))..ignore();
    return _close = _send('close', null).then<void>((_) {});
  }

  void _lost() {
    if (_physicalClosed) return;
    if (_failed) return;
    _failed = true;
    if (!_ready.isCompleted)
      _ready.completeError(StateError('SERVICE_UNAVAILABLE'));
    if (!_input.isCompleted)
      _input.completeError(StateError('SERVICE_UNAVAILABLE'));
    for (final pending in _pending.values) {
      pending.completeError(StateError('SERVICE_UNAVAILABLE'));
    }
    _pending.clear();
    _dispose();
    // Do not kill or infer native cleanup; root must keep its lease on failure.
  }

  void _dispose() {
    _output.close();
    _exit.close();
    _errors.close();
  }
}

void _pipeMain(List<Object?> boot) {
  final worker = _NativePipeOwner(
    boot[0] as SendPort,
    boot[1] as String,
    boot[2] as bool,
    boot[3] as int?,
  );
  worker.start();
}

final class _NativePipeOwner {
  _NativePipeOwner(this.out, this.name, this.server, this.expectedPid);
  final SendPort out;
  final String name;
  final bool server;
  final int? expectedPid;
  final input = ReceivePort();
  final _startup = Completer<void>();
  final _active = <Future<void>>{};
  NativePipe? pipe;
  RetainedProcessIdentity? self;
  EmbeddedBuildBundle? bundle;
  VerifiedApplicationPeer? selfProof, peer;
  String? owner, root, build;
  bool closing = false, failed = false, accepted = false;
  bool identityCreationFailed = false;
  NativePipeCreationFailure? creationFailure;
  Future<void>? _closing;
  void start() {
    _startup.future.ignore();
    input.listen(_handle);
    out.send(['input', true, input.sendPort]);
    () async {
      if (!Platform.isWindows) throw StateError('PREREQUISITE_UNAVAILABLE');
      root = p.dirname(Platform.resolvedExecutable);
      owner = currentUserSid();
      await requireEmbeddedEndpoint(name, owner!);
      bundle = await verifyEmbeddedBuildBundle(root!);
      try {
        self = RetainedProcessIdentity.open(pid);
      } catch (_) {
        // The factory did not transfer a retained object, so this owner cannot
        // confirm partial process-handle cleanup. No successful slot reuse.
        identityCreationFailed = true;
        rethrow;
      }
      selfProof = bundle!.verifyPeer(self!, owner!);
      selfProof!.requireCurrentProcess(bundle!);
      build = bundle!.buildId;
      if (closing) throw StateError('SERVICE_UNAVAILABLE');
      pipe = server
          ? NativePipe.createServer(name, owner!)
          : NativePipe.openClient(name, owner!);
      if (!server) {
        final end = Timeline.now + 5000000;
        _proof();
        remainingPipeBudget(end, Timeline.now);
        accepted = true;
      }
      if (closing) throw StateError('SERVICE_UNAVAILABLE');
      out.send([
        'ready',
        true,
        [owner, root, build],
      ]);
    }().then<void>(
      (_) {
        _startup.complete();
      },
      onError: (Object error, StackTrace _) {
        if (error is NativePipeCreationFailure) creationFailure = error;
        failed = true;
        out.send(['ready', false, _safe(error)]);
        _startup.complete();
      },
    );
  }

  void _proof() {
    selfProof!.requireCurrentProcess(bundle!);
    final actual = pipe!.peerIdentity();
    peer ??= bundle!.verifyPeer(actual, owner!);
    peer!.revalidate();
    if (expectedPid != null && actual.pid != expectedPid)
      throw StateError('UNAUTHORIZED');
    selfProof!.requireCurrentProcess(bundle!);
  }

  void _handle(Object? message) {
    if (message is! List ||
        message.length != 3 ||
        message[0] is! int ||
        message[1] is! String)
      return;
    final id = message[0] as int,
        method = message[1] as String,
        params = message[2];
    if (method == 'ackClose') {
      if (closing && _closedOkay) input.close();
      return;
    }
    if (method == 'close') {
      _close().then<void>(
        (_) => out.send([id, true, null]),
        onError: (Object error, StackTrace _) =>
            out.send([id, false, _safe(error)]),
      );
      return;
    }
    final done = Completer<void>();
    _active.add(done.future);
    Future<Object?>.sync(() async {
      await _startup.future;
      if (closing || failed) throw StateError('SERVICE_UNAVAILABLE');
      if (method == 'accept') {
        if (!server || accepted) throw StateError('UNAUTHORIZED');
        accepted = true;
        await pipe!.accept();
        if (closing) throw StateError('SERVICE_UNAVAILABLE');
        final end = Timeline.now + 5000000;
        _proof();
        remainingPipeBudget(end, Timeline.now);
        return null;
      }
      if (!accepted || peer == null) throw StateError('UNAUTHORIZED');
      switch (method) {
        case 'proof':
          remainingPipeBudget(params as int, Timeline.now);
          _proof();
          remainingPipeBudget(params, Timeline.now);
        case 'read':
          final values = params as List;
          return await pipe!.read(
            count: values[0] as int,
            deadline: remainingPipeReadBudget(values[1] as int, Timeline.now),
          );
        case 'write':
          final values = params as List, bytes = values[0] as Uint8List;
          try {
            await pipe!.write(
              bytes,
              deadline: remainingPipeBudget(values[1] as int, Timeline.now),
            );
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        case 'drain':
          await pipe!.drainOutput(
            deadline: remainingPipeBudget(params as int, Timeline.now),
          );
        default:
          throw StateError('UNAUTHORIZED');
      }
      return null;
    }).then<void>(
      (result) {
        out.send([id, true, result]);
        if (result is Uint8List) result.fillRange(0, result.length, 0);
        done.complete();
        _active.remove(done.future);
      },
      onError: (Object error, StackTrace _) {
        if (method == 'accept' || method == 'proof') failed = true;
        if (params is List && params.isNotEmpty && params[0] is Uint8List)
          (params[0] as Uint8List).fillRange(
            0,
            (params[0] as Uint8List).length,
            0,
          );
        out.send([id, false, _safe(error)]);
        done.complete();
        _active.remove(done.future);
      },
    );
  }

  bool _closedOkay = false;
  Future<void> _close() {
    if (_closing != null) return _closing!;
    final done = Completer<void>();
    _closing = done.future;
    done.future.ignore();
    closing = true;
    () async {
      await _startup.future;
      var clean = !identityCreationFailed;
      try {
        await pipe?.close();
        await creationFailure?.close();
      } catch (_) {
        clean = false;
      }
      await Future.wait(_active.toList());
      if (self != null && !self!.close()) clean = false;
      if (!clean) throw StateError('SERVICE_UNAVAILABLE');
      _closedOkay = true;
    }().then<void>(
      done.complete,
      onError: (Object _, StackTrace __) =>
          done.completeError(StateError('SERVICE_UNAVAILABLE')),
    );
    return done.future;
  }
}
