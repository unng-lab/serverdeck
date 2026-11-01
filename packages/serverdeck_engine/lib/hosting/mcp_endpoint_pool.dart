import 'dart:async';

import 'package:serverdeck_protocol/discovery.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;

import '../api/mcp_channel.dart';
import '../api/mcp_server.dart';
import '../platform/ports.dart';
import 'sessions.dart';

/// Native implementations return an owned attempt before ready can fail.
/// Listeners accept one peer only; a slot is rebound after physical close.
abstract interface class McpListener {
  Future<void> get ready;
  Future<VerifiedMcpChannel> accept();
  Future<void> close();
}

/// The OS adapter protects/atomically replaces, then removes only its own exact
/// descriptor. Publish/remove futures represent actual I/O, never just timeout.
abstract interface class McpDiscoveryStore {
  Future<void> publish(DiscoveryDescriptor descriptor);
  Future<void> removeOwned(DiscoveryDescriptor descriptor);
}

final class _SlotAttempt {
  _SlotAttempt(this.name, this.onCloseFailure);
  final String name;
  final void Function() onCloseFailure;
  final provided = Completer<McpListener?>();
  VerifiedMcpChannel? peer;
  McpServerChannel? channel;
  Future<void>? run, closing, _peerClosing, _channelClosing;
  Future<void> closeChannel() {
    if (_channelClosing != null) return _channelClosing!;
    final value = channel;
    if (value == null) return Future.value();
    final done = Completer<void>();
    _channelClosing = done.future;
    done.future.ignore();
    Future<void>.sync(value.close).then<void>(
      done.complete,
      onError: (Object _, StackTrace __) {
        onCloseFailure();
        done.completeError(StateError('SERVICE_UNAVAILABLE'));
      },
    );
    return done.future;
  }

  Future<void> closePeer() {
    if (_peerClosing != null) return _peerClosing!;
    final value = peer;
    if (value == null) return Future.value();
    final done = Completer<void>();
    _peerClosing = done.future;
    done.future.ignore();
    Future<void>.sync(value.disconnect).then<void>(
      done.complete,
      onError: (Object _, StackTrace __) {
        onCloseFailure();
        done.completeError(StateError('SERVICE_UNAVAILABLE'));
      },
    );
    return done.future;
  }

  Future<void> close() {
    if (closing != null) return closing!;
    final done = Completer<void>();
    closing = done.future;
    done.future.ignore();
    () async {
      final listener = await provided.future;
      final results = await Future.wait<bool>([
        if (listener != null)
          Future<void>.sync(listener.close)
              .then((_) => true, onError: (Object _, StackTrace __) => false),
        if (channel != null)
          closeChannel().then(
            (_) => true,
            onError: (Object _, StackTrace __) => false,
          ),
        if (peer != null)
          closePeer().then(
            (_) => true,
            onError: (Object _, StackTrace __) => false,
          ),
      ]);
      if (results.contains(false)) throw StateError('SERVICE_UNAVAILABLE');
    }().then<void>(
      done.complete,
      onError: (Object _, StackTrace __) =>
          done.completeError(StateError('SERVICE_UNAVAILABLE')),
    );
    return done.future;
  }
}

/// One Host generation's eight actual MCP endpoints. This pool issues no owner
/// capability and never launches another process, store or domain service.
final class McpEndpointPool {
  McpEndpointPool({
    required this.descriptor,
    required this.server,
    required McpListener Function(String) createListener,
    required McpDiscoveryStore discovery,
    required void Function() checkLive,
    Duration Function()? elapsed,
  }) : _create = createListener,
       _discovery = discovery,
       _checkLive = checkLive,
       _elapsed = elapsed {
    if (descriptor.generation != server.sessions.generation ||
        descriptor.pipeNames.length != 8 ||
        descriptor.pipeNames.toSet().length != 8)
      throw ArgumentError('INVALID_MCP_PUBLICATION');
    _failure.future.ignore();
  }
  final DiscoveryDescriptor descriptor;
  final McpApiServer server;
  final McpListener Function(String) _create;
  final McpDiscoveryStore _discovery;
  final void Function() _checkLive;
  final Duration Function()? _elapsed;
  final _slots = <_SlotAttempt>[];
  final _loops = <Future<void>>{};
  final _permit = Completer<bool>();
  final _failure = Completer<void>();
  Future<void>? _binding, _activation, _closing;
  Future<void>? _bindPhysical, _activatePhysical;
  bool _stopping = false, _published = false, _physicalCloseFailed = false;
  int _channelId = 0;
  bool get isPublished => _published && !_stopping;
  Future<void> get failure => _failure.future;
  void _check() {
    if (_stopping) throw StateError('SERVICE_UNAVAILABLE');
    _checkLive();
  }

  static StateError _safe(Object error) => StateError(
    error is StateError &&
            const {
              'INCOMPATIBLE',
              'UNAUTHORIZED',
              'TIMEOUT',
              'NOT_READY',
              'RESOURCE_LIMIT',
              'STORAGE_BLOCKED',
              'PREREQUISITE_UNAVAILABLE',
              'SERVICE_UNAVAILABLE',
            }.contains(error.message)
        ? error.message
        : 'SERVICE_UNAVAILABLE',
  );
  void _fail([Object? error]) {
    if (!_failure.isCompleted)
      _failure.completeError(_safe(error ?? StateError('SERVICE_UNAVAILABLE')));
    stop();
  }

