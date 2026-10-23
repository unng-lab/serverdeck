# Trusted workspace startup ownership

[Migration](migration.md), [loading](loading.md), [trusted services](trusted-services.md),
[tasks](../tasks.md).

Workspace.openTrusted is the separate format3 startup storage owner. It uses the
caller-owned actual workspace mutex, owner SID/DPAPI custody and verified trusted
native runtime. It never opens a schema3 store through Workspace.open's schema1
model and never starts an SSH connection or enables a service on its own.

A new workspace is created in the fixed protected default.creating sibling with
exactly receipt-key.dpapi, workspace.manifest.json, workspace.isar and
workspace.isar-lck. Directories/files retain owner-only custody. It generates a
fresh receipt key and format3 manifest, creates all sixteen native collections,
and commits the schema3 workspace/settings default rows in a real durable Isar
transaction. No profile/trust/credential/grant/plan/job/default observation is
invented. The native initializer is called before private workspace creation.

The narrowly separate readTrustedInitialWorkspace validates only that exact
creation-stage pathname, protected ancestors/native files, current key/lease,
schema3 native registry, full typed graph and default empty foundation. All
other native row groups must be empty. It does not relax the active loader or
migration source/target path checks. Because there are no grants/credentials in
an accepted initial graph, it neither inspects nor creates an active default
credential directory. Unknown stage files, partial creation, nonempty data,
foreign manifest/key/custody or simultaneous active/stage paths block startup.
It does not delete or repair those files. A complete empty stage can be reopened
and validated after interruption. Promotion occurs only after confirmed native
close and exact stage inventory recheck; then the full ordinary schema3 loader
opens the active store before Workspace ownership is transferred.

For an existing workspace, an authenticated format3 manifest without upgrade
residue goes directly to the normal schema3 loader. This matters for unfinished
jobs: normal startup must permit the job service's explicit observational
generation recovery instead of applying migration's stricter no-active-job rule.
Older manifests or migration residue enter the existing runTrusted migration
controller with the same retained mutex and its own reservation. No fresh
workspace is created over upgrade residue when active is missing. Migration
remains responsible for its exact source/target/key/row/receipt preservation.

The creation owner hands its reservation synchronously to migration/store open,
without releasing the OS writer lease. A throwing native open is not proof of
close: cleanup may close only the attributable registered creation-stage
instance. An unconfirmed close retains the reservation, including the gap before
Isar.open returns an instance. Store/migration reservations are retained on their
own uncertain cleanup. Receipt key cleanup never means the writer mutex may be
released early. The process-level startup/shutdown owner must wait for actual
storage/initialization completion and require no open reservation before release.

Production entry points now select this path through the
[trusted startup contract](trusted-startup.md). Source presence and selected
static analysis do not establish installed startup, crash recovery or feature
qualification; complete bundle/runtime checks remain deferred.
