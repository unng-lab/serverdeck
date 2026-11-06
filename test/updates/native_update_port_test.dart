import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/runtime/native_platform.dart';
import 'package:serverdeck/updates/update_owner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('updates-port-unit');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'restart request is restricted to owner epoch and exact version',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      final platform = NativePlatform(epoch: 'unit-owner', channel: channel);
      expect(await platform.requestUpdateRestart('0.1.0+4'), isTrue);
      expect(calls.single.method, 'runtime.requestUpdateRestart');
      expect(calls.single.arguments, {
        'ownerEpoch': 'unit-owner',
        'version': '0.1.0+4',
      });
      expect(
        PlatformSnapshot.decode({
          'ownerEpoch': 'unit-owner',
          'seq': 2,
          'windowState': 'visible',
          'trayAvailable': true,
          'osEnding': false,
          'exitRequested': true,
          'updateRestartRequested': true,
        }).updateRestartRequested,
        isTrue,
      );
    },
  );
  testWidgets('native stop and drain use same epoch and wait for termination', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    var polls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'updates.drained') return ++polls >= 2;
      return null;
    });
    final port = NativeUpdatePort(
      NativePlatform(epoch: 'owner', channel: channel),
    );
    await port.stopAdmission();
    var done = false;
    final draining = port.drain().then((_) => done = true);
    await tester.pump();
    expect(done, isFalse);
    await tester.pump(const Duration(milliseconds: 25));
    await draining;
    expect(done, isTrue);
    expect(calls.map((c) => c.method), [
      'updates.stopAdmission',
      'updates.drained',
      'updates.drained',
    ]);
    expect(
      calls.every((c) => (c.arguments as Map)['ownerEpoch'] == 'owner'),
      isTrue,
    );
    messenger.setMockMethodCallHandler(channel, (_) async => 'drained');
    await expectLater(port.drain(), throwsA(isA<FormatException>()));
  });
  test('only typed owner-scoped update arguments cross the channel', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'updates.snapshot') {
        return {
          'state': 'current',
          'currentVersion': '0.1.0+1',
          'enabled': false,
          'bytes': 0,
        };
      }
      if (call.method == 'updates.check' || call.method == 'updates.download')
        return true;
      return null;
    });
    final port = NativeUpdatePort(
      NativePlatform(epoch: 'unit-owner', channel: channel),
    );
    expect((await port.snapshot()).state, UpdateState.current);
    expect(await port.check(), isTrue);
    expect(await port.download('0.2.0+1'), isTrue);
    await port.cancel();
    await port.setEnabled(false);
    await port.defer();
    expect(calls.map((c) => c.method), [
      'updates.snapshot',
      'updates.check',
      'updates.download',
      'updates.cancel',
      'updates.setEnabled',
      'updates.defer',
    ]);
    expect(calls.map((c) => c.arguments), [
      {'ownerEpoch': 'unit-owner'},
      {'ownerEpoch': 'unit-owner'},
      {'ownerEpoch': 'unit-owner', 'version': '0.2.0+1'},
      {'ownerEpoch': 'unit-owner'},
      {'ownerEpoch': 'unit-owner', 'enabled': false},
      {'ownerEpoch': 'unit-owner'},
    ]);
  });
  test(
    'rejects malformed admissions and preserves native stale-epoch rejection',
    () async {
      final port = NativeUpdatePort(
        NativePlatform(epoch: 'old', channel: channel),
      );
      messenger.setMockMethodCallHandler(channel, (_) async => 'accepted');
      await expectLater(port.check(), throwsA(isA<FormatException>()));
      await expectLater(port.snapshot(), throwsA(isA<FormatException>()));
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'STALE_EPOCH'),
      );
      await expectLater(
        port.download('0.2.0+1'),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'STALE_EPOCH'),
        ),
      );
    },
  );
}
