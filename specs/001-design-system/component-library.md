# Контракты C01–C30

Источник: [реестр](../../docs/design/components/registry.json). Карты страниц исключены.

## C01 — Основы

Основы: палитра ролей, типографика, интервалы, геометрия, focus, motion, иконки и логотип

**Состав**: Палитра ролей; шесть ролей текста; интервалы; геометрия; focus/motion; иконки; логотип.

**Варианты**: палитра ролей; типографика; интервалы; геометрия; focus; motion; иконки и логотип.

**Входы**: BrandTheme.dark/light; BrandColors.roles; BrandTypography; BrandGeometry.

**События**: Смена темы/ширины задаётся корневым owner.

**Состояния**: default.

**Ограничения**: Точные токены; bundled fonts/assets; без сетевой загрузки.

**Критерии приёмки**: Цвета совпадают с canonical JSON; обе темы читаемы; target/focus/contrast сохраняются.

**Реализация**: lib/theme/brand_theme.dart; lib/theme/brand_tokens.dart; lib/theme/brand_assets.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
MaterialApp(theme: BrandTheme.dark, home: MyScreen());
```

## C02 — Кнопки

Кнопки: основная, вторичная, текстовая, опасная, icon-only, группа действий

**Состав**: Label; icon; граница/заливка; focus; pending indicator; причина недоступности.

**Варианты**: основная; вторичная; текстовая; опасная; icon-only; группа действий.

**Входы**: child; kind; onPressed; pending; disabledReason; autofocus.

**События**: onPressed → FutureOr<void>; синхронный guard повтора.

**Состояния**: default; hover; focus; pressed; disabled; pending.

**Ограничения**: Не создаёт requests/retry/consent; danger не default Enter.

**Критерии приёмки**: Второй click/Enter до результата не вызывает callback; disabled не активен.

**Реализация**: lib/ui/deck_controls.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckButton(kind: DeckButtonKind.primary, onPressed: onCreate, child: const Text('Создать'));
```

## C03 — Поля

Поля: текст, многострочное, число, пароль с явным показом/скрытием, read-only, prefix/suffix, helper/error

**Состав**: Полная подпись; input; prefix/suffix; helper/error; show/hide secret.

**Варианты**: текст; многострочное; число; пароль с явным показом/скрытием; read-only; prefix/suffix; helper/error.

**Входы**: label; controller/initialValue; readOnly; secret; enabled; validator; keyboardType.

**События**: onChanged; onFieldSubmitted; validator возвращает ошибку.

**Состояния**: default; hover; focus; pressed; disabled; error; pending.

**Ограничения**: Controller и validators у формы; secret скрыт по умолчанию; значение не копируется общим copy control.

**Критерии приёмки**: Draft сохраняется на theme/resize; error/readonly видны; reveal только явно.

**Реализация**: lib/ui/deck_controls.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckTextField(label: 'Адрес', controller: address, validator: validateAddress, onChanged: onAddressChanged);
```

## C04 — Выбор значения

Выбор значения: select, checkbox, radio, switch, segmented single choice

**Состав**: Select; checkbox; radio; switch; segmented selection.

**Варианты**: select; checkbox; radio; switch; segmented single choice.

**Входы**: Material choice widgets: value/groupValue/selected; items/segments; enabled.

**События**: onChanged/onSelectionChanged → новое значение owner.

**Состояния**: default; hover; focus; pressed; disabled; selected.

**Ограничения**: Штатные Material controls с BrandTheme; validation формы не придумывается.

**Критерии приёмки**: Выбор меняет только локальное значение; disabled не вызывает событие.

**Реализация**: lib/theme/brand_theme.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
CheckboxListTile(value: selected, onChanged: onChanged, title: const Text('Доступные'));
```

## C05 — Поиск и фильтры

Поиск и фильтры: строка поиска, выбор фильтра, chip активного фильтра, очистка, панель инструментов

**Состав**: Поисковое поле; clear; активный filter chip; панель инструментов.

