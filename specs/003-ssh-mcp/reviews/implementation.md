# Implementation003 — actual evidence

## T001 — SSH dependency and policy patch

Runtime002 base preserved; feature003 still in progress. T001 adds vendored
lib/package metadata/license from pinned dartssh2-4.1.0 archive.95pristine file
hashes verified against archive; only3library files patched. UPSTREAM.json records
pristine/patched/added file hashes and patch hash; tools/check-ssh-vendor.py runs
statically before build, no package code execution. Preserved license copied into
release alongside licenses of asn1lib/convert/meta/pointycastle/pinenacl.

Policy changes: host verifier receives copied verified raw key blob; missing raw
verifier rejects, SSHClient requires first/rekey hooks and exactly one password/key
method, forbids skip-signature/interactive/hostbased/agent/password-change callbacks.
Initial none auth removed; partial success gives typed SSHUnsupportedAuthError.
Rekey identity compares exact bytes (same RSA key with different signature algorithm
is not a different identity); mismatch closes then notifies with copied verified key.
Upstream nullable handshake/auth timers already sufficient: no timer patch required;
application adapterT009 will use null timers/keepalive and own budgetT010.

Unit tests added use only memory streams: missing host/rekey hook, no auth method,
mixed methods, skip signature, interactive forbidden before transport I/O;
configured password starts/closes synthetic transport without server or real key.
Actual raw KEX/auth/rekey byte regressions remain T008/T022; no claim they passed now.

Actual checks: tools/test-unit.ps1 exit0 boundary11files/format144files0changes/
analyze0issues/Flutter45passed (output/003-setup-unit.log). Native6/6 passed
output/003-setup-native.log. Build-release exit0 output/003-setup-build.log, including
source provenance and static manifest/import closure. No GUI/SSH/TCP/stdio process/
real Isar/VM/integration tests. Remote CI not run; installedcopy/userdata unchanged.

Source research copies under ignored output/ had analyzer errors and format drift;
output/ excluded from source analysis and research copies formatted. Production
vendor remains analyzed; its local config keeps upstream lint style only, compiler
errors/warnings not suppressed. Initial failures are not counted as passed.

Первый review выявил воспроизводимость artifacts; исправления и чистый повторный отчёт ниже.


### T001 review round1 and T027 fixes

Read-only review_003_t001_1 found2confirmed reproducibility defects, not semantic
SSH policy defects: CRLF source hashes incompatible with Git eol=lf (P1), and
CRCRLF patch couldn't reverse-apply (P2). Both sources and added hashed files now
LF; UPSTREAM hashes recomputed. Patch regenerated with byte writes:7304bytes,
3library sources only (old broken artifact was303562bytes/fullfile replacement).
Static guard rejects CR and runs git apply --reverse --check, read-only. Git is
build prerequisite only. TaskT027 records this correction without marking T001 done.

Actual forward/check/apply + reverse/check/apply on fresh scratch from pinned
archive matched all3patched SHA then original3SHA byte-for-byte. Temporary scratch
removed only after resolved-path containment check; no reviewed source was patched
in place. Evidence output/003-research/patch-roundtrip.json. All97expected vendor
hashes pass in LF checkout representation. Pristine archive SHA unchanged.

After fixes actual mandatory checks exit0: boundary11/format144files0changes/
analyze0issues/Flutter45passed (003-setup-unit.log), native6/6 (003-setup-native.log),
build-release source provenance/reversecheck/manifest/import closure exit0
(003-setup-build.log). CandidateSHA256
cdcb69e3ed8c49c123c7aefeff93917fc10054bdc062f8917068c513339cc868.
Fresh independent review pending; no integration/realSSH/GUI/Isar/VM run.


Fresh independent read-only review_003_t001_2 completed: замечаний не найдено
в T001/T027, готовность к следующей реализации установлена. Reviewer independently
verified archive95pristine hashes,97current provenance files and forward/reverse
patch on LF-controlled scratch. Actualmandatorychecks/logs inspected; suites not
rerun by reviewer. T001/T027 closed. Feature003 goal stays active; T002–T026 open.

Implementation note for T009: upstream RSA verifier uses embedded signature.type
rather than negotiated hostkey signature algorithm. Existing No-SHA1 requirement
needs explicit packet policy validation, not just advertised algorithm allowlist.
Recorded mandatory future taskT028 with in-memory vectors; this policy is not
claimed implemented or tested in T001. Next phase: complete format2 schema/migration
and common domain owners, then SSH/trust/nativeIPC/MCP/UI and finalunit gates.


## T002 — Full schema2 and copy migration

Production records now contain all7collections: AppSettings, Profile, Credential,
EndpointTrust, McpGrant, MutationReceipt, SecurityState; unique/composite indexes
and protected byte fields generated. workspaceSchemas used for every backend open.
CURRENT accepts supported1/2, refuses future before backend initialization; metadata
publication version also requires int. New stores use format2. Existing format1
is copied under owner lock to a live-owner UUID, converted in one txn with protected
SecurityState, closed/flushed/reopened/validated/closed, then native publication.
Original is never DB-opened/written. Live retry retains copy/key/converted/validated
stages and handles failed close without admitting new open/copy/publication. A lost
ack after rename/CURRENT reuses owned target; restart selects only canonical CURRENT.

Native file.flushAtomic adds data/flush/UUIDv4 with emptybytes: staging only, no
rename/CURRENT; validates canonical UUID. Publication repeats flush before replace.
Isolated native fixture covers no publication on flush, nonemptybytes/badUUID rejection,
normal publication and refusal to flush destination as staging. It uses synthetic
messenger and tempfiles, no product HWND/Isar/SSH/stdio process.

Receipt HMAC key generated32bytes via Random.secure, protected with native purpose
receipt-hmac.v1 before txn, only ciphertext stored, plaintext input cleared. Existing
format2 missing SecurityState/key refuses rather than regenerating. DesktopWorkspace
wires production DPAPI; tests use fake protected output. Shutdown drains in-flight
startup and write leases without reopening admission. Models do not expose secrets
as public DTOs; domain validation/operations/UI/grants still upcoming tasks.

Actual checks after all production changes: tools/test-unit.ps1 exit0,
boundary12files/format145files0changes/analyze0issues/Flutter60passed
(output/003-storage-unit.log).15new format2 tests cover copy/settings/source, failure
before/after rename/CURRENT, protection/txn/verification/flush/close failure, explicit
retry, shutdown during open, future format, missing security and preserved key/MCP flag.
They run fake backend plus synthetic files; not real engine durability/migration.
Repeated model generation byte-identical to prior hash (003-storage-regeneration.log
and003-storage-schema-before.sha256). Build-release exit0 with provenance/manifest/
imports (003-storage-build.log). Native6/6 exit0 (003-storage-native.log), lychee
143total137OK6excluded0errors (003-storage-links.log). Initial native fixture missed
its parent directory, failed STORAGE_IO:3; fixture setup fixed and6/6 rerun passed.
Initial flush-order test wrongly assumed no prior failed conversion open; changed
to assert closed converted state and verification-after-flush. Failed runs not passed.

CandidateSHA256 a5930d7c3ec33db84c7b2da2453f704fd17eefe5903a87f01a99c163706e0ec9.
Installed EXE/user data untouched; no integration/VM/real DB/SSH/GUI/capture tests.
T002 awaits independent review; T004 migration-unit portion only, not wholeT004.
Future native credential ciphertext>1MiB issue recorded asT029 beforeT005/T016;
HMAC32bytes here fits existing native bounds. Other feature tasks remain open.


Independent read-only review_003_storage_1 completed: замечаний не найдено;
готовность реализации T002 подтверждена. Fullschema2/copy/init/key/close/flush/
verify/publication/retry/shutdown inspected against artifacts and tests; current
generated schema hash independently matches regeneration hash. Reviewer inspected
actual logs, no suites rerun and no integration executed. T002 closed. T004 remains
open (only migration-unit portion implemented); all domain/SSH/MCP/UI tasks remain.
Next implementation stageT003: typed operations/actors/projections, bounded writer
and authorization/version/generation fences. Goal003 remains active, not complete.


## T003 — Typed operations and command kernel

New lib/domain/actor.dart: opaque issuer+ownerEpoch-bound UiActor/McpActor, root-owned
ActorAuthority kept out of wire router. Internal OwnerActor is CommandActor but
not public Actor, for app-owned session callbacks after initiating grant revoke.
No actor-from-JSON. Canonical UUID/version guards on context creation. Public API
AppOperations has14typed methods, UI delete specifically UiActor; no generic command,
raw DB or Map result. This interface is not a claim of business implementation:
concrete profile/SSH/trust/grant adapters remain T006/T010/T013/T016/T025.

