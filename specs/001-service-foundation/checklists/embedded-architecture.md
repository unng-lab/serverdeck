# Checklist: качество требований встроенного движка

**Purpose**: reviewer-owned проверка полноты существующей001/002/021 после поправки.
**Created**: 2026-10-30 | [Spec](../spec.md) | [Plan](../plan.md)
Новые пункты остаются unchecked до решения reviewer; это не implementation tests.

## Completeness and consistency

- [ ] CHK001 Ясно ли заменён обязательный locald существующими требованиями001, без нового feature? [Consistency; Spec FR-SVC-001/002]
- [ ] CHK002 Закреплены ли domain/UI/MCP/platform responsibilities и неподделываемый источник owner/MCP полномочий? [Completeness; embedded-engine]
- [ ] CHK003 Полностью ли описаны schema versions, record families, secret bindings, adoption/return и close-failure ownership? [Completeness; embedded-migration]
- [ ] CHK004 Сохранены ли challenge/grant/revoke/approval/publication fences при смене process identity? [Security; 021 embedded-host]
- [ ] CHK005 Однозначны ли close→tray, tray absence, explicit exit, sleep/suspend/crash/resume? [Clarity; embedded-engine lifecycle]
- [ ] CHK006 Отличены ли remote accepted job и observer loss, lost ACK/missing attempt/unknown/cancel/reconcile? [Recovery; 021 embedded-host]
- [ ] CHK007 Определены ли limits, CAS, sampler identity, event ordering и late-response fences всех клиентов? [Concurrency; embedded-engine]
- [ ] CHK008 Указаны ли точные bundle/discovery/handshake versions и старый bridge refusal? [Compatibility; 021 embedded-host]
- [ ] CHK009 Разделены ли Windows implementation и будущие платформенные поставки без ложных доказательств? [Scope; embedded-platforms]
- [ ] CHK010 Каждое новое FR имеет contract/task/AC, а старые completed tasks/evidence сохранены? [Traceability; Tasks T253–T272]
- [ ] CHK011 Определены ли разрешённые full checks до адресных tests, ограничения evidence и запрет native/SSH/container/UI automation? [Validation; Quickstart]
- [ ] CHK012 Отсутствуют ли обязательные решения, оставленные исполнителю под видом будущей задачи, и конфликт с конституцией4.3.0? [Readiness; полный пакет]
