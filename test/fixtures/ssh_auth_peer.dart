import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/hostkey/hostkey_ed25519.dart';
import 'package:dartssh2/src/hostkey/hostkey_rsa.dart';
import 'package:dartssh2/src/kex/kex_x25519.dart';
import 'package:dartssh2/src/message/msg_ext_info.dart';
import 'package:dartssh2/src/message/msg_kex.dart';
import 'package:dartssh2/src/message/msg_kex_ecdh.dart';
import 'package:dartssh2/src/message/msg_request.dart';
import 'package:dartssh2/src/message/msg_service.dart';
import 'package:dartssh2/src/message/msg_userauth.dart';
import 'package:dartssh2/src/ssh_kex_utils.dart';
import 'package:dartssh2/src/ssh_message.dart';
import 'package:dartssh2/src/ssh_packet.dart';
import 'package:dartssh2/src/utils/cipher_ext.dart';
import 'package:pointycastle/export.dart';

enum SyntheticAuthReply { success, failure, partial }

/// Deterministic protocol fixture over memory streams; never opens a socket.
/// Its deliberately narrow codec accepts the pinned client's one-packet writes,
/// X25519, Ed/RSA-SHA256 host keys, AES128-CTR/HMAC-SHA256 and opt-in synthetic channel packets (never remote execution).
final class MemoryAuthPeer implements SSHSocket {
  MemoryAuthPeer({
    required SSHKeyPair hostKey,
    this.authReply = SyntheticAuthReply.success,
    this.expectedPassword = 'synthetic-password',
    this.serverSignatureAlgorithms,
    this.fragmentSize,
    this.replyToPing = true,
  }) : _hostKey = hostKey {
    _sink = _MemorySink(_write, close, _closed.future);
  }
  SSHKeyPair _hostKey;
  final SyntheticAuthReply authReply;
  final String expectedPassword;
  final List<String>? serverSignatureAlgorithms;
  final int? fragmentSize;
  bool replyToPing;
  bool authSuccessBeforeRequest = false;
  final _incoming = StreamController<Uint8List>();
  final _closed = Completer<void>();
  Future<void>? _closing;
  late final _MemorySink _sink;
  SSHKexX25519 _kex = SSHKexX25519();
  String? _clientVersion;
  static const _version = 'SSH-2.0-ServerDeck-memory-auth-unit';
  Uint8List? _clientKex, _serverKex, _sessionId;
  _Crypto? _out, _in, _nextOut, _nextIn;
  int _sendSequence = 0, _receiveSequence = 0;
  bool _serverInitiated = false;
  final clientMessageIds = <int>[];
  final authRequests = <SSH_Message_Userauth_Request>[];
  int pings = 0, exchanges = 0;
  bool authenticated = false, lastAuthSignatureValid = false;
  Object? codecFailure;
  // Optional protocol fixture extension; default auth tests still reject channels.
  void Function(Uint8List)? onChannelPacket;
  void sendChannelPacket(Uint8List packet) {
    if (!authenticated) throw StateError('Synthetic peer is not authenticated');
    _send(packet);
  }

  @override
  Stream<Uint8List> get stream => _incoming.stream;
  @override
  StreamSink<List<int>> get sink => _sink;
  @override
  Future<void> get done => _closed.future;

  Uint8List _kexInit() => SSH_Message_KexInit(
    kexAlgorithms: [SSHKexType.x25519Rfc.name, 'ext-info-s'],
    serverHostKeyAlgorithms: [
      _hostKey is OpenSSHRsaKeyPair
          ? SSHHostkeyType.rsaSha256.name
          : SSHHostkeyType.ed25519.name,
    ],
    encryptionClientToServer: [SSHCipherType.aes128ctr.name],
    encryptionServerToClient: [SSHCipherType.aes128ctr.name],
    macClientToServer: [SSHMacType.hmacSha256.name],
    macServerToClient: [SSHMacType.hmacSha256.name],
    compressionClientToServer: ['none'],
    compressionServerToClient: ['none'],
    firstKexPacketFollows: false,
  ).encode();

  /// A verified different key is for the client's changed-host notification test.
  void beginRekey(SSHKeyPair hostKey) {
    if (_closing != null || !authenticated || _serverInitiated)
      throw StateError('Invalid fixture rekey');
    _hostKey = hostKey;
    _kex.privateKey.fillRange(0, _kex.privateKey.length, 0);
    _kex = SSHKexX25519();
    _serverInitiated = true;
    _serverKex = _kexInit();
    _send(_serverKex!);
  }

