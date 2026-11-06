import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/runtime/native_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('serverdeck/version-unit');
  for (final value in <String?>['7.6.4325', null, '']) {
    test('local running release projection handles $value', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'initialize');
            calls++;
            return {
              'ownerEpoch': 'owner',
              'dataRoot': 'synthetic-data',
              'runtimeRoot': 'synthetic-runtime',
              'exePath': 'synthetic-program',
              'userSid': 'synthetic-user',
              'logonSid': 'synthetic-logon',
              if (value != null) 'release': value,
            };
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final platform = NativePlatform(epoch: 'owner', channel: channel);
      expect(platform.release.value, isNull);
      await platform.initialize();
      for (var i = 0; i < 5; i++) {
        expect(
          platform.release.value,
          value == null || value.isEmpty ? null : value,
        );
      }
      expect(calls, 1);
    });
  }
}
