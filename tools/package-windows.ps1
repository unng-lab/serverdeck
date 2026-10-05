param([string]$Compiler = 'wix', [switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'build-windows.ps1') }
$bundle = Join-Path $repo 'build\windows\x64\runner\Release'
foreach ($name in @('serverdeck.exe', 'serverdeck_locald.exe', 'flutter_windows.dll', 'libisar.dll', 'vcruntime140.dll', 'msvcp140.dll', 'data\flutter_assets')) {
    if (-not (Test-Path -LiteralPath (Join-Path $bundle $name))) { throw "Incomplete bundle: $name" }
}
$version = [regex]::Match((Get-Content (Join-Path $repo 'pubspec.yaml') -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$').Groups[1].Value
if (-not $version) { throw 'Expected stable version+build in pubspec.yaml' }
$dist = Join-Path $repo 'output\dist'
$source = Join-Path $repo 'build\packaging\serverdeck.wxs'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
python (Join-Path $PSScriptRoot 'windows_installer.py') --bundle $bundle --output $source
if ($LASTEXITCODE -ne 0) { throw 'Installer source generation failed' }
$package = Join-Path $dist "ServerDeck-$version-windows-x64.msi"
& $Compiler build -arch x64 -pdbtype none -o $package $source
if ($LASTEXITCODE -ne 0) { throw 'WiX installer compilation failed' }
Write-Output $package
