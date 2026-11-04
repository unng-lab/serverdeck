import '../fixtures/key_material.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/connections/host_signature.dart';
import 'package:serverdeck/connections/private_signer.dart';
import 'package:serverdeck/connections/ssh_transport.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/credential_parser.dart';
import 'package:serverdeck/profiles/key_envelope.dart';
import 'package:serverdeck/runtime/owned_work.dart';

import '../fixtures/ssh_auth_peer.dart';
import '../fixtures/ssh_kex_peer.dart';

Uint8List fixture(String name) =>
    File('test/fixtures/ssh/$name.txt').readAsBytesSync();
TypeMatcher<OperationFailure> failure(FailureCode code) =>
    isA<OperationFailure>().having((e) => e.code, 'code', code);
Future<void> turn() => Future<void>.delayed(Duration.zero);

final class Harness {
  Harness({
    String? keyName,
    SyntheticAuthReply reply = SyntheticAuthReply.success,
    Future<bool> Function(HostObservation)? trust,
    Future<void> Function(HostObservation)? changed,
    Future<String?> Function()? prompt,
    Duration Function()? budget,
    AdmitSshWrite? admit,
    SSHSocket Function(MemoryAuthPeer)? wrap,
  }) {
    peer = MemoryAuthPeer(
      hostKey: host.key,
      authReply: reply,
      expectedPassword: ' exact password ',
      serverSignatureAlgorithms: [
        'ssh-ed25519',
        'rsa-sha2-512',
        'rsa-sha2-256',
      ],
    );
    final bytes = keyName == null
        ? Uint8List.fromList(utf8.encode(' exact password '))
        : fixture(keyName);
    credential = keyName == null
        ? PasswordCredential(bytes)
        : PrivateKeyCredential(
            bytes,
            revision: 3,
            publicHint: readPublicKeyHint(
              bytes,
              publicKeyBytes: fixturePublicBytes(bytes),
            ),
            inspection: readPublicKeyHint(
              bytes,
              publicKeyBytes: fixturePublicBytes(bytes),
            ).inspection,
          );
    transport = StrictSshTransport(
      socket: wrap?.call(peer) ?? peer,
      username: 'synthetic',
      credential: credential,
      verifier: verifier,
      signer: signer,
      cancellation: cancellation,
      admitWrite:
          admit ??
          (write) async {
            writes++;
            if (!authorized)
              throw const OperationFailure(FailureCode.accessRevoked);
            write();
          },
      checkAuthentication: () {
        if (!authorized)
          throw const OperationFailure(FailureCode.accessRevoked);
      },
      verifyHost: (observation) {
        observations.add(observation);
        return trust?.call(observation) ?? Future.value(true);
      },
      changedHost: changed ?? (_) async {},
      requestPassphrase: () {
        prompts++;
        return prompt?.call() ?? Future.value('serverdeck-unit-passphrase');
      },
      remainingBudget: budget ?? () => const Duration(seconds: 30),
    );
  }
  final host = parsePrivateKey(fixture('ed25519'));
  final verifier = HostSignatureVerifier(),
      signer = PrivateSigner(),
      cancellation = WorkCancellation();
  late final MemoryAuthPeer peer;
  late final AttemptCredential credential;
  late final StrictSshTransport transport;
  bool authorized = true;
  int writes = 0, prompts = 0;
  final observations = <HostObservation>[];
  Future<void> close() async {
    await transport.close();
    await verifier.dispose();
    await signer.dispose();
    host.dispose();
    expect(peer.codecFailure, isNull);
  }
}

final class DeferredSocket implements SSHSocket {
  DeferredSocket(this.peer) {
    _sink = DeferredSink(this);
  }
  final SSHSocket peer;
  final entered = Completer<void>(), release = Completer<void>();
  final received = <List<int>>[],
      snapshots = <List<int>>[],
      pending = <List<int>>[];
  late final DeferredSink _sink;
  bool closed = false;
  @override
  Stream<Uint8List> get stream => peer.stream;
  @override
  StreamSink<List<int>> get sink => _sink;
  @override
  Future<void> get done => peer.done;
  @override
  Future<void> flush() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    for (final bytes in List.of(pending)) {
      if (!closed) peer.sink.add(bytes);
    }
    pending.clear();
  }

  @override
  Future<void> close() {
    closed = true;
    return peer.close();
  }

  @override
  void destroy() {
    closed = true;
    peer.destroy();
  }
}

