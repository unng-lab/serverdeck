import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/connections/host_signature.dart';
import 'package:serverdeck/connections/private_signer.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/credential_parser.dart';
import 'package:serverdeck/profiles/key_envelope.dart';

import '../fixtures/ssh_auth_peer.dart';

Uint8List fixture(String name) =>
    File('test/fixtures/ssh/$name.txt').readAsBytesSync();
Future<void> turn() => Future<void>.delayed(Duration.zero);

final class Harness {
  Harness({
    String? keyName,
    SyntheticAuthReply reply = SyntheticAuthReply.success,
    int? fragment,
    List<String>? serverAlgorithms,
    Future<bool> Function()? trust,
    Future<String?> Function()? phrase,
    void Function(String, Uint8List, Uint8List)? changed,
  }) {
    peer = MemoryAuthPeer(
      hostKey: host.key,
      authReply: reply,
      fragmentSize: fragment,
      expectedPassword: ' synthetic-password ',
      serverSignatureAlgorithms: serverAlgorithms,
    );
    if (keyName != null) {
      final bytes = fixture(keyName);
      identity = OwnedPrivateIdentity(
        file: bytes,
        credentialRevision: 9,
        expected: readPublicKeyHint(bytes).inspection,
        signer: signer,
        checkAdmission: (revision) {
          expect(revision, 9);
          if (!accepted || client.isClosed)
            throw const OperationFailure(FailureCode.trustRequired);
        },
        serverAlgorithms: () => client.serverSigAlgs,
        requestPassphrase: () {
          prompts++;
          return phrase?.call() ?? Future.value('serverdeck-unit-passphrase');
        },
        remainingBudget: () => const Duration(seconds: 30),
      );
    }
    client = SSHClient(
      peer,
      username: 'synthetic-user',
      identities: identity == null ? null : [identity!],
      onPasswordRequest: identity != null
          ? null
          : () {
              expect(accepted, isTrue);
              passwords++;
              return ' synthetic-password ';
            },
      onVerifyHostSignature: (type, key, signature, hash) {
        signatureChecks++;
        return verifier.verify(type, key, signature, hash);
      },
      onVerifyHostKey: (type, fingerprint, blob) async {
        hostChecks++;
        expect(type, 'ssh-ed25519');
        expect(blob, host.key.toPublicKey().encode());
        accepted = await (trust?.call() ?? Future.value(true));
        return accepted;
      },
      onHostKeyChanged: changed ?? (_, _, _) {},
      keepAliveInterval: null,
      handshakeTimeout: null,
      authTimeout: null,
    );
    client.done.ignore();
  }
  final host = parseOpenSshKey(fixture('ed25519'));
  final verifier = HostSignatureVerifier(), signer = PrivateSigner();
  late final MemoryAuthPeer peer;
  late final SSHClient client;
  OwnedPrivateIdentity? identity;
  bool accepted = false;
  int hostChecks = 0, signatureChecks = 0, passwords = 0, prompts = 0;
  Future<void> close() async {
    identity?.dispose();
    await client.close();
    await peer.close();
    await verifier.dispose();
    await signer.dispose();
    host.dispose();
    expect(peer.codecFailure, isNull);
  }
}

