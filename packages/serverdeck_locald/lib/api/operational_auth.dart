import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_windows/pipe_worker.dart';

import '../storage/state_store.dart';

part 'operational_sessions.dart';
part 'operational_grants.dart';
part 'operational_context.dart';
part 'operational_open_failure.dart';

String _randomNonce() => base64Url
    .encode(List<int>.generate(32, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');

OperationalRole _clientRole(OperationalPipePeer peer) {
  if (peer.localRole != BundlePeerRole.locald) throw StateError('UNAUTHORIZED');
  return switch (peer.role) {
    BundlePeerRole.owner => OperationalRole.owner,
    BundlePeerRole.mcp => OperationalRole.mcp,
    _ => throw StateError('UNAUTHORIZED'),
  };
}

bool _sameMac(List<int> a, List<int> b) {
  var different = a.length ^ b.length;
  for (var i = 0; i < a.length; i++) {
    different |= a[i] ^ (i < b.length ? b[i] : 0);
  }
  return different == 0;
}

/// Operational server bootstrap. Only a private native peer can supply a role;
/// the registry has no public registration or caller-selected role API.
final class OperationalServerHandshake {
  factory OperationalServerHandshake({
    required OperationalPipePeer peer,
    required List<int> token,
    required String channel,
    required OperationalSessions sessions,
    Duration Function()? elapsed,
  }) {
    if (token.length != 32 ||
        token.any((b) => b < 0 || b > 255) ||
        channel.isEmpty) {
      throw ArgumentError('INVALID_HANDSHAKE_CONFIGURATION');
    }
    final role = _clientRole(peer);
    return OperationalServerHandshake._(
      peer,
      Uint8List.fromList(token),
      channel,
      sessions,
      role,
      elapsed,
    );
  }
  OperationalServerHandshake._(
    this.peer,
    this._token,
    this.channel,
    this.sessions,
    this.role,
    Duration Function()? elapsed,
  ) {
    _clock = elapsed ?? () => _watch.elapsed;
    _deadline = _clock() + rpcDeadline;
  }

  final OperationalPipePeer peer;
  final String channel;
  final OperationalSessions sessions;
  final OperationalRole role;
  final Uint8List _token;
  final _watch = Stopwatch()..start();
  late final Duration Function() _clock;
  late final Duration _deadline;
  OperationalHello? _hello;
  String? _issuedSessionId;
  bool _started = false, _used = false, _closed = false;

  Duration _remaining() {
    if (_closed) throw StateError('UNAUTHORIZED');
    final remaining = _deadline - _clock();
    if (remaining <= Duration.zero) throw StateError('TIMEOUT');
    return remaining;
  }

  Future<void> _verify() async {
    try {
      await peer.revalidate().timeout(_remaining());
      _remaining();
      if (_clientRole(peer) != role) throw StateError('UNAUTHORIZED');
    } on TimeoutException {
      throw StateError('TIMEOUT');
    } on StateError catch (error) {
      if (error.message == 'TIMEOUT') rethrow;
      throw StateError('UNAUTHORIZED');
    }
  }

  String _mac(Uint8List transcript) {
    final key = SecretKeyData(
      List<int>.of(_token),
      overwriteWhenDestroyed: true,
    );
    try {
      _remaining();
      return base64Url
          .encode(
            DartHmac.sha256()
                .calculateMacSync(
                  transcript,
                  secretKeyData: key,
                  nonce: const [],
                )
                .bytes,
          )
          .replaceAll('=', '');
    } finally {
      key.destroy();
      transcript.fillRange(0, transcript.length, 0);
    }
  }

  Future<OperationalHello> hello() async {
    if (_started || _closed) {
      close();
      throw StateError('UNAUTHORIZED');
    }
    _started = true;
    try {
      await _verify();
      return _hello = OperationalHello(
        generation: sessions.generation,
        serverNonce: _randomNonce(),
        buildId: peer.buildId,
        clientRole: role,
      );
    } catch (_) {
      close();
      rethrow;
    }
  }

  Future<OperationalAuthenticated> authenticate(List<int> frame) async {
    if (_used || _hello == null || _closed) {
      close();
      throw StateError('UNAUTHORIZED');
    }
    _used = true;
    var registered = false;
    try {
      _remaining();
      if (frame.isEmpty ||
          frame.length > maxHandshakeBytes ||
          frame.any((b) => b < 0 || b > 255)) {
        throw StateError('UNAUTHORIZED');
      }
      final frozen = Uint8List.fromList(frame);
      await _verify();
      final input = OperationalAuthenticate.decode(frozen);
      if (input.clientBuildId != peer.buildId) throw StateError('INCOMPATIBLE');
      final transcript = OperationalBootstrapTranscript(
        hello: _hello!,
        clientNonce: input.clientNonce,
        requestedCapabilities: input.requestedCapabilities,
      );
      if (!_sameMac(
        base64Url.decode('${_mac(transcript.clientBytes())}='),
        base64Url.decode('${input.proof}='),
      ))
        throw StateError('UNAUTHORIZED');
      final unsigned = OperationalAuthenticated(
        sessionId: _randomNonce(),
        clientRole: role,
        capabilities: [role.name],
        proof: input.proof,
      );
      final response = OperationalAuthenticated(
        sessionId: unsigned.sessionId,
        clientRole: role,
        capabilities: unsigned.capabilities,
        proof: _mac(transcript.serverBytes(unsigned)),
      );
      await _verify();
      _remaining();
      _issuedSessionId = response.sessionId;
      sessions._register(channel, response.sessionId, _hello!, peer);
      registered = true;
      return response;
    } on FormatException {
      throw StateError('UNAUTHORIZED');
    } finally {
      // Successful registration outlives the consumed bootstrap key. The channel
      // must disconnect it if authenticated response delivery subsequently fails.
      _disposeToken();
      if (!registered) _removeOwnedSession();
    }
  }

  void _disposeToken() {
    _closed = true;
    _token.fillRange(0, _token.length, 0);
    _watch.stop();
  }

  void close() {
    _disposeToken();
    _removeOwnedSession();
  }

  void _removeOwnedSession() {
    final current = sessions._sessions[channel];
    if (current != null &&
        current.id == _issuedSessionId &&
        identical(current.peer, peer)) {
      sessions.disconnect(channel);
    }
  }
}
