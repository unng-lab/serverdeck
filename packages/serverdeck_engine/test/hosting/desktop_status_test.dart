import 'package:test/test.dart';
import 'package:serverdeck_engine/hosting/capability_snapshot.dart';
import 'package:serverdeck_engine/hosting/worker_controller.dart';

import 'worker_controller_test.dart' as fixture;

void main() {
  test(
    'desktop status comes from same recovered Host without owner attachment',
    () async {
      final s = fixture.Setup();
      s.connection.bootstrap.setup.resources.unresolvedJobs = 7;
      await s.controller.start();
      final status = await s.controller.refreshDesktopStatus();
      expect(status.status.phase, 'ready');
      expect(status.mcpSessions, 0);
      expect(status.unresolvedJobs, 7);
      expect(s.connection.sent.last['kind'], 'desktopStatus');
      expect(s.connection.links, isEmpty);
      await s.close();
    },
  );
  test(
    'unknown job count remains unknown; status requires exact closed fields',
    () {
      final phase = {
        'phase': 'starting',
        'reason': null,
        'readiness': null,
        'capabilities': EngineCapabilities.unavailable(
          EnginePlatformKind.windows,
        ).toJson(),
      };
      expect(
        DesktopEngineStatus.fromJson({
          'status': phase,
          'mcpSessions': 0,
          'unresolvedJobs': null,
        }).unresolvedJobs,
        isNull,
      );
      for (final body in [
        {'status': phase, 'mcpSessions': 5, 'unresolvedJobs': null},
        {'status': phase, 'mcpSessions': -1, 'unresolvedJobs': null},
        {'status': phase, 'mcpSessions': 0, 'unresolvedJobs': 251},
        {'status': phase, 'mcpSessions': 0, 'unresolvedJobs': -1},
        {
          'status': phase,
          'mcpSessions': 0,
          'unresolvedJobs': 1,
          'names': ['private'],
        },
      ]) {
        expect(() => DesktopEngineStatus.fromJson(body), throwsA(anything));
      }
    },
  );
}
