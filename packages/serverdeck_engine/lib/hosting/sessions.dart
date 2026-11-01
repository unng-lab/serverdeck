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
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_engine/platform/ports.dart';

import 'authority.dart';

import 'package:serverdeck_engine/storage/state_store.dart';

import 'package:serverdeck_engine/hosting/target_changes.dart';

part 'session_registry.dart';
part 'grant_authority.dart';
part 'mcp_context.dart';
part 'owner_context.dart';
part 'open_failure.dart';

part 'session_peer.dart';
part 'owner_session.dart';

String _randomNonce() => base64Url
    .encode(List<int>.generate(32, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');

OperationalRole _sessionRole(_SessionPeer peer) {
  peer.requireCurrent();
  return peer.role;
}

bool _sameMac(List<int> a, List<int> b) {
  var different = a.length ^ b.length;
  for (var i = 0; i < a.length; i++) {
    different |= a[i] ^ (i < b.length ? b[i] : 0);
  }
  return different == 0;
}

OperationalRole _bootstrapRole(
  List<int> token,
  String channel,
  _SessionPeer peer,
) {
  if (token.length != 32 ||
      token.any((b) => b < 0 || b > 255) ||
      channel.isEmpty)
    throw ArgumentError('INVALID_HANDSHAKE_CONFIGURATION');
  // Preserve configuration validation first, but reject a wrong native side
  // before allocating any owned secret buffer in a constructor that can fail.
  return _sessionRole(peer);
}

/// External bootstrap is MCP-only. Owner sessions have no handshake path.
final class McpServerHandshake {
  factory McpServerHandshake({
    required VerifiedMcpChannel peer,
    required List<int> token,
    required String channel,
    required EngineSessions sessions,
    Duration Function()? elapsed,
  }) {
    final binding = _McpPeer(sessions, peer);
    _bootstrapRole(token, channel, binding);
    return McpServerHandshake._(
      peer,
      binding,
      token,
      channel,
      sessions,
      elapsed,
    );
  }
  McpServerHandshake._(
    this.peer,
    this._binding,
    List<int> token,
    this.channel,
    this.sessions,
    Duration Function()? elapsed,
  ) : role = _bootstrapRole(token, channel, _binding),
      _token = Uint8List.fromList(token) {
    try {
      _clock = elapsed ?? () => _watch.elapsed;
      _deadline = _clock() + rpcDeadline;
    } catch (_) {
      _token.fillRange(0, _token.length, 0);
      _watch.stop();
      rethrow;
    }
  }

  final VerifiedMcpChannel peer;
  final _McpPeer _binding;
  final String channel;
  final EngineSessions sessions;
  final OperationalRole role;
  final Uint8List _token;
  final _watch = Stopwatch()..start();
  late final Duration Function() _clock;
  late final Duration _deadline;
  OperationalHello? _hello;
  String? _issuedSessionId;
  bool _started = false, _used = false, _closed = false;

  /// Endpoint liveness only, including bootstrap response after token disposal.
  Future<void> verifyPeer() => _binding.revalidate();

  Duration _remaining() {
    if (_closed) throw StateError('UNAUTHORIZED');
    final remaining = _deadline - _clock();
    if (remaining <= Duration.zero) throw StateError('TIMEOUT');
    return remaining;
  }

  Future<void> _verify() async {
    try {
      await _binding.revalidate().timeout(_remaining());
      _remaining();
      if (_sessionRole(_binding) != role) throw StateError('UNAUTHORIZED');
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
        buildId: _binding.buildId,
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
      if (input.clientBuildId != _binding.buildId)
        throw StateError('INCOMPATIBLE');
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
      sessions._register(
        channel,
        response.sessionId,
        _hello!,
        _binding,
        _binding,
        admissionEpoch: _binding._epoch,
      );
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
        identical(current.peer, _binding)) {
      sessions.disconnect(channel);
    }
  }
}
