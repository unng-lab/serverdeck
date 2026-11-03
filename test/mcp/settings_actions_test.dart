import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/mcp/settings_controller.dart';

import '../fixtures/feature_harness.dart';

void main() {
  test('settings require consent, produce token-free config and drive durable revoke', () async {
    final h = FeatureHarness();
    var retries = 0;
    final c = McpSettingsController(
      owner: h.grants,
      actor: h.actors.ui,
      retryTransport: () async {
        retries++;
      },
      transportError: () => null,
      poll: false,
    );
    try {
      await c.issue('Client', confirmed: false);
      expect(c.error, isNotNull);
      expect(c.grants, isEmpty);
      await c.issue('Client', confirmed: true);
      expect(c.error, isNull);
      expect(c.grants.length, 1);
      expect(c.configuration, isNotNull);
      final id = c.grants.single.clientId;
      expect(c.configuration!.args, ['--mcp-stdio', '--client', id]);
      await c.setEnabled(true);
      expect(c.enabled, isTrue);
      expect(h.transport.enabled, isTrue);
      await c.rotate(id, confirmed: true);
      expect(c.grants.single.version, 2);
      await c.revoke(id, confirmed: true);
      expect(c.grants.single.revoked, isTrue);
      expect(c.configuration, isNull);
      await c.retryMcp();
      expect(retries, 1);
    } finally {
      c.dispose();
      await h.dispose();
    }
  });
  test('failed export is recoverable without issuing another grant', () async {
    final h = FeatureHarness();
    final c = McpSettingsController(
      owner: h.grants,
      actor: h.actors.ui,
      retryTransport: () async {},
      transportError: () => null,
      poll: false,
    );
    try {
      h.transport.failWrite = true;
      await c.issue('Client', confirmed: true);
      expect(c.error, isNotNull);
      expect(c.grants.single.exportPending, isTrue);
      final id = c.grants.single.clientId;
      h.transport.failWrite = false;
      await c.retry(id);
      expect(c.grants.single.exportPending, isFalse);
      expect(c.grants.single.clientId, id);
      expect(c.grants.single.version, 1);
    } finally {
      c.dispose();
      await h.dispose();
    }
  });
}