**Варианты**: строка поиска; выбор фильтра; chip активного фильтра; очистка; панель инструментов.

**Входы**: controller; label; enabled; filters; onChanged.

**События**: onChanged(query); filter callback; clear отправляет пустую строку.

**Состояния**: default; hover; focus; pressed; disabled; pending; empty; no-results; unavailable; stale; partial; unknown.

**Ограничения**: Не выполняет запрос и не определяет server-side filtering.

**Критерии приёмки**: No-results отличается от empty; очистка возвращает исходную порцию.

**Реализация**: lib/ui/deck_controls.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckSearch(controller: query, onChanged: onQueryChanged, filters: filters);
```

## C06 — Таблица

Таблица: заголовки и ячейки, сортировка, выбор строк, действия, пустое/ошибка/загрузка, узкий вариант

**Состав**: Header/cells; stable ID; sort controls; checkbox; row actions; narrow labels.

**Варианты**: заголовки и ячейки; сортировка; выбор строк; действия; пустое/ошибка/загрузка; узкий вариант.

**Входы**: rows; idOf; columns; state; selectedIds; onSortChanged; maxBodyHeight.

**События**: onSelectionChanged(Set<String>); onSortChanged(DeckSort?); onOpen(row).

**Состояния**: default; hover; focus; pressed; disabled; selected; pending; error; empty; no-results; unavailable; stale; partial; unknown.

**Ограничения**: Только переданная порция; ленивые строки; owner сортирует/фильтрует; нет I/O.

**Критерии приёмки**: Bounded host не переполняется; 1000 rows lazy; row action не меняет selection.

**Реализация**: lib/ui/deck_collections.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckCollection<Map<String, String>>(rows: rows, idOf: (r) => r['id']!, columns: [DeckColumn(id: 'name', label: 'Имя', value: (r) => r['name'])], onOpen: onOpen);
```

## C07 — Список

Список: строка с названием/описанием/leading/trailing, разделитель, выбор, раскрытие, адаптивная карточка

**Состав**: Leading; title; description; trailing; divider; selected; expandable details.

**Варианты**: строка с названием/описанием/leading/trailing; разделитель; выбор; раскрытие; адаптивная карточка.

**Входы**: DeckListItem(title, description, leading, trailing, selected, onTap); DeckExpander.

**События**: onTap; onExpansionChanged.

**Состояния**: default; hover; focus; pressed; disabled; selected; empty.

**Ограничения**: Не выводит факт связи/прав из названия или цвета; коллекция хранится у owner.

**Критерии приёмки**: Выбор виден; actions независимы; раскрытие показывает переданные детали.

**Реализация**: lib/ui/deck_patterns.dart; lib/ui/deck_collections.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckListItem(title: item.name, description: item.description, selected: isSelected, onTap: onSelect);
```

## C08 — Навигация набора

Навигация набора: страницы, размер страницы, счётчик, «Показать ещё»

**Состав**: Назад/далее; page counter; page size; load-more.

**Варианты**: страницы; размер страницы; счётчик; «Показать ещё».

**Входы**: page >= 0; pageSize; pageSizes; hasMore; total?; pending; enabled.

**События**: onPageChanged; onPageSizeChanged; onLoad.

**Состояния**: default; hover; focus; pressed; disabled; pending; unknown.

**Ограничения**: page/load-more opt-in; неизвестный total остаётся неизвестным; без автоматической загрузки.

**Критерии приёмки**: Границы отключены; pending блокирует повтор; изменение размера сбрасывает page=0.

**Реализация**: lib/ui/deck_collections.dart; lib/ui/deck_page.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckPagination(page: page, hasMore: hasMore, total: total, onPageChanged: loadPage);
```

## C09 — Карточка

Карточка/поверхность: обычная, интерактивная, выбранная, ошибка; секция и заголовок с действиями

**Состав**: Surface; padding; border; header; description; actions; selected/error/focus.

**Варианты**: обычная; интерактивная; выбранная; ошибка; секция и заголовок с действиями.

