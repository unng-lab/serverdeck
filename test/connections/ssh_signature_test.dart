import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:serverdeck/profiles/credential_parser.dart';
import 'package:serverdeck/connections/host_signature.dart';

import '../fixtures/ssh_kex_peer.dart';

void main() {
  for (final useWorker in [false, true]) {
    for (final negotiated in [
      SSHHostkeyType.rsaSha1,
      SSHHostkeyType.rsaSha256,
      SSHHostkeyType.rsaSha512,
    ]) {
      for (final signatureType in ['ssh-rsa', 'rsa-sha2-256', 'rsa-sha2-512']) {
        test(
          'KEX ${negotiated.name} binds embedded $signatureType before host callback, worker=$useWorker',
          () async {
            final parsed = parsePrivateKey(
              File('test/fixtures/ssh/rsa2048.txt').readAsBytesSync(),
            );
            final peer = MemoryKexPeer(
              hostKey: parsed.key,
              negotiated: negotiated,
              rsaSignatureType: signatureType,
            );
            var verifies = 0, passwords = 0;
            final verifier = HostSignatureVerifier();
            final client = SSHClient(
              peer,
              username: 'synthetic',
              algorithms: SSHAlgorithms(hostkey: [negotiated]),
              onPasswordRequest: () {
                passwords++;
                return 'SYNTHETIC';
              },
              onHostKeyChanged: (_, _, _) {},
              onVerifyHostSignature: useWorker ? verifier.verify : null,
              onVerifyHostKey: (type, fingerprint, blob) {
                verifies++;
                expect(type, negotiated.name);
                expect(blob, parsed.key.toPublicKey().encode());
                expect(
                  utf8.decode(fingerprint),
                  'SHA256:${base64.encode(SHA256Digest().process(blob)).replaceAll('=', '')}',
                );
                return false; // No trust acceptance/auth continuation in this fixture.
              },
              keepAliveInterval: null,
              handshakeTimeout: null,
              authTimeout: null,
            );
            try {
              await expectLater(
                client.authenticated,
                throwsA(isA<SSHAuthAbortError>()),
              );
              expect(peer.signatureVerifies, isTrue);
              expect(
                verifies,
                signatureType == negotiated.name && signatureType != 'ssh-rsa'
                    ? 1
                    : 0,
              );
              expect(passwords, 0);
              expect(peer.clientMessageIds, isNot(contains(50)));
            } finally {
              await client.close();
              await verifier.dispose();
              await peer.done;
              parsed.dispose();
            }
          },
        );
      }
    }
    for (final tamper in [false, true]) {
      test(
        'Ed25519 KEX verifies exact blob before trust, tampered=$tamper worker=$useWorker',
        () async {
          final parsed = parsePrivateKey(
            File('test/fixtures/ssh/ed25519.txt').readAsBytesSync(),
          );
          final peer = MemoryKexPeer(
            hostKey: parsed.key,
            negotiated: SSHHostkeyType.ed25519,
            tamperSignature: tamper,
          );
          var calls = 0;
          final verifier = HostSignatureVerifier();
          final client = SSHClient(
            peer,
            username: 'synthetic',
            onPasswordRequest: () => 'SYNTHETIC',
            onHostKeyChanged: (_, _, _) {},
            onVerifyHostSignature: useWorker ? verifier.verify : null,
            onVerifyHostKey: (_, _, Uint8List blob) {
              calls++;
              expect(blob, parsed.key.toPublicKey().encode());
              return false;
            },
            keepAliveInterval: null,
            handshakeTimeout: null,
            authTimeout: null,
          );
          try {
            await expectLater(
              client.authenticated,
              throwsA(isA<SSHAuthAbortError>()),
            );
            expect(calls, tamper ? 0 : 1);
          } finally {
            await client.close();
            await verifier.dispose();
            parsed.dispose();
          }
        },
      );
    }
  }
}
