import '../fixtures/key_material.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/hostkey/hostkey_ed25519.dart';
import 'package:dartssh2/src/hostkey/hostkey_rsa.dart';
import 'package:dartssh2/src/ssh_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/connections/private_signer.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/credential_parser.dart';
import 'package:serverdeck/profiles/key_envelope.dart';
import 'package:serverdeck/runtime/owned_work.dart';

Uint8List fixture([String name = 'ed25519']) =>
    File('test/fixtures/ssh/$name.txt').readAsBytesSync();
final challenge = Uint8List.fromList(
  utf8.encode('synthetic SSH authentication challenge'),
);
Matcher failure(FailureCode code) =>
    isA<OperationFailure>().having((e) => e.code, 'code', code);
Future<void> turn() => Future<void>.delayed(Duration.zero);
Uint8List signature() {
  final key = parsePrivateKey(fixture());
  try {
    return key.key.sign(challenge).encode();
  } finally {
    key.dispose();
  }
}

Uint8List envelope({
  Uint8List? publicBlob,
  Uint8List? privateBlob,
  int count = 1,
}) {
  final original = OpenSshEnvelope.read(fixture());
  try {
    final writer = SSHMessageWriter();
    writer.writeBytes(utf8.encode('openssh-key-v1\x00'));
    writer.writeUtf8('none');
    writer.writeUtf8('none');
    writer.writeString(Uint8List(0));
    writer.writeUint32(count);
    writer.writeString(publicBlob ?? original.hint.encoded);
    writer.writeString(privateBlob ?? original.privateBlob);
    return Uint8List.fromList(
      utf8.encode(
        SSHPem('OPENSSH PRIVATE KEY', const {}, writer.takeBytes()).encode(),
      ),
    );
  } finally {
    original.dispose();
  }
}

final class Worker implements PrivateSignWorker {
  final value = Completer<Uint8List>(), exited = Completer<void>();
  bool failStop = false;
  int stops = 0;
  @override
  Future<Uint8List> get result => value.future;
  @override
  Future<void> stop() {
    stops++;
    return failStop
        ? Future.error(StateError('SYNTHETIC_STOP_DETAIL'))
        : exited.future;
  }
}

OwnedPrivateIdentity identity(
  PrivateSigner signer, {
  String name = 'ed25519',
  void Function(int)? guard,
  List<String>? Function()? algorithms,
  Future<String?> Function()? prompt,
  Duration Function()? remaining,
  WorkCancellation? cancellation,
}) {
  final file = fixture(name);
  return OwnedPrivateIdentity(
    file: file,
    publicHint: readPublicKeyHint(
      file,
      publicKeyBytes: fixturePublicBytes(file),
    ),
    credentialRevision: 7,
    expected: readPublicKeyHint(
      file,
      publicKeyBytes: fixturePublicBytes(file),
    ).inspection,
    signer: signer,
    checkAdmission: guard ?? (_) {},
    serverAlgorithms: algorithms ?? () => null,
    requestPassphrase: prompt ?? () async => 'serverdeck-unit-passphrase',
    remainingBudget: remaining ?? () => const Duration(seconds: 30),
    cancellation: cancellation,
  );
}

