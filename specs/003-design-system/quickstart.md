# Quickstart: проверка003

Это воспроизводимый validation guide [плана](plan.md), а не отчёт о выполненных проверках. Fixture helpers/tests, отмеченные ниже как новые, создаются задачами реализации. Запускать из корня репозитория; пользовательские профили/серверы не нужны.

## Prerequisites

- Windows и закреплённый Flutter3.47.7 / Dart3.13.5 / framework `abaf9c523780a608bd46686fd5e53740a07077f8`.
- Runtime SDK лежит в `.local/sdk/3.47.7/flutter` либо `SERVERDECK_FLUTTER_ROOT` указывает его. Текущий исследованный SDK: `H:/flutter/flutter`; это локальный путь, не portable default.
- Существующие dependencies/assets доступны. Для root analysis preflight добавляется только dev dependency `analyzer:13.3.0`; pinned offline resolution обновляет root lock, production dependency set не расширяется.
- Статическая проверка эталона использует Python≥3.10 со stdlib: `python tools/validate-design.py`. После T003 доступен тонкий wrapper `tools/check-design-references.ps1`; если `python` отсутствует на PATH, передать явный executable через `-Python`. Дублировать проверяющую логику в PowerShell не требуется.
- Для Windows smoke — действующие prerequisites001 и script `tools/test-bootstrap-ui.ps1`; он строит отдельный synthetic application bundle/profile. Не запускать обычный клиент против реального профиля ради screenshot.

```powershell
$env:SERVERDECK_FLUTTER_ROOT = 'H:/flutter/flutter'
. ./tools/foundation-sdk.ps1
flutter pub get --offline
```

Если SDK identity или offline pinned dependency resolution не совпали, зафиксировать failure и исправить среду; не подменять SDK/version и не объявлять check passed. Preflight helper проверяется в explicit package context. В отдельном checkout сначала создать его generated package configuration:

```powershell
Push-Location packages/serverdeck_protocol
try { dart pub get --offline --enforce-lockfile } finally { Pop-Location }
```

Затем из корня:

```powershell
dart --packages=packages/serverdeck_protocol/.dart_tool/package_config.json tools/unit-coverage-zero.dart --references lib/theme/brand_theme.dart
```

Ожидается exit0 и корректный JSON результата references, без изменения helper. Это smoke совместимости helper, не весь coverage gate. Начальный root analyze с13issues известен до внесения dev dependency; новый успешный результат записывается отдельно.

## Mandatory commands

После specification changes, перед review пакета:

```powershell
lychee "specs/**/*.md"
```

После каждого Flutter increment:

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Каждая команда должна реально завершиться exit0; scope/количество tests/диагностика фиксируются. Затем отдельный reviewer без истории читает применимые AGENTS/source/specs и завершает review/fix loop. Наличие screenshot или старого253/253 результата не заменяет повтор после изменения.

## Focused validation

После создания новых files задачами реализации:

```powershell
flutter test test/theme/brand_theme_test.dart test/widget/foundation_shell_test.dart test/widget/design_adoption_test.dart test/widget/design_graph_test.dart
```