**Входы**: DeckSurface(child, selected, error, enabled, onTap); DeckSectionHeader.

**События**: onTap только при enabled.

**Состояния**: default; hover; focus; pressed; disabled; selected; error.

**Ограничения**: Не интерактивная поверхность не получает button role/focus.

**Критерии приёмки**: Обычная/интерактивная/error/selected карточки различимы; focus не скрывает error.

**Реализация**: lib/ui/deck_components.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckSurface(selected: isSelected, error: hasError, onTap: onOpen, child: const Text('Объект'));
```

## C10 — Статус

Статус/badge/chip: все DeckTone, счётчик, текст + символ, pending

**Состав**: Символ; подпись; семантическая роль; pending; badge/chip count.

**Варианты**: все DeckTone; счётчик; текст + символ; pending.

**Входы**: DeckStatus(label, tone, pending); Material Badge/Chip.

**События**: Не генерирует серверных событий.

**Состояния**: default; pending; error; unknown; unavailable; success.

**Ограничения**: Статус не только цвет; unknown не success/zero.

**Критерии приёмки**: Все DeckTone имеют текст/символ; reduced motion оставляет понятный pending.

**Реализация**: lib/ui/deck_components.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
const DeckStatus(label: 'Неизвестно', tone: DeckTone.unknown);
```

## C11 — Сообщения

Сообщения: inline notice, banner, локальное краткое уведомление, ошибка с повтором

**Состав**: Inline notice; title; reason; next step; actions; snackbar close.

**Варианты**: inline notice; banner; локальное краткое уведомление; ошибка с повтором.

**Входы**: DeckNotice(message, title, tone, nextStep, actions); SnackBar.

**События**: Только явно переданные действия; close краткого уведомления.

**Состояния**: default; hover; focus; pressed; disabled; pending; error; unknown.

**Ограничения**: Security/unknown/errors постоянны; snackbar только для несущественного локального результата.

**Критерии приёмки**: Ошибка не исчезает автоматически; retry только явный и разрешённый owner.

**Реализация**: lib/ui/deck_components.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckNotice(title: 'Не удалось прочитать', message: reason, actions: [DeckButton(onPressed: retryRead, child: const Text('Повторить чтение'))]);
```

## C12 — Состояние области

Состояние области: loading indicator, skeleton, empty, no-results, error, unavailable, stale/partial

**Состав**: Indicator/skeleton; empty/no-results; error; unavailable; stale/partial/unknown.

**Варианты**: loading indicator; skeleton; empty; no-results; error; unavailable; stale/partial.

**Входы**: DeckCollectionState(state, message, onRetry, onClearSearch); DeckSkeleton.

**События**: onRetry только error; onClearSearch только no-results.

**Состояния**: default; hover; focus; pressed; pending; error; empty; no-results; unavailable; stale; partial; unknown.

**Ограничения**: Не подставляет demo/zero; качество и snapshot даёт owner.

**Критерии приёмки**: Каждое состояние имеет отдельный смысл и допустимое следующее действие.

**Реализация**: lib/ui/deck_collections.dart; lib/ui/deck_page.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckCollectionState(state: DeckDataState.noResults, onClearSearch: clearQuery);
```

## C13 — Форма

Форма: секция полей, labels/helper/error, validation summary, панель отправки/отмены

**Состав**: Form sections; labels/helper/errors; summary; submit/cancel.

**Варианты**: секция полей; labels/helper/error; validation summary; панель отправки/отмены.

**Входы**: Form/key; DeckFormSection(title, children); owner controllers/validators.

**События**: validate; submit; cancel.

**Состояния**: default; hover; focus; pressed; disabled; pending; error.

**Ограничения**: Согласие/requests/recovery у владельца; pending блокирует submit.

**Критерии приёмки**: Invalid form не отправляется; summary и ошибки видны; draft сохраняется.

