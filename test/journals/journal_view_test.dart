import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/journals/journal_models.dart';
import 'package:serverdeck/journals/journal_view.dart';
import 'package:serverdeck/journals/journal_protocol.dart';
import 'package:serverdeck/storage/records.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

import 'journal_owner_test.dart' show JournalHarness;

Widget screen(JournalHarness h, {String profile = 'a'}) => MaterialApp(
  theme: BrandTheme.dark,
  home: Scaffold(
    body: SingleChildScrollView(
      child: JournalView(
        owner: h.owner,
        profileId: profile,
        connectionRevision:
            h.repository.state.profiles[profile]?.connectionRevision ?? 0,
      ),
    ),
  ),
);
Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DeckTextField && w.label == label),
  matching: find.byType(TextFormField),
);
Future<String> prepareDetail(
  WidgetTester tester,
  JournalHarness h, {
  bool expiring = false,
}) async {
  await h.owner.start();
  final id = await h.owner.add('a', JournalKind.journal, 'a.service', 'A');
  await h.repository.write((r) {
    final s = r.journalSource(id)!;
    s.enabled = false;
    s.payload = JournalPayload(
      entries: [
        JournalEntry(
          id: 'entry',
          receivedAt: h.clock.utc - (expiring ? 3599000 : 0),
          text: 'private detail payload',
        ),
      ],
    ).encode();
    r.putJournalSource(s);
  });
  await h.owner.reconcile();
  await tester.pumpWidget(screen(h));
  await tester.tap(find.text('Открыть').first);
  await tester.pumpAndSettle();
  final records = find.byWidgetPredicate(
    (w) => w is DeckCollection<JournalEntry>,
  );
  final open = find
      .descendant(
        of: records,
        matching: find.widgetWithText(TextButton, 'Открыть'),
      )
      .first;
  await tester.ensureVisible(open);
  await tester.tap(open);
  await tester.pumpAndSettle();
  expect(find.byType(DeckLogMessage), findsOneWidget);
  return id;
}

