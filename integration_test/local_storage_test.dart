import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverdeck/data/fixtures.dart';
import 'package:serverdeck/data/local_profiles.dart';
import 'package:serverdeck/ui/app.dart';
import 'package:serverdeck_locald/local_api.dart';
import 'package:serverdeck_locald/locald.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final library =
      '${File(Platform.resolvedExecutable).parent.path}/libisar.dll';
  testWidgets(
    'BR-S01 native UI edit and deletion persist across service restart',
    (tester) async {
      late Directory root;
      late LocaldServer server;
      late LocalApiClient client;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('serverdeck-ui-storage-');
        server = await LocaldServer.start(
          directory: root.path,
          nativeLibraryPath: library,
        );
        client = LocalApiClient(port: server.port, proof: server.proof);
        await client.initializeProfiles(
          FixtureRepository().servers.map(profileJson).toList(),
        );
      });
      addTearDown(() async {
        client.close();
        await server.close();
        await root.delete(recursive: true);
      });
      final profiles = await tester.runAsync(() => client.profiles());
      await tester.pumpWidget(
        ServerDeckApp(
          client: client,
          profiles: profiles!.map(profileFromJson).toList(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-menu-lab-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Редактировать fixture'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-name')),
        'Persisted native profile',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Сохранить'));
        for (var i = 0; i < 50; i++) {
          if ((await client.profiles()).any(
            (p) => p['name'] == 'Persisted native profile',
          )) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        fail('UI did not persist the profile through Local API');
      });
      await tester.pumpAndSettle();
      expect(find.text('Persisted native profile'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-menu-lab-b')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Удалить профиль fixture'));
        for (var i = 0; i < 50; i++) {
          if (!(await client.profiles()).any((p) => p['id'] == 'lab-b')) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        fail('UI did not persist profile removal');
      });
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        client.close();
        await server.close();
        server = await LocaldServer.start(
          directory: root.path,
          nativeLibraryPath: library,
        );
        client = LocalApiClient(port: server.port, proof: server.proof);
        await client.initializeProfiles(
          FixtureRepository().servers.map(profileJson).toList(),
        );
      });
      final restored = await tester.runAsync(() => client.profiles());
      await tester.pumpWidget(
        ServerDeckApp(
          client: client,
          profiles: restored!.map(profileFromJson).toList(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Persisted native profile'), findsOneWidget);
      expect(find.text('Analytics Lab'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'BR-S01 failed service write is visible and leaves profile unchanged',
    (tester) async {
      late Directory root;
      late LocaldServer server;
      late LocalApiClient client;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp(
          'serverdeck-ui-rejection-',
        );
        server = await LocaldServer.start(
          directory: root.path,
          nativeLibraryPath: library,
        );
        client = LocalApiClient(
          port: server.port,
          proof: 'invalid-fixture-proof',
        );
      });
      addTearDown(() async {
        client.close();
        await server.close();
        await root.delete(recursive: true);
      });
      await tester.pumpWidget(
        ServerDeckApp(client: client, profiles: FixtureRepository().servers),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-menu-lab-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Редактировать fixture'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-name')),
        'Rejected edit',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Сохранить'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Изменение не сохранено.'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(find.text('Ubuntu Lab'), findsOneWidget);
      expect(find.text('Rejected edit'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
