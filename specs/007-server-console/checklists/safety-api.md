# Safety and API requirements checklist: Консоль сервера

**Purpose**: Reviewer-owned качество требований и полного design перед implement.
**Created**: 2026-11-06
**Feature**: [spec](../spec.md), [plan](../plan.md)
**Ownership**: [x] подтверждает качество требований после reviewer evaluation, не реализацию.

## Completeness / consistency

- [x] CHK001 Определены ли общие owner/channel/история UI/MCP без скрытого exec? [FR701/719/726]
- [x] CHK002 Определены ли default, поля/валидация и атомарность settings, включая отсутствующие/повреждённые данные? [FR704–706,data-model]
- [x] CHK003 Различены ли завершение оболочки, потеря связи, закрытие и удаление истории? [FR710/720,AC720]
- [x] CHK004 Закреплены ли авторизация grants, echooff/privacy, отзыв/expiry/EOF и предел уже выданных данных? [FR714/715/725]
- [x] CHK005 Определены ли единственное право ввода, UI takeover, expiry,partialline и отсутствие смешивания? [FR722]
- [x] CHK006 Определены ли retry/highWater/eviction/partialunknown без хранения payload или повторного эффекта? [FR724,data-model]

## Clarity / measurable boundaries

- [x] CHK007 Заданы ли caps сессий/очередей/parser/screen/history/replay и поведение превышения? [FR707/713,contracts]
- [x] CHK008 Определены ли pagination/current screen/versiongap/Unicode без неограниченного transcript? [FR720–721]
- [x] CHK009 Согласованы ли MCPtools,версии/discovery,schemas/results/errors и baseline003? [FR726,mcp-console]
- [x] CHK010 Определены ли late-open/rekey/pre-encryption/cancellation границы при сохранении общегоSSH? [ssh-console]

## Dependencies / acceptance

- [x] CHK011 Закреплены ли готовый engine/license/offline supply и scope001 C26 без локального аналога? [FR716–717]
- [x] CHK012 Все ли FR/AC/SC связаны с конкретными implementation/unit tasks без featurelayout/integration gates? [FR718,tasks]

## Notes

Пункты оставлены непомеченными при генерации. Reviewer оценивает качество исходных документов; статус не означает, что tests уже прошли.

Reviewer evaluation: CHK001–012 PASS; перенос маркеров поручен reviewer review_console_design_final, [отчёт](../reviews/design.md).
