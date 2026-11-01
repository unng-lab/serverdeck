# Независимое ревью реализации 003.4, round 2

Найдено 4 замечания, которые стоит исправить.

Готовность к реализации: готов — обязательные решения закреплены; новые продуктовые/архитектурные решения не нужны.

Готовность реализации к приёмке: не готова. Read-only reviewer `/root/review_components_code_round2`, `fork_turns="none"`, проверил AGENTS, пакет, библиотеку, каталог, тесты, adoption diffs, registry, HTML и tooling. Посторонние backend/spec изменения исключены, файлы не изменялись.

1. **P2, C26**: editable `text` без внешнего controller копирует начальное значение; current-copy исправлен только для controller-пути. Нужен local controller либо запрет режима, exact edit→copy regression.
2. **P2, C27**: unavailable оставляет дерево активным; selectedId не передаётся, callback только report. Нужны настоящий controlled selection и unavailable без активных callbacks, assertions.
3. **P2, C19**: реальный каталог сохраняет ValueKey(id); изменение initiallyExpanded не управляет уже существующим ExpansionTile. Default→expanded и обратный переход не работают, хотя captures пересоздают fixture и проходят. Нужна синхронизация/пересоздание при selector state change; theme/resize должны сохранять draft.
4. **P2, C25**: Flutter-пример содержит changed/added/conflict, но обязательный removed отсутствует. Нужны удалённая запись, проверка отсутствующей after-стороны и новые captures.

Round1 fixes подтверждены частично: bounded collection/code, карточки документации, независимые fixtures и достижимые validators улучшены. Остаются части T141/T144/T145. Проверенные логи: format499/0, analyze clean, test195/1skip, lychee0errors, Windows builds и HTML2504/0. Reviewer их самостоятельно не запускал. Native pixels/control clicks не установлены; новые backend-эффекты/перенос полномочий не найдены.
