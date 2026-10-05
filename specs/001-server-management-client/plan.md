# Implementation plan: ServerDeck

Feature: 001-server-management-client | Date: 2026-10-05 | [Spec](spec.md)

## Summary

Windows-first Flutter desktop, independent domain models and repositories.
Flutter talks to a separate Dart locald over authenticated loopback Local API;
locald exclusively owns Isar and durable job coordination. Deliver fixtures,
then OS custody/pinned read-only SSH through locald, then Linux Ansible Runner
execution on disposable Ubuntu 24.04 amd64 systemd hosts. Optional sync later.

## Technical context

Installed Flutter 3.47.0 revision 4cf2416426, Dart 3.13.0. SDK reports user-branch;
record warning, do not change shared SDK. .flutter-version records the expected version. M0 uses Flutter
SDK only, flutter_test and flutter_lints locked in pubspec.lock.
M1: dartssh2 4.1.0, Win32 6.4.0 + ffi 2.2.0 direct Windows Credential Manager,
Isar Community 3.3.2 for non-secret data, matching the Docs architecture.
Native custody and disposable SSH smoke performed; demo profile persistence is
added in the architecture increment. Enrollment UI and connected repositories
remain pending. locald is compiled with Dart; Isar Core is bundled from the
version-pinned flutter_libs package, with no runtime binary downloads.
Credential blobs are limited to 2560 encoded bytes; larger PEMs fail explicitly
until a protected-envelope adapter exists. flutter_secure_storage 11.2.0 was
evaluated but its native ATL prerequisite is absent; no shared VS change made.
M2: Python 3.12.12 Linux,
ansible-core==2.21.4 and ansible-runner==2.4.3 (declared Python support verified, pair
localhost assertion smoke passed). Base image digest and transitive hash lock
are in runner/Dockerfile and runner/requirements.lock. This smoke proves neither
SSH package executor nor recipe compatibility.
Installed Docker Desktop 4.89.0/client+engine 29.7.2 Linux; Visual Studio 17.14.16,
Windows SDK 10.0.26100.0. Detection does not prove recipe compatibility.
No backend, remote write listener, arbitrary command editor or Terraform installer.

## Budgets (initial, not measurements)

Inventory manual/60-second cadence, 30-second command deadline, two sessions/host,
10,000 observations cap with explicit truncation. Metrics poll 5 seconds, stale at
15 seconds; inventory stale at 5 minutes. CPU uses sampled deltas. Journal history
100 default/1..1000, 500-record ring/server, 64 KiB record cap, two streams total.
Reconnect 1/2/4/8/16/30 seconds+jitter with cursor/boot gap; denied requires action.
Preflight 60 seconds, job 30 minutes, probes 120 seconds. Writes never blindly retry.
Local terminal summaries retained 30 days; raw runner events never synced. Export
explicit. Measure limits in T007/T010, not inferred from fixtures.

## Constitution check

Pre-research PASS; post-design PASS: local-first, fixture default, authority gates,
no Logs reuse, NetBird exclusion, honest observations and job outcomes. M1/M2 gates
are mandatory, not waived by M0. No unjustified complexity violations.

## Project structure

lib/domain/ typed observations and bounded journals; lib/data/ fixture and Local
API mappings; lib/ui/ five views; test/ domain/widgets; integration_test/ Windows
smoke; packages/serverdeck_locald/ pure Dart service, API client, Isar collections
and fault tests; tools/build-windows.ps1 bundles compiled locald with Flutter.
runner/ is only the future Ansible execution container, not a persistence owner.
docs/verification.md records actual evidence. specs/001-server-management-client/
contains research.md, data-model.md, contracts/local.md, quickstart.md, traceability.md.

## Phases

M0 T001..T004: configured Spec Kit, refined requirements, analysis, runnable fixtures.
Pure read-parser and durable job-model foundation subchecks may be developed after
M0 without enabling connected UI or writes; completing T005/T010 still needs every gate.
M1 T005..T008: custody/pinned SSH before connected inventory/logs/metrics.
T009 service writes depend on M2 authority/reconciliation.
M2 T010..T011: durable executor before disposable installs.
M3 T012: sync cannot authorize execution. T013 evidence at each increment.
Architecture increment T014..T018 refines T005/T010 and does not complete their
connected SSH or remote execution acceptance gates. Its scope is independent of
future T006..T012: isolated local storage, profile UI and job-model parity.

## Runner and recovery

Isar, owned only by Dart locald, stores immutable host fingerprint, version, recipe digest, parameters,
approval, idempotency key, phase, event sequence and named container identity before
launch. Transactions claim one durable active-host writer. Closing UI does not
stop a job. Detached container persists and emits bounded private events; observers
read redacted summaries by sequence. Cancel stops new tasks, not rollback.
Lost process/network becomes unknown, retains lock and reconciles container identity,
dpkg audit/lock, version, units and probes before retry. No success from exit code alone.
Use dropped capabilities/read-only rootfs, job-only mounts, no Docker socket, no
whole SSH-directory mounts. Private keys handed off briefly from OS custody.
Stock Ansible become elevates generated Python modules and cannot enforce a command
sudo allowlist. Strict least privilege needs a preprovisioned root-owned validated
helper with recipe allowlist, package pins, server lock and no arbitrary shell.
M2 direct privileged execution is disabled until this gate is implemented.
Install/adopt separate; no implicit downgrade/reset/config/data replacement.
Check mode predicts only. Allowlisted recipes cannot reference NetBird.

## Validation

M0 format/analyze/test, Windows release build and Windows fixture integration smoke.
M1 disposable SSH: enrollment/mismatch, injection, denied journal, stopped/failed/
instance mapping, cursor/boot resume, interval metrics and OS custody persistence.
M2 real systemd disposable Ubuntu VM: image smoke, exact versions, no-op rerun,
adoption data/config hashes, failed probe, crash/cancel/network partition, competing
writers. Docker package checks alone cannot prove systemd acceptance.
M3 offline/conflict/privacy. See research.md and traceability.md.
