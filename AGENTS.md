# Working Rules

## Spec Kit

- Spec Kit is installed in this repository: `.specify/` and `.agents/skills/speckit-*`.
- If the user asks to work through Spec Kit, use the Spec Kit skills and workflow.
- The user's 2026-10-28 cleanup instruction removes the custom design-binding
  language, duplicate reference validators, schema bundles and hash/receipt
  pipeline. Keep design work in Flutter with ordinary unit/widget tests and
  direct comparison with the canonical mockups. Do not recreate that machinery.
- The user temporarily permitted Computer Use on 2026-10-29, then explicitly
  suspended it again. Do not use Computer Use or desktop UI automation until
  the user grants new permission. Ordinary executable launch for delivery
  remains authorized; this does not authorize native/integration test workloads.

## Current user priority — 2026-10-29

- The intermediate003 visual-correction candidate is `0.3.0-preview.3+14`.
  Prior private `0.3.0-preview.2+13` installations remain preserved. The
  released/installed `0.3.0-preview.1+12` remains preserved. Earlier
  `0.2.1+11` installations are preserved historical progress builds. Its normal
  local build/install precedes the final full test run by explicit user order.

- The current task is **003 only**. Do not implement packages004–020 as part of
  this task. Their product roadmap is preserved, not a prerequisite for003.
- Finish the remaining003 implementation as one batch, then prepare and install
  an intermediate Windows Release build so the user can use it. Do not block
  that local delivery on repeated full test cycles for individual UI changes.
- Run the full mandatory static/unit/widget set after that implementation and
  intermediate install. Run targeted tests only for scenarios that fail in the
  full run; fix them and rerun the mandatory set before final completion.
- Audit test duplication without deleting distinct behavior, privacy, identity,
  concurrency, recovery or accessibility coverage merely to shorten the run.
- The validation stage remains static/unit/widget only, locally and in CI.
  No native/integration dispatch, provider work or public Windows
  binaries follows from this order. Existing source-only publication and CI
  gates remain applicable; local intermediate delivery may precede them.

## Required Checks

- After changing Flutter code, run `dart format --output=none --set-exit-if-changed .`,
  `flutter analyze`, and `flutter test`. Fix failures before committing.
- After changing specifications, check their links with
  `lychee "specs/**/*.md"`. Fix broken links before committing.
- Do not report checks as passed unless they were actually run successfully.

### Current Unit/Widget Stage

- The user explicitly approved this stage on 2026-10-27 for both local checks
  and automatic GitHub CI, in accordance with constitution VII (4.0.0).
  It continues for the ordinary MIT source-only `0.2.0` release
  (Flutter version `0.2.0+10`), following the completed PR #3 / preview9.
  Required checks use unit/widget tests and static analysis only. The ordinary
  release label does not establish platform or whole-product acceptance.
- The user's 2026-10-28 instruction explicitly continues the same local and CI
  unit/widget/static stage for the corrected `003.4` base-page design port.
  The current implementation scope is existing base functions with their exact
  canonical design; future feature packages own their design and functionality
  together. A private build, preservation-safe install and actual UI showing are
  authorized delivery actions. No public release, new provider deployment or
  native/integration test dispatch follows from that instruction.
- The corrected private base-design build uses Flutter metadata `0.2.1+11`.
  It continues this same unit/widget/static stage; the version increment does
  not establish visual, platform or native qualification, or publish a release.
- Use the pinned Flutter 3.47.7 / Dart 3.13.5 SDK via
  `tools/foundation-sdk.ps1`; SDK preparation resolves locked tooling and
  verifies identity. It does not authorize native build or fixture scripts.
  Restore the root and `serverdeck_protocol`, `serverdeck_windows`,
  `serverdeck_locald`, and `serverdeck_mcp` package dependencies with
  `pub get --enforce-lockfile`. MCP restore supplies package configuration
  required by root analysis; it does not select the MCP test suite.
- From the repository root, run the existing format and analysis checks and
  `flutter test --reporter expanded` against ordinary `test/`. Set
  `SERVERDECK_NATIVE_CONTROL_RED=0`, clear `DESIGN_CAPTURE_DIR`,
  `DESIGN_STATE_CAPTURE_DIR`, and `DESIGN_STOCK_CAPTURE_DIR`, and supply no
  capture `--dart-define` flags. The normal opt-in capture skip is expected.
- Run `dart analyze` in each affected Dart package; the current automatic
  gate analyzes `packages/serverdeck_protocol`, `packages/serverdeck_windows`,
  and `packages/serverdeck_locald`. The additional selected unit commands are:
  - In `packages/serverdeck_protocol`:
    `dart test --reporter expanded`.
  - In `packages/serverdeck_locald`:
    `dart test test/server_peer_coordination_test.dart --reporter expanded`.
    This scheduler suite uses fake delegates and completers; its filename
    does not authorize native peer fixtures.
- Do not run full `dart test` in `serverdeck_windows`, `serverdeck_locald`,
  or `serverdeck_mcp` in this stage. Product-native/FFI/Isar/DPAPI, real
  service/process/pipe/SSH, integration, container/Docker/systemd/Ansible,
  cold-runner, and native qualification workloads are deferred and not run.
  Ordinary SDK tooling and the Flutter VM/widget runner are prerequisites
  of the selected unit tests, not product-native qualification.
