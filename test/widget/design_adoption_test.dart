import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/servers/metrics_history.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/settings/settings_form.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

import '../support/design_host.dart';
import '../support/design_scenarios.dart';

void _text(String value) =>
    expect(find.text(value), findsWidgets, reason: value);
void _contains(String value) =>
    expect(find.textContaining(value), findsWidgets, reason: value);

Finder _shellTarget() => find.descendant(
  of: find.byKey(const ValueKey('foundation-page-context')),
  matching: find.byType(SelectableText),
);

Future<void> _showText(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .05);
  await tester.pump();
  expectDesignVisible(tester, finder);
  final target = _shellTarget();
  if (target.evaluate().isNotEmpty) expectDesignVisible(tester, target);
}

/// The cases assert each origin's actual content and intent. They intentionally
/// do not infer acceptance from a mounted widget or from the reference flag.
Future<void> _assertOrigin(WidgetTester tester, DesignFixtureHost host) async {
  final h = host.harness;
  switch (host.binding.screenId) {
    case '01-startup':
      _text('Запуск локальной службы');
      _text('Ожидаем результат запуска.');
      expect(find.byType(DeckStatus), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Повторить запуск'), findsNothing);
    case '02-service-unavailable':
      _text('Локальная служба недоступна');
      _text('Не удалось связаться с локальной службой.');
      _text('Повторить запуск');
      expect(testerStatus(DeckTone.unavailable), isTrue);
      expect(find.text('Не подключён'), findsNothing);
    case '03-storage-blocked':
      _text('Локальное хранилище заблокировано');
      _contains('Требуется проверка локального пространства');
      _text('Повторить запуск');
      expect(testerStatus(DeckTone.error), isTrue);
      expect(find.textContaining('Сбросить'), findsNothing);
      expect(find.textContaining('plaintext'), findsNothing);
    case '04-empty-workspace':
      _text('Добро пожаловать в ServerDeck');
      _text('Локальных профилей пока нет');
      _text('Создать профиль');
      expect(h.profiles.profiles, isEmpty);
      expect(find.text('ИИ-доступ и Ansible-профили'), findsNothing);
    case '05-server-list':
      _text('Локальные профили');
      _text(h.initialProfile.name);
      _text('${h.initialProfile.address}:22');
      _text('Пользователь SSH: admin');
      _text('Секрет доступа сохранён; содержимое не отображается');
      _text('Подключение к серверу пока недоступно');
      _text('Редактировать профиль');
      expect(find.text('Подключены'), findsNothing);
      expect(find.text('Требуют внимания'), findsNothing);
    case '06-server-overview':
      _text('Подключение к серверу');
      _text('Подключён');
      _text('Система и метрики');
      _contains('synthetic-сервер-例.example');
      _text('Источник: ssh:proc/stat+meminfo+net/dev+df');
      _text('Наблюдение: ${DesignServerFixtures.observedAt} · UTC');
      _text('Получено: ${DesignServerFixtures.observedAt} · UTC');
      _text('Обновить подключение');
      expect(find.textContaining('Устаревшие данные'), findsNothing);
    case '07-profile-create':
      _text('Новый профиль');
      _text('Параметры профиля');
      _text('Подключение по SSH');
      _text('Сохранить');
      _contains('Подключение к серверу выполняется отдельно');
      expect(find.text('Сохранить и подключиться'), findsNothing);
    case '08-profile-edit':
      _text('Редактирование профиля');
      _text('Цель изменения');
      _text('${h.initialProfile.name} · ${h.initialProfile.address}:22');
      _text('Сохранить');
      _text('Сохранить существующий');
    case '09-profile-delete':
      _text('Удаление профиля');
      _text(h.initialProfile.name);
      _text('${h.initialProfile.address}:22');
      _text('Удаляется локальный профиль; сервер не меняется');
      _text('Подтвердить удаление');
    case '10-host-trust':
      _text('Подтвердить SSH-ключ');
      _text('Сверьте отпечаток с ключом вашего сервера.');
      _text(h.trustProfile.name);
      _text('${h.trustProfile.address}:${h.trustProfile.port}');
      _text(DesignServerFixtures.key.fingerprint);
      _text('Действует до ${DesignServerFixtures.expiresAt} · UTC');
      _text('Отмена');
      _text('Подтвердить');
      expect(find.text('Повторить'), findsNothing);
    case '12-credential-input':
      _text('Доступ к серверу');
      _text('Пароль');
      _text('Показать введённый секрет');
      _contains('Существующий секрет не читается в форму');
      final password = find.byKey(const ValueKey('credential-password'));
      expect(password, findsOneWidget);
      expect(
        (password.evaluate().single.widget as TextFormField).controller!.text,
        isEmpty,
      );
    case '13-mutation-conflict':
      _text('Профиль изменён другим окном. Введённые данные сохранены в форме');
      _text('Перечитать профиль');
      _contains('Перечитайте актуальные данные');
      expect(testerStatus(DeckTone.warning), isTrue);
      expect(find.text('Повторить тот же запрос'), findsNothing);
    case '16-install-catalog':
      _text('Сервер для установки');
      _text(h.initialProfile.name);
      _text('Каталог установки');
      _text('Только чистая установка');
      _text('План установки PostgreSQL 16');
      _text('${h.initialProfile.address}:${h.initialProfile.port}');
      expect(find.text('Всё установленное ПО'), findsNothing);
    case '17-recipe-detail':
      _text('Каталог установки');
      _text('PostgreSQL 16');
      _text('16.10');
      _text('Ubuntu 24.04 · amd64 · systemd');
      _text('Максимум подключений');
      _text('PostgreSQL License\nСинтетический пример лицензии');
      _text('Точный рецепт, параметры и условия');
    case '18-install-preflight':
      _text('План готов к подтверждению');
      _text(h.automationServerProfile.name);
      _text('192.0.2.44:2222');
      _text('${DesignAutomationFixtures.expiresAt} (UTC)');
      _text('Изменить конфигурацию: Приветствие сервера');
      _text('Проверить содержимое файла');
      _text('Подтвердить план');
      _text('Запустить');
    case '19-plan-approval':
      _text('Подтвердить этот план?');
      _text(h.automationServerProfile.name);
      _text('192.0.2.44:2222');
      _text(DesignAutomationFixtures.profile().name);
      _text('Изменить конфигурацию: Приветствие сервера');
      _text('${DesignAutomationFixtures.expiresAt} (UTC)');
      _text('Подтвердить план');
    case '22-server-logs':
      _text('Журнал сервера');
      _text('Фильтр журнала');
      _text('Данные получены · записей: 1');
      _text('Источник: journald · UTC');
      _text('Наблюдение: ${DesignServerFixtures.observedAt} · UTC');
      _text(DesignServerFixtures.record()['message'] as String);
      expect(find.text('Пауза'), findsNothing);
      expect(find.text('Продолжить'), findsNothing);
    case '23-log-record':
      _text('Запись журнала');
      final projection = tester
          .widget<ServerLogRecordDialog>(find.byType(ServerLogRecordDialog))
          .recordContext;
      expect(projection.profile, same(h.trustProfile));
      expect(projection.serverId, h.recordLogs['serverId']);
      _text(h.trustProfile.name);
      _text('${h.trustProfile.address}:${h.trustProfile.port}');
      _text('Источник: ${h.recordLogs['source']}');
      final record =
          (h.recordLogs['records'] as List).single as Map<String, Object?>;
      _text('Время записи: ${record['timestamp']} UTC');
      _text('Наблюдение: ${h.recordLogs['observedAt']} UTC');
      _text(record['message'] as String);
      _text('Закрыть');
      expect(find.byType(SelectableText), findsWidgets);
    case '27-job-list':
      _text('Задания сервера');
      _text('Сервер: ${DesignAutomationFixtures.serverId}');
      _text(DesignAutomationFixtures.jobId);
      _text('Выполняется');
      _text('Обновить задания');
      expect(find.text('Выбранное задание'), findsNothing);
    case '28-job-detail':
      _text('Выбранное задание');
      _text(DesignAutomationFixtures.jobId);
      _text('Получено событий: 3. Пропущено в источнике: 0');
      _text('Последние 200 полученных событий');
      _text('План задания');
    case '29-job-unknown':
      _text('Исход не подтверждён');
      _text('Возможны неподтверждённые изменения');
      _text('Уточнить результат');
      expect(find.text('Остановить после текущего шага'), findsNothing);
      expect(find.text('Повторить тот же запрос'), findsNothing);
    case '30-job-cancel':
      _text('Выполняется');
      _text('Остановить после текущего шага');
      _contains('прекращает только ожидание в интерфейсе');
      expect(find.text('Откатить изменения'), findsNothing);
    case '31-recent-operations':
      _text('Недавние подтверждённые операции');
      _contains('До 20 последних подтверждённых записей');
      _text('Изменение настроек подтверждено');
      _text('00000000-0000-4000-8000-000000000099');
      _text('Ревизия пространства');
      _text(DesignServerFixtures.observedAt);
      _text('Обновить список');
    case '32-automation-profiles':
      _text('Ansible-профили');
      _text(DesignAutomationFixtures.profile().name);
      _text('Версия 2');
      expect(find.text('Активные'), findsNothing);
      expect(find.text('Архив'), findsNothing);
    case '33-profile-authoring':
      _text('Новый Ansible-профиль');
      _text('Описание и содержимое');
      _text('Сохранить версию');
      _text('Проверить без сохранения');
      expect(h.body.text, contains('system.motd'));
    case '34-profile-revisions':
      _text('Приветствие сервера · версия 2');
      _text('Сравнение версий 1 и 2');
      _text('/parameters/greeting/default');
      _text('Было: Здравствуйте\nСтало: Привет');
      _text('Выбрать версию');
      _text('Сравнить версии');
      _contains('Новая версия требует отдельного разрешения');
    case '35-plan-parameters':
      _text('Параметры плана');
      _text('Ansible-профиль: Приветствие сервера · версия 2.');
      _text(h.automationServerProfile.name);
      _text('192.0.2.44:2222');
      _text(
        'Проверьте параметры для выбранной версии. Продолжение создаст план; запуск потребует отдельного подтверждения.',
      );
      _text('greeting');
      _text('Привет');
      _text('JSON');
      _text('Продолжить');
      expect(h.jsonInput.text, contains('"greeting": "Привет"'));
      final context = tester
          .widget<AutomationJsonEditorDialog>(
            find.byType(AutomationJsonEditorDialog),
          )
          .contextDetails!;
      expect(context['profileId'], DesignAutomationFixtures.profileId);
      expect(context['revision'], 2);
      expect(
        context['bodyDigest'],
        DesignAutomationFixtures.revision()['digest'],
      );
      expect(context['serverId'], DesignAutomationFixtures.serverId);
    case '36-ai-grants':
      _text('Доступ ИИ рабочего пространства');
      _text('Доступ действует');
      _text('Выданные права');
      _text(h.automationServerProfile.name);
      _text('192.0.2.44:2222');
      _text('2026-10-25T17:00:00.000Z (UTC)');
      _text('Отозвать доступ');
    case '37-ai-grant-form':
      _text('Выдать ИИ доступ через MCP');
      _text(
        'Выдайте только необходимые права на перечисленные серверы. Сохранение выдаст доступ клиенту ИИ на указанный срок.',
      );
      _text('Выдаваемые права');
      _text(
        'Чтение состояния, Чтение журналов, Создание и изменение профилей, Создание планов',
      );
      _text(h.automationServerProfile.name);
      _text('192.0.2.44:2222');
      _text('28800 секунд');
      _text('Продолжить');
    case '38-mcp-client-config':
      _text('Конфигурация MCP');
      _text('Команда');
      _text(r'C:\Synthetic\ServerDeck\mcp.exe');
      _text('Аргументы');
      _text('Скопировать конфигурацию');
      for (final content in [
        find.text('Конфигурация MCP').last,
        find.text(r'C:\Synthetic\ServerDeck\mcp.exe'),
        find.text('Аргументы'),
        find.text(
          '--app-root, C:\\Synthetic\\ServerDeck, --grant-id, ${DesignAutomationFixtures.grantId}',
        ),
      ]) {
        if (host.textScale == 1) {
          expectDesignVisible(tester, content);
        } else {
          await _showText(tester, content);
        }
      }
    case '39-delegations':
      _text('Делегирование «Synthetic client» · версия 2');
      _text(
        'Ansible-профиль: Приветствие сервера · версия 2. Доступ клиента до: 2026-10-25T17:00:00.000Z (UTC).',
      );
      _text(h.automationServerProfile.name);
      _text('192.0.2.44:2222');
      _text(
        'Разрешить запуск только этой неизменной версии в заданных границах параметров. Новые версии потребуют отдельного делегирования.',
      );
      _text('3600 секунд');
      _text('Одно из значений: Привет');
      _text('Продолжить');
      final context = tester
          .widget<AutomationJsonEditorDialog>(
            find.byType(AutomationJsonEditorDialog),
          )
          .contextDetails!;
      expect(context['profileId'], DesignAutomationFixtures.profileId);
      expect(context['revision'], 2);
      expect(
        context['bodyDigest'],
        DesignAutomationFixtures.revision()['digest'],
      );
      expect(context['serverId'], DesignAutomationFixtures.serverId);
      expect(context['grantId'], DesignAutomationFixtures.grantId);
    case '40-executor-binding':
      _text('Подтвердить исполнитель');
      _text(
        'Привязать исполнитель к этому серверу и его проверенному SSH-ключу?',
      );
      _text(h.trustProfile.name);
      _text('${h.trustProfile.address}:${h.trustProfile.port}');
      _text('Технические сведения');
      _text(DesignServerFixtures.key.fingerprint);
      _text(
        'Подтверждение действует до ${DesignServerFixtures.expiresAt} · UTC',
      );
      _text('Отмена');
      _text('Привязать');
    case '84-settings':
      _text('Оформление и рабочий контекст');
      _text('Тема: тёмная');
      _text('Уменьшение анимации: включено');
      _text('${h.initialProfile.name} · ${h.initialProfile.address}:22');
      _text('Экспорт приватных данных недоступен');
      _text('Изменить настройки');
    case '85-settings-form':
      _text('Изменение настроек');
      _text('Оформление');
      _text('Рабочий контекст');
      _text('Сохранить настройки');
      _text(h.initialProfile.name);
    case '94-plan-invalidated':
      _text('План заблокирован');
      _text(h.automationServerProfile.name);
      _text('192.0.2.44:2222');
      _text('Обновить план');
      expect(find.text('Запустить'), findsNothing);
      expect(find.text('Подтвердить план'), findsNothing);
    default:
      fail('Missing baseline acceptance for ${host.binding.screenId}');
  }
  // All origins use at least one meaningful Deck component in their own body.
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is DeckSurface ||
          widget is DeckDialogLayout ||
          widget is DeckFormSection ||
          widget is DeckKeyValue,
    ),
    findsWidgets,
  );
}

