import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/console/console_models.dart';
import 'package:serverdeck/console/console_settings.dart';
import 'package:serverdeck/domain/models.dart';

import '../fixtures/feature_harness.dart';

void main() {
  late FeatureHarness h;
  late ConsoleSettingsOwner settings;
  setUp(() {
    h = FeatureHarness();
    settings = ConsoleSettingsOwner(
      actors: h.actors,
      gate: h.gate,
      repository: h.repository,
    );
  });
  tearDown(() async {
    await settings.dispose();
    await h.dispose();
  });
  test('missing configuration uses login; save is atomic and survives owner recreation', () async {
    expect(settings.snapshot.defaultId, 'login');
    final profile = ConsoleShellProfile(
      id: featureId(4),
      name: ' Bash ',
      path: '/bin/bash',
    );
    final result = await settings.save(
      h.actors.ui,
      ConsoleConfiguration(profiles: [profile], defaultId: profile.id),
      expectedRevision: 1,
    );
    expect(result.ok, isTrue);
    expect(settings.snapshot.profiles.single.name, 'Bash');
    final stored = h.repository.state.settings.terminalConfiguration;
    expect(ConsoleSettingsCodec.decode(stored).defaultId, profile.id);
    final before = stored;
    h.repository.failCommit = true;
    final failed = await settings.save(
      h.actors.ui,
      const ConsoleConfiguration(),
      expectedRevision: 2,
    );
    expect(failed.ok, isFalse);
    expect(h.repository.state.settings.terminalConfiguration, before);
    expect(
      (await settings.save(
        h.actors.ui,
        const ConsoleConfiguration(),
        expectedRevision: 1,
      )).error?.code,
      FailureCode.conflict,
    );
  });
  test('strict profile and version bounds reject invalid configuration', () {
    for (final path in [
      'relative',
      '/bad\npath',
      '/bad\u0000path',
      '/${'a' * 1024}',
    ]) {
      expect(
        () => ConsoleSettingsCodec.encode(
          ConsoleConfiguration(
            profiles: [
              ConsoleShellProfile(id: featureId(2), name: 'shell', path: path),
            ],
          ),
        ),
        throwsA(isA<OperationFailure>()),
      );
    }
    for (final payload in [
      '',
      '{}',
      '{"version":2}',
      jsonEncode({
        'version': 1,
        'revision': 1,
        'defaultId': 'other',
        'profiles': [],
      }),
      jsonEncode({
        'version': 1,
        'revision': 1,
        'defaultId': 'login',
        'profiles': [],
        'extra': true,
      }),
    ]) {
      expect(
        () => ConsoleSettingsCodec.decode(payload),
        throwsA(isA<OperationFailure>()),
      );
    }
    expect(
      () => ConsoleSettingsCodec.encode(
        ConsoleConfiguration(
          profiles: [
            for (var i = 0; i < 17; i++)
              ConsoleShellProfile(
                id: featureId(i + 1),
                name: 'shell',
                path: '/bin/sh',
              ),
          ],
        ),
      ),
      throwsA(isA<OperationFailure>()),
    );
  });
  test(
    'stored corruption is visible and never replaced with default',
    () async {
      h.repository.state.settings.terminalConfiguration = 'not-json';
      expect(() => settings.snapshot, throwsA(isA<OperationFailure>()));
      final saved = await settings.save(
        h.actors.ui,
        const ConsoleConfiguration(),
        expectedRevision: 1,
      );
      expect(saved.error?.code, FailureCode.storageUnavailable);
      expect(h.repository.state.settings.terminalConfiguration, 'not-json');
    },
  );
  test('generated nullable reader defines existing record default without loading Isar', () {
    final source = File('lib/storage/records.g.dart').readAsStringSync();
    expect(
      source,
      contains('object.terminalConfiguration = reader.readStringOrNull('),
    );
    expect(source, contains("r'terminalConfiguration'"));
  });
}
