# Startup verification and internal owner lease transfer

T059 adds Executor::PrepareStartup and trusted AcquireOwnerFromLease, plus an
activation-only entry point. PrepareStartup requires maintenance+owner leases,
checks staging, recovers journal and verifies complete canonical app/setup,
installation/commit binding and retained setup resources. No GUI owner descriptor
or database is opened by that check. Internal transfer moves the same owner HANDLE
without reopening the file; maintenance remains held by the caller.

## Actual verification

- Native unit suite: 17/17, 11.14s, exit0. Existing interruption-stage matrix now
  passes through PrepareStartup; additional fixtures refuse missing installation,
  corrupt app/setup/commit, unknown stage bytes and invalid embedded resources.
  Data sentinels remain unchanged. Owner fixtures verify exact HANDLE continuity,
  exclusion after maintenance release, invalid roots/missing owner rejection and
  activation-only failure without creating authority.
- Full DEVELOPER app/setup build and static resource/import/identity audits:
  `tools/build-release.ps1`, exit0.
- `lychee "specs/**/*.md"`: exit0, 274 total, 268 OK, 0 errors,
  6 excluded, 2 redirects.

Fresh read-only reviewer `review_006_startup_boundary`, fork_turns=none: no findings;
ready for this preparatory API scope. Reviewed source, contracts and supporting
lease/staging/recovery adapters directly; did not modify files or rerun commands.

## Remaining scope

Bootstrap main.cpp still uses its earlier entry path. Wiring preflight and pending
activation, validating raw inherited argv HANDLEs, process/ack handoff, fresh apply,
consumption/deferOnce and uninstall remain T018–024/T028. AcquireOwnerFromLease
accepts an in-process validated Lease; it does not replace validation of untrusted
inherited handles. T059 completion does not establish T018 or full feature completion.
No product, live database, integration, VM, process-kill or clean-OS acceptance run
was performed. The remaining work stays in the active goal.
