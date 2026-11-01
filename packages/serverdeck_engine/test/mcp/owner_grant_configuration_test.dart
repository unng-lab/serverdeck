import 'package:serverdeck_engine/platform/ports.dart';
import 'package:test/test.dart';

import '../support/actual_mcp_setup.dart';

/// Declared RAM bundle identity only. Actual Host/session/API/store admission,
/// configuration capture and owner result validation are production code.
final class Bundle implements VerifiedAppConfiguration {
  @override
  String get appRoot => r'C:\ServerDeck';
  @override
  String get buildId => '${'a' * 40}+Release+${'b' * 64}';
  @override
  Map<String, Object?> mcpConfiguration(String grantId) => {
    'command': '$appRoot\\serverdeck.exe',
    'args': ['--mcp-stdio', '--grant-id', grantId],
  };
}

void main() {
  test('actual owner grant configuration crosses both owner validators with current exe mode', () async {
    final s = await Setup.create(bundle: Bundle());
    final grant = await s.grant();
    final before = s.repository.provider.readBytes();
    final result = await s.ownerCall('grants.configuration', {
      'grantId': grant,
    });
    expect(result, {
      'command': r'C:\ServerDeck\serverdeck.exe',
      'args': ['--mcp-stdio', '--grant-id', grant],
    });
    expect(s.repository.provider.readBytes(), before);
    expect(s.io.attempts, isEmpty);
  });
}
