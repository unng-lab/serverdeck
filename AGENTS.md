# Working rules

- This is an independent application, not an Infrastructure or Logs rewrite.
  Modify only this repository. Other repositories and live servers are read-only
  unless the human explicitly authorizes a specific additional action.
- Read spec/plan/tasks before implementation. Maintain requirement-to-task-to-test
  traceability; use Spec Kit when configured. Never claim it ran if unavailable.
- Do not copy Logs source: its licensing has not been established. Behavioral
  research is recorded with an exact source commit.
- Keep passwords, keys, real host inventories, private logs and runner artifacts
  out of Git. Credentials belong in the OS credential store, not preferences.
- NetBird and every NetBird client are protected: no stop, restart, update,
  removal, enrollment, route, DNS, key or configuration changes.
- Host inspection must be read-only. Testing installation uses disposable fixtures.
  Do not treat a synchronized job or a UI mock as authorization for live writes.
- Pin SSH host identity; changed/unknown keys require an explicit enrollment flow.
- After Flutter code changes run dart format, flutter analyze and flutter test;
  verify desktop behavior on Windows. Report unperformed checks explicitly.
- Use conventional commits. No destructive cleanup of user data or automatic
  downgrade/reset/uninstall. Partial jobs require reconciliation.
