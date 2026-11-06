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
