param([switch]$LocalTest)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
if (-not $LocalTest -and -not (Test-Path -LiteralPath (Join-Path $repo 'android\key.properties'))) {
    throw 'RuStore package requires android/key.properties and a persistent production signing key. Use -LocalTest only for local review.'
}
Push-Location $repo
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependencies failed' }
    $arguments = @('build', 'apk', '--release', '--target-platform', 'android-arm,android-arm64,android-x64')
    if ($LocalTest) { $arguments += '-PserverdeckLocalTest=true' }
    & flutter @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed' }
    $version = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$').Groups[1].Value
    $suffix = if ($LocalTest) { 'android-LOCAL-TEST.apk' } else { 'android-rustore.apk' }
    $dist = Join-Path $repo 'output\dist'
    New-Item -ItemType Directory $dist -Force | Out-Null
    $package = Join-Path $dist "ServerDeck-$version-$suffix"
    Copy-Item -LiteralPath (Join-Path $repo 'build\app\outputs\flutter-apk\app-release.apk') -Destination $package -Force
    Write-Output $package
} finally { Pop-Location }