1. **003.1 / AC-003-1A/B/C**: проверить exact roles/assets/typography13button/geometry, status text+symbol,5sections, honest local context и A01–A12. `design_scenarios.dart` связывает все35origins;98registry IDs сохраняют35/63 classification/source owners. Global Logs/Jobs объясняют отсутствие общего списка и существующий server context при нужных правах; «К серверам» меняет только local section, без connect/read. Пример отсутствующей возможности даёт реальную причину/следующий шаг, а не активный fake handler. History values/patterns уже доступны текстом поFR-125.
2. **003.2 / AC-003-2A/B/C**: каждая применимая family/state в light/dark при1100×760,800×600,390×800,360×800 и100%/200%; отдельно boundaries520/521/1060/1061. Long Unicode target/tags/messages, keyboard insets и notices не скрывают actions. Touch targets≥44×44; phone server list/whole page не имеют horizontal scroll. Full bottom labels/rail tooltips и selected semantics доступны.
3. **State identity**: открыть draft/filter, захватить controller identity и fake-client call counters; сменить тему/width через все3layouts. Draft/filter/target и текущий pause, если owner его имеет, не меняются. Счётчик connect/read/approve/apply не увеличивается из-за layout; действующее controller polling отделяется от нового вызова. Current logs без pause не получают demo pause; N/A фиксируется.
4. **Keyboard**: Tab/Shift+Tab reading order и видимый focus; Enter/Space для action/expand, Escape cancel, возврат focus. Проверить profile/settings/delete/trust/plan/grant dialogs, multiline credential behavior и graph text section. Reduced motion оставляет статичный pending status без cyclic animations.
5. **Graph**:0/1/120samples, three series, real zero, missing/invalid value, gap15000ms и15001ms, duplicate/reversed timestamps, stale parent context. CPU/RAM/disk имеют name/unit/color/pattern/symbol; text rows содержат UTC/values/нет данных/gaps; нет interpolation/line-to-now. Проверяются keyboard/touch и contrast≥3:1. На1100/800 измеряются общий блок300/270px, три plot25px одной строкой без отдельных рамок/больших процентов, нижняя линия с actions слева и graphs справа, растущие notices выше без перекрытия. При тесноте actions переносятся перед graphs; наphone graphs перед connection/navigation actions. При stale все curve/legend strokes dash6-4, shapes/names/roles и stale text сохраняются; проверка не ограничивается одним quality label.
6. **003.3 / AC-003-3A/B/C**: применимые loading/successful-empty/data/validation/denied/unsupported/stale/dropped/incomplete/local-unavailable/SSH-unavailable/unknown states. Проверить mutation exact retry/conflict, plan expiry/stale и actual owner recovery paths; pending не блокирует independent nav. Locald-ready+SSH-offline оставляет local catalogs доступными.
7. **Privacy**: показать private profile/form/modal, начать delayed callback/picker; потерять ready/authorized session. Target/values/secrets исчезают из render/semantics/tooltips; late completion их не возвращает. Новыйready не принимает trust/approval и не повторяет запись; persisted store/history не удаляются.

## Visual comparison

Использовать [автономный атлас](../../docs/design/ServerDeck-design.html) и [правила](../../docs/design/DESIGN.md), выбирая назначенный screenID/theme/frame. Runtime captures выполняются только с synthetic fixtures, bundled fonts и фиксированными frame/scale. Основной runner использует reduced motion; supplementary stock popup cases явно используют normal motion и settled animations. Сравнивать hierarchy/layout/role/spacing/actions, не копировать demo values. Сохранять capture вместе с binding/check result в evidence этапа; browser render отчёты эталона не считаются Flutter acceptance.

Opt-in runner сохраняет003.1 default mode (140primary+4graph) и явный003.2 mode (560primary+184readable supplements). В003.2 дополнительные views показывают history/MCP, полные labels08/12/33, private-key mode/key/helper/passphrase12 и понятные targets40/19/35/37/39. Перед toImage runner ждёт decoded bundled images и проверяет mounted RawImage. Для003.2 нужен новый пустой каталог внутри `.local/design-003/003.2/`; существующий непустой run не перезаписывается:

```powershell
$taskCaptureRoot = Join-Path (Get-Location) ('.local/design-003/003.2/review-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
flutter test test/widget/design_capture_test.dart --dart-define=DESIGN_CAPTURE_STAGE=003.2 "--dart-define=DESIGN_CAPTURE_DIR=$taskCaptureRoot" --reporter expanded
python tools/build-design-capture-gallery.py $taskCaptureRoot
```

Gallery tool требует Python≥3.10; contact sheets дополнительно используют Pillow. Вариант `--no-contact-sheets` создаёт HTML только со stdlib. Это optional local review tooling, не production dependency. `gallery.html` открывается локально, содержит metadata и ссылки на original PNG; labels указывают view/frame/theme/scale/state. При200% source/UTC/history и MCP heading/command/args/details/copy записаны отдельными readable views. Partial bounded JSON/list viewport не объявляется показом всего содержимого одновременно. Geometry/keyboard/touch tests и независимая visual QA обязательны отдельно; обычный `flutter test` оставляет capture case skipped и ничего не пишет.

T080/T081 actual paint regressions дополнительно сохраняют24focused+32pending-checkbox PNG из тех же asserted widgets, без отдельного capture renderer. Нужен новый absolute run внутри `.local/design-003/003.2/`; каждая test family владеет отдельными `focus/` или `disabled/` PNG/records, prior evidence не перезаписывается:

```powershell
$taskStockCaptureRoot = Join-Path (Get-Location) ('.local/design-003/003.2/stock-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
$env:DESIGN_STOCK_CAPTURE_COMMAND = "flutter test test/widget/design_stock_focus_test.dart test/widget/design_checkbox_contrast_test.dart `"--dart-define=DESIGN_STOCK_CAPTURE_DIR=$taskStockCaptureRoot`" --concurrency=1 --reporter expanded"
flutter test test/widget/design_stock_focus_test.dart test/widget/design_checkbox_contrast_test.dart "--dart-define=DESIGN_STOCK_CAPTURE_DIR=$taskStockCaptureRoot" --concurrency=1 --reporter expanded
python tools/build-design-capture-gallery.py (Join-Path $taskStockCaptureRoot 'focus')
python tools/build-design-capture-gallery.py (Join-Path $taskStockCaptureRoot 'disabled')
Remove-Item Env:\DESIGN_STOCK_CAPTURE_COMMAND
```

Без opt-in directory эти обычные regression tests выполняются, но ничего не записывают. Component case ID и `originIds` различаются: resource popup не объявляется36-м origin, shared MotionDropdown имеет usage mappings без приёмки всех полных экранов. Снимок сохраняется после actual contrast/focus assertions, до последующей activation; metadata содержит именно текущие counters/checked/pending/focus/motion. Capture creation не заменяет independent visual review.

T085 добавляет64version cases: catalog header, install effect, configuration recipe и executor runtime ×1100×760/800×600/390×800/360×800 ×light/dark×100/200%. Используется тот же opt-in helper и отдельная family `versions/` со своими PNG/records; human labels остаются UI. Standalone запуск сохраняет только64version PNG:

```powershell
$taskVersionCaptureRoot = Join-Path (Get-Location) ('.local/design-003/003.2/versions-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
$env:DESIGN_STOCK_CAPTURE_COMMAND = "flutter test test/widget/design_version_typography_test.dart `"--dart-define=DESIGN_STOCK_CAPTURE_DIR=$taskVersionCaptureRoot`" --reporter expanded"
flutter test test/widget/design_version_typography_test.dart "--dart-define=DESIGN_STOCK_CAPTURE_DIR=$taskVersionCaptureRoot" --reporter expanded
python tools/build-design-capture-gallery.py (Join-Path $taskVersionCaptureRoot 'versions')
Remove-Item Env:\DESIGN_STOCK_CAPTURE_COMMAND
```

Combined run с тремя component test files сохраняет24focus+32disabled+64versions=120PNG; основной runner отдельно добавляет744. Версии проверяются по actual bundled-Mono glyph metrics/pixels, точным значениям, переносам и сохранности UI labels/callbacks. Component evidence не добавляет origin36 и не доказывает native install/enrollment. Обычный запуск без directory ничего не пишет.

T087 дополняет component evidence family `scroll`: production shell context и log record ×4точныхframes×2themes×2scales, по два views start/end =64PNG. Их сохраняет `test/widget/design_bounded_scroll_test.dart` через тот же `DESIGN_STOCK_CAPTURE_DIR` и обязательный `DESIGN_STOCK_CAPTURE_COMMAND`. Снимки выполняются после keyboard/render assertions; selection/copy/close проверяются дополнительно. Usage05/23 обозначает representative shared component, `originIds=[]` не принимает полный runtime origin.

```powershell
$taskScrollCaptureRoot = Join-Path (Get-Location) ('.local/design-003/003.2/scroll-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
$env:DESIGN_STOCK_CAPTURE_COMMAND = "flutter test test/widget/design_bounded_scroll_test.dart `"--dart-define=DESIGN_STOCK_CAPTURE_DIR=$taskScrollCaptureRoot`" --reporter expanded"
flutter test test/widget/design_bounded_scroll_test.dart "--dart-define=DESIGN_STOCK_CAPTURE_DIR=$taskScrollCaptureRoot" --reporter expanded
python tools/build-design-capture-gallery.py (Join-Path $taskScrollCaptureRoot 'scroll')
Remove-Item Env:\DESIGN_STOCK_CAPTURE_COMMAND
```

Combined run четырёх component files сохраняет184PNG (24+32+64+64); основной runner отдельно744. Новый run не перезаписывает прежние результаты. PNG не заменяют independent visual review и не доказывают native clipboard или service effects.

## Снимки003.3: baseline и состояния

Existing capture entry поддерживает два отдельных режима. Baseline сохраняет35origins×4frames×2themes×2scales=560primary и184supplementary PNG. State запускает те же production state/privacy providers с четырьмя representative вариантами:1100×760/light+dark/100% и360×800/light+dark/200%. Это не полный F16 набор каждого состояния. Количество дополнительных checkpoints определяется исполняемыми journeys; нельзя подставлять число case IDs вместо числа PNG.

Используйте свежие разные sibling directories и exact command provenance. Не удаляйте partial/failed run ради повторного использования; выберите новый run suffix. Пример выполняется из корня репозитория после соответствующих regression tests:

```powershell
$taskDesignRun = Join-Path (Get-Location) ('.local/design-003/003.3/review-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
$taskBaselineRoot = Join-Path $taskDesignRun 'baseline'
$taskStateRoot = Join-Path $taskDesignRun 'state'
Remove-Item Env:DESIGN_STATE_CAPTURE_DIR -ErrorAction SilentlyContinue
Remove-Item Env:DESIGN_CAPTURE_DIR -ErrorAction SilentlyContinue
$env:DESIGN_CAPTURE_COMMAND = "flutter test test/widget/design_capture_test.dart --dart-define=DESIGN_CAPTURE_STAGE=003.3 --dart-define=DESIGN_CAPTURE_MODE=baseline `"--dart-define=DESIGN_CAPTURE_DIR=$taskBaselineRoot`" --reporter expanded"
flutter test test/widget/design_capture_test.dart --dart-define=DESIGN_CAPTURE_STAGE=003.3 --dart-define=DESIGN_CAPTURE_MODE=baseline "--dart-define=DESIGN_CAPTURE_DIR=$taskBaselineRoot" --reporter expanded
if ($LASTEXITCODE -ne 0) { throw 'Baseline capture failed; preserve this run and inspect its output' }
Remove-Item Env:DESIGN_CAPTURE_COMMAND
$env:DESIGN_STATE_CAPTURE_COMMAND = "flutter test test/widget/design_capture_test.dart --dart-define=DESIGN_CAPTURE_STAGE=003.3 --dart-define=DESIGN_CAPTURE_MODE=state `"--dart-define=DESIGN_STATE_CAPTURE_DIR=$taskStateRoot`" --reporter expanded"
flutter test test/widget/design_capture_test.dart --dart-define=DESIGN_CAPTURE_STAGE=003.3 --dart-define=DESIGN_CAPTURE_MODE=state "--dart-define=DESIGN_STATE_CAPTURE_DIR=$taskStateRoot" --reporter expanded
if ($LASTEXITCODE -ne 0) { throw 'State capture failed; preserve this run and inspect its output' }
Remove-Item Env:DESIGN_STATE_CAPTURE_COMMAND
python tools/build-design-capture-gallery.py $taskBaselineRoot
foreach ($taskFamily in @('foundation','server','automation','privacy')) {
  python tools/build-design-capture-gallery.py (Join-Path $taskStateRoot $taskFamily)
}
```

State mode разрешён только для003.3; неизвестный mode/stage, противоположный output directory и отсутствие003.3 command provenance отклоняются. Ordinary run без opt-in directory ничего не пишет. Перед gallery убедитесь в успешном exit соответствующего capture run; gallery generation сама по себе не acceptance. Actual input hashes, enclosing test exits, per-case scope, inventory и независимые visual reports конкретного прохода записываются в [evidence](evidence.md). Positive privacy trust/executor fixtures используют реальный future deadline, поэтому отдельные timestamp digits между runs могут отличаться; это требует сверки значений, а не произвольного identity carry.

## Windows composition smoke

Для финальной изменённой shell/app composition после mandatory widget checks:

```powershell
./tools/test-bootstrap-ui.ps1
```

Ожидается успешный build/drive и фактические assertions synthetic bootstrap/readiness/profile lifecycle текущего integration test; script сохраняет изолированную fixture для диагностики. Smoke не доказывает remote install/trust/grants/security matrix и не объявляет завершённым001/021. Нативный запуск нельзя заменить открытием HTML.

## Evidence record

Для каждого этапа записать revision/dirty-scope, SDK identity, changed files, A-group/screenID/FR/AC/taskID, fixture/state/frame/theme/scale, command/exit/result, capture и ограничения. `not-run`/blocked/N/A с причиной не превращать в pass. До handoff реализации после Tasks завершить mandatory link check и fresh независимый review пакета; после confirmed fixes повторить checks/review. Этот guide не содержит выполненных результатов.
