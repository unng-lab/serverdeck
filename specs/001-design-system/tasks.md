# Задачи 001

Сохранены готовые элементы прежней 003. Старые задачи и их выполненная история находятся во внешнем архиве из [RESET](../../RESET.md); они не задают требования нового проекта.

- [x] R001 Сохранить полный исходный снимок и Git history вне проекта.
- [x] R002 Оставить брендбук, assets, темы и C01–C30 с контрактами и примерами.
- [x] R003 Удалить страницы, карты экранов, продуктовые пакеты и их тесты.
- [x] R004 Оставить единственный пакет 001-design-system.
- [x] R005 Выполнить format, analyze, functional tests, component tests и lychee.
- [x] R006 Завершить независимый review и устранить подтверждённые замечания.

## Исправления независимого review — 2026-11-02

- [x] R007 C14: закрепить ответственность host без удалённых private-session/showMotionDialog.
- [x] R008 HTML: сохранить draft/selection при смене темы и проверить взаимодействие.
- [x] R009 Закрепить активный контекст Spec Kit на 001 и проверить разрешение путей.

- [x] R010 Повторно синхронизировать C14 в каноническом реестре, Flutter-метаданных и HTML после обнаружения оставшейся записи.
- [x] R011 Применить query-тему до первого HTML render, проверить artwork и подпись в прямых light/dark ссылках.

Итоговый независимый review 2026-11-02: замечаний не найдено; готовность подтверждена только для библиотеки и каталогов C01–C30. Windows-сборка не выполнялась. Проверки: format/analyze, 1 functional test, 111 component tests (1 opt-in skip), lychee 13/0, boundary check, 16 HTML journeys; HTML matrix 1720/0 до финальных исправлений, после них C14 48/0 и C17 40/0.

## Расширение C17 для runtime 002 — 2026-11-03

- [x] R012 Добавить optional owner inputs `status` и `fallbackContent` в FoundationShell, сохранив defaults каталога; проверить synthetic owner content/actions и существующую компонентную suite, ссылки и independent review. Дизайн runtime экрана не проверять.


## Функциональная privacy-корректировка C03 для003 — 2026-11-03

- [x] R013 Запретить copy/cut секрета в DeckTextField при secret=true также после reveal: keyboard shortcuts и selection menu; paste сохранить, suggestions/autocorrect/IME learning отключить. Реализация и synthetic functional unit test в рамках FR305003, без изменения дизайна и без screen-layout/golden/matrix gate. Проверить обычные mandatory unit/static/link checks и независимое ревью вместе с003 до завершения.


## C21 compact для текущего мониторинга — 2026-11-04

- [X] R014 Добавить optional compact в общий DeckMetric C21 в lib/ui/deck_patterns.dart, сохранив default; контракт component-library.md и synthetic units test_design/components. Использование в003/004 не требует layout/golden/overflow тестов feature экрана. Независимое ревью в текущем scope001/002/003/004.


## Server workspace primitives — 2026-11-04
- [X] R015 Обновить C07 compact/error/status, C10 iconOnly/icon с hover/focus/semantics,
  C21 compact/icon и C17 FoundationShell(sidebar,child,state,status,recoveryAction)
  в lib/ui/deck_patterns.dart,deck_components.dart,lib/shell/foundation_shell.dart;
  текущий catalog tool/component_catalog/examples.dart и synthetic shared units
  обновить напрямую без старых slots/enum. Component-library контракт и независимое
  ревью вместе003/T069–077; только shared001 design checks.

- [X] R016 Добавить обязательные icons и label-tooltip в C16 DeckTabs, обновить
  callers/каталоги напрямую и synthetic shared units; связанный release-font fix
  002/T046 и server caller003/T082. Mandatory checks и независимый review.

- [X] R017 Обновить canonical C16 Dart пример в component-library.md к обязательным
  icons (review_missing_icons_code P3); проверить ссылки и fresh independent review.

## C22 hour extension

- [X] R018 Extend lib/ui/deck_history.dart with bounded720 hour variant,fractions,explicit segment breaks; synthetic units test_design/components/history_hour_test.dart; mandatory/shared checks and review with004/T032–034. No feature-screen acceptance/captures.
