# Evidence 003.4 — библиотека компонентов

Дата: 2026-11-01. Статус: этап 003.4 принят в scope библиотеки C01–C30, offline каталога/атласа и затронутых existing compositions. [Независимое round4](reviews/2026-11-01-component-library-code-round4.md) завершено без замечаний; T103–T152 закрыты. Native pixel/control-click acceptance не установлена и в этот вывод не входит. Старое evidence 003.1–003.3 не переписывается.

## Артефакты

- [Реестр](../../docs/design/components/registry.json): 30 C IDs, 98 screen IDs, 35 existing / 63 concept; реальные пути библиотеки и tests, отдельные статусы.
- [Каталог и подключение](../../docs/design/components/README.md); Flutter entrypoint `tool/component_catalog.dart` и синтетические owners в `tool/component_catalog/examples.dart`.
- Обновлённый [HTML-атлас](../../docs/design/ServerDeck-design.html) с общими renderers и отдельным каталогом; версионируемые исходники в `docs/design/source/`, builder `tools/build-design-atlas.py`.
- Production: `lib/ui/deck_controls.dart`, `deck_collections.dart`, `deck_patterns.dart`, `deck_page.dart`, `deck_history.dart`, существующие theme/Deck foundations. Основная точка импорта `deck_components.dart`.
- Внедрение: ProfileList и AutomationJobsSection используют DeckCollection; профиль — DeckFieldFrame/DeckExpander; FoundationShell — DeckPageBody; JSON и diff automation — DeckCode/DeckExpander/DeckDiff; план — DeckPlanSummary.content; log modal — DeckLogMessage; MetricsHistory сохранён как alias общей DeckHistory. Feature owners, requests, trust и storage не переносились.

## Фактические проверки перед code review round 1

