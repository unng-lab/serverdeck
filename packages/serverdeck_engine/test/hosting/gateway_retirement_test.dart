import 'dart:async';

import 'package:test/test.dart';

import 'in_process_gateway_test.dart' as core;
import 'worker_gateway_test.dart' as wire;
import 'sessions_test.dart' show settle;

void main() {
  test(
    'in-process retirement precedes physical drain of accepted work',
    () async {
      final s = await core.Setup.create(),
          effect = Completer<Map<String, Object?>>();
      s.services.effect = (_, __) => effect.future;
      s.gateway.call('settings.get', {}, requestId: core.id).ignore();
      await settle();
      var closed = false;
      final close = s.gateway.close().then((_) => closed = true);
      await s.gateway.retired;
      expect(s.gateway.isClosed, isTrue);
      expect(closed, isFalse);
      effect.complete(core.settings());
      await close;
      await s.auth.close();
    },
  );
  test(
    'worker proxy retirement precedes physical settlement acknowledgement',
    () async {
      final b = await wire.Bridge.create(),
          effect = Completer<Map<String, Object?>>();
      b.setup.services.effect = (_, __) => effect.future;
      b.call().ignore();
      await settle();
      var closed = false;
      final close = b.proxy.close().then((_) => closed = true);
      await b.proxy.retired;
      expect(b.proxy.isClosed, isTrue);
      expect(closed, isFalse);
      effect.complete(core.settings());
      await close;
      await b.close();
    },
  );
  test(
    'worker loss retires interest without claiming successful close',
    () async {
      final b = await wire.Bridge.create();
      b.channel.stream.addError(StateError('private transport diagnostics'));
      await b.proxy.retired;
      expect(b.proxy.isClosed, isTrue);
      await expectLater(b.proxy.close(), core.failure('SERVICE_UNAVAILABLE'));
      await expectLater(b.server.close(), core.failure('SERVICE_UNAVAILABLE'));
      await b.setup.auth.close();
    },
  );
}
