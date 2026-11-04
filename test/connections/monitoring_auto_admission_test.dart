import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/runtime/owned_work.dart';

import 'connection_owner_test.dart' as fixture;

void main() {
  test(
    'completed canonical failure receipt is unchanged by later cancellation',
    () async {
      final h = fixture.Harness();
      addTearDown(h.dispose);
      final cancel = WorkCancellation();
      final outcome = await h.owner.connectForMonitoring(
        h.actors.ui,
        fixture.id(1),
        expectedRevision: 2,
        cancellation: cancel,
      );
      expect(outcome.operation.error!.code, FailureCode.conflict);
      cancel.cancel();
      expect(outcome.cancelledBeforeAdmission, isFalse);
      expect(h.owner.generation(fixture.id(1)), 0);
    },
  );
  test('canonical history forbids auto reconnect after inactive MCP disconnect and revision change', () async {
    final h = fixture.Harness();
    addTearDown(h.dispose);
    await h.connected(actor: h.mcp);
    await h.owner.disconnect(
      h.actors.ui,
      fixture.id(1),
      sessionId: h.owner.connection(fixture.id(1)).sessionId!,
    );
    final p = h.repository.state.profiles[fixture.id(1)]!;
    p.profileRevision++;
    p.connectionRevision++;
    final result = await h.owner.connectForMonitoring(
      h.actors.ui,
      fixture.id(1),
      expectedRevision: 2,
      cancellation: WorkCancellation(),
    );
    expect(result.operation.error!.code, FailureCode.conflict);
    expect(h.dials, hasLength(1));
    expect(
      (await h.owner.connect(
        h.actors.ui,
        fixture.id(1),
        expectedRevision: 2,
      )).ok,
      isTrue,
    );
  });
  test('auto admission checks history after a manual attempt won earlier snapshot race', () async {
    final h = fixture.Harness();
    addTearDown(h.dispose);
    expect(h.owner.generation(fixture.id(1)), 0);
    await h.connect();
    final result = await h.owner.connectForMonitoring(
      h.actors.ui,
      fixture.id(1),
      expectedRevision: 1,
      cancellation: WorkCancellation(),
    );
    expect(result.operation.error!.code, FailureCode.conflict);
    expect(h.dials, hasLength(1));
  });
  test('cancelled queued automatic admission never creates a dial', () async {
    final h = fixture.Harness();
    addTearDown(h.dispose);
    final release = Completer<void>();
    var once = false;
    h.state.before = (actor, point) async {
      if (!once && point == AuthorizationPoint.admission) {
        once = true;
        await release.future;
      }
    };
    final cancel = WorkCancellation();
    final result = h.owner.connectForMonitoring(
      h.actors.ui,
      fixture.id(1),
      expectedRevision: 1,
      cancellation: cancel,
    );
    await fixture.turns();
    cancel.cancel();
    release.complete();
    final outcome = await result;
    expect(outcome.operation.error!.code, FailureCode.conflict);
    expect(outcome.cancelledBeforeAdmission, isTrue);
    expect(h.dials, isEmpty);
    expect(h.owner.generation(fixture.id(1)), 0);
  });
}
