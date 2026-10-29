import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/servers/server_compositions.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_page.dart';

import '../support/design_server_fixtures.dart';
import '../support/design_host.dart' show loadDesignFonts;

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
  theme: BrandTheme.dark,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  setUpAll(loadDesignFonts);

  for (final retirement in ['profile', 'owner']) {
    testWidgets(
      'revoke consent retires on $retirement change and never retargets',
      (tester) async {
        final changes = ChangeNotifier();
        addTearDown(changes.dispose);
        final reviewed = DesignServerFixtures.profile();
        var current = reviewed;
        var currentOwner = true;
        var writes = 0;
        await tester.pumpWidget(
          _app(
            ServerRevokeConfirmation(
              profile: reviewed,
              changes: changes,
              currentProfile: () => current,
              currentOwner: () => currentOwner,
              title: 'Отозвать доверие',
              confirmLabel: 'Отозвать',
              child: const Text('Проверенная цель'),
              onCancel: () {},
              onConfirm: () => writes++,
            ),
          ),
        );
        final button = find.widgetWithText(FilledButton, 'Отозвать');
        final late = tester.widget<FilledButton>(button).onPressed!;
        if (retirement == 'profile') {
          current = DesignServerFixtures.profile(
            address: 'replacement.example',
          );
        } else {
          currentOwner = false;
        }
        // The event may arrive before the next frame or owner notification.
        late();
        await tester.pumpAndSettle();
        expect(writes, 0);
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        current = reviewed;
        currentOwner = true;
        changes.notifyListeners();
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        expect(find.text('replacement.example'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        late();
        expect(writes, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('changed host key owns its composition and review only probes', (
    tester,
  ) async {
    var probes = 0, writes = 0, closed = 0;
    await tester.pumpWidget(
      _app(
        ServerOverviewSection(
          profile: DesignServerFixtures.profile(),
          state: DesignServerFixtures.state(),
          onCloseChangedKey: () => closed++,
          connection: ServerConnectionSection(
            connection: DesignServerFixtures.connection(),
            trust: DesignServerFixtures.trust(),
            busy: false,
            error: 'TRUST_CHANGED',
            hasTrustChallenge: false,
            onRefresh: () => writes++,
            onProbeTrust: () => probes++,
            onConfirmTrust: () => writes++,
            onConnect: () => writes++,
            onDisconnect: () => writes++,
            onRevokeTrust: () => writes++,
            onCancel: () {},
          ),
        ),
      ),
    );
    expect(find.text('SSH-ключ изменился'), findsOneWidget);
    expect(find.byType(ServerResourceCards), findsNothing);
    expect(find.textContaining('Новый отпечаток не получен'), findsOneWidget);
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Пересмотреть доверие'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Пересмотреть доверие'));
    expect(probes, 1);
    expect(writes, 0);
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Закрыть'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Закрыть'));
    expect(closed, 1);
  });

  testWidgets('log search and filters edit drafts; explicit read is separate', (
    tester,
  ) async {
    final query = TextEditingController();
    addTearDown(query.dispose);
    var reads = 0, previous = 0;
    var scope = false;
    String? unit, sentUnit, sentText;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => ServerLogsSection(
            logs: DesignServerFixtures.logs(nextCursor: 'actual-cursor'),
            filterController: query,
            busy: false,
            units: const ['observed.service'],
            unitScope: scope,
            selectedUnit: unit,
            onScopeChanged: (value) => setState(() {
              scope = value;
              if (!value) unit = null;
            }),
            onUnitChanged: (value) => setState(() => unit = value),
            canRead: !scope || unit != null,
            onLoad: () {
              reads++;
              sentUnit = scope ? unit : null;
              sentText = query.text;
            },
            onPrevious: () => previous++,
            onOpenRecord: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Поиск'));
    await tester.enterText(find.byType(TextField), 'real query');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Фильтры'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Фильтры'));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(reads + previous, 0);
    await tester.ensureVisible(find.text('Выбранная служба'));
    await tester.tap(find.text('Выбранная служба'));
    await tester.pumpAndSettle();
    await tester.pump();
    final read = find.widgetWithText(FilledButton, 'Получить журнал');
    expect(tester.widget<FilledButton>(read).onPressed, isNull);
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('observed.service').last);
    await tester.pumpAndSettle();
    expect(reads + previous, 0);
    await tester.ensureVisible(read);
    await tester.tap(read);
    expect(reads, 1);
    expect(sentUnit, 'observed.service');
    expect(sentText, 'real query');
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Пауза'))
          .onPressed,
      isNull,
    );
    expect(
      find.textContaining('Пауза, период и приоритет пока недоступны'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('changed query cannot reuse a previous result cursor', (
    tester,
  ) async {
    final query = TextEditingController(text: 'new query');
    addTearDown(query.dispose);
    var reads = 0;
    await tester.pumpWidget(
      _app(
        ServerLogsSection(
          logs: DesignServerFixtures.logs(nextCursor: 'previous-result-cursor'),
          filterController: query,
          busy: false,
          canPrevious: false,
          onLoad: () => reads++,
          onPrevious: () => reads++,
          onOpenRecord: (_) {},
        ),
      ),
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Предыдущие записи'),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.textContaining('Показан предыдущий полученный результат'),
      findsOneWidget,
    );
    expect(reads, 0);
  });

  testWidgets('record copy uses the exact captured message', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final record = DesignServerFixtures.record(
      message: 'exact first line\nsecond line',
    );
    await tester.pumpWidget(
      _app(
        ServerLogRecordDialog(
          recordContext: ServerLogRecordContext.capture(
            DesignServerFixtures.profile(),
            DesignServerFixtures.logs(records: [record]),
          ),
          record: record,
          onClose: () {},
        ),
      ),
    );
    final copy = find.widgetWithText(FilledButton, 'Скопировать запись');
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pump();
    expect(copied, record['message']);
    expect(find.text('Сведения'), findsOneWidget);
    expect(find.text('Сообщение'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'trust review is readonly until the explicit guarded confirmation',
    (tester) async {
      final changes = ChangeNotifier();
      addTearDown(changes.dispose);
      final profile = DesignServerFixtures.profile(),
          challenge = DesignServerFixtures.challenge();
      var confirmed = 0;
      await tester.pumpWidget(
        _app(
          ServerTrustConfirmation(
            profile: profile,
            challenge: challenge,
            changes: changes,
            currentProfile: () => profile,
            currentChallenge: () => challenge,
            onCancel: () {},
            onConfirm: () => confirmed++,
          ),
        ),
      );
      expect(find.text('Параметры и условия'), findsOneWidget);
      expect(find.text('Последствия'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(confirmed, 0);
      final confirm = find.widgetWithText(FilledButton, 'Подтвердить ключ');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      expect(confirmed, 1);
    },
  );

  for (final width in [360.0, 520.0, 800.0, 1100.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('overview cards and two panels adapt at $width text$scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var calls = 0;
        void action() => calls++;
        await tester.pumpWidget(
          _app(
            ServerOverviewSection(
              profile: DesignServerFixtures.profile(),
              state: DesignServerFixtures.state(),
              connection: ServerConnectionSection(
                connection: DesignServerFixtures.connection(),
                trust: DesignServerFixtures.trust(),
                busy: false,
                error: null,
                hasTrustChallenge: false,
                onRefresh: action,
                onProbeTrust: action,
                onConfirmTrust: action,
                onConnect: action,
                onDisconnect: action,
                onRevokeTrust: action,
                onCancel: action,
              ),
            ),
            scale: scale,
          ),
        );
        expect(find.byType(ServerResourceCards), findsOneWidget);
        final system = find.widgetWithText(DeckPanel, 'Сведения о сервере');
        final chart = find.widgetWithText(DeckPanel, 'Процессор');
        expect(system, findsOneWidget);
        expect(chart, findsOneWidget);
        final systemRect = tester.getRect(system),
            chartRect = tester.getRect(chart);
        if (width > 760 && scale == 1) {
          expect(chartRect.left, greaterThan(systemRect.left));
        } else {
          expect(chartRect.left, systemRect.left);
          expect(chartRect.top, greaterThanOrEqualTo(systemRect.bottom));
        }
        expect(calls, 0);
        expect(find.textContaining('DEMO'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