void main() {
  testWidgets(
    'open detail and list remove payload at exact expiry between polling ticks',
    (tester) async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await prepareDetail(tester, h, expiring: true);
      h.clock.advance(const Duration(seconds: 1));
      await h.owner.drain();
      await tester.pumpAndSettle();
      expect(find.byType(DeckLogMessage), findsNothing);
      expect(find.text('private detail payload'), findsNothing);
      expect(find.text('Запись больше недоступна'), findsOneWidget);
    },
  );
  testWidgets('open detail cannot retain source-deleted payload', (
    tester,
  ) async {
    final h = JournalHarness();
    addTearDown(h.dispose);
    final id = await prepareDetail(tester, h);
    await h.owner.deleteSource(id);
    await tester.pumpAndSettle();
    expect(find.byType(DeckLogMessage), findsNothing);
    expect(find.text('private detail payload'), findsNothing);
  });
  testWidgets('same-profile revision reset retires record route immediately', (
    tester,
  ) async {
    final h = JournalHarness();
    addTearDown(h.dispose);
    await prepareDetail(tester, h);
    await h.repository.write((r) {
      final p = r.profile('a')!..connectionRevision = 2;
      r.putProfile(p);
    });
    await tester.pumpWidget(screen(h));
    await tester.pumpAndSettle();
    expect(find.byType(DeckLogMessage), findsNothing);
    expect(find.text('private detail payload'), findsNothing);
  });
  testWidgets(
    'offline Refresh after endpoint change cannot resurrect old service rows',
    (tester) async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      h.connection.respond = (_) async => JournalReply(units: ['old.service']);
      await h.owner.discover('a');
      h.clock.elapsed += const Duration(seconds: 5);
      await h.repository.write((r) {
        final p = r.profile('a')!..connectionRevision = 2;
        r.putProfile(p);
      });
      h.connection.connected = false;
      await tester.pumpWidget(screen(h));
      await tester.tap(find.text('Обновить сервисы'));
      await tester.pumpAndSettle();
      expect(find.text('old.service'), findsNothing);
      expect(find.text('Добавить сервис'), findsNothing);
    },
  );
  testWidgets('retired Add service callback cannot create A unit for B', (
    tester,
  ) async {
    final h = JournalHarness();
    addTearDown(h.dispose);
    await h.owner.start();
    h.repository.state.profiles['b'] = Profile()
      ..profileId = 'b'
      ..endpointId = 'e';
    h.connection.respond = (_) async => JournalReply(units: ['old.service']);
    await h.owner.discover('a');
    await tester.pumpWidget(screen(h));
    final button = tester.widget<DeckButton>(
      find.ancestor(
        of: find.text('Добавить сервис'),
        matching: find.byType(DeckButton),
      ),
    );
    final callback = button.onPressed!;
    await tester.pumpWidget(screen(h, profile: 'b'));
    await tester.pumpAndSettle();
    await callback();
    await tester.pumpAndSettle();
    expect(h.owner.sources('a'), isEmpty);
    expect(h.owner.sources('b'), isEmpty);
  });
  testWidgets(
    'long discovered unit uses bounded label while keeping full target',
    (tester) async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      final unit = '${'a' * 81}.service';
      h.connection.respond = (_) async => JournalReply(units: [unit]);
      await tester.pumpWidget(screen(h));
      await tester.tap(find.text('Обновить сервисы'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Добавить сервис'));
      await tester.tap(find.text('Добавить сервис'));
      await tester.pumpAndSettle();
      expect(h.owner.sources('a').single.target, unit);
      expect(h.owner.sources('a').single.name.runes.length, 80);
    },
  );
  testWidgets(
    'endpoint revision change hides old discovered units without refresh',
    (tester) async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      h.connection.respond = (_) async =>
          JournalReply(units: ['old-endpoint.service']);
      await h.owner.discover('a');
      await tester.pumpWidget(screen(h));
      expect(find.text('old-endpoint.service'), findsOneWidget);
      await h.repository.write((r) {
        final p = r.profile('a')!..connectionRevision = 2;
        r.putProfile(p);
      });
      await tester.pumpWidget(screen(h));
      await tester.pumpAndSettle();
      expect(find.text('old-endpoint.service'), findsNothing);
      expect(find.text('Добавить сервис'), findsNothing);
    },
  );
  testWidgets(
    'discovery add and inert record contents belong to current server',
    (tester) async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      h.connection.respond = (r) async => r.kind == JournalRequestKind.discover
          ? JournalReply(units: ['good.service'])
          : JournalReply(
              cursor: 'c',
              events: [
                const JournalEntry(
                  id: 'c',
                  receivedAt: 0,
                  sourceAt: 1700000000000,
                  priority: 3,
                  text: 'server message',
                ),
              ],
            );
      await tester.pumpWidget(screen(h));
      await tester.tap(find.text('Обновить сервисы'));
      await tester.pumpAndSettle();
      expect(find.text('good.service'), findsOneWidget);
      expect(h.owner.sources('a'), isEmpty);
      await tester.ensureVisible(find.text('Добавить сервис'));
      await tester.tap(find.text('Добавить сервис'));
      await tester.pumpAndSettle();
      await h.tick();
      await tester.pumpAndSettle();
      expect(find.text('server message'), findsOneWidget);
      expect(h.owner.sources('a').single.target, 'good.service');
    },
  );
  testWidgets('rename and delete confirmation retain errors and recover', (
    tester,
  ) async {
    final h = JournalHarness();
    addTearDown(h.dispose);
    await h.owner.start();
    await tester.pumpWidget(screen(h));
    await tester.tap(find.text('Добавить файл'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Название источника'), 'Before');
    await tester.enterText(field('Абсолютный путь на сервере'), '/a');
    await tester.tap(find.text('Сохранить источник'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Переименовать'));
    await tester.tap(find.text('Переименовать'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Название источника'), 'After');
    await tester.tap(find.text('Сохранить источник'));
    await tester.pumpAndSettle();
    expect(h.owner.sources('a').single.name, 'After');
    await tester.ensureVisible(find.text('Удалить'));
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    h.repository.failCommit = true;
    await tester.tap(find.text('Удалить источник'));
    await tester.pumpAndSettle();
    expect(find.text('Удаление не выполнено'), findsOneWidget);
    expect(h.owner.sources('a'), hasLength(1));
    await tester.tap(find.text('Удалить источник'));
    await tester.pumpAndSettle();
    expect(h.owner.sources('a'), isEmpty);
  });
  testWidgets(
    'offline saved history remains readable with source state and pagination',
    (tester) async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      final id = await h.owner.add(
        'a',
        JournalKind.journal,
        'a.service',
        'Saved',
      );
      await h.repository.write((r) {
        final s = r.journalSource(id)!;
        s.payload = JournalPayload(
          partial: true,
          entries: List.generate(
            201,
            (i) => JournalEntry(
              id: 'e$i',
              receivedAt: h.clock.utc,
              text: 'entry $i',
            ),
          ),
        ).encode();
        r.putJournalSource(s);
      });
      h.connection.connected = false;
      await tester.pumpWidget(screen(h));
      await tester.tap(find.text('Открыть').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Нет подключения; показана локальная история'),
        findsWidgets,
      );
      expect(find.text('История неполная'), findsOneWidget);
      Finder records() =>
          find.byWidgetPredicate((w) => w is DeckCollection<JournalEntry>);
      expect(
        tester.widget<DeckCollection<JournalEntry>>(records()).rows.length,
        200,
      );
      await tester.ensureVisible(find.text('Показать ещё'));
      await tester.tap(find.text('Показать ещё'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DeckCollection<JournalEntry>>(records()).rows.length,
        201,
      );
    },
  );
  testWidgets(
    'global source limit keeps file form draft and shows actionable failure',
    (tester) async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      for (var i = 0; i < 1024; i++) {
        final profile = 'p${i ~/ 16}';
        h.repository.state.profiles[profile] = Profile()
          ..profileId = profile
          ..endpointId = 'e';
        h.repository.state.journalSources['s$i'] = JournalSource()
          ..sourceId = 's$i'
          ..profileId = profile
          ..target = 's$i.service'
          ..name = 's$i'
          ..enabled = false;
      }
      await tester.pumpWidget(screen(h));
      await tester.tap(find.text('Добавить файл'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Название источника'), 'Kept');
      await tester.enterText(field('Абсолютный путь на сервере'), '/kept');
      await tester.tap(find.text('Сохранить источник'));
      await tester.pumpAndSettle();
      expect(find.text('Достигнут предел источников журналов'), findsOneWidget);
      expect(find.text('Kept'), findsOneWidget);
      expect(find.text('/kept'), findsOneWidget);
    },
  );
  testWidgets(
    'file validation and failed commit retain input, successful add selects source',
    (tester) async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      await tester.pumpWidget(screen(h));
      await tester.tap(find.text('Добавить файл'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Название источника'), 'App');
      await tester.enterText(field('Абсолютный путь на сервере'), 'relative');
      await tester.tap(find.text('Сохранить источник'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Укажите абсолютный путь'), findsOneWidget);
      await tester.enterText(
        field('Абсолютный путь на сервере'),
        '/opt/app.log',
      );
      h.repository.failCommit = true;
      await tester.tap(find.text('Сохранить источник'));
      await tester.pumpAndSettle();
      expect(find.text('App'), findsOneWidget);
      expect(find.text('/opt/app.log'), findsOneWidget);
      await tester.tap(find.text('Сохранить источник'));
      await tester.pumpAndSettle();
      expect(find.text('Источник: App'), findsOneWidget);
      await tester.ensureVisible(find.text('Выключить сбор'));
      await tester.tap(find.text('Выключить сбор'));
      await tester.pumpAndSettle();
      expect(h.owner.sources('a').single.enabled, isFalse);
    },
  );
  testWidgets(
    'switching server closes owned form and never shows A sources at B',
    (tester) async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      await h.owner.add('a', JournalKind.file, '/a', 'Only A');
      await tester.pumpWidget(screen(h));
      expect(find.text('Only A'), findsOneWidget);
      await tester.tap(find.text('Добавить файл'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(screen(h, profile: 'b'));
      await tester.pumpAndSettle();
      expect(find.text('Добавить файловый журнал'), findsNothing);
      expect(find.text('Only A'), findsNothing);
    },
  );
}