models.dart defines sealed PublicValue projections and envelope meta/error matching
registry shapes, typed fields/reasons/codes (no raw remote messages), immutable lists
and detached JSON. Secret input types are not PublicValue, have no JSON serializer,
keep exact password, own/read-only key copy, byte-size guards and explicit disposal.
String GC wiping is not guaranteed; disposal drops references and clears owned bytes.
nextRevision guards JSON-safe overflow before future canonical writes.

Concrete DomainCommandGate/CommandContext implement FIFO64waiting+1active,
preliminary fail-closed auth, canonical async admission/response hooks plus sync bool
isAuthorizedNow (not async-void) on actual effect boundary. Metadata bounds checked.
Context expires BEFORE await response auth. Both success and failure body outputs
are reauthorized; postcommit revoke does not rollback committed effect. Unknown
exceptions sanitize to fixed storage error, queue stays usable. Sync linearize
requires PublicValue return, so Future callback does not fit; invoke INSIDE actual
writeTxnSync or at socket.write admission, not around queued write Future. No network/
crypto/prompt/close wait under gate. No recursive submit/await; phases are separate.
VersionFence reads canonical port only: profile/connection/credential/endpoint/trust/
observation/generation checks, missing entity/conflicts, quarantine/explicitcleanup.
Receipt read has auth but no stale/consumed entity fence, so replay has no new effect.
OperationState is a required canonical-owner boundary, no production allow-all or
second permission/data model. Canonical grants/clock/storage binding not implemented
in this increment; tasks explicitly retain that work. Root UI/MCP wiring still open.

Actual checks: tools/test-unit.ps1 exit0 boundary14files/format150files0changes/
analyze0issues/Flutter95passed (output/003-domain-unit.log),35new domain unit cases.
They cover FIFO/overflow, actor spoofing, revoke/expiry/version/owner fences, response
privacy, expired context, replay, quarantine/cleanup, shutdown, error recovery,
metadata/revision bounds, DTO/input privacy/ownership, internal owner scope.
Native6/6 unchanged-source unit base passed (003-domain-native.log). Build-release
exit0 with vendor/static manifest/import audits (003-domain-build.log). Lychee
143total137OK6excluded0errors (003-domain-links.log). CandidateSHA256
b0163ae3c71e1739f2a70cfe8ac4b228f3552fd0b4b779239100611a02a6b62a.
Initial focused test had fake method/helper name collision; corrected. Early full gate
caught misplaced import then unreachable test line; final format/analyze/tests pass.
No raw Isar/network/stdin subprocess/GUI/VM/integration/design tests, remote CI not run.
Installed EXE/userdata unchanged. T003 awaits independent review; goal003 active.


Independent read-only review_003_domain_1 completed: замечаний не найдено;
готовность T003 подтверждена, не всей003. Проверены actors/DTO/kernel,35newunit
cases, цепочка FR312/316/323–324/328–331 и нормативные artifacts. Reviewer inspected
logs and actual candidateSHA256
b0163ae3c71e1739f2a70cfe8ac4b228f3552fd0b4b779239100611a02a6b62a;
suites not rerun by reviewer, no files modified. T003 closed, no unresolved confirmed
findings. Concrete canonical OperationState and profile/SSH/trust/grant/runtime
implementations remain T006/T010/T013/T016/T025. Next phaseT004–T007 profile tests,
credential validation/protection, atomic CRUD/receipts and controllers/UI.
Goal003 remains active. No integration/VM gates introduced.


## T005 / T029 — Credential preparation (review pending)

Profile field validator: trimmed name1..100 Unicode scalars, username1..255 without
whitespace/control/format, port1..65535, ASCII/punycode DNS lowercase/trailingdot,
canonical IP without zones/URI brackets. Endpoint SHA256 canonical JSON[host,port].
Malformed UTF-16 password/passphrase rejects before UTF-8 replacement conversion.
No DNS resolution. New direct pointycastle4.0.0 was already a pinned SSH dependency.

Pure OpenSSH parser accepts exactly one Ed25519/RSA>=2048 signing key, unencrypted
or bcrypt/AES CTR/CBC private-file input; rejects other algorithms/formats, malformed
container, inconsistent public/private, invalid padding. Fixed errors, no raw strings.
Proof sign/verify is local synthetic crypto, no auth or network. Source file bytes
are never rewritten/toPem in production. Fixture vectors are public upstream test
keys, with archive/hashes and offline derived encrypted vectors; not user credentials.

CancellableKeyParser owns at most4 in-process Dart isolates (pending spawn/uncertain
stop included), deadline<=30s, token cancellation, late key disposal, exit-confirmed
release. RuntimeCapability seam stops admission/cancels/drains. One adapter unit
parses a public synthetic vector in an owned Dart isolate; fake workers/clock cover
capacity, late spawn, failed stop/retry, shutdown, timeout and invalid pre-admission.
No external process or OS process kill. Later connection wiring must pass remaining
network budget after prompt (T010); root capability wiring remains T007/T020.

CredentialPreparer protects original password/key bytes outside txn using purpose
credential.v1:<UUID>, checks cancel after async work, returns owned ciphertext and
key metadata only; clears temporary plain/cipher buffers on all paths. Caller keeps
original input for fenced/idempotent commit then disposes; atomic store write T006.
Passphrase never enters protector or prepared value. Strings/BigInts cannot promise
GC-wide wipe. Native DPAPI input/output bounds1/2MiB directionally, scope-owned wipe
on error/normal return. Boundary native fixture uses only synthetic bytes and direct
component DPAPI APIs:1MiB roundtrip, too-large input and decoded output rejection.

Release now carries embedded OpenBSD Blowfish/Ted Unangst/Joyent bcrypt notices
from pristine source alongside MIT. UPSTREAM addedFiles hash expanded,98files checked;
3 policy source files and patch unchanged. Build guard passed provenance/reverseapply.

Actual checks: tools/test-unit.ps1 exit0, boundary18files, format158files0changes,
analyze0issues, Flutter148passed (output/003-credential-unit.log).53new units since
T003;26 parser/preparer/worker cases and27 field/input cases. Native6/6 exit0
(003-credential-native.log). Build-release exit0, static manifest/import audits
(003-credential-build.log), candidateSHA256
71251df8d04cbeb556b99a70da24d6c4120c41c5490bc810b4e056a19f688cd3.
Lychee143total137OK6excluded0errors (003-credential-links.log). No real Isar/SSH/TCP,
stdio subprocess/GUI/VM/design/integration tests. Installed EXE/user data unchanged.
During doc editing, default Python Windows encoding caused a partial write error;
recovered original UTF-8 explicitly before these checks. No failing check passed off
as success. T005/T029 await independent read-only review; T004 remains incomplete
(profile CRUD/refcount/transaction fault cases still T006). Goal003 remains active.


Independent read-only review_003_credentials_1 completed with1confirmed P2:
FR308 allows IPv6 brackets while validator/model/unit rejected. T005 remains open.
T030 records correction; one outer pair only for valid IPv6, same canonical endpoint,
negative zones/ports/nested/unbalanced/IPv4/DNS brackets. Own inspection also added
explicit disposal of sender-side parsed key after SendPort.send copies its graph,
before isolate natural exit. Next full checks and fresh review required; first review
is not treated as clean. T029 had no confirmed findings but awaits clean whole increment.


T030 corrected FR308 and sender-copy disposal. First correction unit run found
InternetAddress.tryParse accepts a zone within brackets; moved zone/URI/control
rejection before IPv6 bracket parsing, then full rerun passed. Actual final:
003-credential-unit-r2.log exit0 boundary18/format158unchanged/analyze0/Flutter154passed;
003-credential-build-r2.log exit0 staticmanifest/import/vendor98files, candidate
eff1085585f916a0d1802b2105c9bdf34b004c1e1b00cdef953a571f49c3d73f.
Native production/test sources unchanged since native6/6 credential run; repeated
6/6 in003-credential-native-r2.log. Lychee143total137OK6excluded0errors
(003-credential-links-r2.log). Fresh independent review pending, tasks not closed.


Independent read-only review_003_credentials_2 completed with1confirmed P2:
valid encrypted key + empty supplied passphrase mapped bcrypt passlen0 error to
UNSUPPORTED_KEY instead of PASSPHRASE_INVALID. T031 records correction before bcrypt
and new Ed25519/RSA synthetic regression units. Missing value stays REQUIRED.
Adapter test also signs synthetic bytes with returned key before disposal, exercising
usable copied key across sender wipe. IPv6/T029/provenance had no confirmed findings.
Not a clean result yet; rerun checks and fresh reviewer required.


