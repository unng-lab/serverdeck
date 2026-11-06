# Main-window running version — Spec Kit closure

User request2026-11-06: expose current version in UI and ship next release.
Scope FR-620/AC-618/SC-606, T077–081, existing006 amendment; no new package/schema.

Specify/clarify: main state block, full running +build from local native metadata,
truthful unknown before metadata, no offered-version substitution;0 questions needed.
Requirements checklist16/16 retained; custom version checklist8/8 explicitly assessed
PASS by independent read-only design reviewer. Safety14/14 unchanged. Plan/research/
model/contract/task amendments generated with existing templates/setup scripts, all
six constitution principles applied. No extension hooks configured. Cross-artifact
analysis found no unresolved decisions/coverage gaps before implementation.

Implementation: RuntimePlatform exposes read-only ValueListenable<String?> from native
initialize context. RuntimeView observes it using ValueListenableBuilder and C18/C10
inside existing C17 status, passed also into profile workspace. No shared component,
wire event, dependency, network query, timer or persisted field was added.

First independent code review found R1/P2: getter-only UI waited for store.open
notification despite known native context. T081 publishes observable release immediately
and tests a pending fake store with real mocked native initialization. Rebinding ignores
old source; missing/empty stays unknown. Fresh independent reviewer reported0findings
and bounded readiness; workspace tests compose actual status with fake dependencies,
not a full production graph. Temporary full-graph cleanup attempts were interrupted
and removed; they are not counted as passed checks.

Current isolated checks (base75a57d31, unrelated storage WIP excluded):
- exact dart format gate284files0changes; analyzer no issues4.5s;
- Flutter768passed15s, functional boundary95files;
- Python22passed5.760s; unchanged native19passed17.73s;
- full publishable build/resource/version/hash/import audits exit0;
- setup0.1.0+3,57773056bytes,
  SHA256e287a2cd7a98771c867f8608e70e2253f77fa8a12eacbb1099f73d97e92cb110;
- prepare-release -PreviousCatalog verifies publicv2 signature and emits signed
  protocol2 count2; root compared previous11-line record byte-for-byte retained;
- lychee284total278OK0errors6excluded2redirects before this evidence file.

No product/Explorer/real Isar/integration/e2e/VM/process-kill or feature-layout tests.
Unit/static/build evidence does not establish clean-OS integration. Root read-only
registry/build-resource inspection confirmed user's manually installed0.1.0+2 with
trust; this operational observation is not part of unit acceptance.

Final convergence assesses actual source against006 spec/plan/tasks/constitution;
no code gaps remain. Public delivery and final T080 closure follow the clean review;
older release assets are immutable and the publisher private key stays local.
