import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverdeck/ui/app.dart';
import 'package:serverdeck/data/credentials.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('BR-P01 native OS custody synthetic credential roundtrip', (
    tester,
  ) async {
    final reference = 'fixture-test-${DateTime.now().microsecondsSinceEpoch}';
    final store = OsCredentialStore();
    try {
      await store.write(
        reference,
        const SshCredential.password('synthetic-not-a-real-secret'),
      );
      final read = await OsCredentialStore().read(reference);
      expect(read?.material, 'synthetic-not-a-real-secret');
      await store.write(
        reference,
        const SshCredential.key(
          'синтетический key',
          passphrase: 'fixture-phrase',
        ),
      );
      expect(
        (await OsCredentialStore().read(reference))?.passphrase,
        'fixture-phrase',
      );
      await expectLater(
        store.write(reference, SshCredential.key('x' * 3000)),
        throwsArgumentError,
      );
      expect((await store.read(reference))?.material, 'синтетический key');
    } finally {
      await store.delete(reference);
    }
    expect(await store.read(reference), isNull);
  });
  testWidgets('SC01 Windows native fixture navigation', (tester) async {
    await tester.pumpWidget(const ServerDeckApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('ДЕМО'), findsWidgets);
    for (final page in ['software', 'journal', 'metrics', 'jobs', 'servers']) {
      await tester.tap(find.byKey(ValueKey('nav-$page')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
