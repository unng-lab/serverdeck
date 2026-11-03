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
