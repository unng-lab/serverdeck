# Pinned recipes

Recipe contents are generated from actual root-prepared signed APT metadata.
This directory contains the operator request schema; generated catalogs are
immutable digest-keyed maps, not templates with invented versions or hashes.
An exact PostgreSQL16 version and/or exact ClickHouse version, initial settings,
revision and license notices must be supplied explicitly. No latest default is
selected. Existing product/config/data blocks a fresh-install recipe.

On the supported disposable Ubuntu24.04 amd64/systemd environment, prepare the
documented executor/runtime and isolated APT config, sources, keyring, current
signed indexes and no-start policy first.

The explicit administrator helper can prepare those inputs and, only when
requested, refresh metadata before generation:

```sh
/usr/bin/python3 -I executor/packaging/prepare-apt.py \
  --sources /root/serverdeck-recipes/sources.list \
  --keyring /root/serverdeck-recipes/trusted.gpg \
  --request /root/serverdeck-recipes/request.json \
  --output /root/serverdeck-recipes/catalog.json \
  --refresh
```

Supply root-owned protected input files and a root0700 output directory.
`sources.list` accepts HTTPS `deb` rows with exactly
`[signed-by=/etc/apt/keyrings/serverdeck-executor.gpg]`, repository URL, suite
and components; no other options, credentials or shell syntax. For example,
an administrator may prepare Ubuntu noble/noble-updates/noble-security and
the vendor's stable or lts source. Supply an already verified binary public
keyring for those sources, including Ubuntu and the vendor when both are used.
The helper never downloads or chooses a key. Official source instructions are
[Ubuntu archive verification](https://documentation.ubuntu.com/security/software-integrity/archive-verification/)
and [ClickHouse packages](https://packages.clickhouse.com/).

The public keyring is installed root0644 under root0755 `/etc/apt/keyrings`,
so APT's `_apt` verifier can read it. Private executor config/enrollment and
the journal remain root0700/0600. Existing different files are refused, never
silently overwritten. The helper does not install packages, enroll a caller,
start services or select versions; the request still gives exact versions and
settings. Without `--refresh`, no network operation is requested. A partial
refresh fails rather than producing a catalog from mixed metadata. This is an
administrator CLI, absent from installed MCP/bridge routes.

Signed `Date` must be timezone-aware and no more than five minutes in the future.
Signed `Valid-Until`, when present, must be unexpired, timezone-aware and later
than `Date`. An immutable base release without `Valid-Until`, such as the
[Ubuntu noble Release](https://archive.ubuntu.com/ubuntu/dists/noble/Release),
is not rejected by an invented seven-day age rule. This does not claim current security updates:
the exact signed/index/package bytes remain pinned, and changed metadata needs
a new catalog/plan. See [APT's time policy](https://manpages.debian.org/apt/apt.conf.5.en.html).

For inputs that are already prepared, the read-only generator remains:

```sh
/usr/bin/python3 -I executor/packaging/catalog.py \
  --request /root/serverdeck-recipes/request.json \
  --output /root/serverdeck-recipes/catalog.json
```

The request must follow request.schema.json. The input and output parent require
root custody; the output is exclusively created and cannot overwrite a previous
catalog. Dependencies, exact architecture/version/archive SHA256, repository
signers, prepared index digests and transaction digests come from actual APT.
Every singleton and both two-recipe orders are resolved without writes, then
package/index/config evidence is compared again. This checks prepared metadata;
it does not prove database installation or crash recovery.

The administrator publishes the result using the existing explicit installer
with --recipe-catalog /root/serverdeck-recipes/catalog.json. It independently
rechecks the protected candidate in system Python before publishing the registry
and matching release digest. No MCP/SSH bridge route can invoke either CLI.

For the repository release, actual exact-version catalogs and source-bound
runtime acceptance results must be materialized in the owned Docker/runner
workflow for both databases. They have not yet been generated or qualified for
the current worktree. Do not substitute this schema or a generated digest for
the full T028/T188 acceptance evidence.
