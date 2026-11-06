import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/console/console_models.dart';
import 'package:serverdeck/console/console_owner.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/models.dart';

import '../fixtures/feature_harness.dart';
import 'fakes.dart';

void main() {
  late FeatureHarness h;
  late FakeConsolePort port;
  late ConsoleOwner owner;
  late String profile;
  late ConsoleCaller a, b, ui;
  late McpActor actor;
  var sequence = 0;
  setUp(() async {
    h = FeatureHarness();
    profile = await h.create();
    port = FakeConsolePort(h.state.versions);
    owner = ConsoleOwner(
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
    final grant = await h.grants.issue(h.actors.ui, 'Agent A', confirmed: true);
    await h.grants.setEnabled(h.actors.ui, true);
    actor = h.actors.mcp(clientId: grant.clientId, grantVersion: 1);
    a = ConsoleCaller.mcp(actor, ConsoleMcpBinding(actor));
    b = ConsoleCaller.mcp(actor, ConsoleMcpBinding(actor));
    ui = ConsoleCaller.ui(h.actors.ui);
    sequence = 0;
  });
  tearDown(() async {
    await owner.dispose();
    await port.events.close();
    await h.dispose();
  });
  Future<ConsoleActionValue> open() async {
    final result = await owner.openConsole(
      a,
      profile,
      ownerEpoch: h.actors.ownerEpoch,
      operationSequence: ++sequence,
    );
    await featureTurns();
    return result.value!.console as ConsoleActionValue;
  }

  test(
    'single lease, same client new binding busy, UI takeover cancels old token',
    () async {
      final s = await open();
      expect(owner.sessionsFor(profile).single.inputOwner.kind, 'mcp');
      final busy = await owner.acquireConsole(
        b,
        profile,
        s.sessionId,
        generation: 1,
        ownerEpoch: h.actors.ownerEpoch,
        operationSequence: ++sequence,
      );
      expect(busy.error?.code, FailureCode.consoleInputBusy);
      final takeover = await owner.acquireConsole(
        ui,
        profile,
        s.sessionId,
        generation: 1,
      );
      expect(takeover.ok, true);
      final rejected = await owner.writeConsole(
        a,
        profile,
        s.sessionId,
        generation: 1,
        leaseToken: s.leaseToken,
        key: 'Enter',
        ownerEpoch: h.actors.ownerEpoch,
        operationSequence: ++sequence,
      );
      expect(rejected.error?.code, FailureCode.consoleInputBusy);
      expect(port.openings.single.channel.writes, isEmpty);
    },
  );
  test(
    'reads and reacquisition do not renew; accepted input renews; EOF frees',
    () async {
      final s = await open();
      h.clock.advance(const Duration(seconds: 30));
      final same = await owner.acquireConsole(
        a,
        profile,
        s.sessionId,
        generation: 1,
        ownerEpoch: h.actors.ownerEpoch,
        operationSequence: ++sequence,
      );
      expect(
        (same.value!.console as ConsoleActionValue).leaseToken,
        s.leaseToken,
      );
      await owner.readConsole(a, profile, s.sessionId, generation: 1);
      h.clock.advance(const Duration(seconds: 29));
      final written = await owner.writeConsole(
        a,
        profile,
        s.sessionId,
        generation: 1,
        leaseToken: s.leaseToken,
        text: 'abc',
        ownerEpoch: h.actors.ownerEpoch,
        operationSequence: ++sequence,
      );
      expect((written.value!.console as ConsoleActionValue).acceptedBytes, 3);
      h.clock.advance(const Duration(seconds: 2));
      expect(owner.sessionsFor(profile).single.inputOwner.kind, 'mcp');
      a.binding!.close();
      owner.disconnectBinding(a.binding!);
      expect(owner.sessionsFor(profile).single.inputOwner.kind, 'free');
      expect(owner.sessionsFor(profile).single.state, 'active');
      expect(utf8.decode(port.openings.single.channel.writes.single), 'abc');
      final replay = await owner.writeConsole(
        b,
        profile,
        s.sessionId,
        generation: 1,
        leaseToken: s.leaseToken,
        text: 'abc',
        ownerEpoch: h.actors.ownerEpoch,
        operationSequence: sequence,
      );
      expect((replay.value!.console as ConsoleActionValue).replayed, true);
      expect(port.openings.single.channel.writes.length, 1);
      expect(owner.sessionsFor(profile).single.inputOwner.kind, 'free');
    },
  );
  test('lease expires at sixty seconds even when read', () async {
    final s = await open();
    h.clock.advance(const Duration(seconds: 59));
    await owner.listConsoles(a, profile);
    h.clock.advance(const Duration(seconds: 1));
    expect(owner.sessionsFor(profile).single.inputOwner.kind, 'free');
    expect(
      (await owner.writeConsole(
        a,
        profile,
        s.sessionId,
        generation: 1,
        leaseToken: s.leaseToken,
        key: 'Enter',
        ownerEpoch: h.actors.ownerEpoch,
        operationSequence: ++sequence,
      )).error?.code,
      FailureCode.consoleInputBusy,
    );
  });
}
