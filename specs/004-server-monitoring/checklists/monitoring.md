# Monitoring Requirements Quality Checklist: 004

**Purpose**: Reviewer gate before implementation.
**Created**: 2026-11-04
**Feature**: [spec](../spec.md), [plan](../plan.md)

**Review Ownership**: Reviewer-owned. [x] approves requirements quality, not code.
Generated items remain unchecked; implement reads but does not modify markers.

## Completeness and Clarity

- [x] CHK001 Определены ли метрики, формулы и границы 0/90/100? [Clarity, Spec FR-401–403]
- [x] CHK002 Определены ли fresh/stale/partial отдельно от нулей? [Completeness, Spec FR-407/413]
- [x] CHK003 Заданы ли период, deadline, вывод и fairness? [Measurability, Spec FR-405–406]
- [x] CHK004 Покрыты ли новые MCP-профили и ручная остановка? [Coverage, Spec AC-412/414]

## Security and Recovery

- [x] CHK005 Заданы ли trust/credentials, current OwnerActor и отзыв pending actor до promotion? [Consistency, Spec FR-409/412]
- [x] CHK006 Определена ли cancellation до open/exec ACK и retired ресурсы? [Coverage, Contract Bounded transport extension]
- [x] CHK007 Определены ли crash marker и отказы I/O? [Coverage, Spec FR-410, Contract Runtime marker]
- [x] CHK008 Ограничены ли Linux prerequisites и приватность вывода? [Completeness, Spec FR-411/414]

## Acceptance and Dependencies

- [x] CHK009 Связаны ли FR с контрактами/задачами/unit-приёмкой? [Traceability, Spec FR-401–415]
- [x] CHK010 Согласованы ли C IDs и запрет feature-screen design/integration gates? [Consistency, Spec FR-415, Constitution]

## Notes

Generated via speckit-checklist: monitoring lifecycle/security, standard depth,
reviewer before implementation. Author may fix requirements; completed reviewer
owns checkbox evaluation. Requirements.md has separate built-in lifecycle.

Reviewer review_004_plan одобрил CHK001/002/003/006/007/008/010; автор только
механически записал его markers. CHK004/005/009 ждут свежего ревью R1/R2.

Fresh reviewer review_004_plan2 одобрил CHK001–010; markers CHK004/005/009
механически записаны автором по его прямому разрешению. Это quality approval,
не результат выполнения задач/тестов.
