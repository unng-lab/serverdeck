# Checklist: Качество требований компактных событий

**Purpose**: Standard-depth reviewer assessment перед реализацией редизайна событий.
**Created**: 2026-11-10
**Feature**: [spec.md](../spec.md), [UI-контракт](../contracts/tools.md#компактное-событие-истории--2026-11-10).

**Review Ownership**: Reviewer-owned; [x] означает одобренное качество требований,
не готовый код. Implement читает gate и не меняет маркеры.

## Состав и смысл

- [x] CHK001 Определены ли сводка/подробности для каждого kind, host-level и удалённой карточки? [Completeness, AC-809–811/816, Contract Компактное событие]
- [x] CHK002 Согласованы ли author/UTC/сообщённый outcome с неизменными privacy/доменными контрактами? [Consistency, AC-810/816/817, Contract Компактное событие]
- [x] CHK003 Однозначны ли preview160/Unicode/whitespace/пустой результат и доступность полного исходного текста? [Clarity, SC-807, Contract Компактное событие]

## Lifecycle и приёмка

- [x] CHK004 Определены ли independent eventId, refresh/new/исчезнувшие id, context reset и независимость карточек? [Coverage, AC-817, Contract Компактное событие]
- [x] CHK005 Описаны ли keyboard/semantics и отсутствие эффектов раскрытия без новых owner/MCP/store требований? [Consistency, AC-817, Plan Компактные события]
- [x] CHK006 Полна ли цепочка FR-814/SC-807 → решение/контракт → T034–T036 → AC-816/817 с unit-only приёмкой? [Traceability, Plan/Tasks/Quickstart]

- [x] CHK007 Закреплён ли выбор существующих C06/C07 и отсутствие локального accordion-аналога, включая single selection ПО? [Consistency, FR-813/814, Plan Коллекция ПО, Tasks T038]
