import '../../../serverdeck_windows/test/support/trusted_client_fixture.dart';

/// Run startup, cleaning up only when creation fails.
Future<T> runTrustedAuthStartup<T>({
  required Future<T> Function() start,
  required Future<void> Function() cleanup,
}) async {
  late T result;
  var started = false;
  await runOwnedFixtureLifecycle(
    body: () async {
      result = await start();
      started = true;
    },
    cleanup: () async {
      if (!started) await cleanup();
    },
  );
  return result;
}
