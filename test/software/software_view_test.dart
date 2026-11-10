import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/receipt_book.dart';
import 'package:serverdeck/software/software_models.dart';
import 'package:serverdeck/software/software_owner.dart';
import 'package:serverdeck/software/software_view.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/domain/mutation_receipts.dart';
import 'package:serverdeck/storage/records.dart';

import '../fixtures/domain_repository.dart';
import '../fixtures/feature_harness.dart'
    show featureId, FeatureClock, featureTurns;

final class WidgetOperationState implements OperationState {
  WidgetOperationState(this.h);
  final SoftwareWidgetHarness h;
  @override
  String get ownerEpoch => h.actors.ownerEpoch;
  @override
  bool get running => true;
  @override
  int get dataRevision => h.repository.state.settings.dataRevision;
  @override
  EntityVersions? versions(String id) => null;
  @override
  bool isAuthorizedNow(CommandActor actor) => h.actors.owns(actor);
  @override
  Future<void> authorize(CommandActor actor, AuthorizationPoint point) async {
    h.authorizations++;
    if (h.authorizationWait != null) await h.authorizationWait;
    if (h.failure != null) throw h.failure!;
    if (!isAuthorizedNow(actor))
      throw const OperationFailure(FailureCode.authRequired);
  }
}

final class SoftwareWidgetHarness {
  OperationFailure? failure;
  Future<void>? authorizationWait;
  int authorizations = 0;
  SoftwareWidgetHarness() {
    repository.state.profiles[profile.profileId] = Profile()
      ..profileId = profile.profileId
      ..endpointId = profile.endpointId
      ..normalizedHost = profile.host
      ..username = profile.username;
  }
  final actors = ActorAuthority(featureId(9000));
  final repository = MemoryDomainRepository(), clock = FeatureClock();
  final signer = ReceiptSigner(Uint8List.fromList(List.filled(32, 17)));
  late final gate = DomainCommandGate(
    actors: actors,
    state: WidgetOperationState(this),
  );
  int sequence = 100;
  String newId() => featureId(++sequence);
  final profile = ProfileView(
    profileId: featureId(1),
    revision: 1,
    connectionRevision: 1,
    displayName: 'Synthetic',
    host: 'server.invalid',
    port: 22,
    username: 'root',
    authKind: AuthKind.password,
    hasCredential: true,
    endpointId: '0' * 64,
  );
  Future<void> dispose() async {
    gate.stopAdmission();

    signer.dispose();
  }
}

