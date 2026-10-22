import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/validation.dart';

import 'pipe_worker.dart';
import 'mcp_credential_files.dart';

part 'operational_grant_client.dart';
part 'operational_api_client.dart';
part 'client_peer.dart';

/// Bounded framing shared by the operational server/client adapters. Reads and
/// writes use the private epoch-bound native peer, never a raw transport callback.
final class OperationalHandshakeIo extends _HandshakeIo {
  OperationalHandshakeIo(this.peer) : super(_ClientPeer.operational(peer));
  final OperationalPipePeer peer;
}

final class TrustedHandshakeIo extends _HandshakeIo {
  TrustedHandshakeIo(this.peer) : super(_ClientPeer.trusted(peer));
  final TrustedPipePeer peer;
}

class _HandshakeIo {
  _HandshakeIo(this._peer);
  final _ClientPeer _peer;

  Future<Uint8List> read(Duration Function() remaining) async {
    Future<Uint8List> fill(int count) async {
      final result = Uint8List(count);
      var offset = 0;
      while (offset < count) {
        final bytes = await _peer.read(
          count: count - offset,
          deadline: remaining(),
        );
        remaining();
        if (bytes.isEmpty || bytes.length > count - offset)
          throw StateError('UNAUTHORIZED');
        result.setRange(offset, offset + bytes.length, bytes);
        offset += bytes.length;
      }
      return result;
    }

    final header = await fill(4);
    final length = ByteData.sublistView(header).getUint32(0, Endian.little);
    if (length < 1 || length > maxHandshakeBytes)
      throw StateError('UNAUTHORIZED');
    return fill(length);
  }

