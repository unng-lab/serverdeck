import 'package:serverdeck_locald/storage/migration_probe.dart';
import 'package:test/test.dart';

void main() {
  test('ordinary build cannot install or invoke migration fault hooks', () {
    expect(migrationProbesEnabled, isFalse);
    var nativeCalled = false;
    expect(
      () => MigrationProbe.install(
        (_) async {},
        minimumFreeBytes: (_) => 0,
        closeNative: (_) async => true,
      ),
      throwsStateError,
    );
    expect(() => MigrationProbe.minimumFreeBytes(144 << 20), throwsStateError);
    for (final boundary in MigrationBoundary.values) {
      expect(() => MigrationProbe.reached(boundary), throwsStateError);
    }
    expect(
      () => MigrationProbe.closeNative(() async {
        nativeCalled = true;
        return true;
      }),
      throwsStateError,
    );
    expect(nativeCalled, isFalse);
  });
}
