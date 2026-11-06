import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/console/console_models.dart';
import 'package:serverdeck/console/console_owner.dart';
import 'package:serverdeck/domain/models.dart';

import '../fixtures/feature_harness.dart';
import 'fakes.dart';

void main() {
  for (final cause in ['request', 'grant']) {
    for (final stage in ['PTY', 'shell', 'ready']) {
      test(
        '$cause loss before $stage blocks setup and promotion without notifications',
        () async {
          final h = FeatureHarness();
          final profile = await h.create();
          final port = FakeConsolePort(h.state.versions)..autoOpen = false;
          final owner = ConsoleOwner(
            actors: h.actors,
            gate: h.gate,
            state: h.state,
            repository: h.repository,
            connections: port,
            configuration: () => const ConsoleConfiguration(),
            newId: h.newId,
            monotonicNow: h.clock.monotonic,
            schedule: h.clock.schedule,
          );
          try {
            final grant = await h.grants.issue(
              h.actors.ui,
              'Agent',
              confirmed: true,
            );
            await h.grants.setEnabled(h.actors.ui, true);
            final canonical = h.actors.mcp(
              clientId: grant.clientId,
              grantVersion: 1,
            );
            var cancelled = false;
            final caller = ConsoleCaller.mcp(
              canonical.cancellable(() => cancelled),
              ConsoleMcpBinding(canonical),
            );
            expect(
              (await owner.openConsole(
                caller,
                profile,
                ownerEpoch: h.actors.ownerEpoch,
                operationSequence: 1,
              )).ok,
              true,
            );
            await featureTurns();
            final opening = port.openings.single;
            opening.channel.bindingGuard();
            if (stage != 'PTY') opening.channel.bindingGuard();
            if (cause == 'request') {
              cancelled = true;
            } else {
              h.repository.state.grants[grant.clientId]!.revokedAt = h.clock
                  .now();
            }
            if (stage != 'ready')
              expect(
                opening.channel.bindingGuard,
                throwsA(isA<OperationFailure>()),
              );
            opening.complete();
            await featureTurns();
            expect(owner.sessionsFor(profile).single.state, 'error');
            expect(opening.cancelled, true);
            expect(port.connected, true);
          } finally {
            await owner.dispose();
            await port.events.close();
            await h.dispose();
          }
        },
      );
    }
  }
}
