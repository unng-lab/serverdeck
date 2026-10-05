# Update contract

## Source

GET `https://api.github.com/repos/unng-lab/serverdeck/releases/latest` with GitHub JSON Accept and User-Agent ServerDeck. No Authorization or profile parameters. 404 means notPublished; other non-200 statuses mean error. Reject draft/prerelease. tag_name must equal v<manifest.version>.

Find exactly one serverdeck-update.json asset and GET its browser_download_url. HTTPS, exact project release path and matching tag; metadata max 256 KiB, overall check max 25 seconds. Schema:

```json
{"schemaVersion":1,"version":"0.2.0+2","notes":"Changes","assets":{"windows-x64":{"url":"https://github.com/unng-lab/serverdeck/releases/download/v0.2.0+2/ServerDeck-0.2.0+2-windows-x64.msi","size":1234,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}}
```

A published manifest without a compatible asset means unsupported, not current. Only offer newer versions. Redirects: validate every hop (maximum five), HTTPS GitHub/project URLs initially; release-assets.githubusercontent.com and objects.githubusercontent.com allowed as GitHub CDN destinations; preserve no authorization header.

## Download/open

Stream into a unique private temporary directory; enforce declared bytes and 1 GiB cap, 30-minute total and 30-second idle timeout. Verify SHA-256 and exact size before renaming .part file. Opening rechecks digest/size so modified files cannot launch. Never execute a shell-interpolated command. Windows invokes msiexec for MSI; macOS `open <dmg>`; Ubuntu `xdg-open <deb>`, with a copyable `sudo apt install /absolute/package.deb` fallback instruction. User must close ServerDeck before replacement. Download and open are separate UI actions.

## Preferences

Existing authenticated local API `settings/get`; `settings/set` accepts theme and/or updateAutoCheck bool. Merge partial patches, reject unknown keys and wrong values, preserve unrelated settings. No secrets, paths, notes or package bytes persisted in settings.