**Реализация**: lib/ui/deck_components.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
Form(key: formKey, child: DeckFormSection(title: 'Параметры', children: fields));
```

## C14 — Диалог

Диалог: информационный, редактирование, подтверждение, опасное действие; title/body/actions

**Состав**: Dialog title; target; scroll body; cancel/confirm actions.

**Варианты**: информационный; редактирование; подтверждение; опасное действие; title/body/actions.

**Входы**: DeckDialogLayout(title, target, child, actions, maxWidth).

**События**: Открытие/закрытие route и confirm принадлежат owner.

**Состояния**: default; hover; focus; pressed; disabled; pending.

**Ограничения**: Общий layout не хранит consent и не управляет авторизацией. Вызывающий host владеет lifecycle, закрытием dialog route и проверкой полномочий; каталог использует стандартный showDialog без продуктовой private session.

**Критерии приёмки**: Info/edit/confirm/danger представлены; Escape/backdrop не подтверждают.

**Реализация**: lib/ui/deck_components.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckDialogLayout(title: 'Подтверждение', target: Text(target), child: Text(effects), actions: actions);
```

## C15 — Меню

Меню/подсказка: dropdown/context menu, tooltip для icon-only, disabled с причиной

**Состав**: Dropdown/context menu; enabled/disabled item reason; tooltip; focus.

**Варианты**: dropdown/context menu; tooltip для icon-only; disabled с причиной.

**Входы**: Material PopupMenuButton/Tooltip; DeckContextMenu(entries, enabled, child).

**События**: onSelected(label); secondary click/Shift+F10.

**Состояния**: default; hover; focus; pressed; disabled.

**Ограничения**: Не даёт прав; недоступный item объяснён и не активен.

**Критерии приёмки**: Menu keyboard/Escape работают; disabled items не dispatch; tooltip имеет accessible name.

**Реализация**: lib/ui/deck_patterns.dart; lib/theme/brand_theme.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckContextMenu(entries: const [DeckMenuEntry('Открыть')], onSelected: onAction, child: row);
```

## C16 — Вкладки и локальные переходы

Вкладки и локальные переходы: tab bar, breadcrumb, назад, selected/disabled

**Состав**: Tabs; selected; disabled; breadcrumb; back.

**Варианты**: tab bar; breadcrumb; назад; selected/disabled.

**Входы**: DeckTabs(labels, selected, onSelected?); DeckBreadcrumbs; IconButton back.

**События**: onSelected(index); back callback.

**Состояния**: default; hover; focus; pressed; disabled; selected.

**Ограничения**: Переходы локальны; не читают сервер и не меняют owner target.

**Критерии приёмки**: Tab/breadcrumb/back доступны; disabled callbacks отсутствуют.

**Реализация**: lib/ui/deck_patterns.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckTabs(labels: const ['Обзор', 'Журнал'], selected: selectedTab, onSelected: onTabChanged);
```

## C17 — Каркас страницы

Каркас страницы: sidebar/rail/phone navigation, topbar, заголовок, контекст цели, body/actions

**Состав**: Sidebar/rail/phone navigation; topbar; title; target; content slot.

**Варианты**: sidebar/rail/phone navigation; topbar; заголовок; контекст цели; body/actions.

**Входы**: FoundationShell(state, requestedSection, targetName, targetAddress, feature slots,
status, fallbackContent); DeckPageBody. `status` — необязательный виджет статуса от владельца;
`fallbackContent` — необязательное содержимое разделов без собственного слота. При отсутствии
этих входов поведение каталожного примера сохраняется. Runtime/data/error state определяет owner.

**События**: onSectionChanged; разрешённые callback владельца.

**Состояния**: default; hover; focus; pressed; unavailable.

**Ограничения**: Навигация UI-only; readiness/private subtree управляет host; пять разделов.

**Критерии приёмки**: Порог 520/1060; context/draft сохраняются на resize; ready loss скрывает private context.

