# Working Rules

## Spec Kit

- Follow the Spec Kit workflow for all code changes: specification → plan →
  tasks → consistency analysis → implementation.
- Use `speckit-specify`, optionally `speckit-clarify`, then `speckit-plan`,
  `speckit-tasks`, `speckit-analyze`, and `speckit-implement`.
- Before changing code, read the current `spec.md`, `plan.md`, and `tasks.md`.
  If they are missing, create them using Spec Kit first.
- During implementation, follow `tasks.md` and mark completed tasks.
- If Spec Kit is not configured or unavailable, inform the user;
  do not silently skip the workflow.

## Required Checks

After every code change, run all commands from the repository root
in the following order:

```sh
goimports -w .
go vet ./...
golangci-lint run --config .golangci-lint.yaml ./... --timeout 1m
go test -short ./...
govulncheck ./...
```

- `govulncheck` is the tool from `golang.org/x/vuln/cmd/govulncheck`.
- All checks are mandatory and must pass before committing and pushing.
- If a check fails, fix the cause and rerun the full set of checks.
- If a tool, Go module, or configuration is missing, report the blocker;
  do not claim that an unperformed check passed.

## Git

- Use Conventional Commits for commit messages: `feat:`, `fix:`, `docs:`,
  `chore:`, or another appropriate type.

## Boundaries and Constraints

- Changing code in other repositories is prohibited. Make all code changes
  only in this repository.
- Reading files outside this repository, including other repositories, is allowed
  without additional permission.
- Standard tool caches, temporary files, and installed development tools
  may be stored outside this repository without additional permission.
- Do not place tool installations or dependency caches inside this repository.
- Other writes outside this repository require the user's explicit permission.
## Explicit Spec Kit Requests

- If the user asks to work with Spec Kit, use the actual Spec Kit workflow and
  its skills: speckit-specify, optionally speckit-clarify, speckit-plan,
  speckit-tasks, speckit-analyze, then speckit-implement.
- Configure Spec Kit before continuing if it is not configured. If it is
  unavailable, report the concrete blocker; do not replace it with manually
  authored documents while claiming that Spec Kit was used.
- Read spec.md, plan.md and tasks.md before implementation; preserve requirement
  traceability and update task completion only after actual verification.

## ServerDeck Project Rules

The shared servicekit/AGENTS.md above is copied in full. The following rules
add project-specific requirements and do not waive the shared required checks.
# Working rules

- This is an independent application, not an Infrastructure or Logs rewrite.
  Modify only this repository. Other repositories and live servers are read-only
  unless the human explicitly authorizes a specific additional action.
- Read spec/plan/tasks before implementation. Maintain requirement-to-task-to-test
  traceability; configure and use Spec Kit. Never claim it ran if unavailable.
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