T031 final correction checks: tools/test-unit.ps1 exit0 boundary18/format158unchanged/
analyze0/Flutter156passed (003-credential-unit-r3.log); native6/6 repeat
(003-credential-native-r3.log); build/staticmanifest/import/provenance98files pass
(003-credential-build-r3.log), candidate64a3ce541c925f40a84ee9353227ad92749af1f53c654868d1536b0c5a57023f.
Adapter returned key deterministic signature matches direct synthetic parser key,
so sender-side wipe did not change receiver private material. Lychee143total137OK/
6excluded0errors (003-credential-links-r3.log). Fresh review pending; no integrations.


Independent read-only review_003_credentials_3 completed: замечаний не найдено,
готовность T005/T029/T030/T031 подтверждена для следующих этапов. Reviewed whole
credential increment and normative chain, including IPv6/emptyphrase/sendercopy fixes,
actualr3 logs and notices hash. Suites not rerun by reviewer. No unresolved confirmed
findings in that scope; tasks closed. Whole003 and T004 remain open. Newly started
lib/domain/mutation_receipts.dart + test/domain/mutation_receipt_test.dart (5focused
unit cases) explicitly excluded from credentialreview, belong to upcomingT006.
No current product installed/launched, no user data migration, no integrations.


## T006 foundation — shared private preparation / records / receipts (review pending)

Added owner-only DomainRepository adapter over existing WorkspaceStore; no second
store or cache. readSync uses consistent txn outside writes and reuses current sync
read/write callback for canonical checks without nesting Isar transactions. Inspected
pinned IsarCommon implementation (_beginTxnSync forbids nesting, getTxnSync reuses
ambient), no engine loaded in unit. FakeDatabase now rejects nested transactions,
counts reads and honors failNextTransaction at sync commit, rolling settings/security
snapshots back. Domain repository unit checks detached records, failed atomic write,
ambient checks and recovery; this is not profile CRUD/refcount acceptance yet.

DomainCommandGate.prepare<T> shares FIFO64/auth admission+response with public submit,
returns private intent only. _enqueue internally supports nullable private results;
public submit remains PublicValue-constrained. Expired context remains unusable.
Tests cover FIFO across paths, nullable result, revoke before response, expired
context, post-prepare stale fence, sanitized failure and denied admission. Final
commands still must reacquire gate/check actual transaction. No async crypto/network
wait is added under gate by these primitives.

ReceiptSigner owns a32byte cloned key and signs canonical {method,payload} using
HMAC-SHA256. Recursive ordinal keys/exactstrings/arrayorder/no floats; malformed
UTF-16/nonJSON/deep cyclic input rejects fixed error. No payload retained/persisted,
owned bytes clear on return/dispose; immutable/library copies not globally wiped.
Constant-time comparison for fixed32byte digests.5new units include a fixed vector
computed separately by Python stdlib hmac from exact canonical bytes, key/method/
Unicode/whitespace/presence/order distinctions, invalid data and disposal.

Actual checks: tools/test-unit.ps1 exit0 boundary19files/format161files0changes/
analyze0issues/Flutter169passed (003-profile-foundation-unit.log),13new units since
credential stage156. Native6/6 unchanged sources (003-profile-foundation-native.log).
Build-release staticmanifest/import/provenance98files pass
(003-profile-foundation-build.log), candidateSHA256
ee0a7112d542a584d010ff7c057702b00df81fbb20f02916e27fd28ad9c02266.
Lychee144total138OK6excluded0errors (003-profile-foundation-links.log).
Early focused storage test missed StoreFailure import; fixed before full checks.
One mistyped focused test path did not exist; no pass claimed for that attempt.
No integration/realDB/network/GUI/VM/processkill/design test. Installed app/userdata
untouched. This partial foundation does not close T006/T004: atomic profile CRUD,
refcounts, persistent receipt binding/key load/lifecycle and business canonical state
remain next, followed by UI and SSH/trust/MCP tasks. Independent review pending.


Independent read-only review_003_profile_foundation_1 completed: замечаний не найдено,
foundation ready for nextT006 step. Reviewer checked source/pinnedIsar implementation,
contracts and actual169unit/native/static/link evidence; no reruns or modifications.
No unresolved confirmed findings in foundation. T006/T004 remain open; proceed atomic
profileCRUD/refcounts/receipts/keyload/canonical owner ports, then featureUI.


## T004 / T006 — Profile owner, atomic mutations and receipts (review pending)

ProfileOperations is the profile subset inherited by AppOperations. ProfileOwner
implements list/get/create/update/UI-only delete and RuntimeCapability. Root still
uses runtime002 slot; no profile UI or SSH transport has been installed/wired yet.
Required actual ConnectionOwner port belongsT010, canonical GrantOwner portT016/T025;
plan/tasks refine production T007 wiring after those owner seams. No fake production
transport, allow-all auth or dummy HMAC key is used. Before runtime admission, a
registered composite root capability plus application RuntimeStore wrapper will load
real key/construct graph; full initialization/late shutdown/retry orders fixed in plan,
implementation remainsT007/T020. Current isolated owner scope is not GUI integration.

Create protects original input outside gate; under actual write it repeats current
auth/receipt lookup, checks capacity/quarantine and commits profile+credential+
endpoint refcount+settings revisions+receipt. Update preflight reads receipt before
current version check; validation/protection then confirmed-close port outside gate,
final actual txn rechecks receipt before relevant fence and replacement/refcounts.
Rename/raw host spelling without normalized endpoint change preserves connection;
explicit authentication replacement creates new credential UUID and secretRevision+1.
All accepted patches increase profile/list revision once; connection revision only
on semantic connection change. UI delete closes then removes profile/credential/
last trust atomically, returns last revision, never accepts McpActor.

ReceiptBook signs raw typed profile/patch fields (exact password/key bytes/name/host/
passphrase), preserves port omission internally via nullable ProfileDraft.port, resolves
22 only during field validation. ASCII mutationId1..128, MCP client namespace stable
across grant rotation; UI namespace ui:<epoch>. Receipt current auth before lookup,
24h expiry<=now, committed IDs only replay without current entity/nonce/socket effect.
Concurrent equivalent requests may prepare twice but commit once. Indexed expiresAt
count/prune enforces100000 unexpired receipts without loading all retained records.
Disposed tickets fail closed; fixed fields only persisted, no original payload.

CanonicalOperationState queries same DB/current connection generation/quarantine,
requires explicit CanonicalGrantAuthorization and ConnectionVersionState, checks
record consistency and safe revisions, no permissive defaults/cache. Receipt-key
loader unprotects existing protected32 using receipt-hmac.v1, clears owned ciphertext/
plaintext, rejects missing/corrupt/failed output without key regeneration. Root owns
loaded signer disposal after accepted work, actual composition deferred as above.

T032 records one spec/contract correction found during implementation: input schema
maxLength100 before trim rejected valid padded100 names from FR302. Removed raw cap
from52 copied ProfileInput/ProfilePatch nodes; domain after-trim scalar100 unchanged,
outputProfileView max100 retained and transport frame bounds raw input. Canonical
standard base64/padding decision fixed for later wire adapter (T018/T019); no hidden
base64 spelling normalization before receipt identity.13Tool/26schema validation and
positive padded100 input passed against pinned official MCP2025-11-25 in
output/003-profile-schema.log. This is static schema validation, not implemented MCP.

Added memory snapshot repository (all7records with deep copies), isolated profile
protector/parser/connection/auth fixtures.42new profile units cover exact data/secrets,
key metadata/original protected bytes, snapshot new-owner read/disconnected and issuer
fence, replay after delete/expiry/rotation/current revoke, namespaces/crossmethod,
rename/session preservation, moves/shared trust/last delete, validation/protection/
close/quarantine errors, shutdown, cursor/data errors/capacity and concurrency.
Create5/update7/delete4 injected record-write points plus commit failure all roll back
entire synthetic snapshot. Retained-receipt capacity unit injects indexed count100000;
it does not allocate/open100000 real DB records.7canonical-state and6receipt-key
units add current ambient reads/auth/state consistency/key clear/failure coverage.
Storage fake only models rollback/persistence snapshots, not engine durability.

Actual checks: tools/test-unit.ps1 exit0 boundary24files/format170files0changes/
analyze0issues/Flutter224passed (003-profile-unit.log),55new since foundation169.
Native unchanged-source6/6 pass (003-profile-native.log). Build/staticmanifest/import/
vendor98files pass (003-profile-build.log), candidateSHA256
4183ac260b9e793da93cfd3a8db2526043dc94c510d5aa84b8f5938a98854fa0.
Lychee144total138OK6excluded0errors (003-profile-links.log). Early analyzer found
nullable protected-buffer inference and unused imports/non-null assertions/await
lint; corrected before mandatory final pass. No failing check claimed passed.
No real Isar/SSH/TCP/product/stdio subprocess/GUI/VM/processkill/design/integration
executed; installedEXE/userdata untouched. T004/T006/T032 await independent review;
all UI/SSH/trust/grant/MCP remaining tasks still open, goal003 active.


