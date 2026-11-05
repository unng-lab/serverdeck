# GitHub Releases amendment — evidence

## Design review

2026-11-04, fresh read-only subagent `review_006_github_design`, fork_turns=none.
Scope: github-releases contract, FR-618/AC-616, plan/data model/research/quickstart,
T055–T057/checklist and related pending/platform contracts. Result: no findings;
ready for implementation T055–T057. This does not establish implementation parity.
GitHub API source was cross-checked against official docs by the reviewer.

Actual link check before review: `lychee "specs/**/*.md"`, exit0,
271 total, 265 OK, 0 errors, 6 excluded, 2 redirects.

## Protocol2 implementation step (historical)

Protocol2 codec/signer support and synthetic pending restore coverage were added
after design review. Existing protocol1 behavior remains covered. Production
GitHub adapter/factory, policy enforcement and packaging were then still T055–T057;
no release has been uploaded or published. Channel/runtime work outside this
amendment remains separately unfinished and is not certified by this report.

Checks for that step: native units16/16 (10.19s); signer unit1/1 (3.457s);
Windows release host build exit0 (35.3s); lychee exit0, 271 total/265 OK/0 errors.
Both use synthetic inputs/temporary files. No product/integration/live GitHub
test was run.

Fresh read-only code reviewer `review_006_protocol2`, fork_turns=none: no findings.
Scope: Catalog.protocol/ParseCatalog, protocol-aware signer and their native/Python
fixtures, plus synthetic protocol2 pending download/restore. Ready for this bounded
codec/signer/pending step; no conclusion of GitHub adapter or overall completion.
At that point T055 remained open until production source enforced protocol2.

## GitHub adapter and production policy implementation

Implemented native GitHubReleaseSource/bounded MetadataTransport, latest API and
catalog asset validation, canonical repo/tag URLs, protocol2-only production,
fresh old-target FetchFor and default service factory. Runtime policy reading and
publishable packager/build reject other sources. Operator guide documents final
bytes/signing/assets/body/changelog without performing publication.

Initial independent reviewer `review_006_github_adapter`, fork_turns=none, found
one P3: expected API catalog size was incorrectly also the transport resource cap.
Fixed in T058: cap128KiB is independent; valid larger/smaller asset replacements
give SOURCE_CHANGED, cap overflow gives INVALID_CATALOG. Synthetic fixtures cover
both replacement directions and overflow, and assert the actual request cap.

After fix: native units17/17, 9.42s; host Windows release build exit0, 6.6s;
lychee exit0, 274 total/268 OK/0 errors/6 excluded/2 redirects. Unchanged packaging
was checked before fix: Python tools14/14, 3.522s; full developer installer build
and resource/import/identity audits exit0. Publishable policy is verified with
synthetic fixtures; real operator signing inputs/public production build were
not provisioned. Guide PowerShell example passed static syntax parsing only.

Fresh reviewer `review_006_github_adapter_fresh`, fork_turns=none: no findings;
implementation matches the GitHub source/policy amendment in the reviewed scope.
T055/T056/T058 complete. T057 implementation/checks/review are done; its final
convergence remains part of the unfinished whole-feature T027 audit.
Channel/runtime UI, bootstrap/handoff, pending consumption and uninstall remain
open tasks. This report does not establish full feature completion or clean-OS
integration. No live GitHub/product/integration tests or publication were performed.
