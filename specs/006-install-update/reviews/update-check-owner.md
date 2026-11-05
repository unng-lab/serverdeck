# Catalog check service and scheduling owner

Date: 2026-11-04. Partial implementation milestone; platform/UI binding, download,
pending/bootstrap/handoff and uninstall remain open. No publication/deployment.

## Implemented scope

`native/include/update_service.h`, `native/install/update_service.cpp` implement the
catalog worker, mutex snapshot, generation-fenced cancellation, stop/drain lifecycle,
verified compatible offers, separate attempt/success timestamps and manual bypass of
the enabled flag. Missing immutable policy makes no request and reports
UPDATE_NOT_CONFIGURED. The WinHTTP adapter uses asynchronous requests with OS TLS,
fixed policy endpoint, product/version/platform User-Agent, no redirects/cookies/auth
or automatic credentials, 30s catalog deadline and bounded body. It closes requests
on cancellation/deadline and retains callback context/read buffer until HANDLE_CLOSING.

Preferences use SDUPREF001 and existing bounded SID-bound staging; the only added
data alias maps to `data/update-preferences.v1`. Temporary-file units exercise its
roundtrip and corrupt-record refusal without a database. Native revalidation utility
fetches a fresh catalog and samples time after the response; startup apply wiring is
not yet implemented or accepted by this milestone.

`lib/updates/update_owner.dart` supplies the UpdatePort interface and a RuntimeCapability
owner: persisted daily schedule, manual checks while disabled, monotonic rollback wait,
active-stage polling, exact confirmed version guard, native command admissions and
late-read/retirement fencing. Acknowledged settings/deferral immediately govern the
local schedule; command refresh does not block cancel/disable. No quit/launch API exists.
No view/channel/runtime binding has been added in this milestone.

## Independent review and fixes

All reviewers were fresh `fork_turns=none`, read AGENTS/artifacts/source directly,
and made no edits. Their conclusions apply to the implemented slice only.

1. `review_update_check_service`: incompatible failed catalogs incorrectly updated
   lastSuccess. T042 preserves previous memory/persistent lastSuccess and tests distinct
   timestamps T1/T2.
2. `review_update_owner_and_service`: `_sending` silently dropped cancel/disable while
   command-refresh waited. T043 serializes action admission separately from refresh;
   delayed manual-cancel/automatic-disable regressions added. Native slice had no other
   confirmed findings.
3. `review_update_service_owner_fresh`: setting acknowledgement left stale local
   enabled/timer until refresh, permitting another automatic check after disable.
   T044 immediately applies acknowledged scheduling state and invalidates old reads;
   delayed-refresh timer tests cover disable/deferral, manual bypass, and retirement
   of late preference acknowledgement. No other confirmed findings.
4. `review_update_owner_ack_final`: «Замечаний не найдено»; no unresolved confirmed
   findings in this scope. Native code was unchanged since step3, which independently
   confirmed T042 closure.

## Actual checks

- Exact `dart format --output=none --set-exit-if-changed .`:382files0changes.
- `flutter analyze`: no issues,2.9s.
- `flutter test`:740passed, exit0, including9 new owner tests. Functional unit/fake
  behavior only: no layout/goldens/real database or product launch.
- Boundary audit:91 Dart files, passed.
- Native unit gate:14/14 passed after T042; source/store fakes and synthetic native
  P256 catalogs, plus temporary preference tree. Native unchanged after that run.
- Windows host release compilation passed with the new native source and file alias
  before the subsequent lastSuccess-only fix; latest native unit compilation includes
  that fix. Full final release composition is still a later verification task.
- Lychee after task/data-model changes:258total252OK0errors6excluded2redirects.

WinHTTP was reviewed statically against the Microsoft async close/callback contract;
tests did not contact a real server. These checks establish unit/static/build evidence,
not network/installation/update integration on a clean OS. T013–019/T021 and remaining
removal/final verification tasks retain their original scope and incomplete status.
