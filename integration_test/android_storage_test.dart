import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverdeck/data/mobile_locald.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android private Isar/loopback service persists settings', (
    tester,
  ) async {
    var service = await MobileLocald.start();
    final original = await service.client.call('settings/get') as Map;
    try {
      await service.client.call('settings/set', {
        'theme': 'light',
        'updateAutoCheck': false,
      });
      await service.close();
      service = await MobileLocald.start();
      final settings = await service.client.call('settings/get') as Map;
      expect(settings['theme'], 'light');
      expect(settings['updateAutoCheck'], false);
      await service.client.call('settings/set', {'theme': 'dark'});
      expect(
        (await service.client.call('settings/get') as Map)['updateAutoCheck'],
        false,
      );
    } finally {
      await service.client.call('settings/set', {
        'theme': original['theme'] ?? 'dark',
        'updateAutoCheck': original['updateAutoCheck'] ?? true,
      });
      await service.close();
    }
  });
}