- The automatic push/PR check is `unit-widget-checks` in
  `.github/workflows/mcp.yml`; require successful results for the reviewed
  source revision. The preserved `ssh-transport`, `executor-prerequisites`,
  and `windows` jobs run only with explicit manual
  `workflow_dispatch` profile `native-full`. The separate Foundation Windows
  workflow remains manual. Neither manual native profile may be dispatched
  without a separate user instruction.
- Record deferred checks as not run; skipped CI jobs and earlier partial or
  failed runs do not become native passes. This stage gates the current
  source-only merge/release, including ordinary `0.2.0`, and does not establish full native,
  runtime, signing, distribution, or product acceptance. Authorized private
  build/package/install actions retain separate delivery evidence and do
  not authorize integration tests.
- Specification link checks and the independent review/fix loop below
  remain mandatory. A change of validation stage requires explicit user
  agreement and corresponding updates to rules and CI.

## Independent Review and Fix Loop

- After changing application code and successfully completing the mandatory
  checks, run an independent review in a separate subagent task. Also run this
  review after changing a specification package and completing its mandatory
  checks, before handing the package off for implementation.
- Use `collaboration.spawn_agent` with `fork_turns="none"` so the reviewer does
  not inherit the chat history. Do not use `create_thread`, `fork_thread`, or
  other tools that create a separate user-visible project chat for this review.
- Give the reviewer a self-contained task containing the review instructions
  below, the repository paths, the exact changed files or diff to inspect, and
  the relevant specification package paths. Have it read applicable `AGENTS.md`
  instructions and the source artifacts directly. Pass actual check results as
  evidence, clearly identifying their scope; do not pass conclusions that the
  reviewer should merely confirm.
- The reviewer must inspect without modifying files. It may work in parallel
  with independent work, but do not change the reviewed files while it is
  reviewing them. Wait for its completed report before treating the work as
  finished or committing it.
- Assess every finding against the artifacts and code. Fix confirmed defects
  and missing mandatory decisions within the user's authorized scope, recording
  new specification tasks without erasing completed task history. Do not invent
  product or architecture requirements to close a finding. If a necessary
  decision cannot be established from the authorized scope, ask the user and
  report that the review loop remains incomplete.
- After fixes, rerun all mandatory checks applicable to the changed files, then
  launch a fresh reviewer with `fork_turns="none"` and repeat the cycle. Finish
  only when the completed review has no unresolved confirmed findings and the
  applicable readiness conclusion is supported. A failed, interrupted, or
  inconclusive review is not a clean result. If the loop cannot progress, report
  the concrete blocker and remaining findings instead of claiming success.

### Reviewer Instructions

Проверь изменения кода и связанный пакет спецификации как задание, по которому
другой разработчик должен реализовать сервис без дополнительных продуктовых и
архитектурных решений. Для изменений кода также проверь соответствие реализации
этому пакету, дефекты и регрессии в затронутом поведении.

Ищи не только противоречия и ошибки, но и обязательные решения, которые
отсутствуют: исполнитель будет вынужден задавать вопросы или самостоятельно
придумывать требования. Для каждого такого пробела приведи конкретный сценарий,
последствия и что именно нужно закрепить.

Проверь всю цепочку: требование → проектное решение → контракт → задача
реализации → проверяемый критерий приёмки. Отмечай отсутствующие звенья.

Обязательно рассмотри:

- состав компонентов, их ответственность и место реализации;
- интерфейсы, протоколы, схемы, версии и совместимость;
- авторизацию, отзыв, credentials и жизненный цикл доверия;
- конкурентные операции, повторы, порядок событий и восстановление;
- конфигурацию, defaults, диапазоны, сроки и ресурсные ограничения;
- runtime prerequisites, зависимости, миграции и состав выпуска;
- проверки нормальной работы, отказов и граничных условий.

Формулировки «TBD», «согласовать позже», «определить перед реализацией»,
draft-статус и наличие будущей задачи не закрывают обязательное решение. Укажи,
что пакет пока не готов к реализации, если это решение необходимо для начала
соответствующих задач.

Отличай обязательные требования от деталей, которые разработчик вправе выбрать
самостоятельно. Не требуй конкретные серверы, namespace или production rollout,
если они вне scope; проверь, что сервис определяет необходимые интерфейсы,
артефакты и требования к среде.

Вывод «готов к реализации» допустим только при отсутствии подтверждённых
обязательных пробелов. Отсутствие найденных дефектов само по себе не означает
готовность.

Начни отчёт двумя отдельными выводами:

1. «Найдено N замечаний, которые стоит исправить» либо «Замечаний не найдено».
2. «Готовность к реализации: готов / не готов / не удалось установить» —
   с обоснованием.

Затем покажи проверенный scope, все замечания с доказательствами и необходимым
закрытием, общее влияние и реальные ограничения проверки. Не придумывай
требования или выполненные проверки. Если связанный пакет отсутствует или
недостаточен для оценки, явно укажи это ограничение и не объявляй готовность
установленной.
