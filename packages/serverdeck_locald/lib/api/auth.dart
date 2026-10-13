import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_protocol/wire.dart';

import 'sessions.dart';

String _nonce() => base64Url
    .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');

/// A single channel challenge. The host binds verifyPeer to the retained native
/// pipe peer/image verifier, and closes the channel on any handshake exception.
class ServerHandshake {
  ServerHandshake({
    required List<int> token,
    required this.generation,
    required this.buildId,
    required this.channel,
    required this.sessions,
    required Future<void> Function() verifyPeer,
    Duration Function()? elapsed,
  }) : _token = Uint8List.fromList(token),
       _verifyPeer = verifyPeer {
    requireUuid(generation);
    if (token.length != 32 ||
        token.any((b) => b < 0 || b > 255) ||
        sessions.generation != generation ||
        channel.isEmpty ||
        !RegExp(r'^[a-f0-9]{40}\+(Debug|Release)\+[a-f0-9]{64}$')
            .hasMatch(buildId))
      throw ArgumentError('INVALID_HANDSHAKE_CONFIGURATION');
    _clock = elapsed ?? () => _watch.elapsed;
    _deadline = _clock() + rpcDeadline;
  }
  final String generation, buildId, channel;
  final SessionRegistry sessions;
  final Uint8List _token;
  final Future<void> Function() _verifyPeer;
  final _watch = Stopwatch()..start();
  late final Duration Function() _clock;
  late final Duration _deadline;
  String? _serverNonce;
  bool _started = false, _used = false, _closed = false;

  void _live() {
    if (_closed) throw StateError('UNAUTHORIZED');
    if (_clock() >= _deadline) throw StateError('TIMEOUT');
  }

  Future<void> _verify() async {
    _live();
    try {
      await _verifyPeer().timeout(_deadline - _clock());
    } on TimeoutException {
      throw StateError('TIMEOUT');
    } catch (_) {
      throw StateError('UNAUTHORIZED');
    }
    _live();
  }

  Future<ServerHello> hello() async {
    if (_started) throw StateError('UNAUTHORIZED');
    _started = true;
    try {
      await _verify();
      _serverNonce = _nonce();
      return ServerHello(generation: generation, serverNonce: _serverNonce!);
    } catch (_) {
      close();
      rethrow;
    }
  }

  String _transcript(
    String role,
    String nonce,
    List<String> caps, {
    String? sessionId,
  }) =>
      '$role\n1\ndefault\n$generation\n$_serverNonce\n$nonce\n$buildId\n${caps.join(',')}${sessionId == null ? '' : '\n$sessionId\n${caps.join(',')}'}';

  List<int> _mac(String transcript) {
    final secret = SecretKeyData(
      List<int>.of(_token),
      overwriteWhenDestroyed: true,
    );
    final bytes = Uint8List.fromList(utf8.encode(transcript));
    try {
      return DartHmac.sha256()
          .calculateMacSync(bytes, secretKeyData: secret, nonce: const [])
          .bytes;
    } finally {
      secret.destroy();
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  bool _matches(List<int> a, List<int> b) {
    var difference = a.length ^ b.length;
    for (var i = 0; i < a.length; i++)
      difference |= a[i] ^ (i < b.length ? b[i] : 0);
    return difference == 0;
  }

  Future<Authenticated> authenticate(List<int> frame) async {
    if (_used || _serverNonce == null) throw StateError('UNAUTHORIZED');
    _used = true;
    try {
      _live();
      final document = StrictCodec().decode(frame, maxBytes: maxHandshakeBytes);
      validateAuthenticate(document);
      final body = document['authenticate'] as Map<String, Object?>;
      if (body['clientBuildId'] != buildId) throw StateError('INCOMPATIBLE');
      final caps = (body['requestedCapabilities'] as List)
          .cast<String>()
          .toList();
      final nonce = body['clientNonce'] as String;
      if (!_matches(
        _mac(_transcript('client', nonce, caps)),
        base64Url.decode('${body['proof']}='),
      ))
        throw StateError('UNAUTHORIZED');
      await _verify();
      final sessionId = _nonce();
      final response = Authenticated(
        sessionId: sessionId,
        capabilities: List.unmodifiable(caps),
        proof: base64Url
            .encode(
              _mac(_transcript('server', nonce, caps, sessionId: sessionId)),
            )
            .replaceAll('=', ''),
      );
      _live();
      sessions.register(
        channel,
        sessionId,
        caps
            .map(
              (name) =>
                  Capability.values.singleWhere((c) => c.wireName == name),
            )
            .toSet(),
      );
      return response;
    } on FormatException {
      throw StateError('UNAUTHORIZED');
    } finally {
      close();
    }
  }

  void close() {
    _closed = true;
    _serverNonce = null;
    _token.fillRange(0, _token.length, 0);
    _watch.stop();
  }
}
