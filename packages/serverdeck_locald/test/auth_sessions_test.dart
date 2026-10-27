import 'dart:convert';

import 'package:serverdeck_locald/api/sessions.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

import 'auth_test.dart' show generation, code;

String id(int i) => base64Url.encode(List.filled(32, i)).replaceAll('=', '');
void main() {
  test(
    'expiry identifies its channel without disrupting explicit close replies',
    () {
      var now = Duration.zero;
      final expired = <String>[];
      final registry = SessionRegistry(
        generation: generation,
        elapsed: () => now,
        onExpiredChannel: expired.add,
      );
      registry.register('explicit', id(1), {});
      registry.disconnect('explicit');
      registry.register('expired', id(2), {});
      now = const Duration(seconds: 60);
      registry.expire();
      registry.expire();
      expect(expired, ['expired']);
      registry.register('stopped', id(3), {});
      registry.stop();
      expect(expired, ['expired']);
    },
  );
  test(
    'session channel binding, limits, expiry and revocation use monotonic time',
    () {
      var time = Duration.zero;
      final detached = <String>[];
      final registry = SessionRegistry(
        generation: generation,
        elapsed: () => time,
        onDetached: detached.add,
      );
      for (var i = 1; i <= 8; i++)
        registry.register('pipe-$i', id(i), {Capability.profilesRead});
      expect(
        () => registry.register('overflow', id(9), {}),
        code('RESOURCE_LIMIT'),
      );
      expect(() => registry.begin('other', id(1), null), code('UNAUTHORIZED'));
      final requests = List.generate(
        16,
        (_) => registry.begin('pipe-1', id(1), Capability.profilesRead),
      );
      expect(
        () => registry.begin('pipe-1', id(1), null),
        code('RESOURCE_LIMIT'),
      );
      requests.first.complete();
      requests.first.complete();
      registry.begin('pipe-1', id(1), null).complete();
      time = const Duration(seconds: 59);
      registry.begin('pipe-1', id(1), null).complete();
      time = const Duration(seconds: 60);
      registry.expire();
      expect(registry.count, 1);
      expect(detached, hasLength(7));
      time = const Duration(seconds: 119);
      registry.expire();
      expect(registry.count, 0);
      expect(detached, hasLength(8));
      for (final request in requests) request.complete();
      registry.register('pipe-1', id(9), {Capability.readinessRead});
      expect(() => registry.begin('pipe-1', id(1), null), code('UNAUTHORIZED'));
      registry.disconnect('pipe-1');
      registry.disconnect('pipe-1');
      expect(detached.last, id(9));
      registry.stop();
      expect(() => registry.register('pipe-2', id(10), {}), code('NOT_READY'));
    },
  );
}