void main() {
  for (final fragment in <int?>[null, 1, 7, 23]) {
    test(
      'encrypted password auth and ping over memory, fragment=$fragment',
      () async {
        final h = Harness(fragment: fragment);
        try {
          await h.client.authenticated;
          expect(h.peer.authenticated, isTrue);
          expect(h.passwords, 1);
          expect(h.hostChecks, 1);
          expect(h.signatureChecks, 1);
          expect(h.peer.authRequests.single.methodName, 'password');
          expect(h.peer.authRequests.single.password, ' synthetic-password ');
          expect(
            h.peer.clientMessageIds,
            containsAllInOrder([20, 30, 21, 5, 50]),
          );
          await h.client.ping();
          expect(h.peer.pings, 1);
          expect(
            h.peer.clientMessageIds.any((id) => id >= 90),
            isFalse,
          ); // No channels/exec/shell.
        } finally {
          await h.close();
        }
      },
    );
  }
  for (final value in <(String, List<String>?, String, int)>[
    ('ed25519', null, 'ssh-ed25519', 0),
    ('ed25519-encrypted', ['ssh-ed25519'], 'ssh-ed25519', 1),
    ('rsa2048-encrypted', null, 'rsa-sha2-256', 1),
    ('rsa2048-encrypted', ['rsa-sha2-256', 'rsa-sha2-512'], 'rsa-sha2-512', 1),
  ]) {
    test(
      'async identity produces verified userauth ${value.$1}/${value.$3}',
      () async {
        final h = Harness(keyName: value.$1, serverAlgorithms: value.$2);
        try {
          await h.client.authenticated;
          expect(h.peer.lastAuthSignatureValid, isTrue);
          expect(h.passwords, 0);
          expect(h.prompts, value.$4);
          expect(h.peer.authRequests.single.methodName, 'publickey');
          expect(h.peer.authRequests.single.publicKeyAlgorithm, value.$3);
          await h.client.ping();
          expect(h.peer.pings, 1);
        } finally {
          await h.close();
        }
      },
    );
  }
  for (final key in <String?>[null, 'ed25519']) {
    test(
      'auth refusal with offered fallback methods sends one selected method key=$key',
      () async {
        final h = Harness(keyName: key, reply: SyntheticAuthReply.failure);
        try {
          await expectLater(
            h.client.authenticated,
            throwsA(isA<SSHAuthFailError>()),
          );
          expect(h.peer.authRequests, hasLength(1));
          expect(
            h.peer.authRequests.single.methodName,
            key == null ? 'password' : 'publickey',
          );
          expect(h.peer.authenticated, isFalse);
          await turn();
          expect(h.client.isClosed, isTrue);
        } finally {
          await h.close();
        }
      },
    );
    test(
      'partial MFA is unsupported without another credential method key=$key',
      () async {
        final h = Harness(keyName: key, reply: SyntheticAuthReply.partial);
        try {
          await expectLater(
            h.client.authenticated,
            throwsA(isA<SSHUnsupportedAuthError>()),
          );
          expect(h.peer.authRequests, hasLength(1));
          expect(h.peer.authenticated, isFalse);
        } finally {
          await h.close();
        }
      },
    );
  }
  test('unaccepted host sends no service/userauth and never requests any credential', () async {
    final h = Harness(trust: () async => false);
    try {
      await expectLater(
        h.client.authenticated,
        throwsA(
          isA<SSHAuthAbortError>().having(
            (e) => e.reason,
            'reason',
            isA<SSHHostkeyError>(),
          ),
        ),
      );
      expect(h.passwords, 0);
      expect(h.prompts, 0);
      expect(h.peer.authRequests, isEmpty);
      expect(h.peer.clientMessageIds, isNot(contains(5)));
      expect(h.peer.clientMessageIds, isNot(contains(21)));
    } finally {
      await h.close();
    }
  });
  test(
    'late trust acceptance cannot authenticate after cancellation',
    () async {
      final prompt = Completer<bool>(), entered = Completer<void>();
      final h = Harness(
        trust: () {
          entered.complete();
          return prompt.future;
        },
      );
      final ended = expectLater(h.client.authenticated, throwsA(anything));
      try {
        await entered.future;
        await h.client.close();
        prompt.complete(true);
        await ended;
        await turn();
        expect(h.peer.authRequests, isEmpty);
        expect(h.passwords, 0);
        expect(h.prompts, 0);
      } finally {
        await h.close();
      }
    },
  );
  test('late passphrase cannot authenticate a disposed identity', () async {
    final prompt = Completer<String?>(), entered = Completer<void>();
    final h = Harness(
      keyName: 'ed25519-encrypted',
      phrase: () {
        entered.complete();
        return prompt.future;
      },
    );
    final ended = expectLater(h.client.authenticated, throwsA(anything));
    try {
      await entered.future;
      h.identity!.dispose();
      await h.client.close();
      prompt.complete('serverdeck-unit-passphrase');
      await ended;
      await turn();
      expect(h.peer.authRequests, isEmpty);
      expect(h.signer.activeWorkers, 0);
    } finally {
      await h.close();
    }
  });
  test(
    'server advertising only RSA SHA1 cannot receive a signed userauth',
    () async {
      final h = Harness(keyName: 'rsa2048', serverAlgorithms: ['ssh-rsa']);
      try {
        await expectLater(h.client.authenticated, throwsA(anything));
        expect(h.peer.authRequests, isEmpty);
        expect(h.signer.activeWorkers, 0);
        expect(h.prompts, 0);
      } finally {
        await h.close();
      }
    },
  );
  test(
    'unchanged host rekey re-verifies signature without re-prompt or re-auth',
    () async {
      final h = Harness();
      try {
        await h.client.authenticated;
        await h.client.rekey();
        expect(h.peer.exchanges, 2);
        expect(h.signatureChecks, 2);
        expect(h.hostChecks, 1);
        expect(h.peer.authRequests, hasLength(1));
        await h.client.ping();
        expect(h.peer.pings, 1);
      } finally {
        await h.close();
      }
    },
  );
  test('verified different host during rekey closes and reports raw changed blob without auth', () async {
    final changed = Completer<(String, Uint8List)>();
    final replacement = parseOpenSshKey(fixture('rsa2048'));
    final h = Harness(
      changed: (type, _, blob) =>
          changed.complete((type, Uint8List.fromList(blob))),
    );
    try {
      await h.client.authenticated;
      final closed = expectLater(
        h.client.done,
        throwsA(isA<SSHHostkeyError>()),
      );
      h.peer.beginRekey(replacement.key);
      final report = await changed.future;
      await closed;
      expect(report.$1, 'rsa-sha2-256');
      expect(report.$2, replacement.key.toPublicKey().encode());
      expect(h.signatureChecks, 2);
      expect(h.hostChecks, 1);
      expect(h.peer.authRequests, hasLength(1));
      expect(h.client.isClosed, isTrue);
    } finally {
      await h.close();
      replacement.dispose();
    }
  });
  test(
    'unanswered encrypted ping is still owned until session close',
    () async {
      final h = Harness();
      try {
        await h.client.authenticated;
        h.peer.replyToPing = false;
        final pending = expectLater(h.client.ping(), throwsA(anything));
        await turn();
        expect(h.peer.pings, 1);
        await h.client.close();
        await pending;
      } finally {
        await h.close();
      }
    },
  );
}