**Реализация**: lib/ui/deck_page.dart; lib/shell/foundation_shell.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
FoundationShell(state: readiness, servers: servers, software: software, settings: settings, targetName: targetName);
```

## C18 — Подробности

Подробности: пары ключ–значение, группы метаданных, selectable value, copy с результатом

**Состав**: Label/value; selectable machine value; explicit copy; copy result.

**Варианты**: пары ключ–значение; группы метаданных; selectable value; copy с результатом.

**Входы**: DeckKeyValue(label, value, selectable); DeckCopyButton(value, enabled).

**События**: Явный copy в clipboard с результатом.

**Состояния**: default; hover; focus; pressed; disabled; unknown; stale; partial.

**Ограничения**: Никогда не передавать credentials; missing не превращается в ноль.

**Критерии приёмки**: Exact copy; failure сообщается; unknown value честно подписан.

**Реализация**: lib/ui/deck_components.dart; lib/ui/deck_patterns.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckKeyValue(label: 'Адрес', value: address, selectable: true);
DeckCopyButton(value: address, label: 'Скопировать адрес');
```

## C19 — Раскрываемая область

Раскрываемая область: accordion/expander, дополнительные технические детали

**Состав**: Expandable title; focus; local open state; details.

**Варианты**: accordion/expander; дополнительные технические детали.

**Входы**: DeckExpander(title, children, initiallyExpanded, enabled).

**События**: onExpansionChanged(bool).

**Состояния**: default; hover; focus; pressed; disabled; expanded.

**Ограничения**: Только локальное раскрытие; не подгружает данные и не выдаёт consent.

**Критерии приёмки**: Enter/Space раскрывают; disabled не раскрывается; скрытые mandatory effects не допускаются.

**Реализация**: lib/ui/deck_patterns.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckExpander(title: const Text('Детали'), children: details);
```

## C20 — Журнал

Журнал: строка события, время/уровень/источник, bounded message, детали записи

**Состав**: Event time; level; source; bounded message; full record.

**Варианты**: строка события; время/уровень/источник; bounded message; детали записи.

**Входы**: DeckLogMessage(message, source, eventTime, observedAt, height); list row + record dialog.

**События**: Открытие полной записи owner; selection/copy/scroll.

**Состояния**: default; hover; focus; pressed; disabled; empty; stale; partial.

**Ограничения**: Не смешивает event/observed time; context из того же result; no polling.

**Критерии приёмки**: Exact raw message и две UTC даты; длинный текст прокручивается; missing source честный.

**Реализация**: lib/ui/deck_page.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckLogMessage(message: record.message, source: source, eventTime: eventTime, observedAt: observedAt);
```

## C21 — Числовой показатель

Числовой показатель: значение/единица/лимит, неизвестное, stale/partial, описание

**Состав**: Label; value; unit/limit; quality/source/time.

**Варианты**: значение/единица/лимит; неизвестное; stale/partial; описание.

**Входы**: DeckMetric(label, value?, unit, contextLabel, tone).

**События**: Не создаёт событий.

**Состояния**: default; unknown; stale; partial.

**Ограничения**: Unknown value = нет данных; качество от owner; no polling.

**Критерии приёмки**: Реальный 0 отличается от missing; stale/partial подписаны.

**Реализация**: lib/ui/deck_patterns.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckMetric(label: 'CPU', value: value, unit: '%', contextLabel: quality);
```

## C22 — График истории

График истории: несколько различимых series, gap, legend, текстовая альтернатива

**Состав**: Series; pattern/symbol; legend; gaps; textual values.

**Варианты**: несколько различимых series; gap; legend; текстовая альтернатива.

**Входы**: DeckHistory(points, quality, stale, source, observedAt, receivedAt, actions).

**События**: Локальное раскрытие/keyboard selection текстовых значений.

**Состояния**: default; hover; focus; pressed; empty; stale; partial; unknown.

**Ограничения**: До 120 points; gap >15000ms; no interpolation/polling/new timestamps.

**Критерии приёмки**: 0/1/120, invalid/reversed/duplicate time и gaps не превращаются в непрерывную линию.

**Реализация**: lib/ui/deck_history.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckHistory(points: points, source: source, observedAt: observedAt, stale: stale);
```

## C23 — Прогресс