void main() {
  test(
    'passphrase byte bounds count Unicode scalars without plaintext encoding',
    () {
      for (final value in ['', 'a' * 65536, 'é' * 32768, '😀' * 16384]) {
        expect(isKeyPassphraseBounded(value), isTrue);
      }
      for (final value in [
        'a' * 65537,
        'é' * 32769,
        '😀' * 16385,
        String.fromCharCode(0xdc00),
      ]) {
        expect(isKeyPassphraseBounded(value), isFalse);
      }
    },
  );
  for (final name in ['ed25519', 'rsa2048']) {
    for (final encrypted in [false, true]) {
      final schemes = name == 'ed25519'
          ? [PrivateSignatureScheme.ed25519]
          : [PrivateSignatureScheme.rsa256, PrivateSignatureScheme.rsa512];
      for (final scheme in schemes) {
        test(
          'owned isolate signs $name encrypted=$encrypted with ${scheme.wire}',
          () async {
            final file = fixture('$name${encrypted ? '-encrypted' : ''}'),
                saved = fixture('$name${encrypted ? '-encrypted' : ''}');
            final signer = PrivateSigner();
            try {
              final hint = readPublicKeyHint(
                    file,
                    publicKeyBytes: fixturePublicBytes(file),
                  ),
                  publicKey = hint.toPublicKey();
              final signed = await signer.sign(
                file,
                scheme,
                challenge,
                passphrase: encrypted ? 'serverdeck-unit-passphrase' : null,
                expectedPublicKey: expectedPublic(file),
              );
              expect(signed.encode(), isNotEmpty);
              expect(switch (publicKey) {
                SSHEd25519PublicKey() => publicKey.verify(
                  challenge,
                  signed as SSHEd25519Signature,
                ),
                SSHRsaPublicKey() => publicKey.verify(
                  challenge,
                  signed as SSHRsaSignature,
                ),
                _ => false,
              }, isTrue);
              if (signed is SSHRsaSignature) expect(signed.type, scheme.wire);
              expect(file, saved);
              // A decoded signature owns its data after the encoded worker result is cleared.
              expect(signed.encode().any((b) => b != 0), isTrue);
            } finally {
              await signer.dispose();
            }
            expect(signer.activeWorkers, 0);
          },
        );
      }
    }
  }
  test('identity snapshots challenge before awaiting a prompt and clears request copies', () async {
    final prompt = Completer<String?>();
    final worker = Worker();
    Uint8List? observed;
    PrivateSignRequest? request;
    final signer = PrivateSigner(
      spawn: (r) async {
        request = r;
        observed = Uint8List.fromList(r.challenge);
        return worker;
      },
    );
    final input = Uint8List.fromList(challenge);
    final key = identity(
      signer,
      name: 'ed25519-encrypted',
      prompt: () => prompt.future,
    );
    final pending = key.sign(input);
    await turn();
    input.fillRange(0, input.length, 9);
    prompt.complete('serverdeck-unit-passphrase');
    await turn();
    expect(observed, challenge);
    expect(request!.file.every((b) => b == 0), isTrue);
    expect(request!.challenge.every((b) => b == 0), isTrue);
    expect(request!.passphrase, isNull);
    worker.value.complete(signature());
    await pending;
    expect(input.every((b) => b == 9), isTrue);
    worker.exited.complete();
    key.dispose();
    await signer.dispose();
  });
  test('public-only hint survives decoded file clearing and does not validate private math', () {
    final blob = Uint8List(8); // Invalid private body, valid aligned envelope.
    final file = envelope(privateBlob: blob);
    final hint = readPublicKeyHint(
      file,
      publicKeyBytes: fixturePublicBytes(file),
    );
    file.fillRange(0, file.length, 0);
    expect(
      hint.toPublicKey().encode(),
      readPublicKeyHint(
        fixture(),
        publicKeyBytes: fixturePublicBytes(fixture()),
      ).encoded,
    );
    expect(() => hint.encoded[0] = 0, throwsUnsupportedError);
    expect(
      () => parsePrivateKey(envelope(privateBlob: blob)),
      throwsA(failure(FailureCode.unsupportedKey)),
    );
    final owned = OpenSshEnvelope.read(fixture());
    final privateView = owned.privateBlob, publicCopy = owned.hint.encoded;
    owned.dispose();
    expect(privateView.every((b) => b == 0), isTrue);
    expect(publicCopy, hint.encoded);
  });
  test('hint rejects key counts, malformed UTF8, unsupported formats and noncanonical public blobs', () {
    for (final count in [0, 2, 0xffffffff]) {
      expect(
        () => readPublicKeyHint(
          envelope(count: count),
          publicKeyBytes: fixturePublicBytes(envelope(count: count)),
        ),
        throwsA(failure(FailureCode.unsupportedKey)),
      );
    }
    final pub = readPublicKeyHint(
      fixture(),
      publicKeyBytes: fixturePublicBytes(fixture()),
    ).encoded;
    expect(
      () => readPublicKeyHint(
        envelope(publicBlob: Uint8List.fromList([...pub, 0])),
        publicKeyBytes: fixturePublicBytes(
          envelope(publicBlob: Uint8List.fromList([...pub, 0])),
        ),
      ),
      throwsA(failure(FailureCode.unsupportedKey)),
    );
    for (final name in ['ecdsa', 'public-key']) {
      expect(
        () => readPublicKeyHint(
          fixture(name),
          publicKeyBytes: fixturePublicBytes(fixture(name)),
        ),
        throwsA(failure(FailureCode.unsupportedKey)),
      );
    }
    expect(
      () => readPublicKeyHint(
        Uint8List.fromList([255]),
        publicKeyBytes: fixturePublicBytes(Uint8List.fromList([255])),
      ),
      throwsA(failure(FailureCode.unsupportedKey)),
    );
  });
  test('signature schemes never select SHA1 or another key and respect absent discovery', () {
    final rsa = readPublicKeyHint(
          fixture('rsa2048'),
          publicKeyBytes: fixturePublicBytes(fixture('rsa2048')),
        ),
        ed = readPublicKeyHint(
          fixture(),
          publicKeyBytes: fixturePublicBytes(fixture()),
        );
    expect(
      selectPrivateSignatureScheme(rsa, null),
      PrivateSignatureScheme.rsa256,
    );
    expect(
      selectPrivateSignatureScheme(rsa, ['rsa-sha2-256']),
      PrivateSignatureScheme.rsa256,
    );
    expect(
      selectPrivateSignatureScheme(rsa, ['rsa-sha2-256', 'rsa-sha2-512']),
      PrivateSignatureScheme.rsa512,
    );
    expect(
      selectPrivateSignatureScheme(ed, null),
      PrivateSignatureScheme.ed25519,
    );
    for (final offered in [
      <String>[],
      ['ssh-rsa'],
      ['ecdsa-sha2-nistp256'],
    ]) {
      expect(
        () => selectPrivateSignatureScheme(rsa, offered),
        throwsA(failure(FailureCode.unsupportedServer)),
      );
      expect(
        () => selectPrivateSignatureScheme(ed, offered),
        throwsA(failure(FailureCode.unsupportedServer)),
      );
    }
  });
  for (final phrase in <String?>[null, '', 'wrong']) {
    test(
      'encrypted signing returns a fixed error for phrase=$phrase',
      () async {
        final signer = PrivateSigner();
        try {
          await expectLater(
            signer.sign(
              fixture('ed25519-encrypted'),
              PrivateSignatureScheme.ed25519,
              challenge,
              passphrase: phrase,
              expectedPublicKey: expectedPublic(fixture('ed25519-encrypted')),
            ),
            throwsA(
              failure(
                phrase == null
                    ? FailureCode.passphraseRequired
                    : FailureCode.passphraseInvalid,
              ),
            ),
          );
        } finally {
          await signer.dispose();
        }
      },
    );
  }
  test('before-spawn bounds, wrong key scheme, and stopped admission are fixed failures', () async {
    var spawns = 0;
    final signer = PrivateSigner(
      spawn: (_) async {
        spawns++;
        throw StateError('SYNTHETIC_DETAIL');
      },
    );
    for (final file in [Uint8List(0), Uint8List(1024 * 1024 + 1)]) {
      await expectLater(
        signer.sign(
          file,
          PrivateSignatureScheme.ed25519,
          challenge,
          expectedPublicKey: expectedPublic(file),
        ),
        throwsA(failure(FailureCode.unsupportedKey)),
      );
    }
    await expectLater(
      signer.sign(
        fixture(),
        PrivateSignatureScheme.ed25519,
        Uint8List(maxSignChallengeBytes + 1),
        expectedPublicKey: expectedPublic(fixture()),
      ),
      throwsA(failure(FailureCode.unsupportedKey)),
    );
    await expectLater(
      signer.sign(
        fixture(),
        PrivateSignatureScheme.ed25519,
        challenge,
        passphrase: 'é' * 32769,
        expectedPublicKey: expectedPublic(fixture()),
      ),
      throwsA(failure(FailureCode.invalidArgument)),
    );
    await expectLater(
      signer.sign(
        fixture(),
        PrivateSignatureScheme.ed25519,
        challenge,
        passphrase: String.fromCharCode(0xd800),
        expectedPublicKey: expectedPublic(fixture()),
      ),
      throwsA(failure(FailureCode.invalidArgument)),
    );
    await expectLater(
      signer.sign(
        fixture(),
        PrivateSignatureScheme.ed25519,
        challenge,
        timeout: Duration.zero,
        expectedPublicKey: expectedPublic(fixture()),
      ),
      throwsA(failure(FailureCode.timeout)),
    );
    expect(spawns, 0);
    await signer.dispose();
    await expectLater(
      signer.sign(
        fixture(),
        PrivateSignatureScheme.ed25519,
        challenge,
        expectedPublicKey: expectedPublic(fixture()),
      ),
      throwsA(failure(FailureCode.shuttingDown)),
    );
    final real = PrivateSigner();
    try {
      await expectLater(
        real.sign(
          fixture(),
          PrivateSignatureScheme.rsa512,
          challenge,
          expectedPublicKey: expectedPublic(fixture()),
        ),
        throwsA(failure(FailureCode.unsupportedKey)),
      );
    } finally {
      await real.dispose();
    }
  });
  test('pending cancelled spawns retain all four reservations until late workers exit', () async {
    final factories = <Completer<PrivateSignWorker>>[],
        requests = <PrivateSignRequest>[];
    final signer = PrivateSigner(
      spawn: (r) {
        requests.add(r);
        final c = Completer<PrivateSignWorker>();
        factories.add(c);
        return c.future;
      },
    );
    final cancels = List.generate(4, (_) => WorkCancellation());
    final pending = [
      for (final c in cancels)
        expectLater(
          signer.sign(
            fixture(),
            PrivateSignatureScheme.ed25519,
            challenge,
            passphrase: 'synthetic',
            cancellation: c,
            expectedPublicKey: expectedPublic(fixture()),
          ),
          throwsA(isA<WorkCancelled>()),
        ),
    ];
    await turn();
    for (final c in cancels) {
      c.cancel();
    }
    await Future.wait(pending);
    expect(signer.activeWorkers, 4);
    await expectLater(
      signer.sign(
        fixture(),
        PrivateSignatureScheme.ed25519,
        challenge,
        expectedPublicKey: expectedPublic(fixture()),
      ),
      throwsA(failure(FailureCode.resourceExhausted)),
    );
    final workers = List.generate(4, (_) => Worker());
    for (var i = 0; i < 4; i++) {
      factories[i].complete(workers[i]);
    }
    await turn();
    for (final r in requests) {
      expect(r.file.every((b) => b == 0), isTrue);
      expect(r.challenge.every((b) => b == 0), isTrue);
      expect(r.passphrase, isNull);
    }
    final late = signature();
    workers.first.value.complete(late);
    await turn();
    expect(late.every((b) => b == 0), isTrue);
    expect(signer.activeWorkers, 4);
    for (final w in workers) {
      w.exited.complete();
    }
    await signer.dispose();
    expect(signer.activeWorkers, 0);
  });
  test('result precedes exit but failed stop retains reservation and drain retries', () async {
    final worker = Worker()..failStop = true;
    final signer = PrivateSigner(spawn: (_) async => worker);
    final pending = signer.sign(
      fixture(),
      PrivateSignatureScheme.ed25519,
      challenge,
      expectedPublicKey: expectedPublic(fixture()),
    );
    await turn();
    worker.value.complete(signature());
    await pending;
    await turn();
    expect(signer.activeWorkers, 1);
    worker.failStop = false;
    worker.exited.complete();
    await signer.dispose();
    expect(worker.stops, greaterThanOrEqualTo(2));
    expect(signer.activeWorkers, 0);
  });
  test('deadline clamps at thirty seconds and late outputs are disposed after timeout', () async {
    late void Function() expire;
    late Duration budget;
    final worker = Worker();
    final signer = PrivateSigner(
      spawn: (_) async => worker,
      schedule: (duration, callback) {
        budget = duration;
        expire = callback;
        return () {};
      },
    );
    final pending = expectLater(
      signer.sign(
        fixture(),
        PrivateSignatureScheme.ed25519,
        challenge,
        timeout: const Duration(minutes: 5),
        expectedPublicKey: expectedPublic(fixture()),
      ),
      throwsA(failure(FailureCode.timeout)),
    );
    await turn();
    expect(budget, const Duration(seconds: 30));
    expire();
    await pending;
    final late = signature();
    worker.value.complete(late);
    await turn();
    expect(late.every((b) => b == 0), isTrue);
    worker.exited.complete();
    await signer.dispose();
  });
  test('worker error text and malformed output never escape', () async {
    for (final output in [
      null,
      Uint8List(0),
      Uint8List.fromList([...signature(), 0]),
    ]) {
      final worker = Worker();
      final signer = PrivateSigner(spawn: (_) async => worker);
      final pending = expectLater(
        signer.sign(
          fixture(),
          PrivateSignatureScheme.ed25519,
          challenge,
          expectedPublicKey: expectedPublic(fixture()),
        ),
        throwsA(failure(FailureCode.unsupportedKey)),
      );
      await turn();
      if (output == null) {
        worker.value.completeError(StateError('SYNTHETIC_PRIVATE_DETAIL'));
      } else {
        worker.value.complete(output);
      }
      await pending;
      if (output != null) expect(output.every((b) => b == 0), isTrue);
      worker.exited.complete();
      await signer.dispose();
    }
  });
  test('identity checks current revision and host before any public key, scheme or prompt', () async {
    final signer = PrivateSigner();
    var accepted = false, prompts = 0;
    final key = identity(
      signer,
      guard: (revision) {
        expect(revision, 7);
        if (!accepted) throw const OperationFailure(FailureCode.trustRequired);
      },
      prompt: () async {
        prompts++;
        return null;
      },
    );
    expect(() => key.type, throwsA(failure(FailureCode.trustRequired)));
    expect(
      () => key.toPublicKey(),
      throwsA(failure(FailureCode.trustRequired)),
    );
    accepted = true;
    expect(key.type, 'ssh-ed25519');
    expect(key.toPublicKey().encode(), isNotEmpty);
    expect(prompts, 0);
    key.dispose();
    await signer.dispose();
  });
  test('identity binds metadata to original envelope and rejects mismatched credential metadata', () async {
    final signer = PrivateSigner();
    for (final expected in [
      const KeyInspection(
        keyType: 'ssh-rsa',
        bits: 256,
        encrypted: false,
        publicKeyBytes: <int>[],
      ),
      const KeyInspection(
        keyType: 'ssh-ed25519',
        bits: 2048,
        encrypted: false,
        publicKeyBytes: <int>[],
      ),
      const KeyInspection(
        keyType: 'ssh-ed25519',
        bits: 256,
        encrypted: true,
        publicKeyBytes: <int>[],
      ),
    ]) {
      expect(
        () => OwnedPrivateIdentity(
          file: fixture(),
          publicHint: readPublicKeyHint(
            fixture(),
            publicKeyBytes: fixturePublicBytes(fixture()),
          ),
          credentialRevision: 7,
          expected: expected,
          signer: signer,
          checkAdmission: (_) {},
          serverAlgorithms: () => null,
          requestPassphrase: () async => null,
          remainingBudget: () => const Duration(seconds: 30),
        ),
        throwsA(failure(FailureCode.unsupportedKey)),
      );
    }
    await signer.dispose();
  });
  test('identity freezes RSA512, clears private file and remains usable for client post-sign type read', () async {
    final signer = PrivateSigner();
    var reads = 0;
    final key = identity(
      signer,
      name: 'rsa2048-encrypted',
      algorithms: () {
        reads++;
        return reads == 1 ? ['rsa-sha2-512', 'rsa-sha2-256'] : ['ssh-rsa'];
      },
    );
    try {
      expect(key.type, 'rsa-sha2-512');
      final signed = await key.sign(challenge) as SSHRsaSignature;
      expect(signed.type, 'rsa-sha2-512');
      expect(key.type, 'rsa-sha2-512');
      expect(reads, 1);
      await expectLater(
        key.sign(challenge),
        throwsA(failure(FailureCode.authFailed)),
      );
    } finally {
      key.dispose();
      await signer.dispose();
    }
  });
  test(
    'revocation during prompt prevents worker admission and any retry',
    () async {
      var valid = true, spawns = 0;
      final prompt = Completer<String?>();
      final signer = PrivateSigner(
        spawn: (_) async {
          spawns++;
          throw StateError('must not spawn');
        },
      );
      final key = identity(
        signer,
        name: 'ed25519-encrypted',
        guard: (_) {
          if (!valid) throw const OperationFailure(FailureCode.accessRevoked);
        },
        prompt: () => prompt.future,
      );
      final pending = expectLater(
        key.sign(challenge),
        throwsA(failure(FailureCode.accessRevoked)),
      );
      await turn();
      valid = false;
      prompt.complete('serverdeck-unit-passphrase');
      await pending;
      expect(spawns, 0);
      expect(() => key.type, throwsA(isA<WorkCancelled>()));
      await signer.dispose();
    },
  );
  test('cancellation while prompt remains pending completes promptly and consumes late error', () async {
    final prompt = Completer<String?>(), cancellation = WorkCancellation();
    final signer = PrivateSigner();
    final key = identity(
      signer,
      name: 'ed25519-encrypted',
      prompt: () => prompt.future,
      cancellation: cancellation,
    );
    final pending = expectLater(
      key.sign(challenge),
      throwsA(isA<WorkCancelled>()),
    );
    await turn();
    cancellation.cancel();
    await pending;
    expect(signer.activeWorkers, 0);
    prompt.completeError(StateError('SYNTHETIC_LATE_PROMPT'));
    await turn();
    key.dispose();
    await signer.dispose();
  });
  test('identity rechecks after signature and forwards only the remaining network budget', () async {
    var valid = true;
    late Duration scheduled;
    final worker = Worker();
    final signer = PrivateSigner(
      spawn: (_) async => worker,
      schedule: (duration, _) {
        scheduled = duration;
        return () {};
      },
    );
    final key = identity(
      signer,
      remaining: () => const Duration(milliseconds: 17),
      guard: (_) {
        if (!valid) throw const OperationFailure(FailureCode.conflict);
      },
    );
    final pending = expectLater(
      key.sign(challenge),
      throwsA(failure(FailureCode.conflict)),
    );
    await turn();
    expect(scheduled, const Duration(milliseconds: 17));
    valid = false;
    worker.value.complete(signature());
    await pending;
    worker.exited.complete();
    key.dispose();
    await signer.dispose();
  });
}

// Invalid-file boundary cases still supply an independent valid expected identity.
Uint8List expectedPublic(Uint8List file) {
  try {
    return readPublicKeyHint(
      file,
      publicKeyBytes: fixturePublicBytes(file),
    ).encoded;
  } catch (_) {
    return readPublicKeyHint(
      fixture(),
      publicKeyBytes: fixturePublicBytes(fixture()),
    ).encoded;
  }
}
