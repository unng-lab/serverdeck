# Publisher key ownership / T093 — 2026-11-06

## Defect and correction

Two PublisherBootstrapTest methods failed on GitHub windows-2022 during directory
initialization (run42222799833, then42224077664), while the local23 tooling tests
passed. The old code created directories/files with Windows default security and
then demanded current-user ownership. The original masked directory-phase error did
not log actual owner SID; elevated-token default group ownership was the supported
hypothesis, not a directly captured runner fact.

Commit f71355bc removes reliance on the default owner: new key directory and PEM
receive explicit current-user SID owner plus protected user/SYSTEM FullControl DACL
at creation via FileSystemAclExtensions.Create, before any private bytes are written.
Existing foreign-owned objects are rejected, never reassigned. Existing missing-key,
key reuse, policy-root matching and signing guards remain. Safe directory-create,
directory-owner and directory-acl error phases improve diagnosis without secret output.

The existing private-ACL unit now checks directory and file owner, both exact
principals/rights and protection/no inherited ACEs. A synthetic Get-Acl boundary
fixture verifies foreign-directory rejection before creating key or public policy.
No publication tests, product execution or real key/root changes were performed.

## Checks and independent review

- Local `python -W error -m unittest discover -s tools/tests -p 'test_*.py'`:
  all24 passed; test_release_enablement separately9 passed.
- `lychee "specs/**/*.md"`:0 errors; `git diff --check`: passed.
- Separate read-only reviewer with fork_turns=none inspected source, tests and
  related package006/constitution/AGENTS; no findings, source ready. Reviewer
  independently ran9 publisher units and diff check. Remote proof remained open
  until the actual CI result below; unrelated storage/package002 changes excluded.

[CI42225752992](https://github.com/unng-lab/serverdeck/actions/runs/42225752992)
completed success on f71355bc. Log output/publisher-owner-ci.log confirms:

- boundaries96 Dart files; format285 files unchanged; analyze no issues;
-775 ordinary Flutter tests passed;
-2 MCP Python and24 tooling Python tests passed, including both formerly failing units;
-130 shared component tests passed,1 existing opt-in capture skipped.

The fix is confirmed on the previously failing runner environment. This does not
establish a directly observed default-owner SID from the earlier masked error.
T093 is closed; historical failed runs remain history, not current CI status.
Release v0.1.1/tag/signing secret and unrelated storage work were not changed.
Unit results do not prove full product integration or installation on a clean OS.
