# Main-window version: requirements quality

Reviewer audience; checked means requirements quality, not implementation success.
Feature: [spec](../spec.md), [contract](../contracts/platform.md#main-window-installed-version--fr-620).

- [x] CHK001 Is the current running version distinguished from offered/prepared versions? [Clarity, FR-620]
- [x] CHK002 Is the authoritative local source and full major.minor.patch representation defined? [Completeness, AC-618]
- [x] CHK003 Are pre-initialize/missing/empty values given a truthful unknown state? [Edge cases, contract]
- [x] CHK004 Are no-server and profile workspace paths both covered? [Coverage, AC-618]
- [x] CHK005 Are storage failure/retry and runtime rebinding behavior defined? [Recovery, FR-620]
- [x] CHK006 Are no extra network/DB/server work and no persisted/schema changes specified? [Dependencies/privacy, SC-606]
- [x] CHK007 Are shared components reused with functional-only acceptance? [Constitution, C18/C10/C17]
- [x] CHK008 Is a new immutable release with previous signed record preservation required? [Delivery, T080]

Independent read-only design reviewer assessed CHK001–008 PASS before implementation.
