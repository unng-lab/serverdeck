# Quickstart: обычная проверка и поставка 003.4

Сначала завершить реальный Flutter UI 37 базовых сценариев по [плану](plan.md) и [визуальному контракту](contracts/full-application.md). Остальные 61 экран остаются в [программе 98](../design-delivery.md) у своих функциональных пакетов.

Не нужны custom reference readers, JSON binding language, второй валидатор, corpus/schema bundle, source adapter или receipt graph. Обычные widgets используют реальные owners/callbacks; тесты подменяют только внешние зависимости.

## Подготовка SDK и зависимостей

Используется Flutter 3.47.7 / Dart 3.13.5 через существующий `tools/foundation-sdk.ps1`. Если SDK расположен вне настроенных путей, его фактический каталог задаётся `SERVERDECK_FLUTTER_ROOT`. Это настройка среды разработчика, не новый runtime приложения.

```powershell
. ./tools/foundation-sdk.ps1
flutter pub get --enforce-lockfile
```

В `packages/serverdeck_protocol`, `packages/serverdeck_windows`, `packages/serverdeck_locald` и `packages/serverdeck_mcp` выполнить `dart pub get --enforce-lockfile` тем же SDK. Restore создаёт package configuration для анализа и не запускает native workload.

<a id="current-unit-widget-commands"></a>

## Обязательные локальные проверки

Из корня, с очищенными capture-переменными:

```powershell
$env:SERVERDECK_NATIVE_CONTROL_RED = '0'
foreach ($name in @('DESIGN_CAPTURE_DIR', 'DESIGN_STATE_CAPTURE_DIR', 'DESIGN_STOCK_CAPTURE_DIR', 'BASE_DESIGN_CAPTURE_DIR')) {
  [Environment]::SetEnvironmentVariable($name, $null, 'Process')
}
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --reporter expanded
```

Не передавать capture `--dart-define` флаги. Обычный opt-in capture skip ожидаем. В затронутых пакетах выполнить `dart analyze`; действующий общий gate анализирует protocol/windows/locald. Дополнительные разрешённые unit suites:

```powershell
Push-Location packages/serverdeck_protocol
dart test --reporter expanded
Pop-Location
Push-Location packages/serverdeck_locald
dart test test/server_peer_coordination_test.dart --reporter expanded
Pop-Location
```

Scheduler suite использует fake delegates/completers. Полные suites windows/locald/mcp, real services/process/pipe/SSH, native/FFI/DPAPI, Docker/systemd/Ansible и integration qualification сейчас не запускаются. Полные правила — в [AGENTS](../../AGENTS.md). CI gate — `unit-widget-checks`; manual native profiles без отдельного указания пользователя не dispatch.

Изменения спецификации проверяются `lychee "specs/**/*.md"`. После применимых проверок требуется независимый review/fix loop по AGENTS. Автор документации не объявляет эти команды выполненными до реального результата.

## Полезные widget regressions

Использовать обычные `test/widget/` и существующие test helpers. Проверять production composition, доступные имена, full value/copy и реальные callbacks, а не наличие похожего test-only текста.

- Все 37 базовых сценариев: 1100×760, 800×600, 390×800, 360×800, light/dark, 100%/200% текста; границы перестройки 520/521, 760/761, 1060/1061.
- Формы: длинные значения, Unicode, validation/CAS/unknown, сохранённые draft/selection, полный JSON и 0 invalid dispatch; отдельный реальный delegation guard.
- Навигация: explicit target, обычные Серверы→ПО→Журналы/Задания, late replies, отсутствующий/чужой target без fallback.
- Доступность: Tab/Shift+Tab/Enter/Escape, видимый focus, touch target, reduced motion, keyboard inset и внутренний scroll/copy полного значения.
- Данные/защита: unknown/empty/stale/gaps, текстовые значения графика, pending/expiry/consent, readiness loss и отсутствие приватного текста/секретных editors после retirement.

Рабочий тест должен обнаруживать соответствующий дефект. Старый matcher заменяется на актуальный control только с сохранением поведения, данных и zero-effect checks. Production guards не подменяются дополнительной валидацией в fake submit.

## Прямая визуальная сверка

Сопоставить обычные страницы приложения с [каноническим HTML](../../docs/design/ServerDeck-design.html), [реестром](../../docs/design/screens.json), [брендбуком](../../docs/brandbook/README.md), [токенами](../../docs/brandbook/tokens/serverdeck.tokens.json) и имеющимися исходными PNG. Проверить реальные области/порядок, отступы, шрифты, иконки, переносы, controls и состояния по FA03–FA09.

100% и 200% проверяются как разные text layouts. Изображение страницы не растягивается и full-page PNG не уменьшается до viewport. Имена/версии/состояния демо могут отличаться от фактических; это не разрешает пропустить панель, действие или доступный полный текст. Непроверенное сочетание отмечается как непроверенное.

Не создавать отдельный HTML renderer/DSL, общий corpus или набор хешированных proof receipts. Не использовать Computer Use/автоматизацию рабочего стола вопреки указанию пользователя и не обходить ограничения браузера. Установленная страница, unit/widget результат и макет имеют разные статусы проверки.

## Сборка, установка и показ

После применимых checks и review собрать согласованную private Windows-версию из проверенных исходников. Проверить фактические version/package/source identity и состав ассетов. Сохранить текущие данные и прежнюю рабочую установку; не выполнять очистку store, credentials, trust, истории или unknown jobs ради нового UI.

Установить новую сборку с обычным shortcut и показать реальные разделы/форму/status/context по имеющейся доступности данных. Не запускать gallery/fixture route вместо приложения. Записать фактический результат сборки/установки/показа и ограничения в [evidence](evidence.md)/[handoff](handoff.md). Сборка и показ не объявляют native/integration либо приёмку всех 98 экранов.