Прогресс/шаги: determinate/indeterminate, шаги задания, running/success/error/cancel/unknown

**Состав**: Determinate/indeterminate; step list; terminal/unknown outcome.

**Варианты**: determinate/indeterminate; шаги задания; running/success/error/cancel/unknown.

**Входы**: DeckProgress(label, value?, tone, steps); DeckProgressStep.

**События**: Не отменяет задание; actions даёт owner.

**Состояния**: default; pending; error; success; cancelled; unknown.

**Ограничения**: Null progress не означает успех; unknown не running и не terminal success.

**Критерии приёмки**: Running/success/error/cancel/unknown имеют отдельные подписи/символы; no auto retry.

**Реализация**: lib/ui/deck_patterns.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckProgress(label: outcomeLabel, tone: tone, value: progress, steps: steps);
```

## C24 — План и подтверждение

План и подтверждение: цель, последствия, ограничения, срок, scope, обязательные предупреждения

**Состав**: Target; effects; scope; deadline; warnings; optional technical details; decisions.

**Варианты**: цель; последствия; ограничения; срок; scope; обязательные предупреждения.

**Входы**: DeckPlanSummary(target, effects, scope, deadline, warning, details, actions) / .content.

**События**: Consent и confirm/cancel callbacks у owner.

**Состояния**: default; hover; focus; pressed; disabled; pending; error; unknown; unavailable.

**Ограничения**: Mandatory context всегда виден; нет собственной авторизации/plan matching.

**Критерии приёмки**: Без согласия confirm недоступен в примере; изменённый/unknown plan не повторяется.

**Реализация**: lib/ui/deck_patterns.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckPlanSummary(target: target, effects: effects, scope: scope, deadline: deadline, actions: permittedActions);
```

## C25 — Сравнение

Сравнение: before/after, добавлено/изменено/удалено, конфликт, недоступная сторона

**Состав**: Field/line name; before; after; add/remove/change/conflict.

**Варианты**: before/after; добавлено/изменено/удалено; конфликт; недоступная сторона.

**Входы**: DeckDiff(entries); DeckDifference(label, before?, after?, change).

**События**: Read-only: не генерирует merge/write.

**Состояния**: default; empty.

**Ограничения**: Готовые пары от owner; нет автоматического merge или записи.

**Критерии приёмки**: Missing сторона видна; added/removed/changed/unchanged/conflict не смешиваются.

**Реализация**: lib/ui/deck_patterns.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
const DeckDiff(entries: [DeckDifference(label: 'workers', before: '2', after: '4', change: DeckChange.changed)]);
```

## C26 — Машинный текст

Машинный текст: JSON/конфигурация/команда, mono, read-only/edit, validation, copy, bounded scroll

**Состав**: Label; bounded mono text/editor; validation; explicit copy.

**Варианты**: JSON/конфигурация/команда; mono; read-only/edit; validation; copy; bounded scroll.

**Входы**: DeckCode(label, controller/text, readOnly, maxHeight, validator, enabled, allowCopy).

**События**: onChanged; validator; copy актуального точного значения.

**Состояния**: default; hover; focus; pressed; disabled; error.

**Ограничения**: Не IDE/exec; controller и Form у owner; никаких retries/секретов.

**Критерии приёмки**: Edit→copy даёт новый raw text; long text bounded и keyboard scroll; invalid JSON остаётся в draft.

**Реализация**: lib/ui/deck_patterns.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
Form(key: formKey, child: DeckCode(label: 'JSON', controller: json, readOnly: false, validator: validateJson));
```

## C27 — Путь и дерево

Путь и дерево: breadcrumb пути, папка/файл, раскрытие узла, выбор, недоступный узел

**Состав**: Path breadcrumb; node; expand; select; unavailable reason.

**Варианты**: breadcrumb пути; папка/файл; раскрытие узла; выбор; недоступный узел.

**Входы**: DeckPathTree(path, nodes, expandedIds, selectedId, enabled); DeckPathNode.

**События**: onExpansionChanged(Set<String>); onSelected(id).

