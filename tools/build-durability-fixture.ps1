[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $sdk = & flutter --version --machine | ConvertFrom-Json
    if ($sdk.frameworkVersion -ne '3.47.7' -or $sdk.dartSdkVersion -ne '3.13.5') { throw 'Use the pinned Flutter/Dart SDK for the durability fixture' }
    & flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Durability fixture dependency resolution failed' }
    $directory = Join-Path (Get-Location) 'output/durability-fixture'
    foreach ($target in @("$directory/store_durability.exe", "$directory/build.json", "$directory/import-audit/bootstrap-imports.json")) {
        $walk = [IO.Path]::GetFullPath($target)
        while ($walk) {
            if ((Test-Path -LiteralPath $walk) -and
                ((Get-Item -Force -LiteralPath $walk).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'Reparse point in durability fixture build destination'
            }
            $walk = Split-Path -Parent $walk
        }
    }
    New-Item -ItemType Directory -Force -Path $directory, "$directory/import-audit" | Out-Null
    & dart compile exe tools/fixtures/store_durability.dart -o "$directory/store_durability.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Durability fixture AOT compilation failed' }
    & python tools/package-release.py --bootstrap "$directory/store_durability.exe" --output "$directory/import-audit" --system "$env:SystemRoot/System32"
    if ($LASTEXITCODE -ne 0) { throw 'Durability executable has external runtime imports' }
    $sources = @('tools/fixtures/store_durability.dart', 'lib/storage/records.dart', 'lib/storage/records.g.dart',
        'lib/storage/workspace_store.dart', 'lib/storage/migrations.dart', 'lib/runtime/capability.dart', 'pubspec.lock')
    [ordered]@{
        schemaVersion = 1; scope = 'Developer AOT fixture from current sources; not the GUI product'
        dartSdk = $sdk.dartSdkVersion
        executableSHA256 = (Get-FileHash -LiteralPath "$directory/store_durability.exe" -Algorithm SHA256).Hash.ToLowerInvariant()
        sources = @($sources | ForEach-Object { @{path = $_; sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()} })
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$directory/build.json" -Encoding UTF8
} finally { Pop-Location }
exit 0