  _SlotAttempt _newAttempt(String name) {
    _check();
    final slot = _SlotAttempt(name, () {
      _physicalCloseFailed = true;
      _fail();
    });
    _slots.add(slot);
    try {
      final listener = _create(name);
      slot.provided.complete(listener);
      if (_stopping) slot.close().ignore();
    } catch (_) {
      slot.provided.complete(null);
      rethrow;
    }
    return slot;
  }

  Future<void> bind() {
    if (_binding != null) return _binding!;
    final done = Completer<void>();
    _binding = done.future;
    done.future.ignore();
    final physical = Completer<void>();
    _bindPhysical = physical.future;
    physical.future.ignore();
    Future<void>.sync(() async {
      for (final name in descriptor.pipeNames) _newAttempt(name);
      await Future.wait([
        for (final slot in _slots)
          slot.provided.future.then((listener) => listener!.ready),
      ]);
      _check();
      for (final slot in _slots.toList()) {
        final loop = _serveSlot(slot);
        _loops.add(loop);
        loop
            .then<void>(
              (_) => _loops.remove(loop),
              onError: (Object _, StackTrace __) {
                _loops.remove(loop);
                _fail();
              },
            )
            .ignore();
      }
    }).then<void>(
      (_) {
        physical.complete();
        done.complete();
      },
      onError: (Object error, StackTrace _) {
        _fail(error);
        physical.completeError(_safe(error));
        done.completeError(_safe(error));
      },
    );
    return done.future;
  }

  Future<void> activate({
    required Future<bool Function()> Function() beforePublish,
  }) {
    if (_activation != null) return _activation!;
    final done = Completer<void>();
    _activation = done.future;
    done.future.ignore();
    final physical = Completer<void>();
    _activatePhysical = physical.future;
    physical.future.ignore();
    Future<void>.sync(() async {
      await bind();
      _check();
      // Binding may finish while the same Host is suspended. Its retained
      // startup admission barrier must complete before readiness/publication.
      while (true) {
        final current = await beforePublish();
        _check();
        if (!current()) continue;
        final view = server.readiness();
        if (!current()) continue;
        if (view.state != ReadinessState.ready ||
            view.generation != descriptor.generation ||
            view.workspaceId != descriptor.workspaceId)
          throw StateError('NOT_READY');
        // No async gap between current Host intent and accepting publication I/O.
        break;
      }
      await _discovery.publish(descriptor);
      _check();
      _published = true;
      if (!_permit.isCompleted) _permit.complete(true);
    }).then<void>(
      (_) {
        physical.complete();
        done.complete();
      },
      onError: (Object error, StackTrace _) {
        _fail(error);
        physical.completeError(_safe(error));
        done.completeError(_safe(error));
      },
    );
    return done.future;
  }

  Future<void> _serveSlot(_SlotAttempt first) async {
    var slot = first;
    if (!await _permit.future) return;
    while (!_stopping) {
      try {
        final listener = (await slot.provided.future)!;
        final peer = await listener.accept();
        slot.peer = peer;
        if (_stopping) {
          await slot.closePeer();
          break;
        }
        if (_channelId == 0x7fffffffffffffff)
          throw StateError('RESOURCE_LIMIT');
        final token = descriptor.bootstrapToken;
        try {
          slot.channel = McpServerChannel(
            handshake: McpServerHandshake(
              peer: peer,
              token: token,
              channel: 'embedded:${++_channelId}',
              sessions: server.sessions,
              elapsed: _elapsed,
            ),
            server: server,
            elapsed: _elapsed,
          );
        } finally {
          token.fillRange(0, token.length, 0);
        }
        if (!_stopping) {
          slot.run = slot.channel!.run();
          await slot.run;
        }
      } catch (_) {
        // A bad/disconnected peer cannot kill the Host. Physical close below
        // decides whether this slot is safe to bind again.
      }
      // A cached listener close may predate accept/constructor completion.
      // Own these independently, including when their late close fails.
      await slot.closeChannel();
      await slot.closePeer();
      await slot.close();
      _slots.remove(slot);
      if (_stopping) break;
      slot = _newAttempt(slot.name);
      final listener = (await slot.provided.future)!;
      await listener.ready;
      _check();
    }
    await slot.close();
    _slots.remove(slot);
  }

  void stop() {
    if (_stopping) return;
    _stopping = true;
    _published = false;
    if (!_permit.isCompleted) _permit.complete(false);
    for (final slot in _slots.toList()) slot.close().ignore();
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    final done = Completer<void>();
    _closing = done.future;
    done.future.ignore();
    stop();
    () async {
      var clean = true;
      for (final work in [_bindPhysical, _activatePhysical]) {
        try {
          await work;
        } catch (_) {
          /* actual failure still owned */
        }
      }
      // Remove after late publish settles, so it cannot resurrect discovery.
      try {
        await _discovery.removeOwned(descriptor);
      } catch (_) {
        clean = false;
      }
      final slots = _slots.toList();
      for (final slot in slots) {
        try {
          await slot.close();
        } catch (_) {
          clean = false;
        }
      }
      try {
        await Future.wait(_loops.toList());
      } catch (_) {
        // Loop failure stops admission; slot.close above decides physical safety.
      }
      descriptor.close();
      if (!clean || _physicalCloseFailed)
        throw StateError('SERVICE_UNAVAILABLE');
    }().then<void>(
      done.complete,
      onError: (Object _, StackTrace __) =>
          done.completeError(StateError('SERVICE_UNAVAILABLE')),
    );
    return done.future;
  }
}
