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


## Final convergence and delivery

Converge inspected current spec/plan/tasks/constitution and actual source: no remaining
missing/partial/contradicts/unrequested code findings. No new convergence task/header
was appended; tasks.md stayed byte-identical during assessment (SHA256
2B158F044BBC213A203F99A3C0E51691E5774F9D2EF41440516B3C544387A379).
T080 was then checked only after the actual public release completed. All81 tasks
are checked; requirements16/safety14/version8 checklists have no open items.

Code committed/pushed as46b91f1754244e5874d5d3d711ab0b2c4d00e977.
Published stable `v0.1.0+3` (historical release identifier; former link returns 404 as checked 2026-11-06)
with exactly setup and signed catalog, after draft asset size/digest verification.
Anonymous latest with actual client API headers returnsv0.1.0+3. Previousv2 setup
SHA2567459870343b1e51005206f63c7254bca79fd03bc7f2009fa8a35fde18d323bd0 and
catalog SHA256c0ff43b0d2c01063bdace5464c64dc11a606fa4a2788e34b85d67581f976041b
are unchanged. Private key was not uploaded. Public API/manifest checks are delivery
observations, not product/installation/integration tests. User's installedv2 can
requestv3 through existing confirmation/download/next-launch update flow.
