import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:serverdeck_locald/remote/ssh_transport.dart';
import 'package:test/test.dart';

final _fingerprint =
    'SHA256:${base64.encode(List.filled(32, 1)).replaceAll('=', '')}';
final _pin = SshHostPin('ssh-ed25519', _fingerprint);
Matcher _fails(SshTransportCode code) => throwsA(
  isA<SshTransportFailure>().having((error) => error.code, 'code', code),
);

void main() {
  test(
    'expired worker result cannot open TCP before its due timer callback',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'serverdeck-key-deadline-',
      );
      final keyPath = '${directory.path}/client';
      final generated = await Process.run('ssh-keygen', [
        '-q',
        '-t',
        'ed25519',
        '-a',
        '16',
        '-N',
        'fixture-pass',
        '-f',
        keyPath,
      ]);
      if (generated.exitCode != 0)
        throw StateError('FIXTURE_KEY_GENERATION_FAILED');
      final credential = SshCredential.privateKey(
        await File(keyPath).readAsString(),
        passphrase: 'fixture-pass',
      );
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      var accepted = 0;
      final subscription = server.listen((socket) {
        accepted++;
        socket.destroy();
      });
      final pool = SshTransportPool();
      addTearDown(() async {
        await pool.close();
        await subscription.cancel();
        await server.close();
        await directory.delete(recursive: true);
      });
      final attempt = pool.connect(
        SshEndpoint('127.0.0.1', server.port, 'deck'),
        _pin,
        credential,
      );
      // The real worker runs while this isolate deliberately delays its message
      // and timer queues. Production parsing never blocks the locald isolate.
      sleep(const Duration(milliseconds: 5500));
      await expectLater(
        attempt.result,
        _fails(SshTransportCode.VALIDATION_ERROR),
      );
      await attempt.settled.timeout(const Duration(seconds: 5));
      expect(accepted, 0);
      expect(pool.activeTransports, 0);
    },
  );

  test('real encrypted key worker bounds KDF and preserves concurrent cancellation', () async {
    final directory = await Directory.systemTemp.createTemp('serverdeck-key-');
    final keyPath = '${directory.path}/client';
    final generated = await Process.run('ssh-keygen', [
      '-q',
      '-t',
      'ed25519',
      '-a',
      '16',
      '-N',
      'fixture-pass',
      '-f',
      keyPath,
    ]);
    if (generated.exitCode != 0) {
      throw StateError('FIXTURE_KEY_GENERATION_FAILED');
    }
    final pem = await File(keyPath).readAsString();
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    final accepted = StreamController<int>.broadcast();
    final subscription = server.listen((socket) {
      sockets.add(socket);
      accepted.add(sockets.length);
      socket.listen((_) {}, onError: (Object _) {});
    });
    final pool = SshTransportPool();
    addTearDown(() async {
      await pool.close();
      for (final socket in sockets) {
        socket.destroy();
      }
      await subscription.cancel();
      await server.close();
      await accepted.close();
      await directory.delete(recursive: true);
    });
    final endpoint = SshEndpoint('127.0.0.1', server.port, 'deck');
    final container = OpenSSHKeyPairs.decode(SSHPem.decode(pem).content);
    final options = container.kdfOptions as OpenSSHBcryptKdfOptions;
    for (final rounds in [65, 4294967295]) {
      final expensive = OpenSSHKeyPairs(
        cipherName: container.cipherName,
        kdfName: container.kdfName,
        kdfOptions: OpenSSHBcryptKdfOptions(options.salt, rounds),
        publicKeys: container.publicKeys,
        privateKeyBlob: container.privateKeyBlob,
      ).toPem();
      final attempt = pool.connect(
        endpoint,
        _pin,
        SshCredential.privateKey(expensive, passphrase: 'fixture-pass'),
      );
      await expectLater(
        attempt.result,
        _fails(SshTransportCode.VALIDATION_ERROR),
      );
      await attempt.settled.timeout(const Duration(seconds: 5));
      expect(sockets, isEmpty);
    }
    final wrong = pool.connect(
      endpoint,
      _pin,
      SshCredential.privateKey(pem, passphrase: 'wrong'),
    );
    await expectLater(wrong.result, _fails(SshTransportCode.VALIDATION_ERROR));
    await wrong.settled;
    expect(sockets, isEmpty);
    final initialAccepted = accepted.stream.first;
    final stalled = pool.probe(endpoint);
    final stalledError = expectLater(
      stalled.result,
      _fails(SshTransportCode.CANCELLED),
    );
    await initialAccepted;
    final key = pool.connect(
      endpoint,
      _pin,
      SshCredential.privateKey(pem, passphrase: 'fixture-pass'),
    );
    final keyError = expectLater(
      key.result,
      _fails(SshTransportCode.CANCELLED),
    );
    final clock = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    stalled.cancel();
    await stalledError;
    await stalled.settled;
    expect(clock.elapsedMilliseconds, lessThan(1000));
    // Actual successful parse reaches TCP; polling here does not alter budgets.
    while (sockets.length < 2 && pool.activeTransports != 0) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(sockets.length, 2);
    key.cancel();
    await keyError;
    await key.settled;
    expect(pool.activeTransports, 0);
  });

  test('canonical pin and negotiated RSA names stay distinct', () {
    for (final algorithm in ['rsa-sha2-256', 'rsa-sha2-512']) {
      expect(
        SshHostPin.fromCallback(
          algorithm,
          Uint8List.fromList(utf8.encode(_fingerprint)),
        ),
        SshHostPin('ssh-rsa', _fingerprint),
      );
      expect(
        () => SshHostPin(algorithm, _fingerprint),
        _fails(SshTransportCode.VALIDATION_ERROR),
      );
    }
    for (final format in [
      'ssh-ed25519',
      'ecdsa-sha2-nistp256',
      'ecdsa-sha2-nistp384',
      'ecdsa-sha2-nistp521',
    ]) {
      expect(
        SshHostPin.fromCallback(
          format,
          Uint8List.fromList(utf8.encode(_fingerprint)),
        ),
        SshHostPin(format, _fingerprint),
      );
    }
    for (final algorithm in ['ssh-rsa', 'unknown']) {
      expect(
        () => SshHostPin.fromCallback(
          algorithm,
          Uint8List.fromList(utf8.encode(_fingerprint)),
        ),
        _fails(SshTransportCode.TRUST_CHANGED),
      );
    }
    expect(
      () => SshHostPin.fromCallback('ssh-ed25519', Uint8List.fromList([255])),
      _fails(SshTransportCode.TRUST_CHANGED),
    );
    for (final fingerprint in [
      '$_fingerprint=',
      'SHA256:${'A' * 42}B',
      '$_fingerprint\n',
      'MD5:00',
    ]) {
      expect(
        () => SshHostPin('ssh-ed25519', fingerprint),
        _fails(SshTransportCode.VALIDATION_ERROR),
      );
    }
  });

  test(
    'endpoint and secrets use bounded strict validation with safe formatting',
    () {
      expect(SshEndpoint('::1', 65535, '_user').port, 65535);
      for (final host in [
        'user@host',
        'https://host',
        '[::1]',
        'host\n',
        'x' * 254,
      ]) {
        expect(
          () => SshEndpoint(host, 22, 'deck'),
          _fails(SshTransportCode.VALIDATION_ERROR),
        );
      }
      expect(
        () => SshEndpoint('host', 0, 'deck'),
        _fails(SshTransportCode.VALIDATION_ERROR),
      );
      expect(
        () => SshEndpoint('host', 22, '-deck'),
        _fails(SshTransportCode.VALIDATION_ERROR),
      );
      expect(SshCredential.password('я' * 2048).toString(), 'SshCredential');
      for (final password in ['', 'я' * 2049, 'bad\n', '\u0000', '\ud800']) {
        expect(
          () => SshCredential.password(password),
          _fails(SshTransportCode.VALIDATION_ERROR),
        );
      }
      expect(
        () => SshCredential.privateKey('private-marker'),
        _fails(SshTransportCode.VALIDATION_ERROR),
      );
      expect(SshEndpoint('private-host', 22, 'deck').toString(), 'SshEndpoint');
      expect(_pin.toString(), 'SshHostPin');
      expect(
        const SshTransportFailure(SshTransportCode.CONNECTION_FAILED)
            .toString(),
        'SshTransportFailure(CONNECTION_FAILED)',
      );
    },
  );

  test(
    'actual stalled sockets retain capacity through cancel and pool close',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final accepted = Completer<void>();
      final subscription = server.listen((socket) {
        sockets.add(socket);
        if (sockets.length == 2) accepted.complete();
        socket.listen((_) {}, onError: (Object _) {});
      });
      final pool = SshTransportPool();
      addTearDown(() async {
        await pool.close();
        for (final socket in sockets) {
          socket.destroy();
        }
        await subscription.cancel();
        await server.close();
      });
      final endpoint = SshEndpoint('127.0.0.1', server.port, 'deck');
      final first = pool.connect(
        endpoint,
        _pin,
        SshCredential.password('fixture'),
      );
      final second = pool.probe(endpoint);
      final firstError = expectLater(
        first.result,
        _fails(SshTransportCode.CANCELLED),
      );
      final secondError = expectLater(
        second.result,
        _fails(SshTransportCode.SERVICE_UNAVAILABLE),
      );
      await accepted.future.timeout(const Duration(seconds: 5));
      expect(pool.activeTransports, 2);
      expect(
        () => pool.probe(endpoint),
        _fails(SshTransportCode.RESOURCE_LIMIT),
      );
      first.cancel();
      await firstError;
      await first.settled.timeout(const Duration(seconds: 5));
      expect(pool.activeTransports, 1);
      final closing = pool.close();
      expect(identical(closing, pool.close()), isTrue);
      await closing.timeout(const Duration(seconds: 5));
      await secondError;
      expect(pool.activeTransports, 0);
      expect(
        () => pool.probe(endpoint),
        _fails(SshTransportCode.SERVICE_UNAVAILABLE),
      );
    },
  );

  test(
    'actual stalled peer times out at original fifteen second budget',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      Socket? socket;
      final subscription = server.listen((value) {
        socket = value;
        value.listen((_) {}, onError: (Object _) {});
      });
      final pool = SshTransportPool();
      addTearDown(() async {
        await pool.close();
        socket?.destroy();
        await subscription.cancel();
        await server.close();
      });
      final clock = Stopwatch()..start();
      final attempt = pool.probe(SshEndpoint('127.0.0.1', server.port, 'deck'));
      await expectLater(attempt.result, _fails(SshTransportCode.TIMEOUT));
      expect(clock.elapsedMilliseconds, inInclusiveRange(14500, 18000));
      await attempt.settled.timeout(const Duration(seconds: 5));
      expect(pool.activeTransports, 0);
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );

  test(
    'real malformed key worker exits before TCP, including late spawn cancel',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      var accepted = 0;
      final subscription = server.listen((socket) {
        accepted++;
        socket.destroy();
      });
      final endpoint = SshEndpoint('127.0.0.1', server.port, 'deck');
      final credential = SshCredential.privateKey(
        '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----',
      );
      final pool = SshTransportPool();
      addTearDown(() async {
        await pool.close();
        await subscription.cancel();
        await server.close();
      });
      final invalid = pool.connect(endpoint, _pin, credential);
      await expectLater(
        invalid.result,
        _fails(SshTransportCode.VALIDATION_ERROR),
      );
      await invalid.settled;
      final cancelled = pool.connect(endpoint, _pin, credential);
      cancelled.cancel();
      await expectLater(cancelled.result, _fails(SshTransportCode.CANCELLED));
      await cancelled.settled.timeout(const Duration(seconds: 5));
      final closed = pool.connect(endpoint, _pin, credential);
      final closedError = expectLater(
        closed.result,
        _fails(SshTransportCode.SERVICE_UNAVAILABLE),
      );
      await pool.close().timeout(const Duration(seconds: 5));
      await closedError;
      expect(accepted, 0);
      expect(pool.activeTransports, 0);
    },
  );
}
