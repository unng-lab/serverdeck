import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/hostkey/hostkey_ed25519.dart';
import 'package:dartssh2/src/hostkey/hostkey_rsa.dart';
import 'package:dartssh2/src/kex/kex_x25519.dart';
import 'package:dartssh2/src/message/msg_kex.dart';
import 'package:dartssh2/src/message/msg_kex_ecdh.dart';
import 'package:dartssh2/src/ssh_kex_utils.dart';
import 'package:dartssh2/src/ssh_packet.dart';
import 'package:pointycastle/export.dart';

/// An in-memory pre-NEWKEYS byte fixture, not a listening SSH service.
/// It sends only version/KEX/reply and never encrypts or authenticates a session.
final class MemoryKexPeer implements SSHSocket {
  MemoryKexPeer({
    required this.hostKey,
    required this.negotiated,
    this.rsaSignatureType,
    this.tamperSignature = false,
  }) {
    _serverKex = SSH_Message_KexInit(
      kexAlgorithms: [SSHKexType.x25519Rfc.name],
      serverHostKeyAlgorithms: [negotiated.name],
      encryptionClientToServer: [SSHCipherType.aes128ctr.name],
      encryptionServerToClient: [SSHCipherType.aes128ctr.name],
      macClientToServer: [SSHMacType.hmacSha256.name],
      macServerToClient: [SSHMacType.hmacSha256.name],
      compressionClientToServer: ['none'],
      compressionServerToClient: ['none'],
      firstKexPacketFollows: false,
    ).encode();
    _sink = _PeerSink(_write, close, _closed.future);
  }
  final SSHKeyPair hostKey;
  final SSHHostkeyType negotiated;
  final String? rsaSignatureType;
  final bool tamperSignature;
  final _incoming = StreamController<Uint8List>();
  final _closed = Completer<void>();
  Future<void>? _closing;
  final _kex = SSHKexX25519();
  late final Uint8List _serverKex;
  late final _PeerSink _sink;
  Uint8List? _clientKex;
  String? _clientVersion;
  static const serverVersion = 'SSH-2.0-ServerDeck-synthetic-unit-peer';
  final clientMessageIds = <int>[];
  Uint8List? exchangeHash, signature;
  bool signatureVerifies = false;
  @override
  Stream<Uint8List> get stream => _incoming.stream;
  @override
  StreamSink<List<int>> get sink => _sink;
  @override
  Future<void> get done => _closed.future;
  void injectRaw(Uint8List bytes) {
    if (_closing == null) _incoming.add(Uint8List.fromList(bytes));
  }

  void _write(List<int> bytes) {
    if (_closing != null) return;
    if (_clientVersion == null) {
      _clientVersion = ascii.decode(bytes).trim();
      _incoming.add(Uint8List.fromList(ascii.encode('$serverVersion\r\n')));
      return;
    }
    final packet = Uint8List.fromList(bytes);
    final payload = Uint8List.sublistView(
      packet,
      SSHPacket.headerLength,
      packet.length - SSHPacket.readPaddingLength(packet),
    );
    clientMessageIds.add(payload.first);
    if (payload.first == SSH_Message_KexInit.messageId) {
      _clientKex = Uint8List.fromList(payload);
      _send(_serverKex);
    } else if (payload.first == SSH_Message_KexECDH_Init.messageId) {
      final clientKey = SSH_Message_KexECDH_Init.decode(payload).ecdhPublicKey;
      final hash = SSHKexUtils.computeExchangeHash(
        digest: SHA256Digest(),
        clientVersion: _clientVersion!,
        serverVersion: serverVersion,
        clientKexInit: _clientKex!,
        serverKexInit: _serverKex,
        hostKey: hostKey.toPublicKey().encode(),
        clientPublicKey: clientKey,
        serverPublicKey: _kex.publicKey,
        sharedSecret: _kex.computeSecret(clientKey),
      );
      exchangeHash = hash;
      late SSHSignature signed;
      if (hostKey is OpenSSHRsaKeyPair) {
        final key = hostKey as OpenSSHRsaKeyPair;
        final type = rsaSignatureType ?? negotiated.name;
        final (Digest, String) digest = switch (type) {
          'ssh-rsa' => (SHA1Digest(), '06052b0e03021a'),
          'rsa-sha2-256' => (SHA256Digest(), '0609608648016503040201'),
          'rsa-sha2-512' => (SHA512Digest(), '0609608648016503040203'),
          _ => throw StateError('Unsupported synthetic signature'),
        };
        final signer = RSASigner(digest.$1, digest.$2)
          ..init(
            true,
            PrivateKeyParameter<RSAPrivateKey>(
              RSAPrivateKey(key.n, key.d, key.p, key.q),
            ),
          );
        final rsa = SSHRsaSignature(type, signer.generateSignature(hash).bytes);
        signatureVerifies = (key.toPublicKey() as SSHRsaPublicKey).verify(
          hash,
          rsa,
        );
        signed = rsa;
      } else {
        final ed = hostKey.sign(hash) as SSHEd25519Signature;
        signatureVerifies = (hostKey.toPublicKey() as SSHEd25519PublicKey)
            .verify(hash, ed);
        signed = ed;
      }
      final encoded = signed.encode();
      if (tamperSignature) encoded.last ^= 1;
      signature = encoded;
      _send(
        SSH_Message_KexECDH_Reply(
          hostPublicKey: hostKey.toPublicKey().encode(),
          ecdhPublicKey: _kex.publicKey,
          signature: encoded,
        ).encode(),
      );
    }
  }

  void _send(Uint8List payload) =>
      _incoming.add(SSHPacket.pack(payload, align: SSHPacket.minAlign));
  @override
  Future<void> close() => _closing ??= _finishClose();
  Future<void> _finishClose() async {
    _kex.privateKey.fillRange(0, _kex.privateKey.length, 0);
    await _incoming.close();
    _closed.complete();
  }

  @override
  void destroy() => unawaited(close());
  @override
  Future<void> flush() async {}
}

final class _PeerSink implements StreamSink<List<int>> {
  _PeerSink(this.write, this.stop, this.completion);
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