bool testerStatus(DeckTone tone) => find
    .byWidgetPredicate((widget) => widget is DeckStatus && widget.tone == tone)
    .evaluate()
    .isNotEmpty;

Future<void> _activateByKeyboard(WidgetTester tester, String label) async {
  final button = designButton(label);
  await tester.ensureVisible(button);
  final focus = find.descendant(of: button, matching: find.byType(Focus)).first;
  Element descendant = tester.element(focus);
  // Focus's node may be internally owned. A child below its inherited scope
  // exposes that actual node without adding a test-only focus wrapper.
  for (var depth = 0; depth < 2; depth++) {
    descendant.visitChildren((child) => descendant = child);
  }
  Focus.of(descendant).requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

Future<void> _assertAction(WidgetTester tester, DesignFixtureHost host) async {
  final h = host.harness;
  final (String, String)? action = switch (host.binding.screenId) {
    '02-service-unavailable' ||
    '03-storage-blocked' => ('Повторить запуск', 'retry'),
    '06-server-overview' => ('Обновить подключение', 'refreshConnection'),
    '13-mutation-conflict' => ('Перечитать профиль', 'reload'),
    '16-install-catalog' ||
    '17-recipe-detail' => ('План установки PostgreSQL 16', 'createRecipePlan'),
    '18-install-preflight' => ('Подтвердить план', 'approve'),
    '19-plan-approval' => ('Подтвердить план', 'approve'),
    '22-server-logs' => ('Получить журнал', 'readLogs'),
    '23-log-record' => ('Закрыть', 'closeRecord'),
    '27-job-list' => ('Обновить задания', 'refreshJobs'),
    '28-job-detail' => ('План задания', 'showPlan'),
    '29-job-unknown' => ('Уточнить результат', 'reconcileJob'),
    '30-job-cancel' => ('Остановить после текущего шага', 'cancelJob'),
    '33-profile-authoring' => ('Проверить без сохранения', 'validateVersion'),
    '34-profile-revisions' => ('Сравнить версии', 'compare'),
    '35-plan-parameters' ||
    '37-ai-grant-form' ||
    '39-delegations' => ('Продолжить', 'continueEditor'),
    '36-ai-grants' => ('Отозвать доступ', 'revokeGrant'),
    '38-mcp-client-config' => ('Скопировать конфигурацию', 'copyConfiguration'),
    '94-plan-invalidated' => ('Обновить план', 'refreshPlan'),
    _ => null,
  };
  if (action != null) {
    await _activateByKeyboard(tester, action.$1);
    expect(h.counters[action.$2], 1);
    expect(
      h.counters.values.values.fold<int>(0, (total, value) => total + value),
      1,
    );
    return;
  }
  switch (host.binding.screenId) {
    case '04-empty-workspace':
      await _activateByKeyboard(tester, 'Создать профиль');
      expect(find.byType(ProfileForm), findsOneWidget);
    case '05-server-list':
      await _activateByKeyboard(tester, 'Редактировать профиль');
      expect(find.byType(ProfileForm), findsOneWidget);
    case '07-profile-create':
      await _activateByKeyboard(tester, 'Сохранить');
      _text('Проверьте значение поля');
      expect(h.client.mutations, isEmpty);
    case '08-profile-edit':
      await _activateByKeyboard(tester, 'Сохранить');
      expect(h.client.mutations, hasLength(1));
      _text('Профиль изменён другим окном. Введённые данные сохранены в форме');
    case '09-profile-delete':
      await _activateByKeyboard(tester, 'Подтвердить удаление');
      expect(h.client.mutations, hasLength(1));
      _text('Профиль изменён другим окном. Перечитайте его перед удалением');
    case '12-credential-input':
      await tester.enterText(
        find.byKey(const ValueKey('credential-password')),
        'synthetic password',
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      final input = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('credential-password')),
          matching: find.byType(TextField),
        ),
      );
      expect(input.obscureText, isFalse);
      expect(h.client.mutations, isEmpty);
    case '31-recent-operations':
      final before = h.client.reads.length;
      await _activateByKeyboard(tester, 'Обновить список');
      expect(h.client.reads.length, before + 1);
      expect(h.client.mutations, isEmpty);
      _text('Изменение настроек подтверждено');
    case '32-automation-profiles':
      final surface = find
          .byWidgetPredicate(
            (widget) => widget is DeckSurface && widget.onTap != null,
          )
          .first;
      await tester.ensureVisible(surface);
      await tester.tap(surface);
      await tester.pump();
      expect(h.counters['selectAutomationProfile'], 1);
    case '84-settings':
      await _activateByKeyboard(tester, 'Изменить настройки');
      expect(find.byType(SettingsForm), findsOneWidget);
    case '85-settings-form':
      await _activateByKeyboard(tester, 'Сохранить настройки');
      expect(h.client.mutations, hasLength(1));
      _text(
        'Настройки изменены другим окном. Введённые данные сохранены в форме',
      );
    case '10-host-trust':
      await _activateByKeyboard(tester, 'Отмена');
      expect(h.counters['cancelTrust'], 1);
      expect(h.counters['confirmTrust'], 0);
      await _activateByKeyboard(tester, 'Подтвердить');
      expect(h.counters['confirmTrust'], 1);
      expect(h.counters['cancelTrust'], 1);
    case '40-executor-binding':
      await _activateByKeyboard(tester, 'Отмена');
      expect(h.counters['cancelExecutor'], 1);
      expect(h.counters['confirmExecutor'], 0);
      await _activateByKeyboard(tester, 'Привязать');
      expect(h.counters['confirmExecutor'], 1);
      expect(h.counters['cancelExecutor'], 1);
    case '01-startup':
      // Startup has no action while its owner's readiness attempt is pending.
      expect(h.counters.values, isEmpty);
    default:
      fail('Missing action intent for ${host.binding.screenId}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignFonts);
  for (final binding in designBindings) {
    for (final dimensions in designFrames) {
      final frame = Size(dimensions.width, dimensions.height);
      for (final theme in const [ThemeMode.light, ThemeMode.dark]) {
        for (final scale in designTextScales) {
          testWidgets(
            '${binding.screenId} matrix ${frame.width.toInt()} ${theme.name} ${scale * 100}%',
            (tester) async {
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final host = await mountDesignFixture(
                tester,
                binding,
                frame: frame,
                theme: theme,
                textScale: scale,
              );
              try {
                final target = _shellTarget();
                if (target.evaluate().isNotEmpty) {
                  await Scrollable.ensureVisible(tester.element(target));
                  await tester.pump();
                  expectDesignVisible(tester, target);
                }
                await _assertOrigin(tester, host);
                if (binding.screenId == '06-server-overview') {
                  await revealDesignGraphs(tester);
                  expectDesignVisible(
                    tester,
                    find.byKey(const ValueKey('metrics-history-plots')),
                  );
                  for (final context in [
                    'Источник: ssh:proc/stat+meminfo+net/dev+df',
                    'Наблюдение: ${DesignServerFixtures.observedAt} · UTC',
                    'Получено: ${DesignServerFixtures.observedAt} · UTC',
                  ]) {
                    final content = find.descendant(
                      of: find.byType(MetricsHistory),
                      matching: find.text(context),
                    );
                    if (scale == 1) {
                      expectDesignVisible(tester, content);
                    } else {
                      await _showText(tester, content);
                    }
                  }
                }
                expect(tester.takeException(), isNull);
                expect(host.harness.counters.values, isEmpty);
                final requests = host.harness.client.mutations.length;
                final reads = host.harness.client.reads.length;
                final refreshes = host.harness.client.refreshes;
                final profileController = host.harness.profiles;
                final brightness = tester.element(find.byType(Scaffold).first);
                expect(
                  Theme.of(brightness).extension<BrandColors>(),
                  isNotNull,
                );
                await host.setTheme(
                  tester,
                  theme == ThemeMode.light ? ThemeMode.dark : ThemeMode.light,
                );
                await host.setTheme(tester, theme);
                expect(host.harness.profiles, same(profileController));
                expect(host.harness.client.mutations.length, requests);
                expect(host.harness.client.reads.length, reads);
                expect(host.harness.client.refreshes, refreshes);
                expect(host.harness.counters.values, isEmpty);
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await tester.pump();
                await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
                await tester.pump();
                expect(host.harness.client.mutations.length, requests);
                expect(host.harness.counters.values, isEmpty);
                await _assertAction(tester, host);
                expect(tester.takeException(), isNull);
              } finally {
                await host.close(tester);
              }
            },
          );
        }
      }
    }
  }
}
