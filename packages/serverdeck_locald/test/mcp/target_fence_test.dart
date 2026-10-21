import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:test/test.dart';

void main() {
  const generation = '12345678-1234-4234-8234-123456789abc';
  test('unprepared registry cannot grant mutation ownership', () async {
    final registry = OperationalSessions(generation: generation);
    expect(registry.targetChangesBlocked, false);
    await expectLater(
      registry.beginTargetChange(),
      throwsA(isA<StateError>().having((e) => e.message, 'code', 'NOT_READY')),
    );
    expect(registry.targetChangeInterests, 0);
    await registry.close();
  });
  test('close stops admission synchronously and shares completion', () async {
    final registry = OperationalSessions(generation: generation);
    final closing = registry.close();
    expect(identical(closing, registry.close()), true);
    expect(registry.targetChangesBlocked, true);
    await expectLater(
      registry.beginTargetChange(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'code',
          'SERVICE_UNAVAILABLE',
        ),
      ),
    );
    await closing;
  });
  test('authority work has no unprepared or closed fallback', () async {
    final registry = OperationalSessions(generation: generation);
    var calls = 0;
    Future<int> effect() async => ++calls;
    await expectLater(
      registry.runAuthorityMutation(effect),
      throwsA(isA<StateError>().having((e) => e.message, 'code', 'NOT_READY')),
    );
    expect(registry.hasNativePublicationGate, false);
    await registry.close();
    await expectLater(
      registry.runAuthorityMutation(effect),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'code',
          'SERVICE_UNAVAILABLE',
        ),
      ),
    );
    expect(calls, 0);
  });
}
