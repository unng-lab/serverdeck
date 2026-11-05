import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/journals/journal_models.dart';
import 'package:serverdeck/journals/journal_protocol.dart';
import 'package:serverdeck/storage/records.dart';
import 'package:serverdeck/ui/deck_components.dart';

import 'journal_owner_test.dart' show JournalHarness;
import 'journal_view_test.dart' show screen;

Finder searchField() => find.descendant(
  of: find.byType(DeckSearch),
  matching: find.byType(TextField),
);
DeckCollection<JournalEntry> records(WidgetTester t) =>
    t.widget(find.byWidgetPredicate((w) => w is DeckCollection<JournalEntry>));
DeckCollection<String> services(WidgetTester t) =>
    t.widget(find.byWidgetPredicate((w) => w is DeckCollection<String>));
DeckCollection<JournalSource> sources(WidgetTester t) =>
    t.widget(find.byWidgetPredicate((w) => w is DeckCollection<JournalSource>));
Future<String> addSource(
  JournalHarness h,
  String target, {
  String? name,
  JournalKind kind = JournalKind.journal,
  List<JournalEntry> entries = const [],
}) async {
  final id = await h.owner.add('a', kind, target, name ?? target);
  await h.repository.write((r) {
    final s = r.journalSource(id)!;
    s.enabled = false;
    s.payload = JournalPayload(entries: entries).encode();
    r.putJournalSource(s);
  });
  return id;
}

void main() {
  testWidgets(
    'search is available before selection and matches unit, source name and file target',
    (t) async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      h.connection.respond = (_) async => JournalReply(
        units: ['nginx.service', 'nginx@beta.service', 'redis.service'],
      );
      await h.owner.discover('a');
      await addSource(h, 'nginx.service', name: 'Веб .*');
      await addSource(h, 'redis.service', name: 'Кэш');
      await addSource(
        h,
        '/var/log/app.log',
        kind: JournalKind.file,
        name: 'App',
      );
      await t.pumpWidget(screen(h));
      expect(find.text('Поиск сервиса или источника'), findsOneWidget);
      final requests = h.connection.requests.length;
      await t.enterText(searchField(), '  NGINX  ');
      await t.pumpAndSettle();
      expect(services(t).rows, ['nginx.service', 'nginx@beta.service']);
      expect(sources(t).rows.single.target, 'nginx.service');
      await t.enterText(searchField(), 'ВЕБ .*');
      await t.pumpAndSettle();
      expect(services(t).state, DeckDataState.noResults);
      expect(sources(t).rows.single.name, 'Веб .*');
      await t.enterText(searchField(), '/VAR/LOG');
      await t.pumpAndSettle();
      expect(sources(t).rows.single.kind, 'file');
      await t.enterText(searchField(), 'not-found');
      await t.pumpAndSettle();
      expect(find.text('Сервисы не найдены'), findsOneWidget);
      expect(find.text('Источники не найдены'), findsOneWidget);
      await t.tap(find.byTooltip('Очистить поиск'));
      await t.pumpAndSettle();
      expect(services(t).rows, hasLength(3));
      expect(sources(t).rows, hasLength(3));
      expect(h.connection.requests.length, requests);
    },
  );
  testWidgets(
    'service filtering preserves selection, query and message pagination without text filtering',
    (t) async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      final nginx = await addSource(
        h,
        'nginx.service',
        name: 'Web',
        entries: List.generate(
          450,
          (i) => JournalEntry(
            id: 'e$i',
            receivedAt: h.clock.utc,
            text: 'ordinary $i',
          ),
        ),
      );
      final redis = await addSource(
        h,
        'redis.service',
        name: 'Cache',
        entries: [
          JournalEntry(
            id: 'other',
            receivedAt: h.clock.utc,
            text: 'unrelated content',
          ),
        ],
      );
      await t.pumpWidget(screen(h));
      await t.enterText(searchField(), 'nginx');
      await t.pumpAndSettle();
      sources(t).onOpen!(sources(t).rows.single);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(searchField()).controller!.text, 'nginx');
      expect(records(t).rows, hasLength(200));
      await t.ensureVisible(find.text('Показать ещё'));
      await t.tap(find.text('Показать ещё'));
      await t.pumpAndSettle();
      expect(records(t).rows, hasLength(400));
      await t.enterText(searchField(), 'redis');
      await t.pumpAndSettle();
      expect(sources(t).rows.single.sourceId, redis);
      expect(find.text('Источник: Web'), findsOneWidget);
      expect(records(t).rows, hasLength(400));
      sources(t).onOpen!(sources(t).rows.single);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(searchField()).controller!.text, 'redis');
      expect(records(t).rows.single.text, 'unrelated content');
      expect(h.owner.entries(nginx), hasLength(450));
      expect(h.connection.requests, isEmpty);
    },
  );
  testWidgets(
    'discovery refresh keeps query and filters newly discovered names',
    (t) async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      h.connection.respond = (_) async =>
          JournalReply(units: ['redis.service']);
      await h.owner.discover('a');
      await t.pumpWidget(screen(h));
      await t.enterText(searchField(), 'WORKER');
      await t.pumpAndSettle();
      expect(services(t).rows, isEmpty);
      h.clock.elapsed += const Duration(seconds: 5);
      h.connection.respond = (_) async =>
          JournalReply(units: ['redis.service', 'new-worker.service']);
      await h.owner.discover('a');
      await t.pumpAndSettle();
      expect(t.widget<TextField>(searchField()).controller!.text, 'WORKER');
      expect(services(t).rows, ['new-worker.service']);
    },
  );
  for (final context in ['profile', 'revision', 'owner']) {
    testWidgets(
      '$context change clears the service query and rejects retired callback',
      (t) async {
        final h = JournalHarness();
        addTearDown(h.dispose);
        await h.owner.start();
        h.repository.state.profiles['b'] = Profile()
          ..profileId = 'b'
          ..endpointId = 'e';
        await t.pumpWidget(screen(h));
        await t.enterText(searchField(), 'nginx');
        await t.pumpAndSettle();
        final old = t.widget<DeckSearch>(find.byType(DeckSearch));
        if (context == 'profile') {
          await t.pumpWidget(screen(h, profile: 'b'));
        } else if (context == 'revision') {
          await h.repository.write((r) {
            final p = r.profile('a')!..connectionRevision = 2;
            r.putProfile(p);
          });
          await t.pumpWidget(screen(h));
        } else {
          final other = JournalHarness();
          addTearDown(other.dispose);
          await other.owner.start();
          await t.pumpWidget(screen(other));
        }
        await t.pumpAndSettle();
        old.onChanged('retired');
        await t.pumpAndSettle();
        expect(t.widget<TextField>(searchField()).controller!.text, isEmpty);
        expect(find.text('Источники не найдены'), findsNothing);
      },
    );
  }
  testWidgets(
    'empty discovery and sources remain empty rather than no-results',
    (t) async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      h.connection.respond = (_) async => JournalReply();
      await h.owner.discover('a');
      await t.pumpWidget(screen(h));
      await t.enterText(searchField(), 'missing');
      await t.pumpAndSettle();
      expect(services(t).state, DeckDataState.empty);
      expect(sources(t).state, DeckDataState.empty);
      expect(find.text('Сервисы не обнаружены'), findsOneWidget);
      expect(find.text('Источники не найдены'), findsNothing);
    },
  );
}
