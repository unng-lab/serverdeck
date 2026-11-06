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
  late ConsoleOwner owner;
  late FakeConsolePort port;
  late String profile;
  late ConsoleConfiguration config;
  setUp(() async {
    h = FeatureHarness();
    profile = await h.create();
    port = FakeConsolePort(h.state.versions);
    config = const ConsoleConfiguration();
    owner = ConsoleOwner(
      actors: h.actors,
      gate: h.gate,
      state: h.state,
      repository: h.repository,
      connections: port,
      configuration: () => config,
      newId: h.newId,
      monotonicNow: h.clock.monotonic,
      schedule: h.clock.schedule,
    );
  });
  tearDown(() async {
    await owner.dispose();
    await port.events.close();
    await h.dispose();
  });
  test(
    'typed opening failures retain distinct stable reasons without fallback',
    () async {
      port.autoOpen = false;
      final caller = ConsoleCaller.ui(h.actors.ui);
      for (final code in ConsoleOpenFailureCode.values) {
        final result = await owner.openConsole(caller, profile);
        final opened = result.value!.console as ConsoleActionValue;
        await featureTurns();
        port.openings.last.ready.completeError(ConsoleOpenFailure(code));
        await featureTurns();
        expect(owner.sessionsFor(profile).single.reason, code.name);
        expect(owner.sessionsFor(profile).single.state, 'error');
        await owner.closeConsole(
          caller,
          profile,
          opened.sessionId,
          generation: 1,
        );
      }
      expect(port.openings.length, ConsoleOpenFailureCode.values.length);
    },
  );
  test(
    'list does not connect or open; explicit open shares one engine output',
    () async {
      final caller = ConsoleCaller.ui(h.actors.ui);
      expect((await owner.listConsoles(caller, profile)).ok, isTrue);
      expect(port.openings, isEmpty);
      final result = await owner.openConsole(caller, profile);
      final action = result.value!.console as ConsoleActionValue;
      await featureTurns();
      expect(port.openings.length, 1);
      expect(owner.sessionsFor(profile).single.state, 'active');
      port.openings.single.channel.emit(utf8.encode('hello\r\n'));
      await featureTurns();
      expect(
        owner.engine(action.sessionId)!.screen.first.text,
        startsWith('hello'),
      );
    },
  );
  test(
    'four per-server reservations include pending and completed shells',
    () async {
      final caller = ConsoleCaller.ui(h.actors.ui);
      port.autoOpen = false;
      for (var i = 0; i < 4; i++)
        expect((await owner.openConsole(caller, profile)).ok, isTrue);
      final over = await owner.openConsole(caller, profile);
      expect(over.error?.code, FailureCode.resourceExhausted);
      expect(owner.sessionsFor(profile).length, 4);
    },
  );
  test(
    'late open after cancellation cannot revive disconnected console',
    () async {
      final caller = ConsoleCaller.ui(h.actors.ui);
      port.autoOpen = false;
      await owner.openConsole(caller, profile);
      await featureTurns();
      port.connected = false;
      port.events.add(ConsoleInvalidation(profile, clear: false));
      port.openings.single.complete();
      await featureTurns();
      expect(owner.sessionsFor(profile).single.state, 'disconnected');
      expect(port.openings.single.cancelled, isTrue);
    },
  );
  test('opening deadline exits pending and refuses input', () async {
    port.autoOpen = false;
    await owner.openConsole(ConsoleCaller.ui(h.actors.ui), profile);
    await featureTurns();
    h.clock.advance(const Duration(seconds: 15));
    await featureTurns();
    expect(owner.sessionsFor(profile).single.state, 'error');
    expect(owner.sessionsFor(profile).single.reason, 'timeout');
  });
  test('shell configuration changes only future session snapshots', () async {
    final shell = ConsoleShellProfile(
      id: featureId(9),
      name: 'Bash',
      path: '/bin/bash',
    );
    config = ConsoleConfiguration(profiles: [shell], defaultId: shell.id);
    final caller = ConsoleCaller.ui(h.actors.ui);
    expect((await owner.openConsole(caller, profile)).ok, isTrue);
    await featureTurns();
    config = const ConsoleConfiguration();
    owner.configurationChanged();
    expect((await owner.openConsole(caller, profile)).ok, isTrue);
    await featureTurns();
    expect(port.openings.first.path, '/bin/bash');
    expect(port.openings.last.path, isNull);
    expect(owner.sessionsFor(profile).first.shellName, 'Bash');
    expect(port.openings.first.channel.closed, isFalse);
    expect(
      (await owner.openConsole(
        caller,
        profile,
        shellProfileId: shell.id,
      )).error?.code,
      FailureCode.invalidArgument,
    );
  });
}
