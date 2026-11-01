# Independent review: direct SSH host metadata

Date: 2026-11-01. Reviewers use fresh context and do not modify files.

## Round 1 — direct_ssh_host_review_1

Найдено 2 замечания, которые стоит исправить.

Готовность к реализации: не готов — cancel/recovery defects in the metadata increment. The governing specification supplies the necessary decisions.

Exact scope: remote/direct_ssh.dart (closed factories/tool guards/deadlines), new part remote/direct_ssh_jobs.dart (captured attempt, correlated metadata parser, reserve/stop/status builders), new test/remote/direct_ssh_jobs_test.dart; related SDSSH1 codec and specs001 with006/021 amendments.

P2#1: stop checked the current owner before writing its plan fence. OwnerA between steps could prevent stopB while reserveB was delayed. After A released, B could reserve without a tombstone. Contract section7 requires permanent attempt/plan stop before delayed reserve, even without B's owner. Remediation T437: independent scoped stop fence without modifying foreign owner; compiled source/RAM metadata sequence covers A→stopB→releaseA→lateReserveB and stop-before-plan crash window.

P2#2: global ownerB caused requested terminalA history to be rejected by the metadata parser after lost release ACK. Contract section8 requires reading A's terminal marker. Remediation T438: separate foreign owner presence from matching A records, retain strict schemas/host/attempt/plan correlation, do not return B's tuple as A's owner or permit its release; tampered terminal negatives.

Review inspected actual `.local/direct-ssh-host-full-r6.exit=0`/log: format436/0changes, successful analyses and820Dart tests+16RAM groups. Link evidence `.local/direct-ssh-host-links-r1.exit=0`:1581OK/0errors/2excluded. Formatter emitted known analysis-include resolution warnings in unrelated work/isar-encryption-implementation. Reviewer did not rerun checks or execute shell/SSH/FS/systemd/APT.

The first3tests check RAM data and compiled source structure; they do not prove native race/crash/durability behavior. Two subsequent regression cases reproduced the findings in `.local/direct-ssh-host-review-red.log` before fixes. Round1 remains a non-clean historical result; verified closure is recorded in round2 below. Worker/stage/effects/start/result/release, actual controller/native authority integration and the complete migration remain open tasks; T410/T411 are not closed as a whole.

## Round 2 — direct_ssh_host_review_2

Замечаний не найдено.

Готовность к реализации: готов — в пределах host metadata increment, не полной миграции.

Fresh read-only review inspected the three source/test files, codec/transport, governing001 artifacts and006/021 consumers. It confirmed both closures: stopB fences a delayed reserve independently of ownerA and without changing A; terminalA remains readable with current ownerB, represented only by foreignOwnerPresent rather than returned as A's owner. Strict own record correlation and reserved-response requirements remain. T437/T438 are closed.

The reviewer also checked refusal of partial layouts, permanent lock inode, owner→plan→admission ordering, stale-boot refusal before initialization, custody/mode/link bounds, bounded inventory with required DONE, cross-device refusal, tombstones and non-mutating status. The requirement/design/contract/task/acceptance chain was checked with no mandatory decision gap found in this scope.

Evidence inspected, not rerun: `.local/direct-ssh-host-review-full-r2.exit=0`, format436/0changes, analyses passed, root86+engine656+MCP15+protocol57+Windows8=822Dart tests,16RAM bundle groups. `.local/direct-ssh-host-links-r2.exit=0`,1581OK/0errors/2excluded. The unrelated work/isar-encryption-implementation formatter include-resolution warnings remain explicitly noted.

Native race/crash/durability and real shell/SSH/FS/systemd/APT are not established by RAM/source checks. Stage/worker/effects/start/result/terminal release and actual controller/native authority integration remain open. T406/T410/T411/T412/T422 and the complete migration are not closed by this review.
