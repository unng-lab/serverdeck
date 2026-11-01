# Quickstart and verification — embedded001

Действующая поправка001/002/021 применяется к существующему пакету.
Новый feature/spec не создаётся. Только static и RAM unit проверки локально и CI;
прежние native/integration/process/SSH/container/UI/widget/design harness удалены.
Исторические результаты остаются в [журнале](../../docs/development/foundation-verification.md),
но не являются evidence новой архитектуры. Не менять чужую003 установку/checkout.

## Setup/build

Pinned Flutter3.47.7/Dart3.13.5 и Windows toolchain описаны в
[инструкции среды](../../docs/development/foundation.md).
Один build entry — `tools/run-serverdeck.ps1 -Configuration Debug|Release -BuildOnly`.
Он собирает один serverdeck.exe с runtime/native libraries/notices, manifest4 и
executor descriptor. Source-ready script не означает выполненную сборку или
native/release qualification. В текущей задаче build/launch/install/deploy не запускать.

## Mandatory implementation checks

```powershell
$env:SERVERDECK_FLUTTER_ROOT = 'H:/flutter/flutter'
./tools/test-unit.ps1
lychee "specs/**/*.md"
```

Runner выполняет `dart format --output=none --set-exit-if-changed .`,
`flutter analyze`, `flutter test`, PowerShell RAM manifest units и полный
`dart analyze`/`dart test` текущих packages. Source-empty locald не считается
успешным тестовым набором. Полный набор выполняется до адресных повторов;
адресные проверки только после полного failure. Нет Native/FS/process fixtures,
Isar open, SSH, containers или UI/design tests. C++ может проверяться статически
через MSVC /Zs с pinned SDK headers; не создавать object/binary и не dispatch app.

## Acceptance matrix

| Требование | Проверяемая граница | Текущие задачи |
| --- | --- | --- |
| Один engine/store/writer и private owner capability | RAM ownership, quota, readiness, late work и close failure | T255–T261/T273 |
| Target-schema3 data preservation | Synthetic records/blobs/IDs/revisions и отказ от несовместимых metadata без изменения | T262–T264 |
| MCP только при живом app/tray | Authenticated connection/proof, grant expiry/revoke, no launch/replay, actual publication drain | T265/T266/T268/T274 |
| Remote jobs переживают detach | intent-before-submit, lost ACK/unknown/reconcile, occupancy и terminal sequence | T267/T268 |
| Tray и явный Exit | RAM close-to-tray/fallback/menu/10s drain/CloseBlocked, без UI automation | T259/T275 |
| Portable engine/platform boundary | import/capability fakes и явные prerequisites, без обещания поддержки других ОС | T269/T270 |
| Одна поставка | Manifest4, current lockfiles, native/notices/source binding и удаление legacy entries | T271/T276 |

Наличие RAM model/check не доказывает native Win32/DPAPI/ACL/CRT/loader/GPU/
realFS/Isar/SSH/reboot/release поведение. Не переносить исторические галочки в
новую приёмку; каждая открытая задача требует evidence своего scope.

## Handoff

Использовать существующие spec/plan/contracts/tasks, затем Analyze/Implement/
Converge. После изменения спецификаций — lychee и отдельный read-only reviewer
по AGENTS.md перед handoff. После application changes — обязательные checks и
review/fix loop до отсутствия подтверждённых findings. Reviewer-owned checklists
не отмечаются исполнителем. Записывать actual commands/exit codes/scope/limits в
[tasks](tasks.md) и [текущий evidence](../../docs/development/embedded-engine-verification.md).
Состояние оставшейся работы не заменять предположением о готовности.
## T323 actual transactional MCP unit acceptance

T369–T373 follow the
[existing transactional contract](contracts/embedded-engine.md#t323t369t373--transactional-storage-dependency-2026-10-31).
After implementation, run the same complete `tools/test-unit.ps1` gate above
before any targeted retry, then `lychee "specs/**/*.md"` for changed specs and
the AGENTS.md independent review/fix loop. The full gate must include the new
RAM provider/actual-StateStore tests and the actual24-tool matrix; a green
pre-existing suite does not establish their acceptance.

Expected evidence: all16 fixed native mappings inspected statically; transaction
rollback/uniqueness/lifetime checked in RAM; actual StateStore.open validates
signed metadata, custody and exact pre/post rows; actual mutation receipts/CAS/
publication and fixed failure behavior verified; every MCP catalog tool has
positive and denied assertions through the real router/services. Keep native
byte compatibility, native close/durability and actual SSH/platform/release
qualification explicitly unperformed. No native or integration command is
added by this amendment. T323 stays open until its complete matrix is reviewed.


## T324/T331 observation and recovery RAM gate — T384

Use the existing embedded-engine contract's Local job observation and recovery
section. Run tools/test-unit.ps1 for full format/analysis/root and package RAM
units; only use targeted tests after a completed full failure. Run
`lychee "specs/**/*.md"` after this package amendment and subsequent updates.
Do not launch a native app, UI automation, SSH, real database, executor process,
container, engine worker/isolate fixture, build or installation for this gate.

Check observation DTO/runtime freshness at exactly5s and after UTC jumps, then
actual owner/MCP jobs_get/jobs_list projection and controller epoch/generation
rejection without widget tests. Check retained job IDs/outcomes through checked
RAM store reopen and factory recovery with no transport calls. Exercise current
framed status/reconcile/cancel paths and verify occupancy before and after
correlated terminal proof; childrenStopped=false never releases it. Compare
actual submit/authorize counters and retained metadata, not a scripted tool ACK.
Finish with independent source/spec review and fix all confirmed findings.
T324/T331 remain open until those assertions and full checks actually pass.


## T389 physical-drain handoff RAM gate — T391

Follow the accepted-control section of the existing embedded-engine contract.
Run full tools/test-unit.ps1 before any targeted execution; targeted checks only
after a completed full failure, then a fresh full gate. Run lychee after spec
updates and complete an independent review/fix loop. No native app, engine
worker/isolate, real SSH/FS/database/process/container, UI/design, build or install.

Use the actual factory and current StateStore with owner/HMAC actor. Hold the
RAM transport's positive stdin/channel-close completion after unknown is durable;
verify the old owner remains charged, accept reconcile, and prove no root query
until release. Positive drain should activate exactly one current continuation
within its captured deadline, not another submit/permit. Test logical expiry
while grant remains live, replacement of pending same-kind tickets, independent
cancel/read actors, fairness, late timers, terminal pruning, revoke/identity loss
and suspend/close sealing. Compare actual root requests, complete retained IDs,
store events/receipts and cleanup ownership. Do not infer physical native or
release readiness, or close the broader T387/T388/T324/T331 tasks from this slice.