void main() {
  late SoftwareWidgetHarness h;
  late SoftwareOwner owner;
  late String profile;
  setUp(() async {
    h = SoftwareWidgetHarness();
    profile = h.profile.profileId;
    owner = SoftwareOwner(
      gate: h.gate,
      repository: h.repository,
      receipts: ReceiptBook(h.signer, h.clock.now),
      newId: h.newId,
      utcNow: h.clock.now,
    );
  });
  void testSoftwareWidgets(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        for (var i = 0; i < 6; i++) {
          await tester.pump();
          await tester.runAsync(() => featureTurns());
        }
        await tester.runAsync(() async {
          await owner.dispose();
          await h.dispose();
        });
      }
    });
  }

  Future<void> show(
    WidgetTester tester, {
    Future<void> Function(String)? copyText,
    VoidCallback? console,
    ProfileView? target,
    bool settle = true,
  }) async {
    final projection = target ?? h.profile;
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SoftwareView(
              owner: owner,
              actor: h.actors.ui,
              profile: projection,
              newId: h.newId,
              copyText: copyText,
              onConsole: console,
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.runAsync(() => featureTurns());
      await tester.pumpAndSettle();
    }
  }

  Future<void> click(WidgetTester tester, String text) async {
    final target = find.text(text);
    await tester.ensureVisible(target.first);
    await tester.tap(target.first);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
      await tester.runAsync(() => featureTurns());
    }
    await tester.pumpAndSettle();
  }

  Future<String> seed(
    WidgetTester tester, {
    String name = 'Redis',
    SoftwareCardInput? input,
  }) async => (await tester.runAsync(
    () => owner.save(
      h.actors.ui,
      profile,
      input ??
          SoftwareCardInput(
            name: name,
            version: null,
            service: null,
            dataPaths: [],
            configPaths: [],
          ),
      mutationId: h.newId(),
    ),
  ))!.value!.entityId;

  Finder card(String id) => find.byKey(ValueKey('software-card-$id'));

  Finder details(String id) =>
      find.descendant(of: card(id), matching: find.text('Подробности'));

  Future<void> toggle(WidgetTester tester, String id) async {
    final target = details(id);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Finder action(String id, String label) => find.descendant(
    of: card(id),
    matching: find.widgetWithText(DeckButton, label),
  );

  testSoftwareWidgets(
    'compact summary and independent disclosure have no effects',
    (tester) async {
      final first = await seed(tester);
      final second = await seed(tester, name: 'Nginx');
      var consoleCalls = 0;
      await show(tester, console: () => consoleCalls++);
      expect(find.text('Версия: Не указана'), findsNWidgets(2));
      expect(
        find.descendant(
          of: card(first),
          matching: find.text('root@server.invalid:22'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card(second),
          matching: find.text('root@server.invalid:22'),
        ),
        findsOneWidget,
      );
      expect(find.text('Служба'), findsNothing);
      expect(find.text('Изменить карточку'), findsNothing);
      final reads = h.authorizations;
      final revision = h.repository.state.settings.dataRevision;
      final events = h.repository.state.softwareEvents.length;
      await toggle(tester, first);
      expect(action(first, 'Изменить карточку'), findsOneWidget);
      expect(action(second, 'Изменить карточку'), findsNothing);
      expect(find.text('Не указана'), findsOneWidget);
      expect(find.text('Нет сведений'), findsNWidgets(2));
      await toggle(tester, second);
      expect(find.text('Изменить карточку'), findsNWidgets(2));
      await toggle(tester, first);
      expect(action(first, 'Изменить карточку'), findsNothing);
      expect(action(second, 'Изменить карточку'), findsOneWidget);
      expect(h.authorizations, reads);
      expect(h.repository.state.settings.dataRevision, revision);
      expect(h.repository.state.softwareEvents.length, events);
      expect(consoleCalls, 0);
    },
  );

  testSoftwareWidgets(
    'details preserve full literal values, paths and UTC fallback',
    (tester) async {
      final name = 'Long software ${'n' * 80}';
      final version = 'v${'1' * 250}';
      final path = '/data/${'x' * 900}';
      final id = await seed(
        tester,
        input: SoftwareCardInput(
          name: name,
          version: version,
          service: 'redis-server.service',
          dataPaths: [path, '/data/second'],
          configPaths: ['/etc/redis/a.conf', '/etc/redis/b.conf'],
        ),
      );
      await show(tester);
      expect(find.text(name), findsOneWidget);
      expect(find.text('Версия: $version'), findsOneWidget);
      await toggle(tester, id);
      final values = tester
          .widgetList<DeckKeyValue>(
            find.descendant(of: card(id), matching: find.byType(DeckKeyValue)),
          )
          .toList();
      expect(
        values.singleWhere((v) => v.label == 'Данные').value,
        '$path\n/data/second',
      );
      expect(values.singleWhere((v) => v.label == 'Данные').selectable, isTrue);
      expect(
        values.singleWhere((v) => v.label == 'Конфиги').value,
        '/etc/redis/a.conf\n/etc/redis/b.conf',
      );
      expect(
        values.singleWhere((v) => v.label == 'Исходный хост').value,
        'root@server.invalid:22',
      );
      expect(
        values.singleWhere((v) => v.label == 'Исходный хост').selectable,
        isTrue,
      );
      expect(find.text('redis-server.service'), findsOneWidget);
      final timestamp = tester.widget<DeckTimestamp>(
        find.descendant(of: card(id), matching: find.byType(DeckTimestamp)),
      );
      expect(timestamp.value!.isUtc, isTrue);
      expect(
        timestamp.value!.millisecondsSinceEpoch,
        h.repository.state.softwareCards[id]!.updatedAt,
      );
      h.repository.state.softwareCards[id]!.updatedAt = 9007199254740991;
      await click(tester, 'Обновить ПО');
      expect(find.text('9007199254740991 ms UTC'), findsOneWidget);
      expect(action(id, 'История карточки'), findsOneWidget);
    },
  );

  testSoftwareWidgets(
    'keyboard toggles disclosure and exposes expanded semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final id = await seed(tester);
        await show(tester);
        final labels = MaterialLocalizations.of(tester.element(details(id)));
        expect(
          tester.getSemantics(details(id)),
          isSemantics(hint: labels.expandedHint),
        );
        // Focus the existing C19 interactive tile, without assuming a tab position.
        final focus = Focus.of(tester.element(details(id)));
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(action(id, 'Изменить карточку'), findsOneWidget);
        expect(
          tester.getSemantics(details(id)),
          isSemantics(hint: labels.collapsedHint),
        );
        expect(
          find.descendant(
            of: card(id),
            matching: find.bySemanticsLabel(RegExp('Подробности')),
          ),
          findsWidgets,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(action(id, 'Изменить карточку'), findsNothing);
        expect(
          tester.getSemantics(details(id)),
          isSemantics(hint: labels.expandedHint),
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testSoftwareWidgets('pending preserves action rules and console callback', (
    tester,
  ) async {
    final id = await seed(tester);
    var consoleCalls = 0;
    await show(tester, console: () => consoleCalls++);
    await toggle(tester, id);
    await click(tester, 'Изменить карточку');
    final blocked = Completer<void>();
    h.authorizationWait = blocked.future;
    try {
      final save = tester.widget<DeckButton>(
        find.widgetWithText(DeckButton, 'Сохранить карточку'),
      );
      save.onPressed!();
      await tester.pump();
      for (final label in [
        'Изменить карточку',
        'Удалить карточку',
        'История карточки',
      ]) {
        expect(tester.widget<DeckButton>(action(id, label)).onPressed, isNull);
      }
      tester.widget<DeckButton>(action(id, 'Открыть консоль')).onPressed!();
      expect(consoleCalls, 1);
    } finally {
      h.authorizationWait = null;
      blocked.complete();
      await tester.runAsync(() => featureTurns());
      await tester.pumpAndSettle();
    }
    expect(h.repository.state.softwareCards[id]!.revision, 2);
    expect(
      tester.widget<DeckButton>(action(id, 'Изменить карточку')).onPressed,
      isNotNull,
    );
  });

  testSoftwareWidgets('profile change and return reset disclosure', (
    tester,
  ) async {
    final id = await seed(tester);
    final old = h.profile;
    final other = ProfileView(
      profileId: featureId(2),
      revision: 1,
      connectionRevision: 1,
      displayName: 'Other',
      host: old.host,
      port: old.port,
      username: old.username,
      authKind: old.authKind,
      hasCredential: true,
      endpointId: old.endpointId,
    );
    h.repository.state.profiles[other.profileId] = Profile()
      ..profileId = other.profileId
      ..endpointId = other.endpointId
      ..normalizedHost = other.host
      ..username = other.username;
    await show(tester);
    await toggle(tester, id);
    await show(tester, target: other);
    expect(card(id), findsNothing);
    expect(find.text('Карточек ПО нет'), findsOneWidget);
    await show(tester);
    expect(details(id), findsOneWidget);
    expect(action(id, 'Изменить карточку'), findsNothing);
  });

  testSoftwareWidgets(
    'refresh preserves remaining ids and filter resets disclosure',
    (tester) async {
      final id = await seed(tester);
      await show(tester);
      await toggle(tester, id);
      await tester.runAsync(
        () => owner.save(
          h.actors.ui,
          profile,
          SoftwareCardInput(
            name: 'New name',
            version: '2',
            service: 'new-service',
            dataPaths: [],
            configPaths: [],
          ),
          softwareId: id,
          expectedRevision: 1,
          mutationId: h.newId(),
        ),
      );
      await tester.runAsync(() => featureTurns());
      await tester.pumpAndSettle();
      expect(find.text('New name'), findsOneWidget);
      expect(find.text('new-service'), findsOneWidget);
      final newId = await seed(tester, name: 'New card');
      await tester.runAsync(() => featureTurns());
      await tester.pumpAndSettle();
      expect(action(id, 'Изменить карточку'), findsOneWidget);
      expect(action(newId, 'Изменить карточку'), findsNothing);
      final search = find.descendant(
        of: find.byType(DeckSearch),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'New');
      await tester.pumpAndSettle();
      expect(find.text('Изменить карточку'), findsNothing);
      await toggle(tester, id);
      await tester.enterText(search, 'absent');
      await tester.pumpAndSettle();
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      expect(find.text('Изменить карточку'), findsNothing);
      await toggle(tester, id);
      await click(tester, 'Удалить карточку');
      expect(card(id), findsNothing);
      expect(action(newId, 'Изменить карточку'), findsNothing);
    },
  );

  testSoftwareWidgets(
    'loading and failed reads never claim an empty inventory; refresh recovers',
    (tester) async {
      h.failure = const OperationFailure(FailureCode.storageUnavailable);
      await show(tester, settle: false);
      expect(find.text('Получаем данные'), findsOneWidget);
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        await tester.runAsync(() => featureTurns());
      }
      await tester.pumpAndSettle();
      expect(
        find.text('Не удалось прочитать или сохранить локальные данные.'),
        findsOneWidget,
      );
      expect(find.text('Карточек ПО нет'), findsNothing);
      h.failure = null;
      await click(tester, 'Обновить ПО');
      expect(find.text('Карточек ПО нет'), findsOneWidget);
    },
  );
  testSoftwareWidgets(
    'conflict keeps draft and requires explicit reread before saving',
    (tester) async {
      final id = await seed(tester);
      await show(tester);
      await toggle(tester, id);
      await click(tester, 'Изменить карточку');
      await tester.enterText(
        find.byKey(const ValueKey('software-name')),
        'Local draft',
      );
      await tester.runAsync(
        () => owner.save(
          h.actors.ui,
          profile,
          SoftwareCardInput(
            name: 'Concurrent edit',
            version: null,
            service: null,
            dataPaths: [],
            configPaths: [],
          ),
          softwareId: id,
          expectedRevision: 1,
          mutationId: h.newId(),
        ),
      );
      await tester.runAsync(() => featureTurns());
      await tester.pumpAndSettle();
      await click(tester, 'Сохранить карточку');
      expect(
        tester
            .widget<DeckTextField>(find.byKey(const ValueKey('software-name')))
            .controller!
            .text,
        'Local draft',
      );
      expect(
        tester
            .widget<DeckButton>(
              find.widgetWithText(DeckButton, 'Сохранить карточку'),
            )
            .onPressed,
        isNull,
      );
      expect(h.repository.state.softwareCards[id]!.name, 'Concurrent edit');
      await click(tester, 'Перечитать карточку');
      expect(
        tester
            .widget<DeckTextField>(find.byKey(const ValueKey('software-name')))
            .controller!
            .text,
        'Concurrent edit',
      );
      await tester.enterText(
        find.byKey(const ValueKey('software-name')),
        'Reviewed edit',
      );
      await click(tester, 'Сохранить карточку');
      expect(h.repository.state.softwareCards[id]!.revision, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testSoftwareWidgets(
    'failed local save retains draft and retry has one effect',
    (tester) async {
      await show(tester);
      await click(tester, 'Добавить ПО');
      await tester.enterText(
        find.byKey(const ValueKey('software-name')),
        'Redis',
      );
      h.repository.failCommit = true;
      await click(tester, 'Сохранить карточку');
      expect(
        find.text('Не удалось прочитать или сохранить локальные данные.'),
        findsOneWidget,
      );
      expect(h.repository.state.softwareCards, isEmpty);
      expect(
        tester
            .widget<DeckTextField>(find.byKey(const ValueKey('software-name')))
            .controller!
            .text,
        'Redis',
      );
      await click(tester, 'Сохранить карточку');
      expect(h.repository.state.softwareCards.length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testSoftwareWidgets(
    'filter searches only displayed page and pagination reaches remaining card',
    (tester) async {
      final ids = <String>[];
      for (var i = 0; i < 26; i++) {
        ids.add(await seed(tester, name: 'Seed$i'));
      }
      await show(tester);
      await toggle(tester, ids.first);
      await click(tester, 'Далее');
      expect(action(ids.last, 'Изменить карточку'), findsNothing);
      await toggle(tester, ids.last);
      await click(tester, 'Назад');
      expect(action(ids.first, 'Изменить карточку'), findsNothing);
      await tester.enterText(
        find.descendant(
          of: find.byType(DeckSearch),
          matching: find.byType(TextField),
        ),
        'Seed25',
      );
      await tester.pumpAndSettle();
      expect(find.text('Ничего не найдено'), findsOneWidget);
      await click(tester, 'Далее');
      expect(
        find.descendant(of: card(ids.last), matching: find.text('Seed25')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testSoftwareWidgets(
    'old-target card disables console and editing while local delete stays available',
    (tester) async {
      final id = await seed(tester);
      await tester.runAsync(
        () => h.repository.write(
          (r) => r.putProfile(
            r.profile(profile)!
              ..endpointId = '1' * 64
              ..normalizedHost = 'changed.invalid',
          ),
        ),
      );
      final old = h.profile;
      final target = ProfileView(
        profileId: old.profileId,
        revision: 2,
        connectionRevision: 2,
        displayName: old.displayName,
        host: 'changed.invalid',
        port: 22,
        username: old.username,
        authKind: old.authKind,
        hasCredential: true,
        endpointId: '1' * 64,
      );
      await show(
        tester,
        target: target,
        console: () => fail('Old target must not open current console'),
      );
      expect(find.text('Другой хост профиля'), findsOneWidget);
      expect(action(id, 'Изменить карточку'), findsNothing);
      await toggle(tester, id);
      expect(
        tester
            .widget<DeckButton>(find.byKey(ValueKey('software-console-$id')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<DeckButton>(
              find.widgetWithText(DeckButton, 'Изменить карточку'),
            )
            .onPressed,
        isNull,
      );
      await click(tester, 'Удалить карточку');
      expect(h.repository.state.softwareCards, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testSoftwareWidgets(
    'note shows reported outcome and remains readable after card deletion',
    (tester) async {
      final id = await seed(tester);
      await show(tester);
      await toggle(tester, id);
      await click(tester, 'История карточки');
      await click(tester, 'Написать сообщение');
      await tester.enterText(
        find.byKey(const ValueKey('software-note-summary')),
        'Изменён конфиг Redis',
      );
      await click(tester, 'Добавить сообщение');
      expect(
        h.repository.state.softwareEvents.values
            .singleWhere((e) => e.kind == 'note')
            .softwareId,
        id,
      );
      expect(find.text('Сообщённый исход'), findsOneWidget);
      expect(find.text('unknown'), findsOneWidget);
      expect(find.text('Пользователь'), findsWidgets);
      await click(tester, 'Удалить карточку');
      expect(find.text('Изменён конфиг Redis'), findsOneWidget);
      expect(find.text('История: Redis'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testSoftwareWidgets(
    'form validates, saves five fields and deletes only local card',
    (tester) async {
      await show(tester);
      expect(find.text('Карточек ПО нет'), findsOneWidget);
      await click(tester, 'Добавить ПО');
      await click(tester, 'Сохранить карточку');
      expect(find.textContaining('Некорректное'), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey('software-name')),
        'Redis',
      );
      await tester.enterText(
        find.byKey(const ValueKey('software-version')),
        'test-version',
      );
      await tester.enterText(
        find.byKey(const ValueKey('software-service')),
        'redis-server',
      );
      await tester.enterText(
        find.byKey(const ValueKey('software-dataPaths')),
        '/var/lib/redis',
      );
      await tester.enterText(
        find.byKey(const ValueKey('software-configPaths')),
        '/etc/redis/redis.conf',
      );
      await click(tester, 'Сохранить карточку');
      expect(h.repository.state.softwareCards.values.single.configPaths, [
        '/etc/redis/redis.conf',
      ]);
      expect(find.text('Версия: test-version'), findsOneWidget);
      await toggle(
        tester,
        h.repository.state.softwareCards.values.single.softwareId,
      );
      await click(tester, 'Удалить карточку');
      expect(h.repository.state.softwareCards, isEmpty);
      expect(h.repository.state.softwareEvents.length, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testSoftwareWidgets('analysis is copied explicitly and invokes no shell', (
    tester,
  ) async {
    final copied = <String>[];
    var console = 0;
    await show(
      tester,
      copyText: (value) async {
        copied.add(value);
      },
      console: () => console++,
    );
    expect(copied, isEmpty);
    await click(tester, 'Анализ сервера');
    await tester.enterText(
      find.byKey(const ValueKey('software-analysis-request')),
      'Redis',
    );
    expect(copied, isEmpty);
    await click(tester, 'Копировать задание');
    expect(copied.single, contains(profile));
    expect(copied.single, contains('Redis'));
    expect(console, 0);
    expect(h.repository.state.softwareCards, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
