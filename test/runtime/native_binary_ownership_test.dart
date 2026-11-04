import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/runtime/native_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('binary-ownership-unit');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final operation in [
    'secret.protect',
    'secret.unprotect',
    'credential.pickKey',
  ]) {
    test('$operation hands writable detached bytes to its caller', () async {
      final reply = Uint8List.fromList([19, 27, 39]);
      const codec = StandardMethodCodec();
      final envelope = codec.encodeSuccessEnvelope(reply).asUnmodifiableView();
      final decoded = codec.decodeEnvelope(envelope) as Uint8List;
      expect(
        () => decoded.fillRange(0, decoded.length, 0),
        throwsUnsupportedError,
      );
      messenger.setMockMessageHandler(channel.name, (message) async {
        final call = codec.decodeMethodCall(message!);
        expect(call.method, operation);
        return envelope;
      });
      addTearDown(() => messenger.setMockMessageHandler(channel.name, null));
      final platform = NativePlatform(
        epoch: 'synthetic-epoch',
        channel: channel,
      );
      final bytes = switch (operation) {
        'secret.protect' => await platform.protect(Uint8List(1), 'synthetic'),
        'secret.unprotect' => await platform.unprotect(
          Uint8List(1),
          'synthetic',
        ),
        _ => (await platform.pickPrivateKey())!,
      };
      expect(bytes, [19, 27, 39]);
      bytes.fillRange(0, bytes.length, 0);
      expect(bytes, [0, 0, 0]);
      expect(reply, [19, 27, 39]);
    });
  }
  test('picker cancellation remains null', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    expect(
      await NativePlatform(
        epoch: 'synthetic-epoch',
        channel: channel,
      ).pickPrivateKey(),
      isNull,
    );
  });
}