final class DeferredSink implements StreamSink<List<int>> {
  DeferredSink(this.owner);
  final DeferredSocket owner;
  @override
  void add(List<int> bytes) {
    owner.received.add(bytes);
    owner.snapshots.add(List.of(bytes));
    owner.pending.add(bytes);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      throw StateError('Synthetic consumer error');
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final bytes in stream) {
      add(bytes);
    }
  }

  @override
  Future<void> close() => owner.close();
  @override
  Future<void> get done => owner.done;
}

final class RekeyFlushSocket implements SSHSocket {
  RekeyFlushSocket(this.peer);
  final MemoryAuthPeer peer;
  final flushing = Completer<void>();
  @override
  Stream<Uint8List> get stream => peer.stream;
  @override
  StreamSink<List<int>> get sink => peer.sink;
  @override
  Future<void> get done => peer.done;
  @override
  Future<void> flush() {
    // The synthetic peer has consumed the ECDH request and sent its second KEX
    // reply, but the socket's write acknowledgement can still be outstanding.
    return peer.exchanges >= 2 ? flushing.future : Future<void>.value();
  }

  @override
  Future<void> close() => peer.close();
  @override
  void destroy() {
    if (!flushing.isCompleted)
      flushing.completeError(StateError('SYNTHETIC_DESTROY_FLUSH'));
    peer.destroy();
  }
}

final class ControlledSocket implements SSHSocket {
  ControlledSocket(this.peer, {this.failFirstClose = false, this.holdDone});
  final SSHSocket peer;
  final bool failFirstClose;
  final Completer<void>? holdDone;
  int closes = 0;
  bool failDone = false;
  @override
  Stream<Uint8List> get stream => peer.stream;
  @override
  StreamSink<List<int>> get sink => peer.sink;
  @override
  Future<void> get done {
    if (failDone) throw StateError('SYNTHETIC_DONE_GETTER');
    return _confirmed();
  }

  Future<void> _confirmed() async {
    await peer.done;
    await holdDone?.future;
  }

  @override
  Future<void> close() {
    closes++;
    if (failFirstClose && closes == 1)
      return Future.error(StateError('SYNTHETIC_CLOSE_DETAIL'));
    return peer.close();
  }

  @override
  void destroy() => peer.destroy();
  @override
  Future<void> flush() => peer.flush();
}

