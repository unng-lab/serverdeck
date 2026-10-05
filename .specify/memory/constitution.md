# ServerDeck Constitution

## Core principles

1. Independent, local-first product. Only this repository is writable. Local SSH
   inventory and logs MUST work without a backend or provider API.
2. Least authority. Read adapters MUST contain no host writes. Live installs and
   service actions require a separate human instruction. NetBird and every client
   MUST never be modified. Disposable fixture execution is separate from live mode.
3. Secret custody and identity. Secrets MUST remain in OS protected storage;
   Git, preferences, sync and exported diagnostics MUST exclude secrets and private
   host data. Unknown SSH keys require enrollment; changed keys fail closed.
4. Honest observations. Unknown, unsupported, denied, stale, dropped and incomplete
   results MUST be distinct from successful empty or zero results.
5. Durable operations. Immutable recipe-bound inputs, one writer per host,
   idempotency, cancellation and crash reconciliation MUST precede real jobs.
   Ansible success is insufficient without version/unit/probe verification.
6. Evidence before claims. Preserve requirement/acceptance IDs. Tests, simulations
   and planned checks MUST be recorded separately. Flutter changes require format,
   analyze, tests and Windows validation.
7. Independent implementation. No Logs code reuse without an established license.

## Delivery workflow

M0 fixture UI -> M1 read-only SSH -> M2 disposable installation -> M3 optional sync.
Each increment has explicit boundaries and verification. No automatic downgrade,
reset, removal or retry after uncertain writes. No production operations inferred.

## Governance

User instructions govern scope. Amendments record rationale and preserve traceability.
Unchecked tasks never imply success.

Version: 1.0.0 | Ratified: 2026-10-05 | Amended: 2026-10-05
