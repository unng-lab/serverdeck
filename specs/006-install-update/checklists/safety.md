# Requirements Quality Checklist: доверие и восстановление 006

**Created**: 2026-11-04 | **Feature**: [spec.md](../spec.md)
**Purpose**: Reviewer-owned quality review перед реализацией. [x] = качество требований,
не готовность кода. Новые пункты открыты до независимой оценки. Scope security/recovery.

## Completeness and clarity

- [x] CHK001 Разделены ли installer, приложение и transient maintenance? [Completeness, Spec FR-601, installation §Artifacts]
- [x] CHK002 Определены ли keys/signature/rotation и trust boundary первого setup? [Clarity, releases §Immutable build policy, §Build and signing]
- [x] CHK003 Однозначно ли согласие связано с выпуском? [Consistency, Spec FR-607, releases §Catalog codec]
- [x] CHK004 Описаны ли отзыв/expiry/offline/compatibility до apply? [Coverage, Spec FR-608–609, releases §Network]
- [x] CHK005 Заданы ли размеры, сроки, redirects/cancel? [Measurability, Spec FR-610, releases §Network]

## Recovery and concurrency

- [x] CHK006 Закреплены ли authority, lock order, handoff и отсутствие force kill? [Completeness, FR-611–612, installation §Serialization]
- [x] CHK007 Определены ли partial replace/registration и recovery до host? [Coverage, FR-604,612, installation §Transaction]
- [x] CHK008 Определены ли rollback boundary и сохранность данных? [Consistency, FR-613, installation §Transaction]
- [x] CHK009 Описаны ли self-uninstall/temp image/partial retry? [Coverage, FR-614, installation §Uninstall]
- [x] CHK010 Закреплены ли deletion boundaries/reparse/SID/MCP path? [Clarity, FR-614–615, installation §Artifacts]

## Acceptance and environment

- [x] CHK011 Определены ли developer missing-source и publishable inputs? [Completeness, plan §Delivery, releases §Immutable build policy]
- [x] CHK012 Соответствуют ли UI/lifecycle общей библиотеке и tray-only exit? [Consistency, FR-617, platform §UI]
- [x] CHK013 Проверяемы ли сценарии unit/fake без запрещённых прогонов? [Measurability, quickstart §Unit acceptance]
- [x] CHK014 Есть ли FR/AC/SC → contract → task traceability? [Completeness, plan §Traceability, tasks.md]


## Reviewer evidence

Независимый review_006_design_final подтвердил CHK001–014 как качество требований.
Это не готовность реализации: отдельно найденная неоднозначность manual-check
уточнена в platform contract и T031; fresh independent review требуется до кода.