| Команда / проверка | Результат и scope |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` | Exit 0; 489 files, 0 changed. Предупреждения о package resolution в игнорируемом историческом `work/` сохранены в log, не ошибки formatter |
| `flutter analyze` | Exit 0, no issues. Попутно удалён analyzer-confirmed unused `dart:convert` import из нового постороннего test `direct_ssh_apt_inventory_test.dart`; backend поведение не изменялось |
| `flutter test` | Exit 0; 135 passed, 1 skipped (opt-in visual capture) |
| `lychee "specs/**/*.md"` | Exit 0; 1741 total, 1739 OK, 0 errors, 2 excluded, 1 redirect |
| `tools/check-design-references.ps1` | Exit 0; 30 components, 98 references, 35/63 split, source/asset token/path integrity |
| `node tools/test-design-components.cjs` | Exit 0; 1024 checks = (98 screens + 30 components) × 2 themes × 4 frames. Нет JS errors, broken images, horizontal document overflow, отсутствующего содержимого или общих компонентов |
| Opt-in Flutter capture, `components-round5` | Exit 0; 2544 captures = 159 применимых component/state cases × 2 themes × 4 frames × 2 text scales. Bundled Noto и MaterialIcons, reduced motion, assertions на отсутствие framework exceptions, непрозрачный фон |
| `flutter build windows --debug -t tool/component_catalog.dart` | Exit 0 после добавления SDK OneCore import library для существующего CompareObjectHandles |

Логи этой итерации: `output/design-components-2026-11-01/{format,analyze,test,links}-pre-review.log`, `browser-verification.json`, `capture-test-round5.log`, `catalog-build.log`. Полные Flutter PNG и manifest: `.local/design-003/003.4/components-round5/`. Первые неуспешные прогоны сохранены отдельно: path guard, fake-async image encoding, пустой список без области, прозрачный фон/иконки и промежуточная корректировка capture Material. Они не объявлены успешными.

## Native scope и ограничения

Обычный Windows runner первоначально не линковал CompareObjectHandles. [Microsoft указывает KernelBase](https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-compareobjecthandles); в установленном SDK import symbol присутствует в `OneCore.Lib`, которой дополнен CMake. Сам алгоритм сравнения/изоляции stdio не менялся. Попытка связать `kernelbase.lib`, отсутствующую в данном SDK, сохранена как неуспешная.

Каталог фактически запущен на Windows: процесс responding, VM service ready, дерево доступности содержит controls C06, строки и значения таблицы. Через Alt+F4 каталог завершился, `flutter run` вернул exit 0; entrypoint обрабатывает только closeWindow/exit native host без движка/заданий. Native capture через computer-use дал белую клиентскую область, а вызовы клика по UIA index — stale index. Поэтому native pixel correctness и успешное нажатие этих controls не подтверждены этим smoke. Обычный и диагностический software запуск различаются: software требует отключить Impeller; попытка только software завершилась fatal и не принимается. Это ограничение native визуальной проверки не подменяется 2544 widget PNG.

Новые backend-функции концептов, real SSH, credentials, права на изменения серверов, mobile platforms, publish/release и production rollout этим этапом не проверялись. Исторические команды отсутствующего старого tooling не выдаются за выполненные; актуальные команды записаны в начале [quickstart](quickstart.md).

## Исправления после code review round 1

Все семь замечаний проверены по коду и закрываются T141–T147. C26 слушает controller, копирует текущий raw text и ограничивает оба режима 240 px по умолчанию. DeckCollection резервирует всю область единой sliver-композицией; тестируется Expanded host 400 px, wide/phone, 200%, loading/error и 1000 lazy rows. Read-only машинный текст прокручивается PageDown/Home/End без изменения значения.

В fixtures состояния стали содержательными: no-results очищает существующий query, unavailable блокирует эффекты, disabled убирает callbacks, stale/partial/unknown различаются с empty, терминальные состояния прогресса различимы. Ввод JSON и даты находится в Form с достижимой validate; нормализуемая дата 2026-02-31 отвергается. C17 использует настоящий FoundationShell. Focus/hover/pressed в captures создаются событиями клавиатуры/мыши (см. interaction в manifest), а не одной подписью состояния. Неприменимость объяснена отдельно в реестре.

Обе карточки читают общие metadata: конкретные screen IDs, anatomy, variants, параметры/события, ограничения, критерии и пример. Flutter компилирует их в names.dart; catalog test сравнивает поля с исходным JSON. Независимые CatalogRow и CatalogJob с разными IDs/полями/actions используют одну DeckCollection; meaningful journeys проверяют stable equal/null-last sort, query/clear, selection, removal и unavailable row при narrow resize. HTML owner использует ту же общую table-функцию для двух независимых наборов; контекстное меню поддерживает Shift+F10/arrows/Home/End/Escape и возврат фокуса.

Фактически выполнено после исправлений:

- `dart format --output=none --set-exit-if-changed .` round2: exit 0, 498 files, 0 changed. Сохранены предупреждения о package include в постороннем ignored `work/`; это не объявляется отсутствием предупреждений.
- `flutter analyze` round2: exit 0, No issues found.
- `flutter test` round2: exit 0, 190 passed / 1 skipped (opt-in capture). Дополнительные пять history boundary tests после этого прошли отдельно; финальный полный повтор round3 записывается ниже по завершении.
- `flutter test --dart-define=COMPONENT_CAPTURE_DIR=.local/design-003/003.4/components-round8 test/widget/components/capture_test.dart`: exit 0, 3440 PNG / 215 component-state fixtures × 16 theme/frame/scale combinations, manifest сохранён. Reduced motion включён. Round6 failed, round7 passed; они сохраняются отдельно и не подменяются round8.
- Просмотрены три новых contact sheets round8: все 30 семейств, обе темы, 360 px / 200%; длинные области смотрятся прокруткой, а уменьшенная contact sheet не доказывает читаемость каждого glyph. Источники PNG доступны отдельно.
- `flutter build windows --debug -t tool/component_catalog.dart`, затем `flutter build windows --debug`: оба exit 0; обычный entrypoint восстановлен в build output. Scope native smoke и его ограничения остаются описанными выше, повторная pixel-проверка не заявляется.
- `node tools/test-component-interactions.cjs`: exit 0, 11 сценариев/групп assertions, включая server/job journeys на 1100/360 px, точный current JSON copy, JSON/date/profile validation/recovery, consent, keyboard menu и реальные hover/pressed/focus/disabled.
- `python tools/validate-design.py`: exit 0, 30/98/35/63; paths/tokens/metadata проверены.
- `lychee "specs/**/*.md"` round2: exit 0, 1768 total, 1766 OK / 0 errors / 2 excluded, 1 redirect. После текущего обновления evidence выполняется новый повтор.

Полная HTML state matrix round2 обнаружила пустое содержимое C07 empty и слишком строгую минимальную длину для закрытого C19. C07 исправлен на явный empty state; C19 проверяется по непустому доступному заголовку (8+ символов), без требования раскрывать его. Round3 проверяет 2504 cases, его итог будет добавлен после завершения. На этом месте приёмка ещё не объявлена: нужны завершённые финальные gates и fresh independent review.

Финальные обязательные повторы перед fresh review: round3 format exit 0 (499 files / 0 changed); analyze exit 0 (No issues found); flutter test exit 0 (195 passed / 1 skipped). History assertions покрывают 15000/15001 ms, duplicate/reversed time, 120/121 points и missing/zero. Lychee round3 exit 0: 1771 total / 1769 OK / 0 errors / 2 excluded / 1 redirect. Browser round3 exit 0: 2504 cases / 0 errors. Во время последней части browser round3 дополнены HTML dialog/list/tree/history/paging variants; поэтому после сборки всего файла запущен отдельный round4 на замороженных исходниках. Его результат записывается отдельно. Новые server/job interaction checks повторены после последней сборки HTML: exit 0.

HTML round4 завершён на неизменных исходниках: exit 0, 2504 cases / 0 errors. Новые диалоги, раскрытие history, три series, paging/list/tree и отсутствие activity indicator при unknown вошли в этот прогон. Обычный Windows executable после build проверен с недопустимым аргументом: exit 1 (ожидаемый отказ до bootstrap); это не заменяет запуск подключённого клиента.

## Исправления после code review round 2

[Round2](reviews/2026-11-01-component-library-code-round2.md) нашёл четыре оставшихся дефекта; добавлены T148–T151. Text-only editable DeckCode теперь имеет локальный controller, который сохраняет draft при обычном rebuild и отдаёт текущий raw text в copy. Внешний controller остаётся собственностью caller. C27 передаёт selectedId и локально меняет выбор; unavailable показывает причину без активного дерева. Настоящий ComponentCatalogApp пересоздаёт fixture при смене состояния селектора, но сохраняет его при theme/resize. C25 показывает removed/unchanged с остальными изменениями, missing after не превращается в ноль.

`flutter test test/widget/components/review_round2_test.dart` — exit 0, 4 meaningful regressions: edit→copy без внешнего controller плюс theme rebuild; C27 выбор/selected/unavailable; C19 selector default→expanded→default в настоящем каталоге плюс сохранение C13 draft при theme/resize; removed с отсутствующим after и unchanged. Проверка finder в новом тесте сначала была слишком широкой (в документации тоже есть EditableText), исправлена на поле формы; неуспешный прогон не объявляется успешным поведением.

Новые полные gates/captures и fresh independent review выполняются после этих изменений; результаты добавляются ниже, история прежних прогонов сохранена.

После T148–T151: round4 format exit 0 (500 files / 0 changed), analyze exit 0 / No issues, test exit 0 / 199 passed / 1 skipped. Catalog/default Windows debug builds round3 оба exit 0. Capture round9 exit 0: 3440 PNG в новом каталоге `.local/design-003/003.4/components-round9/`; round8 сохранён. Отдельно просмотрены C25/default/light/360/200 (включая removed и missing after), C27/unavailable/dark/360/200 (нет дерева/кнопок), C27/selected/light/360/100 (подсвечен config.yaml). Контраст C01 проверен численно: text/status roles ≥4.5 на bg/surface/raised/hover/selected; control/focus/series ≥3; onAccent ≥4.5. Точные цвета сравниваются с canonical JSON, bundle fonts/logos/licenses существуют. Новый foundation test exit 0; после его добавления запускается последний полный round5 и fresh review. Lychee round4 exit 0, 1780 total / 1778 OK / 0 errors / 2 excluded.

Round5 завершён: format exit 0 (501 files / 0 changed); analyze exit 0 / No issues; test exit 0 / 200 passed / 1 skipped. Lychee-review3 exit 0 / 0 errors. [Independent round3](reviews/2026-11-01-component-library-code-round3.md) подтвердил четыре round2 fixes, но нашёл HTML-only потерю CPU при viewport 1000 px. T152 удаляет legacy nth-child(n+5) display:none; Flutter-код после round5 не менялся. Новые HTML assertions проверяют все 16 переданных data cells C06 при 1000 px viewport и container 519/520/521/699/700/701 в обеих темах; interactions round4 exit 0 / 13 groups / 0 errors. Общая browser matrix теперь дополнительно проверяет скрытые переданные ячейки, а не только overflow. Пересобранный атлас проходит новый полный browser round5; его итог и fresh review фиксируются после завершения.

## Финальная приёмка 003.4

Browser round5 завершён: exit 0, 2504 cases / 0 errors, включая hidden-cell assertions. Lychee-review4: exit 0, 1784 total / 1782 OK / 0 errors / 2 excluded. [Fresh independent round4](reviews/2026-11-01-component-library-code-round4.md) завершён без замечаний; reviewer самостоятельно воспроизвёл C06 boundary cases и подтвердил сохранение всех полей. Итоговые code/design статусы обновлены в реестре, все T103–T152 отмечены выполненными без удаления истории review/fix. Final bookkeeping не меняет реализацию и не добавляет product/architecture решения.

Все 98 references имеют mapping и evidence: для 35 existing origins сохранены production paths и действующие owners, для 63 concept paths остаются пустыми. Проверки adoption непосредственно упражняют реальный список профилей, jobs и shell/readiness retirement; остальные существующие compositions оценены по source/diff и общей регрессионной suite, без утверждения 35 отдельных native journeys. Стандартные Material controls используют BrandTheme и общие Deck form/dialog/surface/layout primitives. C27 — concept-only; C29 групповой выбор остаётся синтетическим примером той же коллекции, поскольку существующий runtime не предоставляет общего списка/группового API. Новых backend возможностей ради дизайна нет.

Приёмка означает готовность использовать библиотеку и примеры для новых compositions, а не готовность будущих профильных сервисов. Сохраняются ограничения native проверки выше; публикация, реальные серверы/SSH и credentials не проверялись.

После финального bookkeeping: static validator exit 0 (30/98/35/63), HTML interactions exit 0 / 13 groups, registry joins/compiled metadata test exit 0 / 1 passed, lychee-final exit 0 (1789 total / 1787 OK / 0 errors / 2 excluded). Изменены только статусы/evidence/задачи и пробелы двух пустых строк HTML-шаблона; Flutter implementation после успешного round5 не менялась.