  Future<void> write(
    Map<String, Object?> message,
    Duration Function() remaining,
  ) async {
    final bytes = Uint8List.fromList(
      frameBytes(
        StrictCodec().encode(message, maxBytes: maxHandshakeBytes),
        maxBytes: maxHandshakeBytes,
      ),
    );
    try {
      await _peer.write(bytes, deadline: remaining());
      remaining();
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}

/// One client bootstrap attempt. Both the own image role and locald peer are
/// worker-verified; there is deliberately no expected-role argument/callback.
final class OperationalBootstrapClient
    extends _BootstrapClient<OperationalPipePeer, OperationalClientSession> {
  factory OperationalBootstrapClient({
    required PipeWorker pipe,
    required String generation,
    required List<int> token,
    Duration Function()? elapsed,
  }) {
    requireUuid(generation);
    if (token.length != 32 || token.any((b) => b < 0 || b > 255))
      throw ArgumentError('INVALID_HANDSHAKE_CONFIGURATION');
    return OperationalBootstrapClient._(
      pipe,
      generation,
      Uint8List.fromList(token),
      elapsed,
    );
  }
  OperationalBootstrapClient._(
    super._pipe,
    super.generation,
    super._token,
    super.elapsed,
  ) : super._();
  @override
  Future<OperationalPipePeer> _nativePeer() => _pipe.verifyOperationalPeer();
  @override
  _ClientPeer _binding(OperationalPipePeer peer) =>
      _ClientPeer.operational(peer);
  @override
  OperationalClientSession _sessionFor(
    OperationalPipePeer peer,
    OperationalHello hello,
    String id,
  ) => OperationalClientSession._(_pipe, peer, hello, id);
}

/// Format3 bootstrap has no caller-provided role, native proof or schema switch.
final class TrustedBootstrapClient
    extends _BootstrapClient<TrustedPipePeer, TrustedClientSession> {
  factory TrustedBootstrapClient({
    required PipeWorker pipe,
    required String generation,
    required List<int> token,
    Duration Function()? elapsed,
  }) {
    requireUuid(generation);
    if (token.length != 32 || token.any((b) => b < 0 || b > 255))
      throw ArgumentError('INVALID_HANDSHAKE_CONFIGURATION');
    return TrustedBootstrapClient._(
      pipe,
      generation,
      Uint8List.fromList(token),
      elapsed,
    );
  }
  TrustedBootstrapClient._(
    super._pipe,
    super.generation,
    super._token,
    super.elapsed,
  ) : super._();
  @override
  Future<TrustedPipePeer> _nativePeer() => _pipe.verifyTrustedPeer();
  @override
  _ClientPeer _binding(TrustedPipePeer peer) => _ClientPeer.trusted(peer);
  @override
  TrustedClientSession _sessionFor(
    TrustedPipePeer peer,
    OperationalHello hello,
    String id,
  ) => TrustedClientSession._(_pipe, peer, hello, id);
}

sealed class _BootstrapClient<P, S extends _ClientSession<P>> {
  _BootstrapClient._(
    this._pipe,
    this.generation,
    this._token,
    Duration Function()? elapsed,
  ) {
    _clock = elapsed ?? () => _watch.elapsed;
    _deadline = _clock() + rpcDeadline;
  }
  final PipeWorker _pipe;
  final String generation;
  final Uint8List _token;
  final _watch = Stopwatch()..start();
  late final Duration Function() _clock;
  late final Duration _deadline;
  bool _used = false, _closed = false;
  S? _session;
  Future<P> _nativePeer();
  _ClientPeer _binding(P peer);
  S _sessionFor(P peer, OperationalHello hello, String id);

  Duration _remaining() {
    if (_closed) throw StateError('UNAUTHORIZED');
    final value = _deadline - _clock();
    if (value <= Duration.zero) throw StateError('TIMEOUT');
    return value;
  }

  Future<void> _verify(_ClientPeer peer) async {
    await peer.revalidate().timeout(_remaining());
    _remaining();
    if (peer.role != BundlePeerRole.locald ||
        !{BundlePeerRole.owner, BundlePeerRole.mcp}.contains(peer.localRole))
      throw StateError('UNAUTHORIZED');
  }

  String _mac(Uint8List bytes) {
    final key = SecretKeyData(
      List<int>.of(_token),
      overwriteWhenDestroyed: true,
    );
    try {
      _remaining();
      return base64Url
          .encode(
            DartHmac.sha256()
                .calculateMacSync(bytes, secretKeyData: key, nonce: const [])
                .bytes,
          )
          .replaceAll('=', '');
    } finally {
      key.destroy();
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<S> authenticate() async {
    if (_used || _closed) {
      await close();
      throw StateError('UNAUTHORIZED');
    }
    _used = true;
    var success = false;
    try {
      final native = await _nativePeer().timeout(_remaining());
      final peer = _binding(native);
      await _verify(peer);
      final role = peer.localRole == BundlePeerRole.owner
          ? OperationalRole.owner
          : OperationalRole.mcp;
      final io = _HandshakeIo(peer);
      final document = StrictCodec().decode(
        await io.read(_remaining),
        maxBytes: maxHandshakeBytes,
      );
      final shape = document['hello'];
      if (shape is Map<String, Object?> &&
          shape['apiMajor'] is int &&
          shape['apiMinor'] is int &&
          (shape['apiMajor'] != 1 || shape['apiMinor'] != 1))
        throw StateError('INCOMPATIBLE');
      final hello = OperationalHello.fromJson(document);
      if (hello.generation != generation || hello.buildId != peer.buildId)
        throw StateError('INCOMPATIBLE');
      if (hello.clientRole != role) throw StateError('UNAUTHORIZED');
      await _verify(peer);
      final clientNonce = base64Url
          .encode(List<int>.generate(32, (_) => Random.secure().nextInt(256)))
          .replaceAll('=', '');
      final transcript = OperationalBootstrapTranscript(
        hello: hello,
        clientNonce: clientNonce,
        requestedCapabilities: [role.name],
      );
      final request = OperationalAuthenticate(
        clientNonce: clientNonce,
        clientBuildId: peer.buildId,
        requestedCapabilities: [role.name],
        proof: _mac(transcript.clientBytes()),
      );
      await io.write(request.toJson(), _remaining);
      final response = OperationalAuthenticated.decode(
        await io.read(_remaining),
      );
      if (response.clientRole != role ||
          response.capabilities.length != 1 ||
          response.capabilities.single != role.name) {
        throw StateError('UNAUTHORIZED');
      }
      final expected = base64Url.decode(
        '${_mac(transcript.serverBytes(response))}=',
      );
      final actual = base64Url.decode('${response.proof}=');
      var difference = expected.length ^ actual.length;
      for (var i = 0; i < expected.length; i++) {
        difference |= expected[i] ^ (i < actual.length ? actual[i] : 0);
      }
      if (difference != 0) throw StateError('UNAUTHORIZED');
      await _verify(peer);
      _remaining();
      final session = _sessionFor(native, hello, response.sessionId);
      _session = session;
      success = true;
      return session;
    } on TimeoutException {
      throw StateError('TIMEOUT');
    } on FormatException {
      throw StateError('UNAUTHORIZED');
    } finally {
      _token.fillRange(0, _token.length, 0);
      _watch.stop();
      if (!success) await close();
    }
  }

  Future<void> close() async {
    _closed = true;
    _token.fillRange(0, _token.length, 0);
    _watch.stop();
    _session?._retire();
    await _pipe.close();
  }
}

/// A bootstrap session only; an MCP session still has no grant authority until
/// a separate successful, current-policy-checked mcp.open.
final class OperationalClientSession
    extends _ClientSession<OperationalPipePeer> {
  OperationalClientSession._(
    PipeWorker pipe,
    OperationalPipePeer peer,
    OperationalHello hello,
    String id,
  ) : super._(pipe, peer, _ClientPeer.operational(peer), hello, id);
  Future<McpOpenResult> openGrant(McpCredentialFiles files, String grantId) =>
      _openGrant(files, grantId);
}

/// A native format3 bootstrap session; MCP still has no grant authority.
final class TrustedClientSession extends _ClientSession<TrustedPipePeer> {
  TrustedClientSession._(
    PipeWorker pipe,
    TrustedPipePeer peer,
    OperationalHello hello,
    String id,
  ) : super._(pipe, peer, _ClientPeer.trusted(peer), hello, id);
  Future<McpOpenResult> openGrant(McpCredentialFiles files, String grantId) =>
      _openGrant(files, grantId);
}

sealed class _ClientSession<P> {
  _ClientSession._(this._pipe, this.peer, this._binding, this.hello, this.id);
  final PipeWorker _pipe;
  final P peer;
  final _ClientPeer _binding;
  final OperationalHello hello;
  final String id;
  bool _closed = false;
  bool _grantAttempted = false;
  bool _ordinaryClaimed = false;
  McpOpenResult? _grant;
  McpOpenResult? get grant => _closed ? null : _grant;
  OperationalRole get role => hello.clientRole;
  Future<void> revalidate() async {
    if (_closed) throw StateError('UNAUTHORIZED');
    await _binding.revalidate();
    if (_closed) throw StateError('UNAUTHORIZED');
  }

  void _retire() {
    _closed = true;
  }

  Future<void> close() async {
    _retire();
    await _pipe.close();
  }
}