  void _write(List<int> bytes) {
    if (_closing != null) return;
    try {
      if (_clientVersion == null) {
        _clientVersion = ascii.decode(bytes).trim();
        _emit(Uint8List.fromList(ascii.encode('$_version\r\n')));
        return;
      }
      final wire = Uint8List.fromList(bytes);
      final packet = _in == null ? wire : _in!.unpack(wire, _receiveSequence);
      if (packet.length < 8 ||
          SSHPacket.readPacketLength(packet) + 4 != packet.length)
        throw StateError('Synthetic packet framing');
      final payload = Uint8List.sublistView(
        packet,
        5,
        packet.length - SSHPacket.readPaddingLength(packet),
      );
      _receiveSequence = (_receiveSequence + 1) & 0xffffffff;
      clientMessageIds.add(payload.first);
      _handle(payload);
    } catch (error) {
      codecFailure = error;
      _incoming.addError(StateError('Synthetic codec failure'));
      unawaited(close());
    }
  }

  void _handle(Uint8List payload) {
    switch (payload.first) {
      case 20:
        _clientKex = Uint8List.fromList(payload);
        if (!_serverInitiated) {
          if (exchanges > 0) {
            _kex.privateKey.fillRange(0, _kex.privateKey.length, 0);
            _kex = SSHKexX25519();
          }
          _serverKex = _kexInit();
          _send(_serverKex!);
        }
      case 30:
        final clientPublic = SSH_Message_KexECDH_Init.decode(payload)
            .ecdhPublicKey;
        final secret = _kex.computeSecret(clientPublic);
        final hostBlob = _hostKey.toPublicKey().encode();
        final hash = SSHKexUtils.computeExchangeHash(
          digest: SHA256Digest(),
          clientVersion: _clientVersion!,
          serverVersion: _version,
          clientKexInit: _clientKex!,
          serverKexInit: _serverKex!,
          hostKey: hostBlob,
          clientPublicKey: clientPublic,
          serverPublicKey: _kex.publicKey,
          sharedSecret: secret,
        );
        _sessionId ??= Uint8List.fromList(hash);
        Uint8List derive(SSHDeriveKeyType type, int length) =>
            SSHKexUtils.deriveKey(
              digest: SHA256Digest(),
              sharedSecret: secret,
              exchangeHash: hash,
              keyType: type,
              sessionId: _sessionId!,
              keySize: length,
            );
        _nextOut = _Crypto(
          derive(SSHDeriveKeyType.serverKey, 16),
          derive(SSHDeriveKeyType.serverIV, 16),
          derive(SSHDeriveKeyType.serverMacKey, 32),
          true,
        );
        _nextIn = _Crypto(
          derive(SSHDeriveKeyType.clientKey, 16),
          derive(SSHDeriveKeyType.clientIV, 16),
          derive(SSHDeriveKeyType.clientMacKey, 32),
          false,
        );
        _send(
          SSH_Message_KexECDH_Reply(
            hostPublicKey: hostBlob,
            ecdhPublicKey: _kex.publicKey,
            signature: _hostKey.sign(hash).encode(),
          ).encode(),
        );
        _send(Uint8List.fromList([21]));
        _out?.dispose();
        _out = _nextOut;
        _nextOut = null;
        exchanges++;
        if (exchanges == 1 && serverSignatureAlgorithms != null) {
          _send(
            SSH_Message_ExtInfo({
              'server-sig-algs': Uint8List.fromList(
                ascii.encode(serverSignatureAlgorithms!.join(',')),
              ),
            }).encode(),
          );
        }
      case 21:
        _in?.dispose();
        _in = _nextIn;
        _nextIn = null;
        _serverInitiated = false;
      case 5:
        final request = SSH_Message_Service_Request.decode(payload);
        _send(
          authSuccessBeforeRequest
              ? SSH_Message_Userauth_Success().encode()
              : SSH_Message_Service_Accept(request.serviceName).encode(),
        );
      case 50:
        final request = SSH_Message_Userauth_Request.decode(
          Uint8List.fromList(payload),
        );
        authRequests.add(request);
        final accepted = request.methodName == 'password'
            ? request.password == expectedPassword
            : _verifyPublicAuth(request);
        if (accepted && authReply == SyntheticAuthReply.success) {
          authenticated = true;
          _send(SSH_Message_Userauth_Success().encode());
        } else {
          _send(
            SSH_Message_Userauth_Failure(
              methodsLeft: ['password', 'publickey', 'keyboard-interactive'],
              partialSuccess:
                  accepted && authReply == SyntheticAuthReply.partial,
            ).encode(),
          );
        }
      case 80:
        final request = SSH_Message_Global_Request.decode(payload);
        if (!authenticated || request.requestName != 'keepalive@openssh.com')
          throw StateError('Unexpected synthetic global request');
        pings++;
        if (replyToPing && request.wantReply) _send(Uint8List.fromList([81]));
      case 1: // Client disconnect; owner close follows.
      case 7: // Client extension information is irrelevant to this narrow fixture.
        break;
      default:
        if (payload.first >= 90 &&
            payload.first <= 100 &&
            onChannelPacket != null) {
          onChannelPacket!(Uint8List.fromList(payload));
          break;
        }
        throw StateError('Unexpected synthetic message ${payload.first}');
    }
  }

