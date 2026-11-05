# Release source / trust v1

**Production amendment (2026-11-04):** [GitHub Releases](github-releases.md)
задаёт единственный источник, protocol2 и fresh publication checks. Protocol1 и
произвольный endpoint ниже — legacy codec, не альтернативный production server.
При расхождении действует amendment.

## Immutable build policy

JSON input: `schema:1`, `endpoint` HTTPS absolute without userinfo/fragment/secrets,
`downloadHosts`1..8 exact lowercase DNS names, `keys`1..3 records with `id` ASCII
`[a-z0-9-]{1,32}`, `p256`128 hex digits (X||Y,32 bytes each, big endian), `storeFormat`
current positive integer. Reject duplicate ids/hosts, wildcard/IP credentials, invalid
curve points/URLs. Same bytes embedded as `SERVERDECK_TRUST_V1` in app and setup.
Developer build missing policy reports UPDATE_NOT_CONFIGURED, no network. Publishable
build fails missing inputs, never generates or trusts a demo root silently.

ECDSA P256/SHA256 through BCrypt over exact payload bytes; signature raw IEEE-P1363
64 bytes r||s. Key id selects built-in key only. Rotation needs overlapping key built
into preceding release; compromised root needs independently obtained trusted setup.
No runtime downloaded root, UI URL override, user credentials, telemetry or install ID.

## Catalog codec

UTF8 ASCII LF (notes base64), ≤128KiB, final LF, no CR/NUL/extra fields.
Envelope `SDCATALOG001\n<keyId>\n<signatureHex128>\n<payload>`.
Payload: `SDRELEASES001\n<issuedUTCseconds>\n<expiresUTCseconds>\n<count>\n`, then
eleven lines per release in this exact order:

```text
version
windows-x64
bootstrapAbi
storeFormat
publishedUTCseconds
setupSize
setupSha256
appSize
appSha256
setupHttpsUrl
notesUtf8Base64
```

Count0..32. Numbers canonical unsigned decimals, versions per data model; hashes
lowercase64hex. Notes decoded valid UTF8≤16KiB, no NUL, plain text. URL≤2048 bytes,
HTTPS443, no userinfo/fragment, host in build allowlist. issued≤now+300s;
issued≤expires≤issued+7days; expires>now; published≤issued. Reject duplicate IDs,
numeric aliases, unsupported codec/extra lines. Empty signed catalog offers nothing.
Select numeric max eligible version; ABI=1 and storeFormat=current build format
required. Incompatible entries are not offered; compatibility failure is distinguishable
from current/no update. Actual database opening remains its own non-destructive preflight.

Removing target from fresh catalog revokes it. Pending stores exact release fields and
original signed catalog; fresh apply catalog must contain same identity, sizes/hashes,
compatibility. Changed same version → SOURCE_CHANGED. New latest does not retarget
consent; earlier target still listed and unchanged remains valid.

## Network / resources

GET configured endpoint, User-Agent only product/version/platform; no Authorization,
cookie, client certificate, credential fallback or install identifier. OS TLS validation,
no bypass flags. Catalog redirects refused. Download redirects≤3, HTTPS and allowlist
checked for every hop, no downgrade. Never execute notes/URL parameters.
Catalog total30s; download connect/header30s, idle60s, wall30min. Cancel between≤64KiB
chunks. Metadata≤128KiB, setup≤1GiB; enforce actual bytes even without Content-Length,
final exact signed size/hash. Unknown length progress indeterminate. Need setupSize+64MiB
free before download; install disk formula in installation contract. No hidden retries
or partial resume. Cancel/failure deletes only own incomplete staging; ready only after
all signature/hash/size checks and atomic pending publication.

Apply requires a fresh successful network response in that attempt, not offline cache.
Network/trust failure preserves pending and starts full old app with status. Manual
offline setup uses its own explicit confirmation; never consumes stale pending consent.

## Build and signing

Final app with policy → setup embedding exact app+manifest → final setup → signed
catalog with exact final hashes/sizes. Avoid circular self-signing hashes. Build tooling
validates both embedded resources and x64/asInvoker/import closure. Operator may sign
final public binaries with Authenticode; update authenticity itself is pinned catalog
signature plus full file hash. First manually obtained installer is the bootstrap
distribution trust boundary, just as an explicitly executed local application.
`tools/sign-update-catalog.ps1` takes payload/local P256 PEM key path and emits catalog;
private key/path never enters resources, logs or repo. Provisioning/hosting/publishing
are environment inputs outside implementation acceptance, not hidden runtime dependencies.