Independent read-only review_003_profiles_1 completed with1confirmedP2: delayed
identical secret update can reach revision-sensitive close after another request
committed receipt/revision2, throwing CONFLICT (or PROFILE_NOT_FOUND after delete)
before the final lookup. T004/T006/T032 remain open; T033 records correction. Port
now carries a synchronous receipt callback called inside its authorized common-gate
admission BEFORE version/invalidation/close, and again before post-close fences.
It returns replay or confirmed-close fence; error recovery re-resolves current
receipt before surfacing a preparation/close failure. Added delayed protection,
postcommit deletion, late protection failure and gap-before-close-admission units.
Existing first review is not a clean result; mandatory rerun/fresh review pending.


T033 correction final checks: tools/test-unit.ps1 exit0 boundary24files/format170
unchanged/analyze0issues/Flutter228passed (003-profile-unit-r2.log).46profile units,
including4concurrent replay regression cases; total59new since foundation169.
Native6/6 repeated (003-profile-native-r2.log). Build/staticmanifest/import/vendor98
passed (003-profile-build-r2.log), candidateSHA256
acfed538d8c315044d24657508fc6ff341c79470c2d94472633a0f8c439c9bd3.
Lychee144total138OK6excluded0errors (003-profile-links-r2.log). JSONschemas unchanged
since13Tool/26schema staticcheck in003-profile-schema.log. No integration executed.
Fresh independent review required/pending; T004/T006/T032/T033 not closed yet.


Independent read-only review_003_profiles_2 completed: замечаний не найдено;
готовность T004/T006/T032/T033 confirmed for subsequent stages, notwhole003.
Reviewer inspected source/artifacts/46profile+7state+6key cases and actualr2 logs,
including receipt lookup inside close admission, postclose/error recovery, exact
payload/field validation and required owner/root seams. No reruns/modifications.
No unresolved confirmed findings in that increment. Tasks T004/T006/T032/T033 closed.
UI production wiring remains after actual ConnectionOwner/TrustOwner; nextT008/T009/
T028 protocol policy andT010 owner, thenT007/T011/T014 UI wiring. Goal003 active.


## T028 — Exact RSA host-signature binding (review pending)

Vendor ssh_transport.dart now rejects embedded signature.type different from the
negotiated RSA algorithm and always rejects ssh-rsa/SHA1 before RSA verify/host
callback/NEWKEYS/auth. Public key identity still uses unchanged ssh-rsa wire blob.
No unrelated algorithms/source files changed. Patch7908bytesLF, SHA256
6aa168a1dcd687a4d03e6fc1d9e668ed59608c4dfd91dab90fff8672651942a0;
UPSTREAM patched transport and SERVERDECK added-file hashes updated, same98files/
3policy source allowlist. SERVERDECK.md records stronger behavior. Read RFC8332 §3.1
primary source linked in SSH contract to verify signature-name/key-format distinction.

New MemoryKexPeer is a synthetic pre-NEWKEYS byte fixture: version+KEXINIT+
Curve25519+KEX-reply, public upstream synthetic Ed/RSA fixture keys, direct local
sign/verify proof. No SSH listener/TCP/session/auth service.11tests cover3negotiated
RSA algorithms x3 embedded signature types, Ed correct/corrupt signature; only exact
SHA2 pair reaches false trust callback, no password callback/userauth packet. Matching
callback checks raw blob/fingerprint. Callback intentionally refuses so no session
is authenticated, not claimed full auth-order/adapter/session acceptance. T008/T009
and all connection-owner/liveness/cancel/trust tests remain open.

Regression first run (after missing internal type imports fixed) produced4failing
mismatch cases: upstream accepted SHA1/otherSHA2 at host callback. After patch11/11
passed; full unit suite239passed. Forward/reverse patch check initially used global
Git autocrlf in scratch and differed only in CRLF; added repository attributes/LF
configuration, then forward+reverse restored exact pristine bytes (003-ssh-patch.log).
Scratch pristine copies changed to .pristine extension after proof so root formatter
does not process standalone vendor research. Initial format gate caught those2scratch
files, fixed without altering package sources; no failed checks counted successful.

Actual final mandatory: tools/test-unit.ps1 exit0 boundary26files/format172unchanged/
analyze0issues/Flutter239passed (003-ssh-signature-unit.log); native6/6 unchangedsource
(003-ssh-signature-native.log); build/staticmanifest/import/vendor98 pass
(003-ssh-signature-build.log), candidateSHA256
0469b3b7b70e12c204433041fca2bbfe278ffb5aa12fc93f8cceeca614985008.
Lychee145total139OK6excluded0errors (003-ssh-signature-links.log).
No real DB/network/product/stdio subprocess/GUI/VM/integration/processkill/design.
Installedapp/userdata unchanged. Independent review pending; T028 not yet closed.

Source inspection also confirmed expensive RSA verification currently synchronous
before host callback, with server-controlled public numbers. NewT034 fixes concrete
CPU/budget ownership decision beforeT009: async signature-verifier hook, separate
4slot owned-isolate pool/<=remaining30s/bytebounds/confirmedexit and typed failure,
canonical encoding validation; no arbitrary new product key-size requirement.
This scheduling work is explicitly unbuilt, does not prevent reviewing exact RSA
binding in isolation; T009 remains open untilT034 and full adapter are implemented.


Independent read-only review_003_ssh_signature_1 completed: замечаний не найдено;
готовность isolatedT028 confirmed forT034/SSH nexttasks, notwholeT008/T009/T010/003.
Reviewer checked actual source orderverify→hostcallback→NEWKEYS, RSA/Ed matrix,
RFC8332 primary distinction, patch/archivehashes and ran vendor guard98files3sources
successfully; read mandatory239unit/native/static/link evidence, other suites not
rerun. No filesmodified/unresolved confirmed findings. T028 closed. T034 owned
bounded signature pool/hook remains mandatory beforeT009; goal003 staysactive.


## T034/T035 components — owned crypto and bounded wire waits (review pending)

New domain-independent runtime/owned_work.dart centralizes4slot/30s reservations,
own request/result cleanup, cancellation, pending spawn, late output, confirmed exit,
failed stop retry and FIFO-free rejection. Separate pool instances are independent.
Key parser delegates to it, retains existing caller typedefs/API and all input guards;
fixed errors map to prior domain failures. WorkCancelled has a generic fixed string,
not a payload. Parser private isolate adapter stays unchanged. Scheduler/getter faults
are handled without a leaked reservation; late key still explicitly disposed.

connections/host_signature.dart owns a separate4slot public-signature pool and real
Dart-isolate adapter. Root receives bool only; input copies/hash clear, no exception
text crosses worker. Bounded canonical headers before dispatch; worker calls the
same pure vendor verifier. Fixed SSHSignatureVerificationError reasons stopping/
exhausted/timeout/cancelled await adapterT009 mapping; overflow admission has no queue.
The actual strict application adapter is not implemented, so T034 remains open for
its required installation/remainingbudget/error-map acceptance atT009/T010.

Vendor same3source files add optional onVerifyHostSignature hook forwarded by client,
always check format/algorithm before hook, await hook before host callback, and
shared pure verifyHostSignature function. Full canonical re-encoding rejects trailing
fields/nonminimal mpints, RSA numeric sanity does not add an arbitrary key-size floor.
Closure during crypto or trust wait drops late success before NEWKEYS/auth. New
SSHResourceLimitError plus preappend1MiB aggregate incoming cap bounds a verified
source issue: _onSocketData appended while packet processing awaited crypto/prompt.
Single oversized and cumulative sub-limit chunks tested at both waits. T035 guard
and carrier exist; root mapping still belongsT009. No sync fallback will be used by
production adapter; bare component tests intentionally retain both paths.

Vendor patch now14819LF bytes SHA256
f10dea2e1e6bb01156b18941a5392a74fb341359236ab2218f5da7690df574f5.
Pristine archive95hashes verified, full forward+reverse restores exact pristine3
sources (003-host-signature-patch.log); hashes/added variant doc updated, total98files.
Local output/003-research/refresh_policy.py captures the repeatable evidence helper;
proof scratch files renamed .pristine after comparison so root formatter ignores
research source copies. First full format pass caught the two newly edited vendor
files; formatted allowedfiles, regenerated hashes/diff and reran all checks successfully.
No failed result treated as pass. No new package/runtime dependency or license change.

15new verifier-worker tests cover real Ed/RSA isolate math, corruption, canonical/
bytebounds/legacy alg, request ownership, success-before-exit capacity, cancelled
pending spawns, late workers/results, clamped timeout/uncertain stop retry, spawn/
getter/result/scheduler faults, shutdown/zero budget/pre-cancel. KEX matrix now22cases
with fallback and actual bounded worker (11new).7async wire cases cover late positive
signature/trust callbacks, both single/cumulative input overflow, and format rejection
before a custom hook. Memory peer done now confirms stream closure idempotently.
All use public synthetic keys/byte streams/fake workers, not TCP or a listening SSH
service; no authenticated session is claimed by false-trust fixtures.

