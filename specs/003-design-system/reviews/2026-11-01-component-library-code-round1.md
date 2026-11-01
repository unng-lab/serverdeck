# Независимое ревью реализации 003.4, round 1

Найдено 7 замечаний, которые стоит исправить.

Готовность к реализации: готов — обязательных продуктовых или архитектурных решений для начала реализации не выявлено.

Готовность реализации к приёмке: не готова. Успешные gates и число captures не закрывают подтверждённые дефекты и неполное поведение каталога.

Read-only reviewer `/root/review_components_code_round1`, `fork_turns="none"`, прочитал AGENTS.md, пакет 003.4, shared controls/collections/patterns, catalog/tests, registry, HTML sources/tools и adoption diffs; просмотрел репрезентативные round5 captures. Файлы не изменял; посторонний backend исключён.

## Подтверждённые замечания

1. **P2 — C26 копирует прежний текст.** `deck_patterns.dart`, DeckCode читает controller.text при build и передаёт snapshot в DeckCopyButton, не слушая controller. После редактирования JSON копируется исходное значение. Нужны актуальное чтение/подписка и точный edit→copy assertion.
2. **P2 — bounded DeckCollection переполняет высоту.** Высота списка использует весь constraints.maxHeight без резерва для header/notices/sort controls. В Expanded 400 px дополнительные части вызывают RenderFlex overflow. Нужны bounded-host assertions для wide/phone/notices/200%.
3. **P2 — C26 не имеет bounded scroll.** Read-only DeckKeyValue и editable maxLines:null увеличивают высоту с размером JSON. Нужны ограниченная область и собственная прокрутка в обоих режимах, точное selection/copy и keyboard-scroll checks.
4. **P1 — state matrix часто только переименовывает один UI.** C16 disabled активен; C05 no-results превращается в empty; C12 stale/partial выводят empty; focus не переводит control в focus; hover/pressed/no-results/unavailable не имеют реализации или N/A; HTML не показывает ряд состояний и обводит preview вместо control. Нужны настоящие события/fixtures и assertions смысла состояний, правдивая применимость.
5. **P1 — не все обязательные варианты представлены.** Примеры: C03 readonly/error; C09 interactive/error; C13 validation summary; C16 back/disabled; C17 navigation/topbar/shell вместо одного body; C23 success/error/cancel; C29 частичная доступность. Validators C26/C28 недостижимы вне Form/validate; DateTime.tryParse нормализует 2026-02-31. Требуется полный аудит подэлементов C01–C30 и working variants/failure checks.
6. **P2 — карточки без обязательной документации.** Нужны конкретные screen IDs, анатомия, параметры/события, ограничения, критерии и пример подключения на каждой карточке. Общая подсказка импорта и путь examples.dart не заменяют FR-CL-01/AC-CL-01.
7. **P2 — нет независимого job fixture для AC-CL-03.** jobs=true меняет только заголовки тех же server rows. Нужны отдельные job поля/ID/actions и обе схемы через одну коллекцию: sort/filter/selection/narrow, null/equal sort и удаление выбранной строки.

## Влияние и ограничения

Библиотека выделена и применяется; owners и offline-границы прослеживаются. Но 2544 captures не являются 2544 проверками корректных состояний, если часть fixtures одинаковы.

Фактические результаты gates предоставлены основным агентом: format/analyze/test/lychee, 1024 browser cases, 2544 widget captures, catalog/default Windows builds и ранний argument-guard smoke. Reviewer их не повторял. Native pixel correctness/control clicks не установлены; эта честно указанная граница проверки сама по себе не объявлена новым дефектом. После исправлений обязательны применимые gates и fresh independent review. Текущий цикл не завершён.
