import 'dart:async';

import 'package:serverdeck_engine/remote/ssh_transport.dart';
import 'package:test/test.dart';

Matcher transportFailure(SshTransportCode code) => throwsA(
  isA<SshTransportFailure>().having((error) => error.code, 'safe code', code),
);

void main() {
  test(
    'one engine shares two charged slots and retains them during close',
    () async {
      final pool = SshTransportPool();
      final first = pool.reserve(), second = pool.reserve();
      expect(pool.activeTransports, 2);
      expect(pool.reserve, transportFailure(SshTransportCode.RESOURCE_LIMIT));
      first.close();
      first.close();
      await first.done;
      final replacement = pool.reserve();
      expect(pool.activeTransports, 2);

      var physicallyClosed = false;
      final closing = pool.close();
      unawaited(closing.then((_) => physicallyClosed = true));
      expect(identical(closing, pool.close()), isTrue);
      expect(
        pool.reserve,
        transportFailure(SshTransportCode.SERVICE_UNAVAILABLE),
      );
      await Future<void>.delayed(Duration.zero);
      expect(physicallyClosed, isFalse);
      second.close();
      await Future<void>.delayed(Duration.zero);
      expect(physicallyClosed, isFalse);
      replacement.close();
      await closing;
      expect(physicallyClosed, isTrue);
      expect(pool.activeTransports, 0);
    },
  );

  test(
    'typed endpoint rejects executable syntax and never renders credentials',
    () {
      final endpoint = SshEndpoint('unit.invalid', 22, 'unit_user');
      expect(endpoint.host, 'unit.invalid');
      expect(endpoint.toString(), 'SshEndpoint');
      final credential = SshCredential.password('unit-only-secret-marker');
      expect(credential.toString(), 'SshCredential');
      for (final create in <void Function()>[
        () => SshEndpoint('unit.invalid;false', 22, 'unit_user'),
        () => SshEndpoint('unit.invalid', 0, 'unit_user'),
        () => SshEndpoint('unit.invalid', 65536, 'unit_user'),
        () => SshEndpoint('unit.invalid', 22, 'user\ncommand'),
      ]) {
        expect(create, transportFailure(SshTransportCode.VALIDATION_ERROR));
      }
    },
  );

  test(
    'journal request keeps bounded typed filters without starting a transport',
    () {
      final since = DateTime.utc(2026, 10, 30);
      final request = SshReadRequest.journal(
        unit: 'postgresql@16-main.service',
        since: since,
        until: since.add(const Duration(minutes: 1)),
        cursor: 's=opaque;quoted\'cursor',
        priority: 7,
        limit: 1000,
      );
      expect(request.source, SshReadSource.journal);
      expect(request.unit, 'postgresql@16-main.service');
      expect(request.limit, 1000);
      for (final create in <void Function()>[
        () => SshReadRequest.journal(unit: 'a.service;command'),
        () => SshReadRequest.journal(cursor: 'unsafe\nargument'),
        () => SshReadRequest.journal(cursor: 'x' * 4097),
        () => SshReadRequest.journal(limit: 0),
        () => SshReadRequest.journal(limit: 1001),
        () => SshReadRequest.journal(priority: 8),
        () => SshReadRequest.journal(
          since: since,
          until: since.subtract(const Duration(seconds: 1)),
        ),
      ]) {
        expect(create, transportFailure(SshTransportCode.VALIDATION_ERROR));
      }
    },
  );
}