Actual mandatory: tools/test-unit.ps1 exit0 boundary28files/format176unchanged/
analyze0issues/Flutter272passed (003-host-signature-unit.log),33new since239.
Native6/6 unchanged-source repeated (003-host-signature-native.log). Build/static
manifest/import/vendor98 pass (003-host-signature-build.log), candidateSHA256
77f92a393564949fc1990692cc79e127eb36b3b63f1480dc0c2dcb9ec51cdcff.
Lychee145total139OK6excluded0errors (003-host-signature-links.log). Installedapp/
userdata unchanged, no integration/realDB/network/product/GUI/VM/processkill/design.
T034/T035 remain open until strict adapter binding/mapping; current component changes
await independent review. T008/T009/T010 and full feature/root wiring remain open.


Independent read-only review_003_crypto_owners_1 completed: замечаний не найдено;
component readiness forT009/T010 confirmed, not completion ofT034/T035 orwhole003.
Reviewer inspected sharedpool/keyparser compatibility, separate reservations,
async/late-close/aggregatebuffer logic, canonical verifier, 15worker/22wire/7async
cases and actual272unit/native/static/link/patch evidence. Independently checked
patchhash againstmanifest, no suites rerun/filesmodified. No unresolved confirmed
findings in component scope. T034/T035 stay open until strict adapter installation/
fixed error mapping and owner budget/cancel bindings; goal003 active.


### T036 private-signing component — verification before independent review

New profiles/key_envelope.dart shares import framing and public-only hints without
private math; credential_parser.dart/key_parse_worker.dart reuse the helper.
connections/private_signer.dart adds the separate four-reservation signer pool,
signature-only messages and async attempt identity with frozen Ed/RSA-SHA2 scheme,
credential metadata checks, admission rechecks, cancellable phrase wait and
remaining-budget input. Original caller buffers are preserved, owned private file/
challenge/request/result copies are cleared, late workers keep reservations until
confirmed exit. Immutable strings/BigInt internals still carry no GC-wipe claim.

Actual output/003-private-signing-unit.log: tools/test-unit.ps1 exit0; boundaries
29 Dart files, dart format179 files0changes, analyze no issues, flutter test297
passing units. New private_signer_test.dart contains25 cases, includes real owned
Dart-isolate signatures over synthetic Ed/RSA vectors, encrypted/unencrypted,
SHA256/SHA512, malformed hints, Unicode byte bounds, capacity/timeout/cancel/late
and failed-stop retry, frozen post-sign type, prompt revocation/cancel and guarded
return. Existing import/parser/profile suites also ran. No TCP, real DB, subprocess,
VM, product launch or integration check was added/run. Native sources unchanged;
previous native6/6 evidence is historical, not a rerun for this delta. T036 remains
unchecked until strict adapter/root bindings T009/T010. Independent review pending.


Independent read-only review_003_private_signer_1 completed with no findings.
Component readiness for continuing T009/T010 established, not whole003 readiness.
Reviewer inspected public-envelope/private-worker/async-identity paths, pinned
client call sequence, existing parser units and actual297unit/145link logs; did not
rerun suites or change files. T036 stays open for mandatory strict-adapter/root
bindings. No confirmed unresolved findings in the reviewed component scope.


### T008/T010 timer component — verification before independent review

connections/network_budget.dart adds per-attempt30s active-time budget, opaque
trust/passphrase5min leases and15+10s single-ping watchdog. Separate timer tickets/
ping generations fence stale callbacks. All expiry/cleanup effects remain mandatory
connection-owner callbacks; no transport/owner completion is claimed.
Actual output/003-network-budget-unit.log: tools/test-unit.ps1 exit0, boundaries30
Dart files, exact format181files0changes, analyze no issues, flutter test312passing
units. network_budget_test.dart adds15 fake-clock/timer/ping-promise cases (pause,
expiry boundaries, old/foreign leases, early/cancelled timers, missed replies,
late success/error and stopped session). No real network, wall-clock waiting,
subprocess/DB/VM/product launch or integration acceptance. Native unchanged/not
rerun. output/003-network-budget-links.log exit0:145total139OK6excluded0errors.
T008/T010 remain unchecked pending strict transport and complete connection owner.
Independent timer-component review pending.


Independent review_003_timers_1 found one confirmed mandatory API/contract gap:
late authenticated result could call finish after30s before its timer delivered,
suppressing timeout. Original312unit run did not cover this boundary. Added T037
without erasing history. Implemented separate tryComplete fresh time check,
at-most-once success, rejection of active/expired prompt, refreshed isEnded;
finish remains cancel/error cleanup. Contract requires tryComplete inside final
authorized/fenced owner publication, binding still T010. Four new fake-clock
regressions added; fresh checks and independent review required below.


T037 component fix verification: output/003-network-budget-fix-unit.log
 tools/test-unit.ps1 exit0; boundaries30files, format181files0changes, analyze no
issues, fluttertest316pass. Nineteen timer cases include exact30s undelivered timer
success rejection, success-before-deadline at-most-once, active/expired prompts,
refresh on isEnded and no new timeout from cancel cleanup. All other units reran.
Output/003-network-budget-fix-links.log records fresh lychee result below; no native
changes/rerun, network or integration checks. Fresh independent review pending;
T037 remains unchecked until T010 actually uses tryComplete before publication.


Fresh independent read-only review_003_timers_2 completed with no findings.
T037 late-success gap is closed in timer API/contract; readiness to continue
T009/T010 established within component scope. Reviewer inspected full timer code,
19cases and316unit/145link logs without edits/reruns. Owner tryComplete binding,
resource closure and whole003 acceptance remain open and are not claimed.


### T008/T022 encrypted byte-memory policy units — checks before review

Added only test/fixtures/ssh_auth_peer.dart and
 test/connections/ssh_auth_policy_test.dart for this increment. Narrow independent
peer codec computes exchange hashes, directional AES128CTR/HMACSHA256 keys/MACs,
auth challenge proof and continuous packet sequence numbers across rekey. All
input keys are existing public synthetic fixtures; no live credentials, SSH/TCP
service, filesystem DB, subprocess, VM or product launch. Stream fragmentation
cases exercise1/7/23byte chunks. Host/private signature callbacks use real owned
Dart worker units; admission is an explicit fake callback, not production wiring.

Actual output/003-auth-policy-unit.log tools/test-unit.ps1 exit0: boundaries32Dart
files, exactformat183files0changes, analyze no issues, fluttertest335pass. New19cases
cover password/Ed/RSA256/512 encrypted userauth+ping, missing/advertised algorithms,
forced failure/partial MFA nofallback, unaccepted/latehost, latephrase, unchanged
rekey and verified Ed→RSA changed-key raw notification with no new auth, unanswered
ping closed by owner. Native/application sources unchanged, no new release build
or native rerun for test-only increment. Existing316units reran. T008/T022 remain
unchecked; no claim of root/strict-adapter/owner completion. Independent review
pending, fresh link result in output/003-auth-policy-links.log.


Independent read-only review_003_auth_peer_1 completed with no findings:19memory
wire cases and fixture inspected, readiness to continue T009/T010 within test-only
scope. Shared crypto primitives are not an independent cryptographic audit or live
network compatibility evidence. No suites rerun or files modified by reviewer.

### T009 strict adapter component — checks before independent review

Added lib/connections/ssh_transport.dart and test/connections/ssh_policy_test.dart;
existing memory-auth fixture gains only an explicit unsolicited-success switch.
Adapter installs actual shared owned crypto/signer hooks, explicit algorithms,
mandatory root authority/trust/write callbacks, credential cleanup, public raw-host
observations, bounded FIFO wire admission, late/duplicate write callback fencing,
preparation/success checks, one outstanding ping and fixed structured errors.
Changed verified host persistence precedes ended notification, close confirms raw
socket completion even after early library done/destroy and retries uncertain close.

During unit development, concurrent pings were found to enter the vendor's pending
request queue before the socket wrapper. Strict API now permits one outstanding
ping, as required by liveness contract, rejects another with RESOURCE_EXHAUSTED and
lets the original complete. It does not depend on downstream byte queue overflow.
Actual output/003-strict-ssh-unit.log: tools/test-unit.ps1 exit0; boundaries33files,
exactformat185files0changes, analyze no issues, fluttertest355pass. New20strict API
cases include normal password/encryptedEd/RSA, exact algorithms, raw host/fingerprint,
no fallback/MFA, denied trust, expired crypto, cancelledphrase, actual queued auth
write revocation, stale/duplicate write callbacks, unsolicited success, one ping,
changed observation persistence/failure, confirmedclose delay/retry, invalid crypto
and aggregate backlog fixed mappings. No native change/rerun or release rebuild;
no TCP/realDB/subprocess/VM/product launch or integration check. T009/root related
tasks remain open. Fresh lychee evidence output/003-strict-ssh-links.log; independent
review pending. Root actualGate/Actor/TrustOwner/NetworkBudget/watcher bindings are
explicit future work T010/T013/T020, not represented by fake unit callbacks.


