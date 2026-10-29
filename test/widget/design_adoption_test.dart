import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/automation/automation_forms.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/settings/settings_form.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/brand_assets.dart';
import 'package:serverdeck/software/software_panel.dart';
import 'package:serverdeck/ui/deck_icon.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck/servers/server_compositions.dart';

import '../support/design_host.dart';
import '../support/design_scenarios.dart';
import '../support/base_design_bindings.dart';

void _text(String value) =>
    expect(find.text(value), findsWidgets, reason: value);
void _contains(String value) =>
    expect(find.textContaining(value), findsWidgets, reason: value);

void _recordStatus(
  WidgetTester tester,
  String label,
  String symbol,
  String role,
) {
  final text = find.text(label).first;
  final row = find.ancestor(of: text, matching: find.byType(Row)).first;
  final marker = find.descendant(of: row, matching: find.text(symbol));
  expect(marker, findsOneWidget);
  expect(tester.widget<Text>(marker).style!.fontSize, 13);
  expect(tester.widget<Text>(marker).style!.height, 20 / 13);
  final context = tester.element(text);
  expect(DefaultTextStyle.of(context).style.color, deckColors(context)[role]);
}

void _fullParagraph(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  // Selection boxes include font overhang; intrinsic height detects lost lines.
  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(
      paragraph.getMinIntrinsicHeight(paragraph.size.width) - .01,
    ),
  );
  for (final box in paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: paragraph.text.toPlainText().length,
    ),
  )) {
    expect(box.left, greaterThanOrEqualTo(-.01));
    expect(box.right, lessThanOrEqualTo(paragraph.size.width + .01));
  }
}

void _profileMetricsGeometry(WidgetTester tester, DesignFixtureHost host) {
  final card = find.byKey(ValueKey(host.harness.initialProfile.id));
  Finder inside(Finder f) => find.descendant(of: card, matching: f);
  final cpu = inside(find.text('CPU'));
  final grid = find.ancestor(of: cpu, matching: find.byType(Row)).first;
  final metrics = find.ancestor(of: grid, matching: find.byType(Column)).first;
  final identity = inside(find.byType(IntrinsicHeight)).first;
  final status = inside(find.byType(DeckStatus)).first;
  final state = find.ancestor(of: status, matching: find.byType(Wrap)).first;
  final system = inside(find.text('Профиль сохранён · Нет данных о системе'));
  final timestamp = inside(find.text('Измерения появятся после подключения'));
  final actions = inside(find.byType(DeckActions)).first;
  final context = tester.element(card);
  final width = MediaQuery.sizeOf(context).width;
  final phone = width <= 520;
  final compact =
      width <= 760 || MediaQuery.textScalerOf(context).scale(14) >= 28;
  final systemStyle = tester.widget<Text>(system).style!;
  expect(systemStyle.fontSize, 12);
  expect(systemStyle.height, 20 / 12);
  expect(tester.widget<Text>(timestamp).style!.height, 18 / 12);
  expect(
    tester.getRect(timestamp).top - tester.getRect(grid).bottom,
    closeTo(14, .01),
  );
  expect(
    tester.getRect(state).top - tester.getRect(identity).bottom,
    closeTo(compact && !phone ? 16 : 12, .01),
  );
  expect(
    tester.getRect(system).top - tester.getRect(state).bottom,
    closeTo(compact ? (phone ? 12 : 16) : 8, .01),
  );
  if (compact) {
    expect(
      tester.getRect(metrics).top - tester.getRect(system).bottom,
      closeTo(phone ? 18 : 16, .01),
    );
    expect(
      tester.getRect(actions).top - tester.getRect(metrics).bottom,
      closeTo(phone ? 14 : 16, .01),
    );
  } else {
    final info = find
        .ancestor(of: identity, matching: find.byType(Column))
        .first;
    expect(
      tester.getRect(metrics).width,
      closeTo(width <= 1060 ? 270 : 300, .01),
    );
    expect(
      tester.getRect(metrics).left - tester.getRect(info).right,
      closeTo(width <= 1060 ? 16 : 20, .01),
    );
  }
  for (final label in ['CPU', 'RAM', 'Диск /']) {
    final title = inside(find.text(label));
    final column = find
        .ancestor(of: title, matching: find.byType(Column))
        .first;
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: column, matching: find.byType(Text)),
        )
        .toList();
    expect(texts[0].style!.height, 20 / 12);
    expect(texts[1].style!.height, 20 / 12);
    expect(texts[1].style!.fontFamily, BrandAssets.monoFont);
    expect(
      tester.getRect(find.byWidget(texts[1])).top -
          tester.getRect(title).bottom,
      closeTo(4, .01),
    );
    final placeholder = find.descendant(
      of: column,
      matching: find.text('Нет данных'),
    );
    expect(tester.widget<Text>(placeholder).style!.height, 18 / 12);
    expect(tester.widget<Text>(placeholder).textAlign, TextAlign.center);
    final box = find
        .ancestor(of: placeholder, matching: find.byType(Container))
        .first;
    expect(tester.widget<Container>(box).alignment, Alignment.center);
    expect(tester.getRect(box).height, greaterThanOrEqualTo(25));
    _fullParagraph(tester, placeholder);
  }
}

void _draftField(WidgetTester tester, String label, String value) {
  final field = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        (widget.decoration?.labelText == label ||
            widget.key == ValueKey('automation-field-$label')),
  );
  expect(field, findsOneWidget, reason: label);
  expect(tester.widget<TextField>(field).controller!.text, value);
}

void _formValue(WidgetTester tester, String label, String value) {
  final field = find.byWidgetPredicate(
    (widget) => widget is AutomationFormValue && widget.label == label,
  );
  expect(field, findsOneWidget, reason: label);
  expect(tester.widget<AutomationFormValue>(field).value, value);
}

void _contextPair(WidgetTester tester, String firstLabel, String secondLabel) {
  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is AutomationFormValue && w.label == label,
  );
  final first = field(firstLabel), second = field(secondLabel);
  final a = tester.getRect(first), b = tester.getRect(second);
  final context = tester.element(first);
  final two =
      MediaQuery.sizeOf(context).width > 520 &&
      MediaQuery.textScalerOf(context).scale(14) < 27;
  if (two) {
    expect(a.top, closeTo(b.top, .01));
    expect(b.left - a.right, closeTo(14, .01));
    expect(a.width, closeTo(b.width, .01));
  } else {
    expect(b.top, greaterThan(a.bottom));
    expect(a.left, closeTo(b.left, .01));
  }
  for (final target in [first, second]) {
    expect(
      find.descendant(
        of: target,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.isRequired == true,
        ),
      ),
      findsOneWidget,
    );
    final input = tester.widget<TextField>(
      find.descendant(of: target, matching: find.byType(TextField)),
    );
    expect(input.readOnly, isTrue);
    expect(input.onChanged, isNull);
    expect(input.onSubmitted, isNull);
  }
}

