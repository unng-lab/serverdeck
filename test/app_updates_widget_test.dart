import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/ui/app.dart';
import 'package:serverdeck/ui/app_updates.dart';
import 'package:serverdeck/data/app_updates.dart';

class FakeUpdater extends UpdateController {
  @override
  UpdateState state = UpdateState.idle;
  int checks = 0, downloads = 0, installs = 0;
  @override
  String get installedVersion => '0.1.0+1';
  @override
  String? get availableVersion => '0.2.0+2';
  @override
  String get notes => 'New version';
  @override
  String get message => '';
  @override
  double? get progress => null;
  @override
  Future<void> check() async {
    checks++;
    state = UpdateState.available;
    notifyListeners();
  }

  @override
  Future<void> download() async {
    downloads++;
    state = UpdateState.downloaded;
    notifyListeners();
  }

  @override
  Future<void> openInstaller() async {
    installs++;
  }
}

void main() {
  testWidgets(
    'opt-out persists; manual check and separate download/install work',
    (tester) async {
      final updater = FakeUpdater();
      var automatic = false;
      Widget app() => MaterialApp(
        home: Scaffold(
          body: UpdateControls(
            updater: updater,
            readPreference: () async => automatic,
            writePreference: (value) async {
              automatic = value;
            },
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(updater.checks, 0);
      await tester.tap(find.byKey(const ValueKey('app-updates')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('update-check')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Доступно обновление'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('update-download')));
      await tester.pumpAndSettle();
      expect(updater.installs, 0);
      await tester.tap(find.byKey(const ValueKey('update-install')));
      await tester.pumpAndSettle();
      expect(updater.installs, 1);
      await tester.tap(find.byKey(const ValueKey('update-auto')));
      await tester.pumpAndSettle();
      expect(automatic, true);
      await tester.tap(find.byKey(const ValueKey('update-auto')));
      await tester.pumpAndSettle();
      expect(automatic, false);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final oldChecks = updater.checks;
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(updater.checks, oldChecks);
      await tester.pumpWidget(const SizedBox());
      updater.dispose();
    },
  );
  testWidgets('phone viewport exposes update control and navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final updater = FakeUpdater();
    await tester.pumpWidget(ServerDeckApp(updater: updater));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('nav-servers')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-updates')));
    await tester.pumpAndSettle();
    expect(find.text('Обновления ServerDeck'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    updater.dispose();
  });
}