Independent read-only review_003_strict_adapter_1 found2 confirmed defects. (1) The
same byte list passed to IOSink.add was zeroed after admission even though sink can
retain it under backpressure; synchronous-copy fake concealed it. (2) Outstanding
ping failure from changed-host rekey could save UNSUPPORTED_SERVER before warning
persistence resolved, masking HOST_KEY_CHANGED and even STORAGE_UNAVAILABLE. Added
T038 without erasing completed history. Fixed raw sink ownership with separate
immutable transfer and reservation through raw.flush outsidegate, and ping terminal
arbitration through ended after changed persistence. Four regressions cover deferred
consumer success/cancel and outstanding ping + changed-host persist success/failure.
Targeted24strict units pass (output/003-strict-ssh-fix-targeted.log). Fresh full checks
and independent review required below.

Readability repair in data-model.md: restored70 lines of reversible UTF8→CP1251
mojibake (no replacement chars). Every changed line round-tripped exactly to the
original through inverse encoding, before any duplicate cleanup. Removed one exact
consecutive duplicate of the IPv6/Unicode validation paragraph. No requirements,
field names, numeric bounds or links changed. Original SHA256
6a2a5f260042dceeab71ecfd9d1823d94a95c20bab8782d882d996909d26d499,
ignored byte backup output/003-research/data-model-encoding-before.bin. Other003
markdown scanned: no same corruption markers. UTF8 file writes use explicit bytes.


T038 full fix checks: output/003-strict-ssh-fix-unit.log tools/test-unit.ps1 exit0,
boundaries33files, exactformat185files0changes, analyze no issues, fluttertest359pass.
Adapter24cases now include all four regression paths. Fresh lychee exit0 in
output/003-strict-ssh-fix-links.log:145total139OK6excluded0errors. No additional native,
release build or integration check. T038 pending fresh independent review; all
root/owner bindings remain open, goal003 active.


Fresh review_003_strict_adapter_2 found1 remaining T038 race: pending KEX raw.flush
can fail during changed-host destroy and call _fail earlier than persistence,
masking both HOST_KEY_CHANGED/STORAGE_UNAVAILABLE. Prior ping-only fix was incomplete;
T038 never marked complete. Two added regression cases fail before fix with actual
NETWORK_ERROR (output/003-strict-ssh-flush-red.log), proving this separate source.
Fixed common _fail arbitration: once changed observed, it continues close/drain but
leaves terminal selection/auth completion to _onEnded after changedWork. Existing
ping awaits same ended result. New tests combine actual second KEX request consumed
by memory peer, pending flush acknowledgement, blackholed ping and persistence
success/failure. Required fresh full checks/review below; no product decision added.


Common arbitration fix full checks: output/003-strict-ssh-flush-unit.log
 tools/test-unit.ps1 exit0, boundaries33files, exactformat185files0changes,
analyze no issues, fluttertest361pass (adapter26cases). New2regressions green;
previous ownership/ping/cleanup/auth and all other units reran. Fresh lychee exit0
output/003-strict-ssh-flush-links.log:145total139OK6excluded0errors. No native/release
or integration rerun. T038 still unchecked pending fresh independent review.


Fresh independent read-only review_003_strict_adapter_3 completed with no findings.
T038 ownership/common terminal arbitration fixes and complete26adaptercases inspected;
ready to continueT010 within strict-component scope, not completion ofT009/root/003.
Reviewer also verified encoding backup hash/reversible70line data-model restoration.
Actual361unit/145link logs read, no tests rerun or fileschanged. T038 markedcomplete;
T009/T034/T035/T036/T037 remain open for explicit root/owner bindings. No unresolved
confirmed findings in reviewed component scope; goal003 remainsactive.


### T010 owned dial component — checks before independent review

Added lib/connections/owned_dial.dart/test/connections/owned_dial_test.dart. Native
factory uses Socket.startConnect + ConnectionTask; tests invoke injected fake task
factories only. Cancellation returns internal WorkCancelled promptly; cleanup keeps
pending factory/task/late socket until acknowledgment, confirms exact physical done,
allows same-handle retry and explicit one-time ownership transfer. No automatic
redial or Future.timeout abandoning a Socket. Root64slot/current-gate admission,
30s budget,5s quarantine and handed-off raw/strict cleanup remain required T010.

Actual output/003-owned-dial-unit.log tools/test-unit.ps1 exit0: boundaries34files,
exactformat187files0changes, analyze no issues, fluttertest375pass. Fourteen new
units cover synchronous admission, late factory/socket/cancel ack, untransferred
resource, synchronous/asynchronous factory/connect errors, throwing task getter,
cancel/destroy/close faults and retry, shared pending close, single transfer and
synthetic Socket errored-done normalization. Default native dial never executed;
no TCP/realSocket/DB/subprocess/VM/product launch/integration acceptance. No native
C++ or entry/root change/release build/rerun. Fresh link result in
output/003-owned-dial-links.log. T010 remains open; independent review pending.


Independent read-only review_003_owned_dial_1 found1 confirmed issue: catch around
await socket.done also swallowed synchronous getter failure, falsely releasing an
unconfirmed handle. Same pattern existed in native errored-close fallback and prior
strict raw close. Added T039; no completed history erased. Acquired done Future
outside inner asynchronous-error catch in all three paths; getter failure retains
resource for retry. Native returns fixed retryable cleanup failure, strict cleanup
failure now explicitly retryable as required. Added3synthetic getter→retry cases;
existing actual errored-completion case remains. No default native connect invoked.

Actual output/003-owned-dial-fix-unit.log tools/test-unit.ps1 exit0: boundaries34files,
exactformat187files0changes, analyze no issues, fluttertest378pass (dial16cases,
strict27cases). All previous units reran. No nativeC++/release/entry change or rerun;
no TCP/process/DB/VM/product launch/integration check. Fresh link evidence in
output/003-owned-dial-fix-links.log. T039 pending fresh independent review; T010/root
ownership bindings remain explicitly open, not represented by fake component units.


Fresh independent read-only review_003_owned_dial_2 completed with no findings.
Full dial16cases and three done/getter branches inspected, local SDK consumer/
ConnectionTask semantics checked; component readiness to continue ConnectionOwner
established, not completion ofT010/root/003. Provided378unit/145link logs read, no
suite rerun/fileschanged. T039 markedcomplete; T010 remainsopen for quota64, actual
current gate admission, deadline30s/cleanup5s, endpoint quarantine, raw/strict handoff
and full attempt/session owner. No unresolved confirmed findings in this reviewed
scope, goal003 active.


### T010 ConnectionOwner implementation — checks before independent review

Added lib/connections/connection_owner.dart and test/connections/connection_owner_test.dart;
extracted ConnectionOperations in domain/app_operations.dart, added SshConnection
interface to strict adapter and a public-data-only HostObservation factory for fake
ports. Owner uses canonical state/repository/common gate, actual queued byte-write
admission, root-provided shared crypto/default Strict factory, OwnedSshDial, budget/
watchdog, opaque proof/trust controls, passphrase nonce, quota64 and exact cleanup5s/
endpoint quarantine/retry, replay-before-close and app-owned session actor switch.
Runtime-owned denial latch invalidates before immediate close even with busy gate;
no new persistence/auth effect is allowed by that private lifecycle path.

Actual output/003-connection-owner-unit.log tools/test-unit.ps1 exit0: boundaries35
Dart files, exactformat189files0changes, analyze no issues, fluttertest402pass. New24
owner units use fake grants/transport/task/DPAPI/repository/timers; cover explicit/
repeated connects, canonical accepted-key enforcement, first trust commit continuation,
phrase nonce/deadlines, late success/cancel/stale IDs, actual queued write revoke,
OwnerActor session survival/pending revoke,64capacity, replay-before/postclose,
physical close fault/timeout/retry/quarantine/sharedendpoint vs unrelatedendpoint,
busyGate deadline, live projection,15+10 missed ping and shutdown after gate stops.
Default native factory/SSH network never invoked; no realDB/process/TCP/VM/product
launch/integration check. No new C++/release/entry change or native/build rerun.
Real TrustOwner/persistent nonce/warning/receipts and full root/UI/MCP remain unbuilt;
T010/T009/T034-T037 stay open until actual bindings complete. Fresh link evidence
output/003-connection-owner-links.log; independent review pending.


