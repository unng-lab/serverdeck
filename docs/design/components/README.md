# Компоненты ServerDeck

Выбрана существующая в приложении система **Flutter Material 3 + BrandTheme + Deck**. Material задаёт стандартные controls и клавиатурное поведение; брендбук ServerDeck задаёт точные цвета, Noto Sans/Noto Sans Mono, геометрию и отступы. Deck добавляет общие коллекции, состояния, контекст и композиции без переноса полномочий в widgets.

## Открыть дизайн и реализацию

- [Автономный атлас](../ServerDeck-design.html?view=components&component=C06) — вкладки «Экраны» / «Компоненты», 30 семейств, темы и размеры. HTML показывает дизайн; демонстрационные действия не являются рабочим клиентом.
- Flutter-каталог: из корня `flutter run -d windows -t tool/component_catalog.dart`. Отдельный entrypoint использует production widgets и синтетические данные. Не запускает движок, не читает credentials и настройки; native host используется только для закрытия окна.
- [Реестр](registry.json) связывает C01–C30, дизайн, реализацию, примеры, тесты и все 98 screen IDs. Статусы обновляются по фактической приёмке; исходный `implemented` не означает принятую реализацию.
- [Требования](../../../specs/003-design-system/component-library.md), [контракт](../../../specs/003-design-system/contracts/component-library.md), [задачи](../../../specs/003-design-system/tasks.md).

## Как использовать

Публичный импорт: `package:serverdeck/ui/deck_components.dart`. Стандартные controls допустимо использовать непосредственно из Material с `BrandTheme`: отдельная обёртка нужна для общего поведения, а не для каждого конструктора.

| Семейства | Готовые элементы |
| --- | --- |
| C01–C05 | BrandTheme/BrandColors/BrandTypography/BrandGeometry; Material choice controls; DeckButton, DeckTextField, DeckFieldFrame, DeckSearch |
| C06–C08, C29 | DeckCollection/DeckColumn/DeckSort, DeckListItem, DeckPagination, DeckLoadMore, DeckSelectionBar |
| C09–C14 | DeckSurface, DeckSectionHeader, DeckStatus/DeckTone, DeckNotice, DeckCollectionState/DeckSkeleton, DeckFormSection, DeckDialogLayout |
| C15–C19 | Material PopupMenuButton/Tooltip, DeckContextMenu, DeckTabs/DeckBreadcrumbs, DeckPageBody, DeckKeyValue/DeckCopyButton, DeckExpander |
| C20–C24 | DeckLogMessage, DeckMetric, DeckHistory, DeckProgress, DeckPlanSummary |
| C25–C30 | DeckDiff, DeckCode, DeckPathTree, DeckDateTimeInput/DeckTimestamp, DeckSelectionBar, DeckCapability |

Работающие примеры каждого семейства — `tool/component_catalog/examples.dart`. Они передают callbacks локального owner, демонстрируя изменение состояния без серверных эффектов. Коллекция получает стабильные row IDs, данные, selection/sort и callbacks; сама не фильтрует, не сортирует и не запрашивает данные. Широкий и узкий виды используют один контракт. `DeckCollectionLayout.list` сохраняет стабильный список для раскрываемых профилей.

Validators и TextEditingController остаются у формы. Pending блокирует повтор; permission/identity/revision guards и recovery принадлежат существующему owner. Credentials не передаются в поля копирования. Общий диалог отвечает за layout: route, private session и consent задаёт экран.

## Редактирование дизайна

Канонические исходники — `docs/design/source/`. `design-system.js` содержит общие renderers; `components.css` задаёт оформление; `app.js` собирает экраны из этих элементов, `component-gallery.js` показывает отдельные образцы. Исторический экспорт в `output/design-all-pages-2026-10-25` не редактируется.

Собрать: `python tools/build-design-atlas.py`. Результат — автономный HTML со встроенными ассетами. Проверить HTML: `node tools/test-design-components.cjs` (Playwright/Edge из локального runtime; путь можно передать `PLAYWRIGHT_PATH`). Проверить Flutter: `flutter test test/widget/components` и обязательные проверки AGENTS.md. Результаты и ограничения фиксируются в evidence 003.4 и не наследуются из прежних этапов.

Документация обеих карточек берётся из `registry.json`. После её изменения выполнить `python tools/generate-component-metadata.py` и `dart format tool/component_catalog/names.dart`, затем собрать атлас. Проверка настоящих HTML-взаимодействий: `node tools/test-component-interactions.cjs`. Полная HTML-матрица включает все объявленные состояния; Flutter captures запускаются отдельно по quickstart.
