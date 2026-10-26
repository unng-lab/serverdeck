import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck_protocol/models.dart';

Widget app(FoundationShell shell, {bool dark = false, double scale = 1}) =>
    MaterialApp(
      theme: dark ? BrandTheme.dark : BrandTheme.light,
      home: shell,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    );

void main() {
  testWidgets('private content and target are removed on loss of readiness', (
    tester,
  ) async {
    FoundationShell shell(ReadinessState state) => FoundationShell(
      state: state,
      servers: const Text('private profile list'),
      settings: const Text('private settings'),
      targetName: 'private target',
      targetAddress: '192.0.2.1',
    );
    await tester.pumpWidget(app(shell(ReadinessState.ready)));
    expect(find.text('private profile list'), findsOneWidget);
    expect(find.textContaining('private target'), findsOneWidget);
    for (final state in ReadinessState.values.where(
      (state) => state != ReadinessState.ready,
    )) {
      await tester.pumpWidget(app(shell(state)));
      expect(find.text('private profile list'), findsNothing);
      expect(find.text('private settings'), findsNothing);
      expect(find.textContaining('private target'), findsNothing);
      expect(find.textContaining('192.0.2.1'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'wide navigation preserves local section across service failure',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(const FoundationShell(state: ReadinessState.ready)),
      );
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('Серверы'), findsNWidgets(2));
      await tester.tap(find.widgetWithText(OutlinedButton, 'ПО'));
      await tester.pump();
      expect(
        find.text('Управление ПО будет доступно после подключения к серверу'),
        findsOneWidget,
      );
      await tester.pumpWidget(
        app(const FoundationShell(state: ReadinessState.unavailable)),
      );
      expect(find.text('Локальная служба недоступна'), findsOneWidget);
      expect(find.text('ПО'), findsNWidgets(2));
      await tester.pumpWidget(
        app(const FoundationShell(state: ReadinessState.ready)),
      );
      expect(
        find.text('Управление ПО будет доступно после подключения к серверу'),
        findsOneWidget,
      );
    },
  );

  for (final dark in [false, true]) {
    for (final size in const [
      Size(1100, 760),
      Size(800, 600),
      Size(360, 800),
      Size(390, 800),
    ]) {
      testWidgets('all sections reachable at $size scale200 dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(
            const FoundationShell(state: ReadinessState.ready),
            dark: dark,
            scale: 2,
          ),
        );
        for (final section in FoundationSection.values) {
          final button = find.byKey(
            ValueKey('foundation-navigation-${section.name}'),
          );
          await tester.ensureVisible(button);
          expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
          await tester.tap(button);
          await tester.pumpAndSettle();
          final title = tester.widget<Text>(
            find.byKey(const ValueKey('foundation-page-title')),
          );
          expect(title.data, section.label);
          expect(title.style!.fontSize, 24);
          expect(title.style!.height! * title.style!.fontSize!, 32);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('navigation supports keyboard activation', (tester) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(const FoundationShell(state: ReadinessState.ready)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.text('Управление ПО будет доступно после подключения к серверу'),
      findsOneWidget,
    );
  });

  testWidgets('profile selection does not invent an SSH state', (tester) async {
    await tester.pumpWidget(
      app(
        const FoundationShell(
          state: ReadinessState.ready,
          targetName: 'Local profile',
          targetAddress: '192.0.2.1:22',
        ),
      ),
    );
    expect(find.text('Local profile · 192.0.2.1:22'), findsOneWidget);
    expect(find.text('Локальная служба готова'), findsOneWidget);
    expect(find.textContaining('Не подключён'), findsNothing);
  });

  testWidgets('global logs and jobs lead back through local navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var commands = 0;
    await tester.pumpWidget(
      app(
        FoundationShell(
          state: ReadinessState.ready,
          servers: TextButton(
            onPressed: () => commands++,
            child: const Text('Existing local profiles'),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(AppBar)).height, 56);
    expect(
      tester.getSize(find.byKey(const ValueKey('foundation-sidebar'))).width,
      210,
    );
    final sidebar = tester.getRect(
      find.byKey(const ValueKey('foundation-sidebar')),
    );
    expect(sidebar.top, 56);
    expect(sidebar.bottom, 760);
    final serversNavigation = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Серверы'),
    );
    expect(serversNavigation.top, lessThan(150));
    for (final label in ['Журналы', 'Задания']) {
      await tester.tap(find.widgetWithText(OutlinedButton, label));
      await tester.pump();
      expect(find.textContaining('Общий список'), findsOneWidget);
      expect(find.textContaining('карточке сервера'), findsOneWidget);
      await tester.tap(find.text('К серверам'));
      await tester.pump();
      expect(find.text('Existing local profiles'), findsOneWidget);
    }
    expect(commands, 0);
  });

  testWidgets('size and theme keep the mounted feature and permitted draft', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var creations = 0;
    for (final frame in [1100.0, 390.0, 800.0, 1100.0]) {
      tester.view.physicalSize = Size(frame, 760);
      await tester.pumpWidget(
        app(
          FoundationShell(
            state: ReadinessState.ready,
            servers: _RetainedInput(onCreate: () => creations++),
          ),
          dark: frame == 390,
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('retained-field'));
      if (creations == 1 &&
          frame == 1100 &&
          tester.widget<TextField>(field).controller!.text.isEmpty) {
        await tester.enterText(field, 'Permitted RAM draft');
      }
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Permitted RAM draft',
      );
      expect(creations, 1);
      expect(tester.takeException(), isNull);
    }
  });
}

class _RetainedInput extends StatefulWidget {
  const _RetainedInput({required this.onCreate});
  final VoidCallback onCreate;
  @override
  State<_RetainedInput> createState() => _RetainedInputState();
}

class _RetainedInputState extends State<_RetainedInput> {
  final controller = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TextField(key: const ValueKey('retained-field'), controller: controller);
}
