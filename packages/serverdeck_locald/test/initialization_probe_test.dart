import 'package:serverdeck_locald/storage/initialization_probe.dart';
import 'package:test/test.dart';

void main() {
  test('normal compilation cannot install or invoke initialization probes', () {
    expect(initializationProbesEnabled, isFalse);
    var invoked = false;
    expect(
      () => InitializationProbe.install((_) async {
        invoked = true;
      }),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'code',
          'INITIALIZATION_PROBE_UNAVAILABLE',
        ),
      ),
    );
    expect(
      () => InitializationProbe.reached(InitializationBoundary.stagingCreated),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'code',
          'INITIALIZATION_PROBE_UNAVAILABLE',
        ),
      ),
    );
    expect(invoked, isFalse);
  });
}
