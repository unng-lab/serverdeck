import 'dart:convert';

import 'package:test/test.dart';

import '../support/migration_fixture.dart';

void main() {
  test(
    'copied foundation loader validates actual DPAPI and target business invariants',
    () async {
      final fixture = MigrationFixture.create();
      try {
        final child = await fixture.start('semantic');
        final output = child.stdout.transform(utf8.decoder).join();
        final errors = child.stderr.transform(utf8.decoder).join();
        expect(
          await child.exitCode.timeout(const Duration(seconds: 60)),
          0,
          reason: await errors,
        );
        expect(
          await output,
          contains('MIGRATION_COPIED_SEMANTIC_DPAPI_PRESERVATION_PROVED'),
        );
      } finally {
        await fixture.close();
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
