# Planning review: 004

## Round 1 — 2026-11-04

Read-only independent reviewer found two confirmed defects:
R1 (P1): original MCP actor revalidation contradicted 003 application-owned
established sessions. Current canonical OwnerActor required after promotion;
pending revocation policy preserved. Contract/plan/T007/checklist updated.
R2 (P2): completed MCP connect/disconnect while screen inactive could escape
polling suppression. Canonical ConnectionOwner generation>0 and retained IDs now
suppress admission even disconnected; survives profile revisions, checked again
at admission. Model/contract/T010 updated. T021 records both regression scenarios
without erasing existing task history.

Before review lychee exit0:174 total,168OK,0errors,6excluded,2redirects.
No application code/test/build changed or run. Reviewer approved seven custom
checklist IDs; remaining three pending fresh review after fixes.

## Round 2 — 2026-11-04

Fresh read-only reviewer review_004_plan2: замечаний не найдено; готовность к
реализации — готов. Read full package and current relevant001/002/003/code.
R1/R2 closure confirmed. All CHK001–010 approved; author explicitly permitted
to record only mechanical approval markers. No code implementation tested.
After R1/R2 fixes lychee exit0:174total,168OK,0errors,6excluded,2redirects.

## Spec Kit analyze — 2026-11-04

Read-only cross-artifact analysis after task generation: 15 FR, 4 SC, 21 tasks
(including appended review regression T021). Coverage19/19 =100%; ambiguity0,
duplication0, critical0; no unmapped tasks or constitution conflicts found.

| Requirement | Tasks |
| --- | --- |
| FR-401 | T002/T008/T009/T012/T013 |
| FR-402 | T002/T008/T009 |
| FR-403/404 | T014/T015 |
| FR-405 | T010/T011/T012 |
| FR-406 | T005/T006/T008/T010/T011/T016 |
| FR-407 | T002/T016/T017 |
| FR-408 | T010/T011/T012 |
| FR-409 | T005/T006/T007/T010/T011/T017/T021 |
| FR-410 | T003/T004/T016/T017/T018 |
| FR-411 | T009/T016/T017 |
| FR-412 | T002/T005/T006/T007/T011/T016/T017/T021 |
| FR-413 | T016/T017/T018 |
| FR-414 | T001/T004/T005/T006/T007/T009/T016/T017 |
| FR-415 | T001/T012/T013/T015/T018 |
| SC-401 | T010/T011/T013/T019 |
| SC-402 | T014/T015/T019 |
| SC-403 | T016/T017/T018/T019 |
| SC-404 | T007/T010/T016/T017/T021/T019 |

Next: speckit-implement. Converge follows implementation, not this readiness check.
No application changes yet; unit/native/build checks not run in planning phase.