void main() {
  test(
    'strict close never treats throwing done getter as physical confirmation',
    () async {
      late ControlledSocket socket;
      final h = Harness(wrap: (peer) => socket = ControlledSocket(peer));
      try {
        await h.transport.authenticated;
        socket.failDone = true;
        await expectLater(
          h.transport.close(),
          throwsA(
            failure(FailureCode.cleanupRequired)
                .having((e) => e.retryable, 'retryable', true),
          ),
        );
        expect(socket.closes, 1);
        socket.failDone = false;
        await h.transport.close();
        expect(socket.closes, 2);
      } finally {
        socket.failDone = false;
        await h.close();
      }
    },
  );
  for (final persistFailure in [false, true]) {
    test(
      'failed outstanding KEX flush cannot preempt changed-host result failure=$persistFailure',
      () async {
        final entered = Completer<void>(), persisted = Completer<void>();
        final replacement = parsePrivateKey(fixture('rsa2048'));
        final expected = persistFailure
            ? FailureCode.storageUnavailable
            : FailureCode.hostKeyChanged;
        final h = Harness(
          wrap: (peer) => RekeyFlushSocket(peer),
          changed: (_) {
            entered.complete();
            return persisted.future;
          },
        );
        try {
          await h.transport.authenticated;
          h.peer.replyToPing = false;
          var pingEnded = false;
          final ping =
              expectLater(h.transport.ping(), throwsA(failure(expected))).then((
                _,
              ) {
                pingEnded = true;
              });
          await turn();
          expect(h.peer.pings, 1);
          h.peer.beginRekey(replacement.key);
          await entered.future;
          await turn();
          expect(pingEnded, isFalse);
          if (persistFailure) {
            persisted.completeError(
              const OperationFailure(FailureCode.storageUnavailable),
            );
          } else {
            persisted.complete();
          }
          await ping;
          expect((await h.transport.ended)!.code, expected);
        } finally {
          await h.close();
          replacement.dispose();
        }
      },
    );
  }
  test('deferred byte consumer receives original data and retains it unchanged after flush', () async {
    late DeferredSocket socket;
    final h = Harness(wrap: (peer) => socket = DeferredSocket(peer));
    try {
      await socket.entered.future;
      expect(h.writes, 1);
      expect(socket.received, socket.snapshots);
      expect(h.peer.clientMessageIds, isEmpty);
      socket.release.complete();
      await h.transport.authenticated;
      await h.transport.ping();
      expect(h.peer.pings, 1);
      expect(socket.received, socket.snapshots);
      expect(h.credential.bytes.every((b) => b == 0), isTrue);
    } finally {
      if (!socket.release.isCompleted) socket.release.complete();
      await h.close();
    }
    expect(socket.received, socket.snapshots);
  });
  test('unfinished consumer keeps write reservation/drain pending through cancellation', () async {
    late DeferredSocket socket;
    final h = Harness(wrap: (peer) => socket = DeferredSocket(peer));
    final result = expectLater(
      h.transport.authenticated,
      throwsA(isA<OperationFailure>()),
    );
    try {
      await socket.entered.future;
      var closed = false;
      final closing = h.transport.close().then((_) {
        closed = true;
      });
      await turn();
      expect(closed, isFalse);
      expect(h.writes, 1);
      expect(socket.received, socket.snapshots);
      socket.release.complete();
      await closing;
      await result;
      expect(h.peer.authRequests, isEmpty);
      expect(socket.received, socket.snapshots);
    } finally {
      if (!socket.release.isCompleted) socket.release.complete();
      await h.close();
    }
  });
  for (final persistFailure in [false, true]) {
    test(
      'outstanding ping cannot mask changed-host persistence failure=$persistFailure',
      () async {
        final entered = Completer<void>(), persisted = Completer<void>();
        final replacement = parsePrivateKey(fixture('rsa2048'));
        final expected = persistFailure
            ? FailureCode.storageUnavailable
            : FailureCode.hostKeyChanged;
        final h = Harness(
          changed: (_) {
            entered.complete();
            return persisted.future;
          },
        );
        try {
          await h.transport.authenticated;
          h.peer.replyToPing = false;
          var pingEnded = false;
          final ping =
              expectLater(h.transport.ping(), throwsA(failure(expected))).then((
                _,
              ) {
                pingEnded = true;
              });
          await turn();
          expect(h.peer.pings, 1);
          h.peer.beginRekey(replacement.key);
          await entered.future;
          await turn();
          expect(pingEnded, isFalse);
          if (persistFailure) {
            persisted.completeError(
              const OperationFailure(FailureCode.storageUnavailable),
            );
          } else {
            persisted.complete();
          }
          await ping;
          expect((await h.transport.ended)!.code, expected);
          expect(h.peer.authRequests, hasLength(1));
        } finally {
          await h.close();
          replacement.dispose();
        }
      },
    );
  }
  test('strict algorithm allowlists match contract and exclude all legacy MAC/host choices', () {
    expect(strictSshAlgorithms.hostkey.map((a) => a.name), [
      'ssh-ed25519',
      'rsa-sha2-512',
      'rsa-sha2-256',
    ]);
    expect(strictSshAlgorithms.mac.map((a) => a.name), [
      'hmac-sha2-256-etm@openssh.com',
      'hmac-sha2-512-etm@openssh.com',
      'hmac-sha2-256',
      'hmac-sha2-512',
    ]);
    expect(strictSshAlgorithms.kex.map((a) => a.name), [
      'curve25519-sha256',
      'curve25519-sha256@libssh.org',
      'ecdh-sha2-nistp521',
      'ecdh-sha2-nistp384',
      'ecdh-sha2-nistp256',
      'diffie-hellman-group-exchange-sha256',
      'diffie-hellman-group14-sha256',
    ]);
    expect(strictSshAlgorithms.cipher.map((a) => a.name), [
      'aes256-gcm@openssh.com',
      'aes128-gcm@openssh.com',
      'chacha20-poly1305@openssh.com',
      'aes256-ctr',
      'aes128-ctr',
    ]);
  });
  for (final key in <String?>[null, 'ed25519-encrypted', 'rsa2048-encrypted']) {
    test(
      'strict transport authenticates selected method key=$key with shared workers and guarded writes',
      () async {
        final h = Harness(keyName: key);
        try {
          await h.transport.authenticated;
          expect(h.peer.authRequests, hasLength(1));
          expect(h.peer.authenticated, isTrue);
          expect(h.writes, greaterThan(4));
          expect(h.observations, hasLength(1));
          expect(h.observations.single.keyType, 'ssh-ed25519');
          expect(h.observations.single.fingerprint, startsWith('SHA256:'));
          expect(h.observations.single.blob, h.host.key.toPublicKey().encode());
          expect(
            () => h.observations.single.blob[0] = 0,
            throwsUnsupportedError,
          );
          expect(h.credential.bytes.every((b) => b == 0), isTrue);
          if (key == null) {
            expect(h.peer.authRequests.single.password, ' exact password ');
            expect(h.prompts, 0);
          } else {
            expect(h.peer.lastAuthSignatureValid, isTrue);
            expect(h.prompts, 1);
          }
          await h.transport.ping();
          expect(h.peer.pings, 1);
          expect(h.peer.clientMessageIds.any((id) => id >= 90), isFalse);
        } finally {
          await h.close();
        }
      },
    );
  }
  for (final value in [
    (SyntheticAuthReply.failure, FailureCode.authFailed),
    (SyntheticAuthReply.partial, FailureCode.unsupportedServer),
  ]) {
    test(
      'strict adapter fixed auth failure mapping ${value.$1} without fallback',
      () async {
        final h = Harness(reply: value.$1);
        try {
          await expectLater(
            h.transport.authenticated,
            throwsA(failure(value.$2)),
          );
          expect((await h.transport.ended)!.code, value.$2);
          expect(h.peer.authRequests, hasLength(1));
        } finally {
          await h.close();
        }
      },
    );
  }
  test('declined trust maps fixed failure and never dispatches credential or userauth', () async {
    final h = Harness(trust: (_) async => false);
    try {
      await expectLater(
        h.transport.authenticated,
        throwsA(failure(FailureCode.trustRequired)),
      );
      expect(h.peer.authRequests, isEmpty);
      expect(h.prompts, 0);
    } finally {
      await h.close();
    }
  });
  test(
    'unsolicited auth success cannot publish an authenticated transport',
    () async {
      final h = Harness();
      h.peer.authSuccessBeforeRequest = true;
      try {
        await expectLater(
          h.transport.authenticated,
          throwsA(failure(FailureCode.unsupportedServer)),
        );
        expect(h.peer.authRequests, isEmpty);
        expect((await h.transport.ended)!.code, FailureCode.unsupportedServer);
      } finally {
        await h.close();
      }
    },
  );
  test('strict API allows one in-flight ping without entering the vendor request queue', () async {
    var blocked = false;
    final release = Completer<void>(), entered = Completer<void>();
    final h = Harness(
      admit: (write) async {
        if (blocked) {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        }
        write();
      },
    );
    try {
      await h.transport.authenticated;
      blocked = true;
      final first = h.transport.ping();
      await entered.future;
      await expectLater(
        h.transport.ping(),
        throwsA(failure(FailureCode.resourceExhausted)),
      );
      expect(h.peer.pings, 0);
      blocked = false;
      release.complete();
      await first;
      expect(h.peer.pings, 1);
      expect(h.transport.isClosed, isFalse);
    } finally {
      if (!release.isCompleted) release.complete();
      await h.close();
    }
  });
  test(
    'actual auth socket write rechecks authority after queued admission delay',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      late Harness h;
      h = Harness(
        admit: (write) async {
          if (h.peer.clientMessageIds.contains(5)) {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }
          if (!h.authorized)
            throw const OperationFailure(FailureCode.accessRevoked);
          write();
        },
      );
      final result = expectLater(
        h.transport.authenticated,
        throwsA(failure(FailureCode.accessRevoked)),
      );
      try {
        await entered.future;
        expect(h.peer.authRequests, isEmpty);
        h.authorized = false;
        release.complete();
        await result;
        expect(h.peer.authRequests, isEmpty);
        expect((await h.transport.ended)!.code, FailureCode.accessRevoked);
      } finally {
        await h.close();
      }
    },
  );
  test('stale write callback after admission has returned cannot touch the raw sink', () async {
    void Function()? lateWrite;
    final h = Harness(
      admit: (write) async {
        lateWrite = write;
      },
    );
    try {
      await expectLater(
        h.transport.authenticated,
        throwsA(failure(FailureCode.conflict)),
      );
      expect(() => lateWrite!(), throwsA(failure(FailureCode.conflict)));
      expect(h.peer.clientMessageIds, isEmpty);
      expect(h.peer.authRequests, isEmpty);
    } finally {
      await h.close();
    }
  });
  test(
    'duplicate physical write callback is fenced before second socket effect',
    () async {
      final h = Harness(
        admit: (write) async {
          write();
          write();
        },
      );
      try {
        await expectLater(
          h.transport.authenticated,
          throwsA(failure(FailureCode.conflict)),
        );
        expect(h.peer.authRequests, isEmpty);
      } finally {
        await h.close();
      }
    },
  );
  test(
    'expired crypto budget stops before host trust or credentials',
    () async {
      final h = Harness(budget: () => Duration.zero);
      try {
        await expectLater(
          h.transport.authenticated,
          throwsA(failure(FailureCode.timeout)),
        );
        expect(h.observations, isEmpty);
        expect(h.peer.authRequests, isEmpty);
      } finally {
        await h.close();
      }
    },
  );
  test(
    'cancelled prompt never signs or authenticates after late passphrase',
    () async {
      final entered = Completer<void>(), phrase = Completer<String?>();
      final h = Harness(
        keyName: 'ed25519-encrypted',
        prompt: () {
          entered.complete();
          return phrase.future;
        },
      );
      final result = expectLater(
        h.transport.authenticated,
        throwsA(isA<OperationFailure>()),
      );
      try {
        await entered.future;
        h.cancellation.cancel();
        phrase.complete('serverdeck-unit-passphrase');
        await result;
        await h.transport.close();
        expect(h.peer.authRequests, isEmpty);
        expect(h.signer.activeWorkers, 0);
      } finally {
        await h.close();
      }
    },
  );
  test('changed verified host persistence is queued before ended and awaited before terminal event', () async {
    final entered = Completer<void>(), persisted = Completer<void>();
    final replacement = parsePrivateKey(fixture('rsa2048'));
    HostObservation? observed;
    final h = Harness(
      changed: (value) {
        observed = value;
        entered.complete();
        return persisted.future;
      },
    );
    try {
      await h.transport.authenticated;
      var ended = false;
      final terminal = h.transport.ended.then((value) {
        ended = true;
        return value;
      });
      h.peer.beginRekey(replacement.key);
      await entered.future;
      await turn();
      expect(ended, isFalse);
      expect(observed!.keyType, 'ssh-rsa');
      expect(observed!.blob, replacement.key.toPublicKey().encode());
      persisted.complete();
      expect((await terminal)!.code, FailureCode.hostKeyChanged);
      expect(h.peer.authRequests, hasLength(1));
    } finally {
      await h.close();
      replacement.dispose();
    }
  });
  test('failed changed-host persistence returns storage failure instead of losing it to library close', () async {
    final replacement = parsePrivateKey(fixture('rsa2048'));
    final h = Harness(
      changed: (_) async =>
          throw const OperationFailure(FailureCode.storageUnavailable),
    );
    try {
      await h.transport.authenticated;
      h.peer.beginRekey(replacement.key);
      expect((await h.transport.ended)!.code, FailureCode.storageUnavailable);
    } finally {
      await h.close();
      replacement.dispose();
    }
  });
  test('close waits for actual socket done, not early library done', () async {
    final confirm = Completer<void>();
    final h = Harness(
      wrap: (peer) => ControlledSocket(peer, holdDone: confirm),
    );
    try {
      await h.transport.authenticated;
      var closed = false;
      final closing = h.transport.close().then((_) {
        closed = true;
      });
      await turn();
      expect(closed, isFalse);
      confirm.complete();
      await closing;
      expect(closed, isTrue);
    } finally {
      if (!confirm.isCompleted) confirm.complete();
      await h.close();
    }
  });
  test('failed physical close stays retryable after library already reports closed', () async {
    late ControlledSocket socket;
    final h = Harness(
      wrap: (peer) => socket = ControlledSocket(peer, failFirstClose: true),
    );
    try {
      await h.transport.authenticated;
      await expectLater(
        h.transport.close(),
        throwsA(failure(FailureCode.cleanupRequired)),
      );
      await h.transport.close();
      expect(socket.closes, 2);
    } finally {
      await h.close();
    }
  });
  test('invalid host signature and aggregate resource failure have fixed mapping before host acceptance', () async {
    for (final overflow in [false, true]) {
      final parsed = parsePrivateKey(fixture('ed25519'));
      final peer = MemoryKexPeer(
        hostKey: parsed.key,
        negotiated: SSHHostkeyType.ed25519,
        tamperSignature: !overflow,
      );
      final verifier = HostSignatureVerifier(),
          signer = PrivateSigner(),
          cancellation = WorkCancellation();
      final entered = Completer<void>(), trust = Completer<bool>();
      var hosts = 0;
      final transport = StrictSshTransport(
        socket: peer,
        username: 'synthetic',
        credential: PasswordCredential(Uint8List.fromList([120])),
        verifier: verifier,
        signer: signer,
        cancellation: cancellation,
        admitWrite: (write) async => write(),
        checkAuthentication: () {},
        verifyHost: (_) {
          hosts++;
          entered.complete();
          return trust.future;
        },
        changedHost: (_) async {},
        requestPassphrase: () async => null,
        remainingBudget: () => const Duration(seconds: 30),
      );
      final result = expectLater(
        transport.authenticated,
        throwsA(
          failure(
            overflow
                ? FailureCode.resourceExhausted
                : FailureCode.unsupportedServer,
          ),
        ),
      );
      try {
        if (overflow) {
          await entered.future;
          peer.injectRaw(Uint8List(600000));
          peer.injectRaw(Uint8List(600000));
        }
        await result;
        expect(peer.clientMessageIds, isNot(contains(50)));
        if (!overflow) expect(hosts, 0);
      } finally {
        if (!trust.isCompleted) trust.complete(false);
        await transport.close();
        await peer.close();
        await verifier.dispose();
        await signer.dispose();
        parsed.dispose();
      }
    }
  });
  test('error mapping follows structured carriers and never serializes untrusted messages', () {
    for (final value in <(Object, FailureCode)>[
      (
        SSHSignatureVerificationError(SSHSignatureFailure.stopping),
        FailureCode.shuttingDown,
      ),
      (
        SSHSignatureVerificationError(SSHSignatureFailure.cancelled),
        FailureCode.conflict,
      ),
      (
        SSHSignatureVerificationError(SSHSignatureFailure.exhausted),
        FailureCode.resourceExhausted,
      ),
      (
        SSHSignatureVerificationError(SSHSignatureFailure.timeout),
        FailureCode.timeout,
      ),
      (SSHResourceLimitError(), FailureCode.resourceExhausted),
      (
        SSHHandshakeError('SYNTHETIC_REMOTE_DETAIL'),
        FailureCode.unsupportedServer,
      ),
      (
        SSHSocketError(StateError('SYNTHETIC_DETAIL')),
        FailureCode.networkError,
      ),
      (
        SSHAuthAbortError(
          'SYNTHETIC_DETAIL',
          SSHInternalError(
            const OperationFailure(FailureCode.passphraseInvalid),
          ),
        ),
        FailureCode.passphraseInvalid,
      ),
    ]) {
      final mapped = sshFailure(value.$1);
      expect(mapped.code, value.$2);
      expect(mapped.toString(), isNot(contains('SYNTHETIC')));
      expect(mapped.toJson().toString(), isNot(contains('SYNTHETIC')));
    }
  });
}
