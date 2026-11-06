# Stable SemVer / tag-only release review — 2026-11-06

## Scope and user decisions

FR-624/625, AC-621, T089–091: next version0.1.1, strict stable three-part versions,
clean installation without old +N compatibility; GitHub release only via matching
tag push. Constitution4.1.0, workflow, native/Python codecs, CMake resources, active
unit fixtures and package006 documents. Unrelated storage/package002 edits excluded.
No publication tests or trial releases were introduced.

## Actual checks

- `tools/test-unit.ps1`: boundaries96 Dart files, format389 files unchanged,
  flutter analyze no issues, Flutter781 passed, MCP Python2 and tooling Python23 passed.
- `tools/test-release.ps1`: all19 native unit tests passed, historical integration OFF.
- `tools/build-release.ps1`: publishable installer build and font/import/resource/
  packaging audits passed. Final setup-audit version0.1.1.
- Read-only physical host VERSIONINFO: FileVersion/ProductVersion0.1.1,
  numeric0.1.1.0. Bootstrap SDBUILD001 version0.1.1. Host compile definition0.1.1.
- `lychee "specs/**/*.md"`:0 errors.
- `actionlint .github/workflows/release.yml`: passed; static syntax only.
- `git diff --check`: passed.

Logs in local output/semver-unit-checks.log, semver-native-checks.log,
semver-build.log and semver-links.log. No product execution, real database,
integration/e2e, publication or trial release was performed.

## Independent review

Completed separate read-only subagent review with fork_turns=none per AGENTS.md.
Conclusions: «Замечаний не найдено»; «Готовность к реализации: готов».
Reviewer inspected actual source/artifacts, requirement→design→contract→task→acceptance,
trust, ordering/recovery and environment prerequisites. No confirmed findings remain.

Source readiness is separate from publication readiness: repository Actions secret
SERVERDECK_UPDATE_SIGNING_KEY is absent at review time. Existing matching local key
is available; its transfer to GitHub awaits explicit user authorization. Workflow
fails closed if the secret is missing/wrong. No secret upload or remote publication
was part of these checks. Unit/build results do not prove installation on a clean OS.


## Actual tag release completion

User authorized storing existing key in repository Actions secrets; secret name
SERVERDECK_UPDATE_SIGNING_KEY verified present. Source commit f41da826 was pushed.
First actual tag run42222319125 failed before publication: fresh Flutter tool
bootstrap emitted stdout before machine JSON. T092 and commit1eac6aba add a checked
human version call before the separate machine query and exit check. Local build,
23 Python units, link/diff checks passed; fresh independent read-only review found
no findings. No application behavior changed in this build-tool correction.

The still-unpublished tag was advanced once to1eac6aba; no existing public release
or assets were replaced. [Run42222799918](https://github.com/unng-lab/serverdeck/actions/runs/42222799918)
completed success and published [v0.1.1](https://github.com/unng-lab/serverdeck/releases/tag/v0.1.1)
on2026-11-06. Published stable latest, not draft/prerelease. Two uploaded assets:
ServerDeckSetup.exe57778688bytes, SHA256
2428924d55d71a0a24bfc762e706f744e83e7a35f356fdd8636448cd8c8d97b6;
serverdeck-update-catalog.txt1061bytes, SHA256
5826854e0f7d33e2ad7c30c0cd6b953e0a9d6daebc1da1d83b075a1e3e8dabe6.
Read-only verification of downloaded catalog confirmed API digest, signature against
pinned public root, single0.1.1 record and setup size/hash/URL matching published API.
No installed product was executed; this was the requested real release, not a test.

Separate ordinary [unit run42222799833](https://github.com/unng-lab/serverdeck/actions/runs/42222799833)
failed two existing publisher bootstrap units on windows-2022 during directory
initialization. Its775 Flutter and2 MCP tests passed. Local23 tooling tests passed;
remote tooling suite did not. The masked phase error does not establish the exact
cause. T093 records investigation without weakening ownership/trust guards.
The release workflow itself succeeded; whole-repository CI is not all green.
