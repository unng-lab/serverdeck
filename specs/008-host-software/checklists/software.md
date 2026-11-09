# Checklist: Shell, карточки и журнал ПО

**Purpose**: Качество требований перед реализацией; standard depth, независимый reviewer.
**Created**: 2026-11-09
**Feature**: [spec.md](../spec.md), [контракт](../contracts/tools.md).

**Review Ownership**: Checklist принадлежит reviewer. [x] означает рассмотренное
качество требований, а не выполненную реализацию. Новые пункты оставлены unchecked.

## Completeness / Clarity

- [x] CHK001 Определена ли граница между shell-действием и локальным CRUD? [Clarity, Spec FR-801/805, AC-807]
- [x] CHK002 Описаны ли все пять полей и неизвестные значения без угадывания? [Completeness, Spec FR-804; Model SoftwareCardRecord]
- [x] CHK003 Явно ли различаются подтверждение ввода и завершение команды? [Clarity, Spec AC-802; Contract Shell]
- [x] CHK004 Определён ли сценарий конфигов в рамках существующего shell? [Completeness, Spec FR-803]
- [x] CHK005 Определены ли UI/MCP действия и граница внешнего ИИ при анализе? [Completeness, Spec FR-811; Contract Интерфейс]

## Consistency / Privacy

- [x] CHK006 Согласован ли общий владелец UI/MCP с существующим доступом/отзывом? [Consistency, Spec AC-804; Plan Владельцы]
- [x] CHK007 Определён ли автор журнала без доверия к полям клиента? [Clarity, Spec FR-809; Model SoftwareEventRecord]
- [x] CHK008 Различаются ли metadata-журнал и непостоянный terminal output? [Consistency, Spec AC-811; Research История]
- [x] CHK009 Ограничены ли смысл пути и сообщённого исхода обычными данными? [Clarity, Spec Assumptions; Contract Shell/Интерфейс]

## Recovery / Bounds / Acceptance

- [x] CHK010 Определены ли конфликты редакций, смена endpoint и удаление профиля? [Coverage, Spec AC-806/808; Model Транзакции]
- [x] CHK011 Согласованы ли atomic effects/replay24h, включая удалённый профиль и отзыв доступа? [Consistency, Model Транзакции; Contract Общие формы]
- [x] CHK012 Определены ли paging, cursor, quotas, eviction и бюджеты без усечения полей? [Completeness, Contract Pagination; Model]
- [x] CHK013 Определено ли сохранение данных и состав локального выпуска? [Completeness, Spec FR-807/812; Plan Technical Context]
- [x] CHK014 Есть ли цепочка всех FR/AC/SC к задачам и unit-приёмке без запрещённых integration/layout gates? [Measurability, Tasks; Quickstart]

## Notes

speckit-implement читает состояния, но не изменяет маркеры. Оценку пунктов выполняет
reviewer; исправления требований проходят отдельный review/fix loop.
