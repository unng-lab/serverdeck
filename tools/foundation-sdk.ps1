Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$FoundationRoot = Split-Path $PSScriptRoot -Parent
$FoundationSdk = Join-Path $FoundationRoot '.local/sdk/3.47.7/flutter'
if ($env:SERVERDECK_FLUTTER_ROOT) { $FoundationSdk = $env:SERVERDECK_FLUTTER_ROOT }
$FoundationSdk = [IO.Path]::GetFullPath($FoundationSdk)
$FoundationFlutter = Join-Path $FoundationSdk 'bin/flutter.bat'
$FoundationDart = Join-Path $FoundationSdk 'bin/dart.bat'
if (-not (Test-Path -LiteralPath $FoundationFlutter)) { throw 'Install the pinned Flutter 3.47.7 SDK or set SERVERDECK_FLUTTER_ROOT.' }
# A fresh SDK may initialize its tool and print startup text before machine JSON.
& $FoundationFlutter --version | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Pinned SDK initialization failed.' }
$sdkInfo = (& $FoundationFlutter --version --machine | Out-String | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $sdkInfo.frameworkVersion -ne '3.47.7' -or $sdkInfo.dartSdkVersion -ne '3.13.5' -or $sdkInfo.frameworkRevision -ne 'abaf9c523780a608bd46686fd5e53740a07077f8') { throw 'Pinned SDK identity mismatch.' }
$env:PATH = (Join-Path $FoundationSdk 'bin') + [IO.Path]::PathSeparator + $env:PATH
function Invoke-FoundationCommand {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Foundation command failed with exit code $LASTEXITCODE." }
}