**Состояния**: default; hover; focus; pressed; disabled; selected; empty; unavailable.

**Ограничения**: Дети переданы owner; раскрытие не читает filesystem; stable IDs.

**Критерии приёмки**: Закрытые дети не строятся; unavailable node не выбирается; причина видна.

**Реализация**: lib/ui/deck_patterns.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckPathTree(path: path, nodes: nodes, expandedIds: expanded, onExpansionChanged: onExpanded, onSelected: onSelected);
```

## C28 — Время

Время: дата/время наблюдения и события, срок, ввод даты/времени и часового пояса

**Состав**: Date/time fields; zone choice; event/observation labels.

**Варианты**: дата/время наблюдения и события; срок; ввод даты/времени и часового пояса.

**Входы**: DeckDateTimeInput(dateController, timeController, zone, zones, validators, enabled); DeckTimestamp.

**События**: onZoneChanged; validators формы; owner receives text.

**Состояния**: default; hover; focus; pressed; disabled; error.

**Ограничения**: Не scheduler; DST и разрешения у owner; display timestamp UTC.

**Критерии приёмки**: Пустые/некорректные дата/время показывают validation; нормализуемая неверная дата отклоняется.

**Реализация**: lib/ui/deck_page.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckDateTimeInput(dateController: date, timeController: time, zone: zone, onZoneChanged: onZoneChanged, dateValidator: validateDate);
```

## C29 — Группа выбранных объектов

Группа выбранных объектов: количество, групповые действия, очистка, частичная доступность

**Состав**: Selected count; group actions; clear; visible-page select-all; partial availability.

**Варианты**: количество; групповые действия; очистка; частичная доступность.

**Входы**: DeckSelectionBar(count, onClear?, actions); DeckCollection(canSelect, selectedIds).

**События**: Selection и group callbacks; удаление ID при удалении строки выполняет owner.

**Состояния**: default; hover; focus; pressed; disabled; selected; pending; error; empty; no-results; unavailable; stale; partial; unknown.

**Ограничения**: Только видимая порция; скрытые выбранные ID не исчезают автоматически.

**Критерии приёмки**: Независимый job fixture; blocked rows исключены; action не меняет выбор; удалённый ID очищен.

**Реализация**: lib/ui/deck_collections.dart.

**Пример**: `tool/component_catalog/job_example.dart`.

```dart
DeckSelectionBar(count: selected.length, onClear: clearSelection, actions: groupActions);
```

## C30 — Сводка возможностей

Сводка возможностей/ограничений: доступно/не поддерживается/неизвестно, причина и следующий шаг

**Состав**: Capability title; available/unsupported/unknown; reason; next step.

**Варианты**: доступно/не поддерживается/неизвестно; причина и следующий шаг.

**Входы**: DeckCapability(title, reason, tone, nextStep).

**События**: Только переданное разрешённое действие.

**Состояния**: default; hover; focus; pressed; disabled; unknown; unavailable; error.

**Ограничения**: Сведения о возможности от owner; компонент не устанавливает факт поддержки.

**Критерии приёмки**: Состояние/причина/следующий шаг видны; неизвестное не выдаётся за доступное.

**Реализация**: lib/ui/deck_patterns.dart.

**Пример**: `tool/component_catalog/examples.dart`.

```dart
DeckCapability(title: 'SMART', reason: 'Источник не поддерживается', tone: DeckTone.unavailable);
```


## C03: функциональная privacy-поправка для SSH credentials003

При secret=true show/hide меняет только отображение. Copy и cut через keyboard
shortcuts и selection menu запрещены в обоих состояниях; paste остаётся доступным.
Autocorrect, suggestions и personalized IME learning отключены. Владение исходным
значением, очистка controller и срок хранения остаются у вызывающей формы.
Это дополнение существующего C03 в scope001, задача R013; не новый компонент и не
изменение визуального контракта. Проверяется synthetic functional unit fixture
`test/profiles/secret_field_test.dart`, а не дизайном экрана или матрицей viewport.
