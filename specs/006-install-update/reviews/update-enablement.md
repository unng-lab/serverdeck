# Shipped GitHub update enablement — FR-619 / AC-617

User correction2026-11-06: developer-only delivery left the installed updater
unconfigured. T073–076 connect the actual shipping defaults, not just runtime code.
Default build and GitHub workflow now require checked-in public GitHub policy and
emit publishable setup. Explicit developer mode remains available for isolated builds.
Publisher key is persistent outside the repo, restricted to current SID/SYSTEM;
missing/mismatched key never silently replaces deployed trust. No private upload.

Version0.1.0+2 permits one manual bootstrap from unconfigured0.1.0+1. Old unconfigured
clients cannot discover source configuration automatically. New setup embeds identical
policy in app/setup; prepare-release validates final audited bytes/resources/policy,
matching key and signed previous catalog before emitting public protocol2 metadata.
Explicit -FirstRelease is required without previous catalog; later records are carried
unchanged with version/count/notes/resource limits. Neither command publishes a release.

Actual evidence from isolated checkout based on1a533778 (unrelated dirty storage WIP
excluded): format283files0changes; analyzerclean4.8s; Flutter761pass17s; boundaries94;
Python22/22pass5.532s; native19/19pass17.86s on identical unchanged native source in
main workspace; default full build+resource/version/hash/import audits exit0.
setup-audit.profile=publishable; setup-inputs.policyEmbedded=true; version0.1.0+2.
Final setup SHA2567459870343b1e51005206f63c7254bca79fd03bc7f2009fa8a35fde18d323bd0,
57773056bytes. Local signed catalog prepared successfully against the pinned public root.
Lychee before evidence closure281total275OK0errors6excluded2redirects; final docs
are link-checked again. Public local output: output/release/ServerDeckSetup.exe and
serverdeck-update-catalog.txt; public audit/logs in output/update-enabled-evidence.

Fresh independent read-only reviewer without chat history: no findings, scoped readiness
confirmed across requirement/decision/contract/task/unit criteria. Reviewer independently
reran Python22/22pass5.361s, did not modify files or read the real private key.
No product/Explorer/real Isar/integration/VM/process-kill/layout tests or release/key
upload was performed. Unit/static/build evidence does not prove clean-OS integration.
Earlier developer-profile evidence remains historical; it does not describe this artifact.
