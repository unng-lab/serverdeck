# Final verification evidence

Date: 2026-11-05. Current implementation, developer build profile.

| Command | Actual result |
| --- | --- |
| dart format --output=none --set-exit-if-changed . | exit0, 387 files, 0 changed |
| flutter analyze | exit0, no issues, 2.9s |
| flutter test | exit0, 761 passed, 14s |
| tools/check-test-boundaries.ps1 | exit0, 94 Dart files |
| python -m unittest discover -s tools/tests -p test_*.py | exit0, 14 passed, 3.394s |
| tools/test-release.ps1 | exit0, 19/19 unit tests, 18.72s |
| tools/build-release.ps1 | exit0, full developer setup, physical resources/version/hash/import audits |
| lychee specs/**/*.md | exit0, 278total272OK0errors6excluded2redirects before final audit status closure |

Latest native tests include pending lifecycle/interruption, exact consent/freshness,
five-handle/late-ACK permit, physical PE resource parser, removal/retry/replay/reparse,
terminal removal interruption resolver and helper stage reporter. Process/network/
registry/shortcut ports are synthetic; native file fixtures use temporary roots.
Flutter fixtures use fake dependencies; no real Isar/product is opened.

Source evidence logs are local ignored output/{install-final-*,status-*,uninstall-*}
files; successful terminal tool results were inspected, not inferred from command launch.
The final reports are link-checked again before final handoff.

Developer setup output: output/release/ServerDeckSetup.exe. It explicitly reports
UPDATE_NOT_CONFIGURED without a release policy. Publishable policy/signing behavior
has synthetic fixtures; no production signing identity or release was provisioned.
See [release preparation](../release-preparation.md). No publication, deployment,
GitHub issue, app/Explorer/logon-session launch, integration/VM/smoke/process-kill,
real database or feature layout test was performed. Unit/static evidence does not
establish clean-OS runtime integration.
