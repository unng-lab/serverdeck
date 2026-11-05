# Installer resource generator — T010 / T036

**Date**: 2026-11-04. Build-tool milestone, not a built/installed product.

`tools/package-installer.py` prepares exact app size/SHA256/version manifest and
RCDATA source, validates canonical bounded public policy and enforces byte parity
with application's embedded policy even for developer builds. The native resource
reader uses data/resource mapping flags0x60, not product execution. Public point
validation uses P256 parameters; no private key is generated or embedded.

Seven new synthetic tests plus four existing font-tool tests run successfully.
The initial test-first run failed because the new module did not yet exist.
Synthetic PE headers/fake policy resource reader exercise generator/bounds/identity
and policy failures; actual final resource mapping/import/manifest proof remains T011.

Independent read-only/fork_turns=none review loop:

1. `review_006_packager`: numeric dotted names invalid as IPv4 were accepted by Python
   but rejected native. Added exact native-equivalent rejection and endpoint/hosts
   regressions for999.999/256.256.256.256/1.2.3.999; tracked T036.
2. `review_006_packager_fresh`: «Замечаний не найдено»; narrow generator scope ready to
   continue build integration. Reviewer independently reran Python11/11 successfully.

Actual parent checks after code fix: Python tools unit discovery exit0,11/11 OK;
lychee exit0,258total252OK0errors6excluded2redirects. Native unchanged since latest
12/12 unit gate. No006 Flutter changes/checks or app/integration/VM/process-kill run.
Full setup binary, build integration and static final audits remain T008/T011;
catalog signing remains T022. No publication/deployment performed or inferred.
