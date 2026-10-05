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
    # App-local VC runtime avoids requiring an elevated redistributable install.
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio locator missing' }
    $vsRoot = & $vswhere -latest -products '*' -property installationPath
    $crt = Get-ChildItem -LiteralPath (Join-Path $vsRoot 'VC\Redist\MSVC') -Directory |
        Where-Object { $_.Name -match '^\d+\.' } | Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'x64\Microsoft.VC143.CRT' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $crt) { throw 'VC143 app-local redistributable missing' }
    Get-ChildItem -LiteralPath $crt -Filter '*.dll' | Copy-Item -Destination $bundleRoot -Force
    Write-Output "Ready: $bundleRoot"
} finally { Pop-Location }
