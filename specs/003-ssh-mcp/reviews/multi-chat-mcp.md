# Multiple MCP chats per client — 2026-11-10

Scope: FR-326/331/333, T084–T085. The native broker and Dart pipe adapter no
longer impose a per-grant channel quota. The existing application-wide limit
of eight channels remains. Each channel authenticates independently; closing
one channel does not retire its siblings. Client-wide cleanup still targets
all channels of the grant. No wire, credential, storage or UI schema changes.

Fake-only adapter regression coverage permits eight sessions for one grant,
initializes each separately and discovers tools using the same request IDs.
It checks rejection of a ninth channel, reuse after channel closure, a surviving
session's initialization and cleanup of all eight client sessions.

Executed checks:

- `flutter test test/mcp/pipe_adapter_test.dart`: 7 passed.
- `tools/test-unit.ps1`: exit 0; test-boundary check, required
  `dart format --output=none --set-exit-if-changed .`, `flutter analyze`,
  `flutter test` (921 passed), Python MCP schema units (2 passed) and build
  tooling units (24 passed).
- `tools/test-release.ps1`: exit 0; native configure/build and 19 unit CTests
  passed. This entry point executes native unit tests only.
- `lychee "specs/**/*.md"`: exit 0, no broken links.

Independent read-only review `/root/review_mcp_multichat` completed:
«Замечаний не найдено»; «Готовность к реализации: готов» for this change.
The reviewer inspected both layers, grant lifecycle, session isolation,
global admission, the specification chain and actual check logs, and ran
`git diff --check` successfully. No confirmed findings remain.

No integration, product-process, VM or screen layout tests were executed.
These checks do not establish live Codex session integration. The installed
ServerDeck executable has not been replaced.
