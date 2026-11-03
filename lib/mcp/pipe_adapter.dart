import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../domain/actor.dart';
import '../domain/app_operations.dart';
import '../domain/models.dart';
import '../runtime/capability.dart';
import '../runtime/native_platform.dart';
import '../runtime/owned_work.dart';
import 'grant_owner.dart';
import 'router.dart';

/// The native port supplies verified process-token identity, never JSON claims.
abstract interface class McpPipePort {
  Stream<PlatformEvent> get events;
  Future<void> publish();
  Future<void> remove();
  Future<void> send(String channelId, String frame);
  Future<void> close(String channelId);
  Future<void> acknowledge(String channelId);
  Future<void> writeGrant(
    String clientId,
    int version,
    Uint8List protectedSecret,
  );
  Future<void> deleteGrant(String clientId);
}

final class NativeMcpPipePort implements McpPipePort {
  NativeMcpPipePort(this.platform);
  final NativePlatform platform;
  @override
  Stream<PlatformEvent> get events => platform.events;
  @override
  Future<void> publish() => platform.publishMcpOwner();
  @override
  Future<void> remove() => platform.removeMcpOwner();
  @override
  Future<void> send(String id, String frame) =>
      platform.sendMcpFrame(id, frame);
  @override
  Future<void> close(String id) => platform.closeMcpChannel(id);
  @override
  Future<void> acknowledge(String id) => platform.acknowledgeMcpFrame(id);
  @override
  Future<void> writeGrant(String id, int version, Uint8List bytes) =>
      platform.writeMcpGrant(id, version, bytes);
  @override
  Future<void> deleteGrant(String id) => platform.deleteMcpGrant(id);
}

final class _PipeChannel {
  _PipeChannel(this.id, this.userSid, this.logonSid);
  final String id, userSid, logonSid;
  String? clientId;
  McpActor? actor;
  McpSession? session;
  bool closed = false, authenticating = false;
  int pending = 0;
  void Function()? cancelDeadline;
  Future<void>? closing;
  final work = <Future<void>>{};
}

final class McpPipeAdapter implements GrantTransport, RuntimeCapability {
  McpPipeAdapter({
    required this.port,
    required this.ownerEpoch,
    required this.getGrants,
    required this.getRouter,
    required this.utcNow,
    this.onUnavailable,
    ScheduleOwnedDeadline? schedule,
  }) : _schedule = schedule ?? _timer;
  final McpPipePort port;
  final String ownerEpoch;
  final GrantOwner Function() getGrants;
  final McpRouter Function() getRouter;
  final int Function() utcNow;
  final void Function()? onUnavailable;
  final ScheduleOwnedDeadline _schedule;
  static void Function() _timer(Duration d, void Function() callback) {
    final timer = Timer(d, callback);
    return timer.cancel;
  }

  final _channels = <String, _PipeChannel>{}, _work = <Future<void>>{};
  StreamSubscription<PlatformEvent>? _subscription;
  bool _enabled = false, _stopped = false;
  @override
  String get id => 'mcp-pipe';
  Future<void> initialize() async {
    _subscription ??= port.events.listen(_event);
  }

  void _track(Future<void> work) {
    final done = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _work.add(done);
    done.whenComplete(() => _work.remove(done)).ignore();
  }

  void _event(PlatformEvent event) {
    if (event.epoch != ownerEpoch || !event.type.startsWith('mcp')) return;
    if (event.type == 'mcpUnavailable') {
      _enabled = false;
      getGrants().transportReady(false);
      onUnavailable?.call();
      _track(setEnabled(false));
      return;
    }
    final payload = event.payload, id = payload['channelId'];
    if (id is! String || !isCanonicalUuid(id)) return;
    if (event.type == 'mcpChannelOpened') {
      // Native IDs use a non-repeating per-epoch sequence. Keep only live
      // resources here, rather than an unbounded history of closed channels.
      if (_channels.containsKey(id)) {
        _track(_close(_channels[id]!));
        return;
      }
      final user = payload['userSid'], logon = payload['logonSid'];
      if (!_enabled ||
          _stopped ||
          _channels.length >= 8 ||
          user is! String ||
          logon is! String) {
        _track(port.close(id));
        return;
      }
      final channel = _PipeChannel(id, user, logon);
      _channels[id] = channel;
      channel.cancelDeadline = _schedule(
        const Duration(seconds: 5),
        () => _track(_close(channel)),
      );
      return;
    }
    final channel = _channels[id];
    if (channel == null) return;
    if (event.type == 'mcpChannelClosed') {
      channel.closed = true;
      channel.cancelDeadline?.call();
      channel.session?.closed = true;
      // Already admitted mutations retain their commit/receipt semantics on EOF.
      _channels.remove(id);
      return;
    }
    if (event.type != 'mcpFrame' || channel.closed) return;
    final frame = payload['frame'];
    if (frame is! String ||
        utf8.encode(frame).length + 1 > 2 * 1024 * 1024 ||
        channel.pending >= 16) {
      _track(_close(channel));
      return;
    }
    channel.pending++;
    final work = _frame(channel, frame)
        .catchError((Object _, StackTrace __) => _close(channel))
        .whenComplete(() async {
          channel.pending--;
          try {
            await port.acknowledge(channel.id);
          } catch (_) {
            await _close(channel);
          }
        });
    channel.work.add(work);
    work.whenComplete(() => channel.work.remove(work)).ignore();
    _track(work);
  }

