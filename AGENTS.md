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

## Flutter Checks

- After Flutter code changes, run dart format, flutter analyze and flutter test.
- Verify desktop behavior on Windows when the change affects desktop behavior.
- Report unperformed checks explicitly; do not claim they passed.

## Secrets

- Do not commit credentials, private keys or private runtime data.
- Use the OS credential store for application credentials.