Independent review_003_connection_owner_1 found2 confirmed defects: established
transport loss/watchdog retained failed instead of FR318 disconnected-with-reason;
retained old endpoint entry misprojected quarantine after profile A→B. Added T040,
no completed history erased. Fixed established terminal target state, preserving
failed/CLEANUP_REQUIRED override. Projection resolves canonical versions/current
endpoint and hides stale IDs; stale ID cleanup rejects before touching old endpoint.
Live exact handles stay in registry; terminal obsolete metadata prunes at guarded
connect. Three new units cover rename and both moved-profile quarantine directions,
including no cleanup of old endpoint from obsolete session ID. Existing terminal/
blackhole units now assert disconnected state after confirmation. Targeted27owner
units pass; full mandatory checks/fresh review required below.


T040 fix full checks: output/003-connection-owner-fix-unit.log tools/test-unit.ps1
exit0; boundaries35files, exactformat189files0changes, analyze no issues,
fluttertest405pass (owner27cases). Existing strict/dial/profile/kernel units reran.
Fresh lychee exit0 output/003-connection-owner-fix-links.log:145total139OK6excluded
0errors. No native/release/integration rerun. T040 pending fresh independent review;
actual TrustOwner/root bindings and whole003 completion remain open.


Fresh independent read-only review_003_connection_owner_2 completed with no findings.
Full owner27units, interface changes, canonical/gate/dial/Strict/budget/proof controls
and T040 fixes inspected. Component readiness to continue realTrustOwnerT013/root
established, not completion ofT010/003. Reviewer read actual405unit/145link logs,
no suite reruns or edits. T040 markedcomplete. T010/T009/T034-T037 remain open until
actual trust/root/application bindings; no unresolved confirmed findings in this
reviewed scope. Goal003 active.


## Remaining implementation batch after user execution-order override

User requested all remaining functional implementation before unit testing. Added
TrustOwner, GrantOwner,13-tool schema/router, pipe adapter, native JSON/Named Pipe/
stdio implementation, native grant metadata API and original-key file picker,
complete FeatureRuntime/facade/main wiring, profile/trust/connection UI controllers
and forms, and MCP settings/configuration. Native implementation paths are recorded
in T017; no additional bridge executable or interpreter is introduced.

These sources are UNVERIFIED. No format/analyze/test/native build/release/link check
or independent review has run for this batch. Historical405-unit/clean component
results above do not cover it. All remaining task markers stay open until missing
unit fixtures, consolidated mandatory checks and a fresh independent review/fix loop
are complete. No integration, product launch, SSH server, VM or process-kill check
was run or added as an acceptance gate. Goal003 remains active.


## Consolidated verification after the complete functional implementation batch

Execution follows the user's order: remaining functional sources were added first,
then missing unit fixtures, then checks. First analyze/native compile failed on
nullable/import diagnostics and C++ shadow warnings; fixed before unit execution.
The first Flutter unit run exposed a real first-trust transition defect: an internal
connection projection invalidated the selected consent after trustRevision committed
but before its wait resumed. TrustOwner now hides in-flight selected consent from
projection invalidation; expiry and actual connection fences remain enforced.
Two fixture mistakes (reusing owner-disposed authentication input; untyped empty
maps in directly constructed RPC objects) were corrected as well.

Current successful evidence:
- `output/003-consolidated-unit-3.log`: tools/test-unit.ps1 exit0; boundaries48 Dart
  files, dart format214files/0changes, flutter analyze0issues,474 Flutter/Dart unit
  tests and2offline official-schema unit tests pass.
- `output/003-consolidated-native-2.log`: tools/test-release.ps1 exit0;7native unit
  targets pass, including pure IPC JSON/framing fixtures. No product/process/VM
  acceptance was run.
- `output/003-consolidated-build-1.log`: tools/build-release.ps1 exit0; vendored SSH
  provenance, Windows release build, one-EXE packaging and static PE import/manifest
  audit passed. EXE SHA256:
  `23a7c4b59c71940d2c47a0b3edfa943ee28861526332f8f71ec67bc0a0057ac8`.
  The EXE was built, not launched or installed.
- `output/003-consolidated-links-1.log`: lychee exit0,145total139OK6excluded0errors.

Exact source/test review scope is in output/003-full-review-scope.txt. Fresh whole
003 independent review and final Spec Kit convergence/analyze are still pending;
remaining task markers are not completion claims. Earlier unverified notes above
are historical checkpoints superseded only within the scope of these actual checks.


## Whole-feature independent review round1 and convergence

Read-only subagent review_003_full_1 completed: package ready for implementation,
current implementation incomplete,3P2 findings. R1 expiry closes idle pipe but does
not cancel pending SSH; R2 sequential disable stops after cleanup A failure and
never reaches B/listener; R3 mandatory native adapter synthetic identity/ACL/DPAPI/
partial I/O/EOF/worker fixtures are absent (codec-only tests do not cover them).
No tests/app were run by reviewer. Actual successful logs above remain evidence of
their scopes, not closure of findings. No clean result is claimed.

Spec Kit convergence independently checked34FR/9SC/22AC,13plan decisions and5
constitution principles. Appended T041–T046 for reviewer findings plus exact native
close notification/registry retirement, scope001 registration of C03 privacy change,
and FR319 actionable error presentation. No artifact product requirements changed;
no integrations or design-screen gate added. Sources remained unchanged while the
review was running. All findings require implementation/check/fresh-review closure.


## Convergence implementation and checks — T041–T046

Implemented the complete correction batch before rerunning tests. GrantOwner now
owns an expiry timer independently of pipe lifetime and queues version-fenced
cancelPendingClient/exact cleanup; disable starts every client close and transport
removal before aggregating failures, retaining pending transport-close work. Added
trust/passphrase waits after EOF and two-client failed/held-A units.

Actual native production handshake/client-peer/metadata policies, partial frame and
stdio pumps and owned-worker joins were extracted to mcp_boundary.h with synthetic
ports. Tests exercise owner absent, wrong PID/creation/user/logon/token inspection,
ACL/reparse/DPAPI faults before secret send, partial read/write/EOF, stdio wrapping,
concurrent close acknowledgment and release-after-join. The Windows bindings use
these exact functions; tests do not instantiate a real app/bridge/pipe peer.

Native closed events and registry retirement now follow exact worker/handle release;
accepted pipe ownership is transferred rather than duplicated. Incoming frame slots
remain reserved until Dart ack, including engine delivery backlog. Fixed public
error presentation provides FR319 recovery instructions. C03 privacy behavior was
registered in001/R013 and its existing functional test retained.

Fresh successful results:
- output/003-convergence-unit-1.log: tools/test-unit.ps1 exit0; boundaries50files,
  format217files/0changes, analyze0issues,480 Flutter/Dart units and2offline schema
  units passed.
- output/003-convergence-native-1.log: tools/test-release.ps1 exit0,8native unit
  targets passed (codec and new boundary/worker fixtures included).
- output/003-convergence-components-1.log: tools/test-design-components.ps1 exit0,
 112shared synthetic component units passed,1explicit opt-in capture skipped.
  This is scope001/C03 validation, not feature-screen design acceptance.
- output/003-convergence-links-1.log: lychee exit0,145total139OK6excluded0errors.

Post-correction release build and fresh whole-feature independent review remain
pending at this checkpoint. No old evidence is relabelled as a new check; no product
or integration/VM/process-kill acceptance was run. Tasks remain open until the new
review has no unresolved confirmed findings and final convergence/analyze completes.


Post-correction static release build completed successfully:
output/003-convergence-build-1.log, tools/build-release.ps1 exit0, vendor provenance,
Windows release build, single-EXE packaging and static PE import/manifest audit.
EXE SHA256 `dc2b65134383d11d48a1ba9303b934b5970c9f85bfdaf6f998223209c9d0af91`.
The built EXE was not launched/installed. Refreshed links after documentation:
output/003-convergence-links-2.log exit0,145total139OK6excluded0errors.
Fresh independent review round2 is the remaining review gate; source artifacts are
frozen during it. Exact scope output/003-full-review-scope.txt now includes new
native boundary/error presentation/lifecycle fixtures and001 C03 privacy docs.


## Independent review round2

Read-only review_003_full_2 completed: package ready; round1 expiry/disable/native
boundary findings are closed by current code and synthetic units. Native exact
worker/handle close and frame ack had no further confirmed findings. OneP2 remains:
key picker native open/size-query I/O errors and Dart catch-all are misclassified as
validation. FR319 requires preserving the category and safe recovery guidance.
Appended T047; no clean result/completion claimed. Sources were held unchanged
throughout review. Applicable checks and a fresh review follow the correction.


## T047 correction and verification

