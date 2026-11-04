import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/runtime/native_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('serverdeck/monitoring-run-unit');
  const epoch = '12345678-1234-4234-8234-123456789abc';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final allowed in [true, false]) {
    test(
      'begin run uses owner epoch and returns native classification $allowed',
      () async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'monitoring.beginRun');
          expect(call.arguments, {'ownerEpoch': epoch});
          return {'autoAllowed': allowed};
        });
        final platform = NativePlatform(epoch: epoch, channel: channel);
        expect(await platform.beginMonitoringRun(), allowed);
      },
    );
  }

  test('write failure propagates so caller cannot admit monitoring', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      if (++calls == 1) throw PlatformException(code: 'STORAGE_IO');
      return {'autoAllowed': false};
    });
    final platform = NativePlatform(epoch: epoch, channel: channel);
    await expectLater(
      platform.beginMonitoringRun(),
      throwsA(isA<PlatformException>()),
    );
    expect(await platform.beginMonitoringRun(), isFalse);
  });

  test(
    'missing/malformed native classification never implies auto allowed',
    () async {
      for (final reply in [
        null,
        <String, Object>{},
        {'autoAllowed': 'true'},
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => reply);
        final platform = NativePlatform(epoch: epoch, channel: channel);
        await expectLater(
          platform.beginMonitoringRun(),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );
}
