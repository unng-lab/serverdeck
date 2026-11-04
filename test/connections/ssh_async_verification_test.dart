import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/profiles/credential_parser.dart';

import '../fixtures/ssh_kex_peer.dart';

void main() {
  for (final during in ['signature', 'trust']) {
    test(
      'late positive $during callback cannot resume a closed handshake',
      () async {
        final parsed = parsePrivateKey(
          File('test/fixtures/ssh/ed25519.txt').readAsBytesSync(),
        );
        final peer = MemoryKexPeer(
          hostKey: parsed.key,
          negotiated: SSHHostkeyType.ed25519,
        );
        final entered = Completer<void>(), release = Completer<bool>();
        var hosts = 0, passwords = 0;
        final client = SSHClient(
          peer,
          username: 'synthetic',
          onPasswordRequest: () {
            passwords++;
            return 'SYNTHETIC';
          },
          onHostKeyChanged: (_, _, _) {},
          onVerifyHostSignature: (type, key, sig, hash) {
            if (during == 'signature') {
              entered.complete();
              return release.future;
            }
            return SSHTransport.verifyHostSignature(
              negotiatedType: type,
              keyBytes: key,
              signatureBytes: sig,
              exchangeHash: hash,
            );
          },
          onVerifyHostKey: (_, _, _) {
            hosts++;
            if (during == 'trust') {
              entered.complete();
              return release.future;
            }
            return false;
          },
          keepAliveInterval: null,
          handshakeTimeout: null,
          authTimeout: null,
        );
        final failed = expectLater(
          client.authenticated,
          throwsA(isA<SSHAuthAbortError>()),
        );
        try {
          await entered.future;
          await client.close();
          await failed;
          release.complete(true);
          await Future<void>.delayed(Duration.zero);
          expect(hosts, during == 'signature' ? 0 : 1);
          expect(passwords, 0);
          expect(peer.clientMessageIds, isNot(contains(21)));
          expect(peer.clientMessageIds, isNot(contains(50)));
        } finally {
          if (!release.isCompleted) release.complete(false);
          await client.close();
          parsed.dispose();
        }
      },
    );
    for (final cumulative in [false, true]) {
      test(
        'receive buffer is bounded while $during callback waits, cumulative=$cumulative',
        () async {
          final parsed = parsePrivateKey(
            File('test/fixtures/ssh/ed25519.txt').readAsBytesSync(),
          );
          final peer = MemoryKexPeer(
            hostKey: parsed.key,
            negotiated: SSHHostkeyType.ed25519,
          );
          final entered = Completer<void>(), release = Completer<bool>();
          var hosts = 0, passwords = 0;
          final client = SSHClient(
            peer,
            username: 'synthetic',
            onPasswordRequest: () {
              passwords++;
              return 'SYNTHETIC';
            },
            onHostKeyChanged: (_, _, _) {},
            onVerifyHostSignature: (type, key, sig, hash) {
              if (during == 'signature') {
                entered.complete();
                return release.future;
              }
              return SSHTransport.verifyHostSignature(
                negotiatedType: type,
                keyBytes: key,
                signatureBytes: sig,
                exchangeHash: hash,
              );
            },
            onVerifyHostKey: (_, _, _) {
              hosts++;
              if (during == 'trust') {
                entered.complete();
                return release.future;
              }
              return false;
            },
            keepAliveInterval: null,
            handshakeTimeout: null,
            authTimeout: null,
          );
          final failed = expectLater(
            client.authenticated,
            throwsA(
              isA<SSHAuthAbortError>().having(
                (e) => e.reason,
                'reason',
                isA<SSHResourceLimitError>(),
              ),
            ),
          );
          try {
            await entered.future;
            if (cumulative) {
              peer.injectRaw(Uint8List(600 * 1024));
              peer.injectRaw(Uint8List(600 * 1024));
            } else {
              peer.injectRaw(Uint8List(SSHTransport.maxBufferedBytes + 1));
            }
            await failed;
            release.complete(true);
            await Future<void>.delayed(Duration.zero);
            expect(hosts, during == 'signature' ? 0 : 1);
            expect(passwords, 0);
            expect(peer.clientMessageIds, isNot(contains(21)));
            expect(peer.clientMessageIds, isNot(contains(50)));
          } finally {
            if (!release.isCompleted) release.complete(false);
            await client.close();
            parsed.dispose();
          }
        },
      );
    }
  }
  test(
    'format policy is checked before an injected async crypto hook',
    () async {
      final parsed = parsePrivateKey(
        File('test/fixtures/ssh/rsa2048.txt').readAsBytesSync(),
      );
      final peer = MemoryKexPeer(
        hostKey: parsed.key,
        negotiated: SSHHostkeyType.rsaSha512,
        rsaSignatureType: 'ssh-rsa',
      );
      var crypto = 0, hosts = 0;
      final client = SSHClient(
        peer,
        username: 'synthetic',
        onPasswordRequest: () => 'SYNTHETIC',
        onHostKeyChanged: (_, _, _) {},
        onVerifyHostSignature: (_, _, _, _) {
          crypto++;
          return true;
        },
        onVerifyHostKey: (_, _, _) {
          hosts++;
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
        expect(crypto, 0);
        expect(hosts, 0);
      } finally {
        await client.close();
        parsed.dispose();
      }
    },
  );
}
