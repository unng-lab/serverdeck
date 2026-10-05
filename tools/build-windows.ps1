$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot
$packageRoot = Join-Path $repoRoot 'packages\serverdeck_locald'
Push-Location $repoRoot
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependencies failed' }
    Push-Location $packageRoot
    try {
        dart pub get
        if ($LASTEXITCODE -ne 0) { throw 'locald dependencies failed' }
    } finally { Pop-Location }
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    $bundleRoot = Join-Path $repoRoot 'build\windows\x64\runner\Release'
    Push-Location $packageRoot
    try {
        dart compile exe bin/locald.dart -o (Join-Path $bundleRoot 'serverdeck_locald.exe')
        if ($LASTEXITCODE -ne 0) { throw 'locald compilation failed' }
    } finally { Pop-Location }
    if (-not (Test-Path -LiteralPath (Join-Path $bundleRoot 'libisar.dll'))) {
        throw 'Bundled Isar Core is missing'
    }
    Write-Output "Ready: $bundleRoot"
} finally { Pop-Location }
