import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/receipt_book.dart';
import 'package:serverdeck/software/software_models.dart';
import 'package:serverdeck/software/software_owner.dart';
import 'package:serverdeck/software/software_view.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

import 'dart:typed_data';

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
    if (h.failure != null) throw h.failure!;
    if (!isAuthorizedNow(actor))
      throw const OperationFailure(FailureCode.authRequired);
  }
}

final class SoftwareWidgetHarness {
  OperationFailure? failure;
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

  Future<String> seed(WidgetTester tester, {String name = 'Redis'}) async =>
      (await tester.runAsync(
        () => owner.save(
          h.actors.ui,
          profile,
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
      for (var i = 0; i < 26; i++) {
        await seed(tester, name: 'Seed$i');
      }
      await show(tester);
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
      expect(find.widgetWithText(DeckListItem, 'Seed25'), findsOneWidget);
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
      expect(find.text('test-version'), findsOneWidget);
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
