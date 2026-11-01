import 'dart:async';

import 'package:serverdeck_engine/remote/ssh_transport.dart';
import 'package:test/test.dart';

Matcher failure([
  SshTransportCode code = SshTransportCode.SERVICE_UNAVAILABLE,
]) => throwsA(
  isA<SshTransportFailure>().having((e) => e.code, 'safe code', code),
);

Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// Tests never admit a connect/probe into the pool: no sockets, processes,
// isolates, SSH peers or files. Actual pool reservations model pending custody.
void main() {
  test(
    'empty pool stays paused after drain until explicit current resume',
    () async {
      final pool = SshTransportPool();
      final pause = pool.suspend();
      expect(identical(pool.suspend(), pause), isTrue);
      expect(() => pool.reserve(), failure());
      await pause.settled;
      expect(pool.activeTransports, 0);
      expect(() => pool.reserve(), failure());
      pool.resume(pause);
      final reservation = pool.reserve();
      expect(pool.activeTransports, 1);
      reservation.close();
      await pool.close();
    },
  );

  test(
    'pause retains both custody slots until each actual owner releases',
    () async {
      final pool = SshTransportPool();
      final first = pool.reserve(), second = pool.reserve();
      final pause = pool.suspend();
      var drained = false;
      final actual = pause.settled.then((_) => drained = true);
      expect(() => pool.reserve(), failure());
      expect(() => pool.resume(pause), failure());
      await settle();
      expect(drained, isFalse);
      expect(pool.activeTransports, 2);
      first.close();
      await settle();
      expect(drained, isFalse);
      expect(pool.activeTransports, 1);
      second.close();
      await actual;
      pool.resume(pause);
      final a = pool.reserve(), b = pool.reserve();
      expect(() => pool.reserve(), failure(SshTransportCode.RESOURCE_LIMIT));
      a.close();
      b.close();
      await pool.close();
    },
  );

  test(
    'paused pool rejects late custody handoff and direct probe before IO',
    () async {
      final pool = SshTransportPool();
      final reservation = pool.reserve();
      final pause = pool.suspend();
      final endpoint = SshEndpoint('unit.invalid', 22, 'unit');
      final pin = SshHostPin('ssh-ed25519', 'SHA256:${'A' * 43}');
      final credential = SshCredential.password('unit-ephemeral-only');
      expect(() => pool.probe(endpoint), failure());
      expect(() => pool.connect(endpoint, pin, credential), failure());
      expect(
        () => reservation.connect(
          endpoint,
          pin,
          credential,
          deadline: const Duration(seconds: 15),
        ),
        failure(),
      );
      expect(pool.activeTransports, 1);
      reservation.close();
      await pause.settled;
      pool.resume(pause);
      // A released pre-pause reservation never becomes a new connection permit.
      expect(
        () => reservation.connect(
          endpoint,
          pin,
          credential,
          deadline: const Duration(seconds: 15),
        ),
        failure(),
      );
      expect(pool.activeTransports, 0);
      await pool.close();
    },
  );

  test(
    'logical pause timeout neither releases a slot nor opens intake',
    () async {
      final pool = SshTransportPool();
      final reservation = pool.reserve();
      final pause = pool.suspend();
      await expectLater(
        pause.settled.timeout(Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
      expect(identical(pool.suspend(), pause), isTrue);
      expect(pool.activeTransports, 1);
      expect(() => pool.resume(pause), failure());
      expect(() => pool.reserve(), failure());
      reservation.close();
      await pause.settled;
      expect(() => pool.reserve(), failure());
      pool.resume(pause);
      await pool.close();
    },
  );

  test(
    'foreign stale and consumed pause handles cannot resume another cycle',
    () async {
      final pool = SshTransportPool(), other = SshTransportPool();
      final old = pool.suspend(), foreign = other.suspend();
      await Future.wait([old.settled, foreign.settled]);
      expect(() => pool.resume(foreign), failure());
      pool.resume(old);
      expect(() => pool.resume(old), failure());
      final reservation = pool.reserve();
      final current = pool.suspend();
      expect(identical(old, current), isFalse);
      expect(() => pool.resume(old), failure());
      expect(() => pool.resume(current), failure());
      reservation.close();
      await current.settled;
      expect(() => pool.resume(old), failure());
      pool.resume(current);
      other.resume(foreign);
      await Future.wait([pool.close(), other.close()]);
    },
  );

  test(
    'permanent close wins over pending and late-completed suspend',
    () async {
      final pool = SshTransportPool();
      final reservation = pool.reserve();
      final pause = pool.suspend();
      var closed = false;
      final closing = pool.close().then((_) => closed = true);
      await settle();
      expect(closed, isFalse);
      expect(() => pool.resume(pause), failure());
      expect(() => pool.reserve(), failure());
      reservation.close();
      reservation.close();
      await Future.wait([pause.settled, closing]);
      expect(closed, isTrue);
      expect(() => pool.resume(pause), failure());
      expect(() => pool.suspend(), failure());
      expect(() => pool.reserve(), failure());
    },
  );
}
