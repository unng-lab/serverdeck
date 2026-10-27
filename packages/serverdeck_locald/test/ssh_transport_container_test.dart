import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:serverdeck_locald/remote/ssh_transport.dart';
import 'package:test/test.dart';

void main() {
  final fixture = Platform.environment['SERVERDECK_SSH_FIXTURE'];
  if (fixture == null) {
    test(
      'real SSH container requires tools/test-ssh-container.sh',
      () {},
      skip: 'Disposable fixture not started',
    );
    return;
  }
  late SshEndpoint endpoint;
  late SshHostPin pin;
  late SshCredential password;
  late SshCredential key;
  late SshCredential encrypted;
  late SshCredential wrongKey;
  late SshTransportPool pool;
  final container = Platform.environment['SERVERDECK_SSH_CONTAINER']!;
  Future<String> authLog() async {
    final result = await Process.run('docker', [
      'exec',
      container,
      'cat',
      '/run/auth.log',
    ]);
    if (result.exitCode != 0) {
      throw StateError('FIXTURE_LOG_UNAVAILABLE');
    }
    return result.stdout as String;
  }

  Future<void> assertNoAuthSince(String before) async {
    var delta = '';
    final deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5)) {
      delta = (await authLog()).substring(before.length);
      if (delta.contains('Connection closed') ||
          delta.contains('Disconnected from'))
        break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(
      delta.contains('Connection closed') ||
          delta.contains('Disconnected from'),
      isTrue,
      reason: 'Actual preauth connection close required',
    );
    expect(
      delta.contains('userauth-request'),
      isFalse,
      reason: 'Host verification must precede user authentication',
    );
    expect(delta.contains('Accepted '), isFalse);
  }

  Matcher fails(SshTransportCode code) => throwsA(
    isA<SshTransportFailure>().having((error) => error.code, 'code', code),
  );
  setUpAll(() async {
    endpoint = SshEndpoint(
      '127.0.0.1',
      int.parse(Platform.environment['SERVERDECK_SSH_PORT']!),
      'deck',
    );
    pin = SshHostPin(
      Platform.environment['SERVERDECK_SSH_FORMAT']!,
      (await File('$fixture/fingerprint').readAsString()).trim(),
    );
    password = SshCredential.password(
      await File('$fixture/password-value').readAsString(),
    );
    key = SshCredential.privateKey(
      await File('$fixture/client').readAsString(),
    );
    encrypted = SshCredential.privateKey(
      await File('$fixture/encrypted').readAsString(),
      passphrase: 'fixture-passphrase',
    );
    wrongKey = SshCredential.privateKey(
      await File('$fixture/untrusted-client').readAsString(),
    );
  });
  setUp(() {
    pool = SshTransportPool();
  });
  tearDown(() async {
    await pool.close().timeout(const Duration(seconds: 5));
  });

  test(
    'probe returns exact advertised key without user authentication',
    () async {
      final before = await authLog();
      final attempt = pool.probe(endpoint);
      expect(await attempt.result, pin);
      await attempt.settled;
      expect(pool.activeTransports, 0);
      await assertNoAuthSince(before);
    },
  );
  test(
    'wrong pin refuses both valid credential kinds before user authentication',
    () async {
      final wrong = SshHostPin(
        pin.format,
        'SHA256:${base64.encode(List.filled(32, 42)).replaceAll('=', '')}',
      );
      for (final credential in [password, key]) {
        final before = await authLog();
        final attempt = pool.connect(endpoint, wrong, credential);
        await expectLater(
          attempt.result,
          fails(SshTransportCode.TRUST_CHANGED),
        );
        await attempt.settled;
        expect(pool.activeTransports, 0);
        await assertNoAuthSince(before);
      }
    },
  );
  test('actual password, PEM and encrypted PEM authenticate and cleanly reuse capacity', () async {
    for (final credential in [password, key, encrypted]) {
      final attempt = pool.connect(endpoint, pin, credential);
      final lease = await attempt.result;
      expect(pool.activeTransports, 1);
      var settled = false;
      unawaited(
        attempt.settled.then((_) {
          settled = true;
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      await lease.close().timeout(const Duration(seconds: 5));
      await lease.done;
      expect(pool.activeTransports, 0);
    }
  });
  test(
    'wrong password and wrong key are fixed authentication errors',
    () async {
      for (final credential in [
        SshCredential.password('fixture-deliberately-wrong'),
        wrongKey,
      ]) {
        final attempt = pool.connect(endpoint, pin, credential);
        await expectLater(
          attempt.result,
          fails(SshTransportCode.AUTHENTICATION_FAILED),
        );
        await attempt.settled;
        expect(pool.activeTransports, 0);
      }
    },
  );
  test(
    'pool close drains authenticated transports without rewriting success',
    () async {
      final first = pool.connect(endpoint, pin, password);
      final second = pool.connect(endpoint, pin, key);
      final leases = await Future.wait([first.result, second.result]);
      expect(
        () => pool.probe(endpoint),
        fails(SshTransportCode.RESOURCE_LIMIT),
      );
      await pool.close().timeout(const Duration(seconds: 5));
      await Future.wait(leases.map((lease) => lease.done));
      expect(identical(await first.result, leases[0]), isTrue);
      expect(pool.activeTransports, 0);
    },
  );
  test(
    'actual remote disconnect drains and permits a new connection',
    () async {
      final attempt = pool.connect(endpoint, pin, password);
      final lease = await attempt.result;
      final result = await Process.run('docker', [
        'exec',
        container,
        'pkill',
        '-u',
        'deck',
        'sshd',
      ]);
      if (result.exitCode != 0) {
        throw StateError('FIXTURE_DISCONNECT_FAILED');
      }
      await lease.done.timeout(const Duration(seconds: 5));
      expect(pool.activeTransports, 0);
      final next = await pool.connect(endpoint, pin, password).result;
      await next.close();
    },
  );
}