  Future<void> _frame(_PipeChannel c, String line) async {
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    final kind = decoded['kind'];
    if (c.actor == null) {
      if (c.authenticating ||
          kind != 'auth' ||
          decoded.length != 6 ||
          decoded['version'] != 1 ||
          decoded['ownerEpoch'] != ownerEpoch)
        throw const FormatException();
      final client = decoded['clientId'],
          version = decoded['grantVersion'],
          secret = decoded['secret'];
      if (client is! String ||
          !isCanonicalUuid(client) ||
          version is! int ||
          version < 1 ||
          version > 9007199254740991 ||
          secret is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(secret))
        throw const FormatException();
      // Reserve the per-grant slot before asynchronous DPAPI or authentication.
      if (_channels.values
              .where((v) => !v.closed && v.clientId == client)
              .length >=
          2) {
        await _deny(c);
        return;
      }
      c.clientId = client;
      c.authenticating = true;
      final bytes = base64Url.decode('$secret=');
      try {
        if (bytes.length != 32 ||
            base64Url.encode(bytes).replaceAll('=', '') != secret)
          throw const FormatException();
        final grants = getGrants();
        final actor = await grants.authenticate(
          client,
          version,
          bytes,
          peerUserSid: c.userSid,
          peerLogonSid: c.logonSid,
        );
        if (c.closed || !_enabled || _stopped) return;
        c.actor = actor;
        c.session = getRouter().session(actor);
        c.cancelDeadline?.call();
        final expiry = grants.expiry(actor), remaining = expiry - utcNow();
        if (remaining <= 0)
          throw const OperationFailure(FailureCode.accessRevoked);
        c.cancelDeadline = _schedule(Duration(milliseconds: remaining), () {
          _track(grants.expireClient(actor.clientId, actor.grantVersion));
          _track(_close(c));
        });
        await grants.authorize(actor, AuthorizationPoint.response);
        await _send(c, {
          'kind': 'authorized',
          'version': 1,
          'grantVersion': version,
          'expiresAt': expiry,
        });
      } catch (_) {
        await _deny(c);
      } finally {
        bytes.fillRange(0, bytes.length, 0);
        c.authenticating = false;
      }
      return;
    }
    if (kind != 'mcp' ||
        decoded.length != 2 ||
        decoded['payload'] is! Map<String, dynamic>)
      throw const FormatException();
    final actor = c.actor!, grants = getGrants();
    await grants.authorize(actor, AuthorizationPoint.admission);
    if (c.closed) return;
    final result = await c.session!.handle(
      decoded['payload'] as Map<String, dynamic>,
    );
    if (result != null && !c.closed) {
      await grants.authorize(actor, AuthorizationPoint.response);
      await _send(c, {'kind': 'mcp', 'payload': result});
    }
    if (c.session!.closed) await _close(c);
  }

  Future<void> _send(_PipeChannel c, Map<String, Object?> frame) async {
    if (c.closed) return;
    final text = jsonEncode(frame);
    if (utf8.encode(text).length + 1 > 2 * 1024 * 1024)
      throw const FormatException();
    await port.send(c.id, text);
  }

  Future<void> _deny(_PipeChannel c) async {
    try {
      await _send(c, {'kind': 'error', 'code': 'AUTH_REQUIRED'});
    } finally {
      await _close(c);
    }
  }

  Future<void> _close(_PipeChannel c) {
    c.closed = true;
    c.cancelDeadline?.call();
    c.session?.closed = true;
    return c.closing ??= _closeNative(c);
  }

  Future<void> _closeNative(_PipeChannel c) async {
    try {
      await port.close(c.id);
      _channels.remove(c.id);
    } catch (_) {
      c.closing = null;
      rethrow;
    }
  }

  @override
  Future<void> closeClient(String clientId) async {
    await Future.wait(
      _channels.values
          .where((c) => c.clientId == clientId)
          .toList()
          .map(_close),
    );
  }

  @override
  Future<void> setEnabled(bool value) async {
    if (value && _stopped)
      throw const OperationFailure(FailureCode.shuttingDown);
    _enabled = false;
    getGrants().transportReady(false);
    await port.remove();
    await Future.wait(_channels.values.toList().map(_close));
    if (value) {
      await initialize();
      _enabled = true;
      try {
        await port.publish();
        getGrants().transportReady(true);
      } catch (_) {
        _enabled = false;
        rethrow;
      }
    }
  }

  @override
  Future<void> writeGrant(String clientId, int version, Uint8List bytes) =>
      port.writeGrant(clientId, version, bytes);
  @override
  Future<void> deleteGrant(String clientId) => port.deleteGrant(clientId);
  @override
  Future<void> stopAdmission() async {
    _stopped = true;
    _enabled = false;
    getGrants().transportReady(false);
    await port.remove();
  }

  @override
  Future<void> cancelPending() async {
    await Future.wait(_channels.values.toList().map(_close));
  }

  @override
  Future<void> closeSessions() => cancelPending();
  @override
  Future<void> drain() async {
    while (_work.isNotEmpty) {
      await Future.wait(List.of(_work));
    }
  }

  @override
  Future<void> dispose() async {
    await stopAdmission();
    await cancelPending();
    await drain();
    await _subscription?.cancel();
    _subscription = null;
  }
}
