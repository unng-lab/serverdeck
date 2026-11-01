# Независимое ревью embedded-поправки — 2026-10-30, цикл1

Reviewer: отдельный subagent `embedded_readiness_review_1`, fork_turns=none,
read-only, completed report. Проверены001/002/021 и связанные исходники;
backend/003 не оценивались как изменения этой задачи.

1. Найдено1 замечание, которое стоит исправить.
2. Готовность к реализации: не готов — новый watch не имел полного контракта.

P2: [engine](../contracts/embedded-engine.md) вводил общий watch(topic,cursor),
snapshot/delta/gap, но Local API определял snapshots/poll2s, observations021 —
typed start/status/cancel. Не были заданы темы/буферы/cursor/backpressure, разработчику
пришлось бы придумывать новую модель. Reviewer рекомендовал убрать расширение
и сохранить существующие methods/operation handles/polling.

Исправление: watch/event stream удалён из действующего контракта; существующие
typed APIs сохранены, sampler identity явно profile/connection/access/trust bound.
Добавлена T273 к истории задач. Остальные проверенные решения не имели подтверждённых
обязательных пробелов; CHK007/CHK012 ожидали этого исправления.

Переданное evidence первого цикла: lychee1570total/1569OK/0errors/1excluded,
scoped diffcheck0; reviewer сам команды не повторял. После исправления родитель
снова запустил lychee с тем же результатом и scoped diffcheck0. Это проверки
документации, не native/runtime acceptance. Свежий completed review обязателен
до заявления готовности. Flutter/Dart/native/SSH/container/UI не запускались.
