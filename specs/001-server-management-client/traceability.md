# Requirement -> task -> verification

Coverage is planning coverage, not implementation completion. Existing BR IDs remain.

| Requirement | Tasks | Verification/gate |
|---|---|---|
| BR-S01 | T004,T005,T006 | fixture profile/navigation tests; AC01 connected later |
| BR-I01 | T004,T006 | fixture cross-server version view; AC02 detector evidence |
| BR-I02 | T004,T006 | unknown/source fixtures; AC02 unsupported scans |
| BR-L01 | T004,T007 | fixture history/stream; AC03 SSH journal |
| BR-L02 | T004,T007 | journal ring/history/oversize tests; SC02 |
| BR-L03 | T004,T007 | pause/navigation session tests; AC03 reconnect |
| BR-L04 | T004,T007 | message/unit/priority/time/details tests; explicit copy |
| BR-L05 | T004,T007 | malformed/denied/gap tests; AC03 SSH faults |
| BR-L06 | T004,T007 | selectable journal/newest-first fixture; AC03 desktop copy |
| BR-M01 | T004,T008 | stale/null tests; SC03 interval SSH sampling |
| BR-J01 | T004,T010 | nonexecuting plan preview; AC04 real reviewed plan |
| BR-J02 | T011 | AC04 exact pins/no-op/data preservation |
| BR-J03 | T010 | AC05 durable phases/probe failure |
| BR-J04 | T010 | AC05 duplicate/restart/cancel/competing writer |
| BR-S02 | T009 | AC07 and disposable service actions |
| BR-C01 | T004,T005,T012 | fixture offline; AC06 persisted offline |
| BR-C02 | T012 | AC06 conflicts/privacy/revisions |
| BR-A01 | T004,T013 | SC01 Windows build/integration smoke |
| BR-T01 | T002,T010,T011 | runner version smoke + AC04 |
| BR-P01 | T005,T009,T010,T011,T012,T013 | AC07/SC04/SC05 authority/privacy/identity |

20 requirements, 20 with tasks (100%); 13 umbrella tasks, none unmapped.
SC01 T004/T013; SC02 T004/T007; SC03 T004/T008; SC04 T005/T012;
SC05 T010/T011. AC01 T005/T006; AC02 T006; AC03 T007; AC04 T011;
AC05 T010; AC06 T005/T012; AC07 T005/T009/T010/T011.

Source provenance: research BR-L05 (timing/raw fields) maps to canonical BR-L04;
canonical BR-L05 retains its initial spec meaning (honest failure/freshness).
Research BR-L06 is now explicit in the spec; its source ID is not discarded.