Native picker now samples open/size-query success separately from size validation
through the production AdmitKeyFile decision in native/include/credential_file.h;
ReadFile/open/GetFileSizeEx failures keep STORAGE_IO, empty/>1MiB keeps
INVALID_ARGUMENT. ProfileForm preserves fixed platform categories without rendering
native message/details; auth-field read failures have a specific safe recovery hint.
Native decision units and fake-picker widget tests cover both categories and no
unexpected domain calls/secret echo, without a real dialog or user file.

First static check found an unnecessary import, removed. A first widget fixture
used a complete owner graph and stalled its teardown under widget fake async; that
run was interrupted and is NOT passed evidence. Replaced it with an isolated
operations spy appropriate to this UI boundary; no production behavior was changed
to satisfy the fixture. Temporary diagnostics were removed.

Actual successful logs:
- output/003-picker-unit-3.log: tools/test-unit.ps1 exit0;482Flutter/Dart units,
 2offline schema units, format/analyze/boundary gates passed.
- output/003-picker-native-1.log: tools/test-release.ps1 exit0;8native unit targets
 passed, including the new key-file admission cases.
- output/003-picker-links-1.log: lychee exit0,145total139OK6excluded0errors.
C03 source unchanged since112component units passed in
output/003-convergence-components-1.log; no unrelated design rerun needed.
Post-picker build and fresh independent review remain pending at this checkpoint.


Post-T047 release/static build passed: output/003-picker-build-1.log,
tools/build-release.ps1 exit0. EXE SHA256
`7b22937dca7280f5665ca6c43feee1cef979b6f4f8a1a929f8b4a8edafcae3b1`.
No product launch or installation. Current unit gate details:
output/003-picker-unit-3.log boundaries51files, format218files/0changes,
analyze0issues,482Dart/Flutter+2Python units passed. Updated documentation link
check output/003-picker-links-2.log exit0,145total139OK6excluded0errors.
Fresh review round3 is pending; no further sources change while it runs.


## Clean independent review and task closure

Fresh read-only review_003_full_3 completed: no findings; package ready. Reviewer
checked current T047 native→Dart→presentation→synthetic acceptance chain and related
owner/IPC/credential/contract boundaries; no unresolved confirmed defects or missing
mandatory decisions remained. The report distinguishes this targeted fresh review
from round2's broader audit, and unit/static scope from unperformed integration.
Round1 findings and round2 picker finding are closed; no failed/interrupted review
is counted as clean. Source files were held unchanged during every review.

All47 implementation/correction tasks are now checked complete against current
code and successful evidence. Shared C03 privacy correction001/R013 is complete
with its functional fixture,112shared component units and independent review.
Spec status updated to implemented. Final read-only Spec Kit convergence/analyze
and documentation link check follow this administrative closure; no application
source changes or further test broadening are made.


## Final convergence follow-up

Read-only final convergence checked47completed tasks,34FR,9normative SC,22AC,
13plan decisions and5constitution principles. One actionable contradiction remains:
profile rows use a locally composed title/description Column inside C09 while ready
C07 DeckListItem already provides that function. Added CRITICAL T048 per ConstitutionI
and FR320. The previously completed task history is retained; this correction has
no new product/layout requirement. Spec completion status remains pending until
C07 reuse, functional data/action unit and a fresh clean review complete.


## T048 implementation and unit gate

Profile rows now use ready C07 DeckListItem with title, description, selected,
onTap and optional warning trailing input; C09 remains its shared surface. No
component design or source001 changes were introduced. Added an isolated functional
widget fixture checking public data/warning, selection callback/details read and
absence of implicit connect. It does not assert geometry, style or screenshots.

output/003-c07-unit-1.log: tools/test-unit.ps1 exit0,483Flutter/Dart units and2offline
schema units passed; mandatory boundary/format/analyze gates passed. Documentation
links output/003-c07-links-1.log exit0,145total139OK6excluded0errors. Native sources
remain unchanged since8targets passed in003-picker-native-1; shared component
sources unchanged since112passed/1opt-in skip in003-convergence-components-1.
Post-C07 build and fresh independent review remain pending. No remaining task
history was rewritten; T048 waits for clean verification/review.


Post-T048 static build passed: output/003-c07-build-1.log,
tools/build-release.ps1 exit0. Single EXE SHA256
`b0eab541d5846318677d2cc3afe19c2dfc232977c00b0382f9b2f5ae19587a7d`.
Current mandatory gate: boundaries52files, format219files/0changes, analyze0issues,
483Flutter/Dart+2schema units. No product launch/installation. Fresh independent
review round4 of C07 reuse and related contract/action boundaries follows; sources
are held unchanged during review. Link check refreshed after this journal entry.


Read-only review_003_full_4 completed with no findings for T048 and related package/
controller/component boundaries. C07 reuse and its functional criterion are closed.
Final component responsibility inventory then found a further ConstitutionI gap:
MCP configuration used a manual Clipboard callback instead of ready C18 copy with
failure feedback, and trust dialog label/selectable-value pairs duplicated C18.
Appended T049 without erasing completed history. It replaces those local analogs
with ready components, no new product requirement or feature design acceptance.


## T049 C18 composition and unit gate

Trust confirmation public fingerprint label/value pairs now use DeckKeyValue with
selectable=true. MCP configuration renders through a small typed public-data
composition of DeckFormSection/DeckKeyValue/DeckCopyButton; manual feature Clipboard
calls are removed. Exact copy and clipboard failure feedback are owned by existing
C18, not duplicated. Synthetic widget tests supply only command/clientId metadata
and a fake clipboard channel; success copies exact JSON, failure renders fixed safe
feedback without native details. No credential-bearing input or real clipboard.

output/003-c18-unit-1.log: tools/test-unit.ps1 exit0;485Flutter/Dart+2schema units,
mandatory boundary/format/analyze passed. output/003-c18-links-1.log lychee exit0.
Native/shared sources are unchanged from their last successful8/112unit checks.
Post-C18 build/fresh independent review remain pending at this checkpoint; no
feature-screen design check or new product capability was introduced.


Post-T049 build/static audit passed in output/003-c18-build-1.log (exit0).
Latest EXE SHA256 `2a3c7cb3d3bafd239f8adaba1faa6d28e6bc5ad6fbee3bf872000d6d15c9588c`.
Current unit gate: boundary53files, format221files/0changes, analyze0issues,
485Flutter/Dart+2schema units. Native/shared source unchanged from successful8native
and112shared units. Sources are frozen for fresh independent review round5 of C18
reuse/copy feedback and related public data boundaries; no product launch/install.


## Final clean review and implementation closure

Fresh read-only review_003_full_5 completed with no findings. Package ready;
T049 public metadata/copy/trust inputs respect shared component ownership and
credential boundaries. Current code needs no further confirmed correction or
mandatory product/architecture decision. Prior clean reviews cover their related
unchanged boundaries; unsuccessful/interrupted checks are not counted as passes.

All49 tasks T001–T049 are complete, preserving every earlier completed task and
corrective history. Related001/R013 complete. Application sources remained unchanged
during independent reviews and after their verified release builds. Latest executable:
`output/release/ServerDeck.exe`, SHA256
`2a3c7cb3d3bafd239f8adaba1faa6d28e6bc5ad6fbee3bf872000d6d15c9588c`.
Final read-only convergence/analyze and documentation link verification follow;
no product install/launch or integration/VM acceptance is implied.


## Completion — final Spec Kit audit

Fresh independent review_003_full_5 completed with no findings; package ready,
T049 closed. Final read-only Converge found no remaining missing/partial/
contradicting/unrequested implementation. Final Analyze found no unresolved
ambiguity, duplication, missing mandatory decision or unmapped requirement/task.
Inventory:34FR,9normative SC,22AC,49unique tasks completed,13plan decisions,
5constitution principles; requirements quality checklist22/22 unchanged. Coverage
of normative FR/SC by tasks is100%. No extension hooks are registered.
Converge/Analyze do not rewrite task history or application code. Final status
bookkeeping and this evidence summary are separate from their read-only audits.

Latest actual evidence remains485Flutter/Dart+2offline schema units (c18-unit-1),
8native unit targets (picker-native-1, native unchanged),112shared component units
and1explicit opt-in capture skip (convergence-components-1, shared unchanged),
format221files/0changes, analyze0issues, boundary53files, release/static audit
(c18-build-1). Latest EXE hash recorded above. Final documentation links are checked
after writing the final report. No application source changes after clean review;
no integration/e2e/VM/product launch/process-kill acceptance or installation.


Final read-only prerequisite/inventory audit confirmed49/49 unique completed tasks,
34FR/9SC/22AC,22/22quality checklist, no hooks and unchanged task bytes during audit.
Final executable hash matches2a3c7cb3…15c9588c. Documentation including final report:
output/003-final-links-2.log lychee exit0,147total141OK6excluded0errors. Summary table
updated with that actual result; final link recheck follows without changing links.
All required work is complete; goal may be marked achieved.
