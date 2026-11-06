import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/console/console_models.dart';
import 'package:serverdeck/console/console_owner.dart';
import 'package:serverdeck/console/console_port.dart';
import 'package:serverdeck/domain/models.dart';

import '../fixtures/feature_harness.dart';
import 'fakes.dart';

void main() {
  late FeatureHarness h;
  late FakeConsolePort port;
  late ConsoleOwner owner;
  late String profile;
  late ConsoleCaller ui;
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
    ui = ConsoleCaller.ui(h.actors.ui);
  });
  tearDown(() async {
    await owner.dispose();
    await port.events.close();
    await h.dispose();
  });
  Future<ConsoleActionValue> open() async {
    final result = await owner.openConsole(ui, profile);
    await featureTurns();
    return result.value!.console as ConsoleActionValue;
  }

  test('hidden and disabled keyboard preserve output and channel; ended keeps final text', () async {
    final s = await open();
    final engine = owner.engine(s.sessionId)!;
    owner.setVisible(s.sessionId, true);
    owner.setKeyboardActive(false);
    engine.terminal.textInput('hidden-input');
    port.openings.single.channel.emit(utf8.encode('final text'));
    port.openings.single.channel.end(7);
    await featureTurns();
    expect(port.openings.single.channel.writes, isEmpty);
    final page =
        (await owner.readConsole(
              ui,
              profile,
              s.sessionId,
              generation: 1,
            )).value!.console
            as ConsoleHistoryValue;
    expect(page.rows.map((r) => r.text).join(), contains('final text'));
    expect(page.session.state, 'ended');
    expect(page.session.exitCode, 7);
    expect(page.session.inputOwner.kind, 'free');
    expect(
      (await owner.closeConsole(ui, profile, s.sessionId, generation: 1)).ok,
      true,
    );
    expect(port.connected, true);
  });
  test(
    'normal disconnect keeps readonly text, trust clear removes both buffers',
    () async {
      final s = await open();
      port.openings.single.channel.emit(
        utf8.encode('old-history\x1b[?1049hsecret-alt'),
      );
      await featureTurns();
      port.connected = false;
      port.events.add(ConsoleInvalidation(profile, clear: false));
      final kept =
          (await owner.readConsole(
                ui,
                profile,
                s.sessionId,
                generation: 1,
              )).value!.console
              as ConsoleHistoryValue;
      expect(kept.rows.map((r) => r.text).join(), contains('secret-alt'));
      port.events.add(ConsoleInvalidation(profile, clear: true));
      final cleared =
          (await owner.readConsole(
                ui,
                profile,
                s.sessionId,
                generation: 1,
              )).value!.console
              as ConsoleHistoryValue;
      expect(cleared.rows.map((r) => r.text).join(), isNot(contains('secret')));
      expect(
        cleared.rows.map((r) => r.text).join(),
        isNot(contains('old-history')),
      );
      port.openings.single.channel.emit(utf8.encode('late'));
      await featureTurns();
      expect(
        owner.engine(s.sessionId)!.screen.map((r) => r.text).join(),
        isNot(contains('late')),
      );
    },
  );
  test('close one channel preserves another; shutdown removes buffers without reopen', () async {
    final a = await open(), b = await open();
    await owner.closeConsole(
      ui,
      profile,
      a.sessionId,
      generation: 1,
      leaseToken: a.leaseToken,
      confirmed: true,
    );
    expect(port.openings.first.channel.closed, true);
    expect(port.openings.last.channel.closed, false);
    port.openings.last.channel.emit(utf8.encode('survives'));
    await featureTurns();
    await owner.stopAdmission();
    await owner.cancelPending();
    await owner.closeSessions();
    await owner.drain();
    expect(port.openings.last.channel.closed, true);
    expect(
      owner.engine(b.sessionId)!.screen.map((r) => r.text).join(),
      isNot(contains('survives')),
    );
    expect(port.openings.length, 2);
  });
  test(
    'whole action input cap and lease cancellation never send queued suffix',
    () async {
      final s = await open();
      owner.setVisible(s.sessionId, true);
      final channel = port.openings.single.channel;
      channel.hold = Completer<void>();
      final first = owner.writeConsole(
        ui,
        profile,
        s.sessionId,
        generation: 1,
        leaseToken: s.leaseToken,
        text: 'a' * 65536,
      );
      await featureTurns();
      final over = await owner.writeConsole(
        ui,
        profile,
        s.sessionId,
        generation: 1,
        leaseToken: s.leaseToken,
        text: 'b',
      );
      expect(over.error?.code, FailureCode.resourceExhausted);
      await owner.releaseConsole(
        ui,
        profile,
        s.sessionId,
        generation: 1,
        leaseToken: s.leaseToken!,
      );
      channel.hold!.complete();
      final result = (await first).value!.console as ConsoleActionValue;
      expect(result.status, 'cancelledBeforeSend');
      expect(channel.writes, isEmpty);
    },
  );
  test('raw flood ends only its channel with partial output marker', () async {
    final a = await open();
    await open();
    port.openings.first.channel.emit(List.filled(1048577, 65));
    expect(owner.sessionsFor(profile).first.state, 'error');
    expect(owner.sessionsFor(profile).first.partial, true);
    expect(port.openings.first.channel.closed, true);
    expect(port.openings.last.channel.closed, false);
    expect(
      owner.engine(a.sessionId)!.screen.map((r) => r.text).join(),
      isNot(contains('A')),
    );
  });
  test('rename preserves buffer; endpoint edit clears and profile deletion removes records', () async {
    final s = await open();
    port.openings.single.channel.emit(utf8.encode('private-history'));
    await featureTurns();
    final rename = await h.operations.updateProfile(
      h.actors.ui,
      profile,
      const ProfilePatch(displayName: 'Renamed'),
      expectedRevision: 1,
      mutationId: h.newId(),
    );
    expect(rename.ok, true);
    expect(
      (await owner.readConsole(ui, profile, s.sessionId, generation: 1)).ok,
      true,
    );
    expect(owner.sessionsFor(profile).single.state, 'active');
    final changed = await h.operations.updateProfile(
      h.actors.ui,
      profile,
      const ProfilePatch(host: 'new.invalid'),
      expectedRevision: 2,
      mutationId: h.newId(),
    );
    expect(changed.ok, true);
    final page =
        (await owner.readConsole(
              ui,
              profile,
              s.sessionId,
              generation: 1,
            )).value!.console
            as ConsoleHistoryValue;
    expect(
      page.rows.map((r) => r.text).join(),
      isNot(contains('private-history')),
    );
    expect(page.session.state, 'disconnected');
    expect(
      (await h.operations.deleteProfile(
        h.actors.ui,
        profile,
        expectedRevision: 3,
        confirmed: true,
      )).ok,
      true,
    );
    expect(
      (await owner.readConsole(
        ui,
        profile,
        s.sessionId,
        generation: 1,
      )).error?.code,
      FailureCode.consoleNotFound,
    );
    expect(owner.sessionsFor(profile), isEmpty);
  });
  test('sixteen global reservations include completed sessions', () async {
    for (var server = 0; server < 4; server++) {
      final target = server == 0
          ? profile
          : await h.create(host: '$server.invalid');
      for (var i = 0; i < 4; i++) {
        expect((await owner.openConsole(ui, target)).ok, true);
        await featureTurns();
        port.openings.last.channel.end();
        await featureTurns();
      }
    }
    final target = await h.create(host: 'fifth.invalid');
    expect(
      (await owner.openConsole(ui, target)).error?.code,
      FailureCode.resourceExhausted,
    );
    expect(port.openings.length, 16);
  });
}