  bool _verifyPublicAuth(SSH_Message_Userauth_Request request) {
    if (request.methodName != 'publickey' ||
        request.signature == null ||
        request.publicKey == null)
      return false;
    final writer = SSHMessageWriter();
    writer.writeString(_sessionId!);
    writer.writeUint8(50);
    writer.writeUtf8(request.user);
    writer.writeUtf8(request.serviceName);
    writer.writeUtf8('publickey');
    writer.writeBool(true);
    writer.writeUtf8(request.publicKeyAlgorithm!);
    writer.writeString(request.publicKey!);
    final challenge = writer.takeBytes();
    final bool valid;
    if (request.publicKeyAlgorithm == 'ssh-ed25519') {
      valid = SSHEd25519PublicKey.decode(request.publicKey!)
          .verify(challenge, SSHEd25519Signature.decode(request.signature!));
    } else if ([
      'rsa-sha2-256',
      'rsa-sha2-512',
    ].contains(request.publicKeyAlgorithm)) {
      final signature = SSHRsaSignature.decode(request.signature!);
      valid =
          signature.type == request.publicKeyAlgorithm &&
          SSHRsaPublicKey.decode(request.publicKey!)
              .verify(challenge, signature);
    } else {
      valid = false;
    }
    lastAuthSignatureValid = valid;
    return valid;
  }

  void _send(Uint8List payload) {
    if (_closing != null) return;
    final packet = SSHPacket.pack(payload, align: _out == null ? 8 : 16);
    _emit(_out == null ? packet : _out!.pack(packet, _sendSequence));
    _sendSequence = (_sendSequence + 1) & 0xffffffff;
  }

  void _emit(Uint8List bytes) {
    final fragment = fragmentSize ?? bytes.length;
    if (fragment < 1) throw StateError('Invalid synthetic fragmentation');
    for (var offset = 0; offset < bytes.length; offset += fragment) {
      final end = offset + fragment < bytes.length
          ? offset + fragment
          : bytes.length;
      _incoming.add(Uint8List.fromList(bytes.sublist(offset, end)));
    }
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _kex.privateKey.fillRange(0, _kex.privateKey.length, 0);
    for (final crypto in [_out, _in, _nextOut, _nextIn]) {
      crypto?.dispose();
    }
    await _incoming.close();
    _closed.complete();
  }

  @override
  void destroy() => unawaited(close());
  @override
  Future<void> flush() async {}
}

final class _Crypto {
  _Crypto(this.key, this.iv, this.macKey, bool encrypt)
    : cipher = SSHCipherType.aes128ctr.createCipher(
        key,
        iv,
        forEncryption: encrypt,
      ),
      mac = SSHMacType.hmacSha256.createMac(macKey);
  final Uint8List key, iv, macKey;
  final BlockCipher cipher;
  final Mac mac;
  Uint8List _tag(Uint8List packet, int sequence) {
    final number = ByteData(4)..setUint32(0, sequence);
    mac.updateAll(Uint8List.view(number.buffer));
    mac.updateAll(packet);
    return mac.finish();
  }

  Uint8List pack(Uint8List packet, int sequence) => Uint8List.fromList([
    ...cipher.processAll(packet),
    ..._tag(packet, sequence),
  ]);
  Uint8List unpack(Uint8List wire, int sequence) {
    if (wire.length < 48 || (wire.length - 32) % 16 != 0)
      throw StateError('Synthetic cipher framing');
    final packet = cipher.processAll(
      Uint8List.sublistView(wire, 0, wire.length - 32),
    );
    final expected = _tag(packet, sequence),
        actual = Uint8List.sublistView(wire, wire.length - 32);
    var difference = 0;
    for (var i = 0; i < 32; i++) {
      difference |= expected[i] ^ actual[i];
    }
    if (difference != 0) throw StateError('Synthetic MAC failure');
    return packet;
  }

  void dispose() {
    for (final bytes in [key, iv, macKey]) {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}

final class _MemorySink implements StreamSink<List<int>> {
  _MemorySink(this.write, this.stop, this.completion);
  final void Function(List<int>) write;
  final Future<void> Function() stop;
  final Future<void> completion;
  @override
  void add(List<int> bytes) => write(bytes);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      throw StateError('Unexpected synthetic sink error');
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final bytes in stream) {
      write(bytes);
    }
  }

  @override
  Future<void> close() => stop();
  @override
  Future<void> get done => completion;
}
