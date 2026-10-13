# Working Rules

## Spec Kit

- Spec Kit is installed in this repository: `.specify/` and `.agents/skills/speckit-*`.
- If the user asks to work through Spec Kit, use the Spec Kit skills and workflow.

## Required Checks

- After changing Flutter code, run `dart format --output=none --set-exit-if-changed .`,
  `flutter analyze`, and `flutter test`. Fix failures before committing.
- After changing specifications, check their links with
  `lychee "specs/**/*.md"`. Fix broken links before committing.
- Do not report checks as passed unless they were actually run successfully.

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
