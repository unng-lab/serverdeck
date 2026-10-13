# Brandbook integration

Version 1.0 supplied on 2026-10-05 from output/ServerDeck-brandbook-kit.zip.
Archive SHA-256: D17A0566C3F1BB8133E6FEBE211D94074903FCBDE5E9C25D3E0AC1802D24D343.

The complete original kit is versioned here, outside the runtime asset bundle.
Open [README.html](README.html) for PDF, editable SVG layouts, tokens, artwork,
font licenses and generators. A separate repository/submodule is unnecessary
while one client consumes this identity; source and client changes stay atomic.

Runtime subset: assets/brand/fonts (Noto Sans 400/600, Noto Sans Mono 400 and OFL),
assets/brand/logos (dark/light PNG marks), windows/runner/resources/app_icon.ico
(the supplied dark icon). pubspec.yaml bundles only runtime resources.

Palette implementation: lib/ui/brand_theme.dart, exact JSON roles via
ColorScheme and BrandColors ThemeExtension. No generated seed colors.
Dark is initial; theme switch is session-local and preserves existing view state.
Existing supported screens are restyled; reference layouts are not a promise of
new live metrics or server actions. Brandbook verification.json audits the kit,
not the implemented application.

For an update, replace this kit deliberately, copy the runtime subset, update
pubspec/theme mappings, preserve licenses, run token parity/contrast tests,
all Flutter checks and Windows smoke/build, then inspect both themes at desktop
and compact widths. Record a new archive hash/version and actual evidence.

To build and test an alternative complete bundle (PowerShell 7):
```powershell
& tools/build-windows.ps1 -BundleDirectory output/ServerDeck-brandbook-preview
& tools/test-locald-process.ps1 -BundleDirectory output/ServerDeck-brandbook-preview
```
Use a fresh staging destination while the existing client/service is running.
Deploy the complete successfully built/tested bundle together. A running old
service must be restarted for a changed profile contract; replacing client data
alone can leave a healthy service that rejects the current initialization request.
Keep saved data and back it up before restarting; never reset profiles to fix
an incompatible delivery.