Future<Map<String, Object?>> _readonlyPayload(
  WidgetTester tester,
  String title,
) async {
  final view = find.byWidgetPredicate(
    (widget) => widget is AutomationJsonView && widget.title == title,
  );
  final heading = find.descendant(of: view, matching: find.text(title));
  await _showText(tester, heading);
  await tester.tap(heading);
  await tester.pumpAndSettle();
  final text = find.descendant(of: view, matching: find.byType(SelectableText));
  expect(text, findsOneWidget);
  final rendered = tester.widget<SelectableText>(text);
  expect(rendered.enableInteractiveSelection, isTrue);
  return (jsonDecode(rendered.data!) as Map).cast<String, Object?>();
}

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
      _text('Запуск рабочего пространства');
      _text('Запуск локальной службы');
      _text('Ожидаем результат запуска.');
      _text('Состояние и следующие шаги');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Дождаться запуска'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Повторить запуск'), findsNothing);
    case '02-service-unavailable':
      _text('Локальная служба недоступна');
      _text('Не удалось связаться с локальной службой.');
      _text('Состояние и следующие шаги');
      _text('Повторить запуск');
      expect(
        tester.widget<ServerStatusBody>(find.byType(ServerStatusBody)).tone,
        DeckTone.unavailable,
      );
      expect(find.text('Не подключён'), findsNothing);
    case '03-storage-blocked':
      _text('Доступ к хранилищу заблокирован');
      _text('Локальное хранилище заблокировано');
      _contains('Требуется проверка локального пространства');
      _text('Исходные данные сохраняются');
      _text('Повторить запуск');
      expect(
        tester.widget<ServerStatusBody>(find.byType(ServerStatusBody)).tone,
        DeckTone.error,
      );
      expect(find.textContaining('Сбросить'), findsNothing);
      expect(find.textContaining('plaintext'), findsNothing);
    case '04-empty-workspace':
      _text('Первый запуск');
      _text('Все серверы.\nОдин центр управления.');
      _text('Добавить сервер');
      _text('Настроить ИИ-доступ');
      expect(h.profiles.profiles, isEmpty);
      final headerAdd = find.widgetWithText(OutlinedButton, 'Добавить сервер');
      final headerAi = find
          .widgetWithText(OutlinedButton, 'Настроить ИИ-доступ')
          .first;
      if (MediaQuery.sizeOf(tester.element(headerAdd)).width > 960 &&
          MediaQuery.textScalerOf(tester.element(headerAdd)).scale(13) == 13) {
        expect(
          tester.getRect(headerAdd).top,
          closeTo(tester.getRect(headerAi).top, .01),
        );
        expect(
          tester.getRect(headerAi).left,
          greaterThan(tester.getRect(headerAdd).left),
        );
      }
      final welcomeAdd = find.widgetWithText(FilledButton, 'Добавить сервер');
      final welcomeAi = find
          .widgetWithText(OutlinedButton, 'Настроить ИИ-доступ')
          .last;
      final welcomeParagraph = tester.getRect(
        find.text(
          'Добавьте первое подключение, чтобы видеть состояние системы, ресурсы и программное обеспечение.',
        ),
      );
      final nativeAdd = tester.getRect(welcomeAdd),
          nativeAi = tester.getRect(welcomeAi);
      final phoneWelcome =
          MediaQuery.sizeOf(tester.element(welcomeAdd)).width <= 520;
      final welcomeInset = phoneWelcome ? 0.0 : 4.0;
      expect(nativeAdd.height, greaterThanOrEqualTo(44));
      expect(nativeAi.height, greaterThanOrEqualTo(44));
      expect(
        nativeAdd.left + welcomeInset,
        closeTo(welcomeParagraph.left, .01),
      );
      expect(
        nativeAdd.top + welcomeInset - welcomeParagraph.bottom,
        closeTo(24, .01),
      );
      if (phoneWelcome) {
        expect(nativeAi.left, closeTo(nativeAdd.left, .01));
        expect(nativeAi.width, closeTo(nativeAdd.width, .01));
      }
    case '05-server-list':
      _profileMetricsGeometry(tester, host);
      _text('Серверы');
      _text(h.initialProfile.name);
      _text('${h.initialProfile.address}:22');
      expect(find.text('Все серверы'), findsNothing);
      expect(
        find.byKey(const ValueKey('profile-filter-group')),
        findsOneWidget,
      );
      _text('Открыть сервер');
      _text('Изменить');
      expect(h.profiles.selected?.id, h.initialProfile.id);
      expect(
        tester
            .widget<DeckSurface>(find.byKey(ValueKey(h.initialProfile.id)))
            .selected,
        isFalse,
        reason: 'No matching connection observation may be inferred from local selection',
      );
      final cardFinder = find.byKey(ValueKey(h.initialProfile.id));
      final card = tester.widget<DeckSurface>(cardFinder);
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final padding = width <= 520
          ? 16.0
          : width <= 1060
          ? 18.0
          : 20.0;
      expect(card.padding, EdgeInsets.all(padding));
      final cardRect = tester.getRect(cardFinder);
      final state = find
          .descendant(of: cardFinder, matching: find.byType(DeckStatus))
          .first;
      expect(
        tester.getRect(state).left - cardRect.left,
        closeTo(padding + 1 + (width <= 520 ? 48 : 0), .01),
      );
      final statusLabel = find.descendant(
        of: state,
        matching: find.text('Состояние подключения не получено'),
      );
      final statusStyle = tester.widget<Text>(statusLabel).style!;
      expect(statusStyle.fontSize, 12);
      expect(statusStyle.height, (width <= 520 ? 20 : 18) / 12);
      final statusSymbol = find.descendant(of: state, matching: find.text('○'));
      expect(tester.widget<Text>(statusSymbol).style!.fontSize, 13);
      for (final placeholder
          in find
              .descendant(of: cardFinder, matching: find.text('Нет данных'))
              .evaluate()) {
        _fullParagraph(tester, find.byWidget(placeholder.widget));
      }
      final open = tester.getRect(
        find.widgetWithText(FilledButton, 'Открыть сервер'),
      );
      expect(
        open.left + (width <= 520 ? 0 : 4) - cardRect.left,
        closeTo(padding + 1, .01),
      );
      for (final tag in h.initialProfile.tags) {
        final tagFinder = find.descendant(
          of: cardFinder,
          matching: find.text(tag),
        );
        final style = tester.widget<Text>(tagFinder).style!;
        expect(style.fontFamily, BrandAssets.monoFont);
        expect(style.fontSize, 12);
        expect(style.height, 18 / 12);
        final tagBox = tester.widget<Container>(
          find.ancestor(of: tagFinder, matching: find.byType(Container)).first,
        );
        expect(tagBox.padding, const EdgeInsets.symmetric(horizontal: 5));
        final decoration = tagBox.decoration! as BoxDecoration;
        expect(decoration.color, isNull);
        expect((decoration.border! as Border).top.width, 1);
      }
    case '06-server-overview':
      final identity = tester.widget<ServerPageFrame>(
        find.byType(ServerPageFrame),
      );
      final name = find.text(identity.profile.name);
      final nameStyle = tester.widget<Text>(name).style!;
      expect(nameStyle.fontFamily, BrandAssets.monoFont);
      expect(nameStyle.fontWeight, FontWeight.w400);
      expect(nameStyle.fontSize, 20);
      expect(nameStyle.height, 28 / 20);
      final phoneIdentity =
          tester.view.physicalSize.width / tester.view.devicePixelRatio <= 520;
      final emblem = find.byWidgetPredicate(
        (w) =>
            w is DeckIcon &&
            w.name == 'server' &&
            w.size == (phoneIdentity ? 23 : 26),
      );
      expect(emblem, findsOneWidget);
      expect(
        tester.getSize(
          find.ancestor(of: emblem, matching: find.byType(Container)).first,
        ),
        Size.square(phoneIdentity ? 42 : 48),
      );
      expect(
        tester.widget<DeckIcon>(emblem).color,
        deckColors(tester.element(emblem))['accent'],
      );
      final emblemBox = find
          .ancestor(of: emblem, matching: find.byType(Container))
          .first;
      expect(
        tester.getRect(name).left - tester.getRect(emblemBox).right,
        closeTo(phoneIdentity ? 10 : 14, .01),
      );
      final identityRow = find
          .ancestor(of: emblem, matching: find.byType(Row))
          .first;
      expect(
        tester.getRect(find.byType(DeckTabs)).top -
            tester.getRect(identityRow).bottom,
        closeTo(phoneIdentity ? 16 : 20, .01),
      );
      _text('Обзор сервера');
      _text('Сведения о сервере');
      _text('Процессор');
      _text('Подключён');
      for (final label in [
        'Сервер',
        'Система',
        'Ядро',
        'CPU',
        'Память',
        'Корневой диск',
        'Свежесть',
        'Устаревание',
      ]) {
        _text(label);
      }
      for (final axis in ['100', '75', '50', '25', '0', 'CPU, % · UTC']) {
        _text(axis);
      }
      _text('Источник: ssh:proc/stat+meminfo+net/dev+df');
      _text('Наблюдение: ${DesignServerFixtures.observedAt} · UTC');
      _text('Получено: ${DesignServerFixtures.observedAt} · UTC');
      _text('Обновить данные');
      expect(find.textContaining('Устаревшие данные'), findsNothing);
    case '07-profile-create':
      _text('Добавление сервера');
      _text('Параметры подключения');
      _text('Порт SSH *');
      _text('Пользователь SSH *');
      _text('Сохранить без подключения');
      _text('Сохранить и подключить');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Сохранить и подключить'),
            )
            .onPressed,
        isNull,
      );
    case '08-profile-edit':
      _text('Редактирование профиля');
      _text('Сервер *');
      _text('${h.initialProfile.name} · ${h.initialProfile.address}:22');
      _text('Сохранить');
      _text('Сохранить существующий');
    case '09-profile-delete':
      _text('Удаление локального профиля');
      _text('${h.initialProfile.name} · ${h.initialProfile.address}:22');
      _text('Параметры и условия');
      _text('Последствия');
      _text('Проверьте цель, последствия и условия выбранного действия');
      _text('Удаляется локальный профиль; сервер не меняется');
      _text('Удалить профиль');
      expect(find.byType(CheckboxListTile), findsOneWidget);
      final deletionPanels = find.byType(DeckPanel);
      expect(deletionPanels, findsNWidgets(2));
      final parameters = tester.getRect(deletionPanels.at(0));
      final consequences = tester.getRect(deletionPanels.at(1));
      expect(consequences.left, closeTo(parameters.left, .01));
      expect(consequences.width, closeTo(parameters.width, .01));
      expect(
        consequences.top - parameters.bottom,
        closeTo(
          tester.view.physicalSize.width / tester.view.devicePixelRatio <= 520
              ? 16
              : 20,
          .01,
        ),
      );
    case '10-host-trust':
      _text('Проверьте цель, последствия и условия выбранного действия');
      _text('Подтверждение SSH-ключа');
      _text('Сверьте отпечаток с ключом вашего сервера');
      _text('Параметры и условия');
      _text('Последствия');
      _text(
        '${h.trustProfile.name} · ${h.trustProfile.address}:${h.trustProfile.port}',
      );
      _text(DesignServerFixtures.key.fingerprint);
      _text('${DesignServerFixtures.expiresAt} · UTC');
      _text('Отмена');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Подтвердить ключ'),
            )
            .onPressed,
        isNotNull,
      );
    case '11-host-key-changed':
      _text('Состояние и следующие доступные действия');
      _text('SSH-ключ изменился');
      _text('Ключ сервера отличается от сохранённого');
      _text(DesignServerFixtures.key.fingerprint);
      _text('Новый отпечаток не получен. Выполните проверку ключа.');
      _text('Чтение и запись остановлены до решения владельца');
      _text('Пересмотреть доверие');
      _text('Закрыть');
      final changed = tester.widget<ServerChangedKeySection>(
        find.byType(ServerChangedKeySection),
      );
      expect(changed.profile, same(h.trustProfile));
      expect(changed.previousFingerprint, DesignServerFixtures.key.fingerprint);
      expect(changed.currentFingerprint, isNull);
      expect(find.byType(ServerResourceCards), findsNothing);
      expect(find.text('Подключить'), findsNothing);
      expect(find.text('Подтвердить ключ'), findsNothing);
    case '12-credential-input':
      _text('Настройка доступа');
      _text('Цель *');
      _text('Доступ *');
      _text('Файл ключа');
      _text('Приватный ключ *');
      _text('Passphrase');
      _text('Хранение');
      _text('Показать введённый секрет');
      final privateKey = find.byKey(const ValueKey('credential-private-key'));
      expect(privateKey, findsOneWidget);
      expect(
        tester.widget<TextFormField>(privateKey).controller!.text,
        isEmpty,
      );
    case '13-mutation-conflict':
      _text('Состояние и следующие доступные действия');
      _text(
        'Настройки изменены другим окном. Введённые данные сохранены в форме',
      );
      _text('Перечитать настройки');
      final reload = find.widgetWithText(FilledButton, 'Перечитать настройки');
      final close = find.widgetWithText(OutlinedButton, 'Закрыть');
      expect(reload, findsOneWidget);
      final flow = find
          .ancestor(of: reload, matching: find.byType(DeckActions))
          .first;
      expect(find.descendant(of: flow, matching: close), findsOneWidget);
      if (MediaQuery.sizeOf(tester.element(reload)).width >= 800 &&
          MediaQuery.textScalerOf(tester.element(reload)).scale(13) == 13) {
        expect(
          tester.getRect(reload).top,
          closeTo(tester.getRect(close).top, .01),
        );
      }
      _contains('Перечитайте данные и проверьте изменения');
      final status = tester.widget<ServerStatusBody>(
        find.byType(ServerStatusBody),
      );
      expect(status.tone, DeckTone.warning);
      expect(status.facts['Операция'], 'Изменение настроек');
      expect(status.facts['Состояние'], 'Конфликт ревизии');
      expect(find.text('Повторить тот же запрос'), findsNothing);
    case '16-install-catalog':
      final scope = find.descendant(
        of: find.byType(SoftwareServerSelector),
        matching: find.text('Область просмотра'),
      );
      final scopeHeader = find
          .ancestor(
            of: scope,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).border != null,
            ),
          )
          .first;
      final viewport =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final textScale =
          MediaQuery.textScalerOf(tester.element(scope)).scale(14) / 14;
      if (textScale == 1) {
        expect(
          tester.getSize(scopeHeader).height,
          closeTo(viewport <= 520 ? 51 : 53, .01),
        );
        if (viewport == 800) {
          final page = tester.widget<DeckPage>(find.byType(DeckPage));
          final first = tester.getRect(find.byWidget(page.actions[0]));
          final second = tester.getRect(find.byWidget(page.actions[1]));
          final description = tester.getRect(find.text(page.description!));
          expect(first.top, closeTo(second.top, .01));
          expect(first.top + 4 - description.bottom, closeTo(14, .01));
          expect(first.left + 4, closeTo(92, .01));
        }
      }
      _text('Сервер для установки');
      _text(
        '${h.automationServerProfile.name} · ${h.automationServerProfile.address}:${h.automationServerProfile.port}',
      );
      _text('Каталог установки');
      _text('Каталог');
      _text('Планы установки');
      _text('PostgreSQL 16');
      _text('16.10');
      _text('Нужна проверка');
      _text('Время снимка не предоставлено');
      _text('Выбрать программу');
      _text('Поиск по данным экрана');
      expect(
        tester
            .widget<AutomationRecipesSection>(
              find.byType(AutomationRecipesSection),
            )
            .catalog,
        DesignAutomationFixtures.catalog(),
      );
      expect(find.text('Всё установленное ПО'), findsNothing);
    case '17-recipe-detail':
      _text('Рецепт установки');
      _text('PostgreSQL 16');
      _text('16.10');
      _text('Ubuntu 24.04 · amd64 · systemd');
      _text('Сведения');
      _contains('Только чистая установка; существующие данные');
      expect(find.text('Выбрать программу'), findsNothing);
      final recipe = await _readonlyPayload(
        tester,
        'Лицензии, начальные настройки и точные условия',
      );
      expect(recipe, DesignAutomationFixtures.recipe());
      expect((recipe['initialSettings'] as Map)['max_connections'], 100);
      expect(recipe['licenseNotices'], [
        'PostgreSQL License\nСинтетический пример лицензии',
      ]);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Проверить готовность'),
            )
            .onPressed,
        isNull,
      );
      _text('Создать план');
    case '18-install-preflight':
      _text('План готов к подтверждению');
      _text('${h.automationServerProfile.name} · 192.0.2.44:2222');
      _text('${DesignAutomationFixtures.expiresAt} (UTC)');
      _text('Изменить конфигурацию: Приветствие сервера');
      _text('Проверить содержимое файла');
      _text('Просмотреть план');
      final refresh = find.widgetWithText(OutlinedButton, 'Обновить проверку');
      expect(tester.widget<OutlinedButton>(refresh).onPressed, isNull);
      expect(find.text('Подтвердить план'), findsNothing);
      expect(find.text('Запустить'), findsNothing);
    case '19-plan-approval':
      _text('Подтверждение плана');
      _text('${h.automationServerProfile.name} · 192.0.2.44:2222');
      _text('${DesignAutomationFixtures.profile().name} · версия 2');
      _text('Изменить конфигурацию: Приветствие сервера');
      _text('${DesignAutomationFixtures.expiresAt} (UTC)');
      _text('Подтвердить план');
      expect(
        tester
            .widget<AutomationPlanDecisionDialog>(
              find.byType(AutomationPlanDecisionDialog),
            )
            .asPage,
        isTrue,
      );
      expect(find.text('Запустить'), findsNothing);
    case '22-server-logs':
      _text('Журнал сервера');
      final search = find.byKey(const ValueKey('server-log-search'));
      expect(tester.widget<TextField>(search).controller, same(h.filter));
      expect(
        tester.widget<TextField>(search).decoration?.hintText,
        'Поиск в сообщениях',
      );
      _text('Весь сервер');
      _text('Выбранная служба');
      _text('Получено 1 записей');
      _text('Данные получены · UTC');
      _text('journald');
      _text('UTC');
      _text('Наблюдение: ${DesignServerFixtures.observedAt} · UTC');
      _text(DesignServerFixtures.record()['message'] as String);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Пауза'),
            )
            .onPressed,
        isNull,
      );
      _contains('Пауза, период и приоритет пока недоступны');
    case '23-log-record':
      _text('Детали записи журнала');
      _text('Сведения');
      _text('Сообщение');
      final projection = tester
          .widget<ServerLogRecordDialog>(find.byType(ServerLogRecordDialog))
          .recordContext;
      expect(projection.profile, same(h.trustProfile));
      expect(projection.serverId, h.recordLogs['serverId']);
      _text(h.trustProfile.name);
      _text('${h.trustProfile.address}:${h.trustProfile.port}');
      _text('${h.recordLogs['source']}');
      final record =
          (h.recordLogs['records'] as List).single as Map<String, Object?>;
      _text('${record['timestamp']} UTC');
      _text('${h.recordLogs['observedAt']} UTC');
      _text(record['message'] as String);
      _text('Скопировать запись');
      _text('Закрыть');
      expect(find.byType(SelectableText), findsWidgets);
    case '27-job-list':
      _text('Область просмотра');
      _text('Область');
      _text(DesignAutomationFixtures.jobId);
      _text('Выполняется');
      _text('Обновить');
      expect(find.text('Выбранное задание'), findsNothing);
    case '28-job-detail':
      _text('Ход задания');
      _text(DesignAutomationFixtures.jobId);
      _text('Получено событий: 3. Пропущено в источнике: 0');
      _text('Ход выполнения');
      _text('Контекст задания');
      _text('План задания');
      _text('Состояние: Выполняется');
      final jobPanels = find.descendant(
        of: find.byType(AutomationJobsSection),
        matching: find.byType(DeckPanel),
      );
      final heroPanel = tester.getRect(jobPanels.at(0));
      final timelinePanel = tester.getRect(jobPanels.at(1));
      final frameWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final largeText =
          MediaQuery.textScalerOf(tester.element(jobPanels.first)).scale(14) >=
          27;
      expect(
        timelinePanel.top - heroPanel.bottom,
        closeTo(frameWidth <= 520 ? 16 : 20, .01),
      );
      final contextPanel = tester.getRect(
        find
            .ancestor(
              of: find.text('Контекст задания'),
              matching: find.byType(DeckPanel),
            )
            .first,
      );
      if (frameWidth > 760 && !largeText) {
        expect(
          contextPanel.left - timelinePanel.right,
          closeTo(frameWidth <= 960 ? 14 : 20, .01),
        );
      } else {
        expect(
          contextPanel.top - timelinePanel.bottom,
          closeTo(frameWidth <= 520 ? 16 : 20, .01),
        );
      }
      final jobs = tester.widget<AutomationJobsSection>(
        find.byType(AutomationJobsSection),
      );
      for (var i = 0; i < jobs.events.length; i++) {
        final marker = find.byKey(ValueKey('job-timeline-marker-$i'));
        final size = tester.getSize(marker);
        expect(size.width, greaterThanOrEqualTo(frameWidth <= 520 ? 23 : 25));
        expect(size.height, size.width);
        final ordinal = find.descendant(
          of: marker,
          matching: find.byType(Text),
        );
        if (ordinal.evaluate().isNotEmpty) _fullParagraph(tester, ordinal);
        final decoration =
            tester.widget<Container>(marker).decoration! as BoxDecoration;
        expect(
          decoration.color,
          deckColors(
            tester.element(marker),
          )[jobs.events[i]['checkResult'] == 'passed' ? 'selected' : 'raised'],
        );
        final line = find.byKey(ValueKey('job-timeline-line-$i'));
        expect(
          line,
          i + 1 < jobs.events.length ? findsOneWidget : findsNothing,
        );
        if (i + 1 < jobs.events.length) expect(tester.getSize(line).width, 1);
      }
    case '29-job-unknown':
      _text('Исход не подтверждён');
      _text('Возможны неподтверждённые изменения');
      _text('Уточнить результат');
      expect(find.text('Остановить после текущего шага'), findsNothing);
      expect(find.text('Повторить тот же запрос'), findsNothing);
    case '30-job-cancel':
      _text('Остановка задания');
      _text('Состояние: Остановка запрошена');
      _text('Обновить состояние');
      _text('Не предоставлено');
      _text('Автоматический откат не обещается');
      _text('Открыть события');
      expect(find.text('Остановить после текущего шага'), findsNothing);
      expect(find.text('Откатить изменения'), findsNothing);
    case '31-recent-operations':
      for (final label in [
        'Область',
        'Лимит',
        'Цель',
        'Время UTC',
        'Результат',
        'Состояние',
        'Теги',
      ]) {
        _text(label);
      }
      _text('Все окна рабочего пространства');
      _text('Недавние подтверждённые операции');
      _contains('До 20 последних подтверждённых записей');
      _text('Изменение настроек подтверждено');
      _text('00000000-0000-4000-8000-000000000099');
      final historyRevisionLabel = find.text('Ревизия');
      if (historyRevisionLabel.evaluate().isNotEmpty) {
        expect(historyRevisionLabel, findsOneWidget);
      } else {
        _text('Ревизия пространства');
      }
      _text(h.recovery.receipts.single.storeRevision);
      _text(DesignServerFixtures.observedAt);
      _text('Обновить список');
    case '32-automation-profiles':
      _recordStatus(tester, 'Активен', '✓', 'available');
      _text(DesignAutomationFixtures.profile().name);
      _text('2');
      _text('Активные');
      _text('Архив');
      _text('Поиск по данным экрана');
    case '33-profile-authoring':
      _text('Редактор Ansible-профиля');
      _text('Назначение');
      _text('Шаги');
      _text('Параметры');
      _text('Проверки');
      // The canonical form helper is hidden at device widths <=960.
      expect(
        find.text('Перед продолжением'),
        MediaQuery.sizeOf(tester.element(find.byType(AutomationFormPageFrame)))
                    .width >
                960
            ? findsOneWidget
            : findsNothing,
      );
      _text('Сохранить версию');
      _text('Проверить без сохранения');
      expect(h.body.text, contains('system.motd'));
    case '34-profile-revisions':
      final versionAction = find.widgetWithText(
        OutlinedButton,
        'Проверить версию',
      );
      expect(
        tester
            .widget<DeckButtonLabel>(
              find.descendant(
                of: versionAction,
                matching: find.byType(DeckButtonLabel),
              ),
            )
            .icon,
        'refresh',
      );
      _text('Приветствие сервера · версия 2');
      _text('Сравнение версий 1 и 2');
      _text('/parameters/greeting/default');
      _text('Было');
      _text('Стало');
      _text('Здравствуйте');
      _text('Привет');
      _text('Точные значения');
      expect(
        tester
            .widgetList<AutomationExactValue>(find.byType(AutomationExactValue))
            .last
            .value,
        DesignAutomationFixtures.revision()['digest'],
      );
      _text('Выбрать версию');
      _text('Сравнить версии');
      _text('Для новой версии потребуется отдельное согласие');
    case '35-plan-parameters':
      _contextPair(tester, 'Цель', 'Профиль');
      _formValue(tester, 'Проверка', 'Без записи на сервер');
      _formValue(
        tester,
        'Следующий шаг',
        'Получить план с эффектами и проверками',
      );
      _text('Параметры плана');
      _text('Ansible-профиль: Приветствие сервера · версия 2.');
      _formValue(
        tester,
        'Цель',
        '${h.automationServerProfile.name} · 192.0.2.44:2222',
      );
      _text(
        'Проверьте параметры для выбранной версии. Продолжение создаст план; запуск потребует отдельного подтверждения.',
      );
      _text('greeting');
      _draftField(tester, 'greeting', 'Привет');
      _text('JSON · дополнительные сведения');
      _text('Создать план');
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
      _recordStatus(tester, 'Действует', '○', 'muted');
      _text('Доступ ИИ рабочего пространства');
      _text('Действует');
      _text('Истёкший grant');
      _text('Author-only');
      _text(
        'Чтение состояния · Чтение журналов · Создание и изменение профилей · Создание планов · Запуск заданий',
      );
      _text('${h.automationServerProfile.name} · 192.0.2.44:2222');
      _text('2026-10-25T17:00:00.000Z (UTC)');
      _text('Отозвать');
    case '37-ai-grant-form':
      _text('НАСТРОЙКИ / РАБОЧЕЕ ПРОСТРАНСТВО');
      _text('Выдать доступ ИИ');
      _text(
        'Выдайте только необходимые права на перечисленные серверы. Сохранение выдаст доступ клиенту ИИ на указанный срок.',
      );
      _text('Права');
      _text(
        'Чтение состояния, Чтение журналов, Создание и изменение профилей, Создание планов',
      );
      expect(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is AutomationDraftSelectionField &&
                widget.label == 'Цели',
          ),
          matching: find.text(
            '${h.automationServerProfile.name} · 192.0.2.44:2222',
          ),
        ),
        findsOneWidget,
      );
      _draftField(tester, 'Срок, секунд', '28800');
      _text('Выдать доступ');
    case '38-mcp-client-config':
      final copyAction = find.widgetWithText(
        FilledButton,
        'Скопировать конфигурацию',
      );
      expect(
        tester
            .widget<DeckButtonLabel>(
              find.descendant(
                of: copyAction,
                matching: find.byType(DeckButtonLabel),
              ),
            )
            .icon,
        'copy',
      );
      _text('Подключение MCP-клиента');
      _text('Сведения');
      _text('Точные значения');
      _text('Команда');
      _text(r'C:\Synthetic\ServerDeck\mcp.exe');
      _text('Аргументы');
      _text('Скопировать конфигурацию');
      for (final content in [
        find.text('Подключение MCP-клиента').first,
        find.descendant(
          of: find.byType(AutomationExactValue).first,
          matching: find.byType(SelectableText),
        ),
        find.text('Аргументы').last,
        find
            .text(
              '--app-root, C:\\Synthetic\\ServerDeck, --grant-id, ${DesignAutomationFixtures.grantId}',
            )
            .last,
      ]) {
        await _showText(tester, content);
        expectDesignVisible(tester, content);
      }
    case '39-delegations':
      _contextPair(tester, 'ИИ-клиент', 'Профиль');
      _formValue(tester, 'profileId', DesignAutomationFixtures.profileId);
      _formValue(tester, 'revision', '2');
      _formValue(
        tester,
        'bodyDigest (SHA-256)',
        DesignAutomationFixtures.revision()['digest'] as String,
      );
      _formValue(tester, 'Делегирование', 'Только указанная ревизия');
      _text('Делегирование версии');
      _formValue(
        tester,
        'ИИ-клиент',
        DesignAutomationFixtures.grant()['label'] as String,
      );
      _text(
        'Ansible-профиль: Приветствие сервера · версия 2. Доступ клиента до: 2026-10-25T17:00:00.000Z (UTC).',
      );
      _formValue(
        tester,
        'Цель',
        '${h.automationServerProfile.name} · 192.0.2.44:2222',
      );
      _text(
        'Разрешить запуск только этой неизменной версии в заданных границах параметров. Новые версии потребуют отдельного делегирования.',
      );
      _draftField(tester, 'Срок, секунд', '3600');
      _text('Разрешённые точные значения');
      _draftField(tester, 'Значение 1', 'Привет');
      _text('Делегировать версию');
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
      _text('Проверьте цель, последствия и условия выбранного действия');
      _text('Подготовка исполнителя');
      _text('Параметры и условия');
      _text('Последствия');
      _text('Привязать исполнитель к этому серверу');
      _text(
        '${h.trustProfile.name} · ${h.trustProfile.address}:${h.trustProfile.port}',
      );
      _text(DesignServerFixtures.hostId);
      _text(DesignServerFixtures.key.fingerprint);
      _text('${DesignServerFixtures.expiresAt} · UTC');
      _text('Отмена');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Привязать исполнитель'),
            )
            .onPressed,
        isNotNull,
      );
    case '84-settings':
      _text('Настройки приложения');
      _text('Настройки и ограничения');
      _text('Тёмная');
      _text('Включено');
      _text('${h.initialProfile.name} · ${h.initialProfile.address}:22');
      _text('Приватный экспорт');
      _text('Недоступен');
      _text('Изменить настройки');
    case '85-settings-form':
      _text('Изменение настроек');
      _text('Параметры');
      _text('Тема *');
      _text('Уменьшение анимации *');
      _text('Активный профиль');
      _text('Выбор профиля');
      _text('Без подключения и подтверждения SSH-доверия');
      _text('Сохранить настройки');
      _text(h.initialProfile.name);
      for (final prefix in ['page-theme-', 'page-motion-', 'page-selection-']) {
        expect(
          find.byWidgetPredicate((widget) {
            final key = widget.key;
            return key is ValueKey<String> && key.value.startsWith(prefix);
          }),
          findsOneWidget,
          reason: 'Canonical settings field $prefix uses its real dropdown',
        );
      }
      expect(find.byType(CheckboxListTile), findsNothing);
    case '93-protected-effect-blocked':
      _text('План заблокирован');
      _text('Исполнение не разрешено');
      _text('Сведения о конкретном защищённом эффекте не предоставлены');
      _text('Открыть запрещённый эффект');
      _text('Просмотреть причины');
      _text('Закрыть план');
      final planSection = tester.widget<AutomationPlanSection>(
        find.byType(AutomationPlanSection),
      );
      expect(planSection.plan, DesignAutomationFixtures.plan(blocked: true));
      expect(planSection.plan['effects'], isEmpty);
      expect(planSection.plan['checks'], isEmpty);
      expect(planSection.plan['preflight'], isNull);
      final display = BlockedPlanDisplay.tryCreate(
        planSection.plan,
        targetMatches: automationPlanTargetAvailable(planSection.plan, [
          h.automationServerProfile,
        ]),
        expired: planSection.expired,
        invalidated: planSection.invalidReason != null,
      );
      expect(display, isNotNull);
      expect(display!.reasons, [
        {'code': 'EXECUTOR_UNAVAILABLE', 'field': 'executor', 'stepId': null},
      ]);
      expect(display.sourceSteps, isEmpty);
      expect(
        BlockedPlanDisplay.tryCreate(
          planSection.plan,
          targetMatches: false,
          expired: false,
          invalidated: false,
        ),
        isNull,
      );
      expect(
        BlockedPlanDisplay.tryCreate(
          planSection.plan,
          targetMatches: true,
          expired: true,
          invalidated: false,
        ),
        isNull,
      );
      expect(
        BlockedPlanDisplay.tryCreate(
          planSection.plan,
          targetMatches: true,
          expired: false,
          invalidated: true,
        ),
        isNull,
      );
      final forbidden = designButton('Открыть запрещённый эффект');
      expect(tester.widget<FilledButton>(forbidden).onPressed, isNull);
      expect(
        find.byTooltip('Сервис не передал идентичность эффекта'),
        findsOneWidget,
      );
      expect(find.textContaining('NetBird'), findsNothing);
      expect(find.text('Подтвердить план'), findsNothing);
      expect(find.text('Запустить'), findsNothing);
      expect(find.text('Повторить тот же запрос'), findsNothing);
    case '94-plan-invalidated':
      _text('План требует новой проверки');
      _text('${h.automationServerProfile.name} · 192.0.2.44:2222');
      _text('Параметры и условия');
      _text('Последствия');
      _text('Создать новый план');
      final invalidNotice = find.byWidgetPredicate(
        (w) => w is DeckNotice && w.title == 'Следующий шаг',
      );
      final invalidHero = tester.getRect(find.byType(DeckPanel).first);
      final noticeRect = tester.getRect(invalidNotice);
      final conditionsRect = tester.getRect(
        find
            .ancestor(
              of: find.text('Параметры и условия'),
              matching: find.byType(DeckPanel),
            )
            .first,
      );
      final invalidGap =
          tester.view.physicalSize.width / tester.view.devicePixelRatio <= 520
          ? 16.0
          : 20.0;
      expect(noticeRect.top - invalidHero.bottom, closeTo(invalidGap, .01));
      expect(conditionsRect.top - noticeRect.bottom, closeTo(invalidGap, .01));
      expect(find.text('Запустить'), findsNothing);
      expect(find.text('Подтвердить план'), findsNothing);
    default:
      fail('Missing baseline acceptance for ${host.binding.screenId}');
  }
  if (const {
    '01-startup',
    '02-service-unavailable',
    '03-storage-blocked',
    '10-host-trust',
    '11-host-key-changed',
    '13-mutation-conflict',
    '40-executor-binding',
  }.contains(host.binding.screenId)) {
    final panels = find.byType(DeckPanel);
    final gap =
        tester.view.physicalSize.width / tester.view.devicePixelRatio <= 520
        ? 16.0
        : 20.0;
    expect(
      tester.getRect(panels.at(1)).top - tester.getRect(panels.first).bottom,
      closeTo(gap, .01),
    );
  }
  // All origins use at least one meaningful Deck component in their own body.
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is DeckPanel ||
          widget is DeckPage ||
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
    '06-server-overview' => ('Обновить данные', 'readState'),
    '13-mutation-conflict' => ('Перечитать настройки', 'reload'),
    '22-server-logs' => ('Получить журнал', 'readLogs'),
    '23-log-record' => ('Закрыть', 'closeRecord'),
    '16-install-catalog' => ('Подключиться и открыть рецепты', 'loadRecipes'),
    '17-recipe-detail' => ('Создать план', 'createRecipePlan'),
    '19-plan-approval' => ('Подтвердить план', 'approve'),
    '27-job-list' => ('Обновить', 'refreshJobs'),
    '28-job-detail' => ('План задания', 'showPlan'),
    '29-job-unknown' => ('Уточнить результат', 'reconcileJob'),
    '30-job-cancel' => ('Обновить состояние', 'selectJob'),
    '33-profile-authoring' => ('Проверить без сохранения', 'validateVersion'),
    '34-profile-revisions' => ('Сравнить версии', 'compare'),
    '35-plan-parameters' => ('Создать план', 'continueEditor'),
    '37-ai-grant-form' => ('Выдать доступ', 'continueEditor'),
    '39-delegations' => ('Делегировать версию', 'continueEditor'),
    '36-ai-grants' => ('Отозвать', 'revokeGrant'),
    '38-mcp-client-config' => ('Скопировать конфигурацию', 'copyConfiguration'),
    '94-plan-invalidated' => ('Создать новый план', 'editPlanSource'),
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
    case '11-host-key-changed':
      final reads = h.client.reads.length;
      final mutations = h.client.mutations.length;
      await _activateByKeyboard(tester, 'Пересмотреть доверие');
      expect(h.counters['probeTrust'], 1);
      expect(h.counters['confirmTrust'], 0);
      expect(h.counters['connect'], 0);
      expect(h.client.reads.length, reads);
      expect(h.client.mutations.length, mutations);
      await _activateByKeyboard(tester, 'Закрыть');
      expect(h.counters['closeChangedKey'], 1);
      expect(
        h.counters.values.values.fold<int>(0, (sum, value) => sum + value),
        2,
      );
      expect(h.client.mutations.length, mutations);
    case '93-protected-effect-blocked':
      final plan = tester
          .widget<AutomationPlanSection>(find.byType(AutomationPlanSection))
          .plan;
      final reads = h.client.reads.length;
      final mutations = h.client.mutations.length;
      await _activateByKeyboard(tester, 'Просмотреть причины');
      _text('EXECUTOR_UNAVAILABLE');
      _text('executor');
      expect(
        find.text('Открыть исходный шаг'),
        findsNothing,
        reason: 'The received reason has no exact source step ID',
      );
      expect(
        tester
            .widget<AutomationPlanSection>(find.byType(AutomationPlanSection))
            .plan,
        same(plan),
      );
      expect(h.counters.values, isEmpty);
      expect(h.client.reads.length, reads);
      expect(h.client.mutations.length, mutations);
      await _activateByKeyboard(tester, 'Открыть запрещённый эффект');
      expect(h.counters.values, isEmpty);
      expect(h.client.reads.length, reads);
      expect(h.client.mutations.length, mutations);
      await _activateByKeyboard(tester, 'Закрыть план');
      expect(h.counters['closePlan'], 1);
      expect(h.counters['approve'], 0);
      expect(h.counters['apply'], 0);
      expect(h.counters['retry'], 0);
      expect(
        h.counters.values.values.fold<int>(0, (sum, value) => sum + value),
        1,
      );
      expect(h.client.reads.length, reads);
      expect(h.client.mutations.length, mutations);
    case '18-install-preflight':
      final previous = tester
          .widget<AutomationPlanSection>(find.byType(AutomationPlanSection))
          .plan;
      final reads = h.client.reads.length;
      final mutations = h.client.mutations.length;
      await _activateByKeyboard(tester, 'Просмотреть план');
      _text('Подтвердить план');
      expect(
        tester
            .widget<AutomationPlanSection>(find.byType(AutomationPlanSection))
            .plan,
        same(previous),
      );
      expect(h.counters.values, isEmpty);
      expect(h.client.reads.length, reads);
      expect(h.client.mutations.length, mutations);
    case '04-empty-workspace':
      await _activateByKeyboard(tester, 'Добавить сервер');
      expect(find.byType(ProfileForm), findsOneWidget);
    case '05-server-list':
      await _activateByKeyboard(tester, 'Изменить');
      expect(find.byType(ProfileForm), findsOneWidget);
    case '07-profile-create':
      await _activateByKeyboard(tester, 'Сохранить без подключения');
      _text('Проверьте значение поля');
      expect(h.client.mutations, isEmpty);
    case '08-profile-edit':
      await _activateByKeyboard(tester, 'Сохранить');
      expect(h.client.mutations, hasLength(1));
      _text('Профиль изменён другим окном. Введённые данные сохранены в форме');
    case '09-profile-delete':
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await _activateByKeyboard(tester, 'Удалить профиль');
      expect(h.client.mutations, hasLength(1));
      _text('Профиль изменён другим окном. Перечитайте его перед удалением');
    case '12-credential-input':
      // Only new RAM input can be revealed; saved credentials are never read.
      await _activateByKeyboard(tester, 'Показать введённый секрет');
      await tester.enterText(
        find.byKey(const ValueKey('credential-private-key')),
        'synthetic private key\n',
      );
      final input = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('credential-private-key')),
          matching: find.byType(TextField),
        ),
      );
      expect(input.obscureText, isFalse);
      expect(input.controller!.text, 'synthetic private key\n');
      expect(h.client.mutations, isEmpty);
    case '31-recent-operations':
      final before = h.client.reads.length;
      await _activateByKeyboard(tester, 'Обновить список');
      expect(h.client.reads.length, before + 1);
      expect(h.client.mutations, isEmpty);
      _text('Изменение настроек подтверждено');
    case '32-automation-profiles':
      final row = find.text(DesignAutomationFixtures.profile().name).last;
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump();
      expect(h.counters['selectAutomationProfile'], 1);
      expect(
        h.counters.values.values.fold<int>(0, (total, value) => total + value),
        1,
      );
    case '84-settings':
      final reads = h.client.reads.length;
      await _activateByKeyboard(tester, 'ИИ-доступ');
      expect(h.counters['openAiAccess'], 1);
      expect(h.client.reads.length, reads);
      expect(h.client.mutations, isEmpty);
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
      await _activateByKeyboard(tester, 'Подтвердить ключ');
      expect(h.counters['confirmTrust'], 1);
      expect(h.counters['cancelTrust'], 1);
    case '40-executor-binding':
      await _activateByKeyboard(tester, 'Отмена');
      expect(h.counters['cancelExecutor'], 1);
      expect(h.counters['confirmExecutor'], 0);
      await _activateByKeyboard(tester, 'Привязать исполнитель');
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
  final cardBinding = currentBaseBindings.singleWhere(
    (b) => b.screenId == '05-server-list',
  );
  for (final width in [760.0, 761.0, 1000.0, 1061.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('profile card source boundaries $width scale $scale', (
        tester,
      ) async {
        final host = await mountDesignFixture(
          tester,
          cardBinding,
          frame: Size(width, 800),
          theme: ThemeMode.dark,
          textScale: scale,
          currentBase: true,
        );
        try {
          _profileMetricsGeometry(tester, host);
          expect(tester.takeException(), isNull);
          expect(host.harness.counters.values, isEmpty);
          expect(host.harness.client.mutations, isEmpty);
        } finally {
          await host.close(tester);
        }
      });
    }
  }

  for (final binding in currentBaseBindings) {
    for (final frame in currentBaseFrames) {
      for (final theme in currentBaseThemes) {
        for (final scale in currentBaseScales) {
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
                currentBase: true,
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
                  final chart = find.byType(ServerObservationChart).first;
                  await _showText(tester, chart);
                  for (final text in [
                    'Источник: ssh:proc/stat+meminfo+net/dev+df',
                    'Наблюдение: ${DesignServerFixtures.observedAt} · UTC',
                    'Получено: ${DesignServerFixtures.observedAt} · UTC',
                  ]) {
                    await _showText(tester, find.text(text).first);
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
