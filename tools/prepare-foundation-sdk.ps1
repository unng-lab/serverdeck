[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/native-isar-inputs.ps1"
$run=Join-Path $NativeIsarRepository ('.local/sdk-preparation-'+[Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $run
[void][IO.Directory]::CreateDirectory($run)
$hosted=$env:GITHUB_ACTIONS -ceq 'true'
$phase='identity'
function Write-SdkPreparationPhase {
    param([ValidateSet('dependencies','initialization')][string]$Name)
    Write-NativeIsarJson (Join-Path $run ('safe-started-'+$Name+'.json')) ([ordered]@{
        schemaVersion=1;kind='sdk-preparation';status='started';phase=$Name;hosted=$hosted
        revision=$(if($hosted){$env:GITHUB_SHA}else{$null})
        runId=$(if($hosted){$env:GITHUB_RUN_ID}else{$null})
        runAttempt=$(if($hosted){$env:GITHUB_RUN_ATTEMPT}else{$null})
        fullAcceptance=$false;distributionReady=$false;activated=$false
    })
    Write-Host ('SDK_PREPARATION_PHASE_STARTED='+$Name)
}
$previousFlutterRoot=$env:FLUTTER_ROOT
try {
    if ($hosted) {
        if ($env:GITHUB_SHA -cnotmatch '^[a-f0-9]{40}$' -or $env:GITHUB_RUN_ID -cnotmatch '^\d+$' -or
            $env:GITHUB_RUN_ATTEMPT -cnotmatch '^\d+$') { throw 'Invalid hosted identity.' }
        $head=& git -C $NativeIsarRepository rev-parse HEAD
        if ($LASTEXITCODE -ne 0 -or $head -cne $env:GITHUB_SHA) { throw 'Hosted checkout mismatch.' }
    }
    $sdk=$(if($env:SERVERDECK_FLUTTER_ROOT){$env:SERVERDECK_FLUTTER_ROOT}else{Join-Path $NativeIsarRepository '.local/sdk/3.47.7/flutter'})
    $sdk=[IO.Path]::GetFullPath($sdk)
    Assert-NativeIsarPlainPath $sdk
    $dart=Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe'
    $tool=Join-Path $sdk 'packages/flutter_tools'
    $lock=Join-Path $tool 'pubspec.lock'
    $before=Get-NativeIsarDigest $lock
    $env:FLUTTER_ROOT=$sdk
    $phase='dependencies'
    Write-SdkPreparationPhase $phase
    Push-Location $tool
    try {
        & $dart pub get --enforce-lockfile *> (Join-Path $run 'dependencies.private.txt')
        if ($LASTEXITCODE -ne 0) { throw 'Pinned SDK tool dependencies failed.' }
    } finally { Pop-Location }
    if ((Get-NativeIsarDigest $lock) -cne $before) { throw 'SDK tool lock changed.' }
    $phase='initialization'
    Write-SdkPreparationPhase $phase
    . "$PSScriptRoot/foundation-sdk.ps1" *> (Join-Path $run 'initialization.private.txt')
    if ((Get-NativeIsarDigest $lock) -cne $before) { throw 'SDK initialization changed tool lock.' }
    Write-NativeIsarJson (Join-Path $run 'safe-proof.json') ([ordered]@{
        schemaVersion=1;kind='sdk-preparation';status='sdk-identity-verified';hosted=$hosted
        revision=$(if($hosted){$env:GITHUB_SHA}else{$null})
        runId=$(if($hosted){$env:GITHUB_RUN_ID}else{$null})
        runAttempt=$(if($hosted){$env:GITHUB_RUN_ATTEMPT}else{$null})
        fullAcceptance=$false;distributionReady=$false;activated=$false
    })
    'PINNED_SDK_PREPARATION_PASSED'
} catch {
    Write-NativeIsarJson (Join-Path $run 'safe-failure.json') ([ordered]@{
        schemaVersion=1;kind='sdk-preparation';status='failed';phase=$phase;hosted=$hosted
        fullAcceptance=$false;distributionReady=$false;activated=$false
    })
    throw "SDK preparation failed during $phase; private evidence retained locally."
} finally { $env:FLUTTER_ROOT=$previousFlutterRoot }
