import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck_protocol/models.dart';

void main() {
  test('UI uses protocol and OS adapter without storage/provider access', () {
    final forbidden = RegExp(
      r'''(?:import|export)\s+['"][^'"]*(?:isar|serverdeck_locald|/storage/|/credentials/|/test/)''',
    );
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      expect(
        forbidden.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: file.path,
      );
    }
  });
  test('normal Dart entrypoints have no network or test build surface', () {
    final forbidden = RegExp(
      r'''(?:Socket\.connect|ServerSocket\.bind|HttpClient\(|HttpServer\.bind|ImpersonateNamedPipeClient|RevertToSelf|(?:import|export)\s+['"][^'"]*/(?:test|support)/)''',
    );
    for (final root in [
      'lib',
      'packages/serverdeck_protocol/lib',
      'packages/serverdeck_windows/lib',
      'packages/serverdeck_locald/lib',
      'packages/serverdeck_locald/bin',
    ]) {
      for (final file in Directory(
        root,
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        expect(
          forbidden.hasMatch(file.readAsStringSync()),
          isFalse,
          reason: file.path,
        );
      }
    }
    expect(Capability.values.map((value) => value.wireName).toSet(), {
      'readiness.read',
      'profiles.read',
      'profiles.write',
      'settings.read',
      'settings.write',
      'mutations.read',
    });
  });
}
