[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/native-artifact.ps1"

# No cached artifact, active selection, approval, or activation is an input.
$run=Join-Path $NativeIsarRepository ('.local/cold-runner-' + [Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $run
[void][IO.Directory]::CreateDirectory($run)
$script:coldPhase='sdk'
$hosted=$env:GITHUB_ACTIONS -ceq 'true'
function Write-ColdRunnerProgress {
    param([ValidateSet('sdk','dependencies-root','dependencies-serverdeck_protocol','dependencies-serverdeck_windows','dependencies-serverdeck_locald','dependencies-serverdeck_mcp','source-build','supplements','rust-material','sources','assembly','qualification','validation')][string]$Name)
    $script:coldPhase=$Name
    Write-NativeIsarJson (Join-Path $run ('safe-progress-'+$Name+'.json')) ([ordered]@{
        schemaVersion=1;kind='cold-runner-phase';status='started';phase=$Name;hosted=$hosted
        revision=$(if($hosted){$env:GITHUB_SHA}else{$null})
        runId=$(if($hosted){$env:GITHUB_RUN_ID}else{$null})
        runAttempt=$(if($hosted){$env:GITHUB_RUN_ATTEMPT}else{$null})
        fullAcceptance=$false;distributionReady=$false;activated=$false
    })
    Write-Host ('COLD_RUNNER_PHASE_STARTED='+$Name)
}
function Invoke-ColdRunnerStep {
    param([string]$Name,[scriptblock]$Action,[string]$ExpectedPrefix='')
    Write-ColdRunnerProgress $Name
    $log=Join-Path $run ($Name+'.private.txt')
    & $Action *> $log
    if ($ExpectedPrefix) {
        $lines=@(Get-Content -LiteralPath $log | Where-Object { $_.Trim() })
        if (-not $lines.Count) { throw 'Missing component output.' }
        $path=[IO.Path]::GetFullPath($lines[-1],$NativeIsarRepository)
        Assert-NativeIsarPlainPath $path
        if (-not (Test-Path -LiteralPath $path -PathType Container) -or
            [IO.Path]::GetFileName($path) -cnotmatch ('^'+$ExpectedPrefix+'-[a-f0-9]{32}$')) {
            throw 'Invalid component output.'
        }
        return $path
    }
}
try {
    if ($hosted) {
        if ($env:GITHUB_SHA -cnotmatch '^[a-f0-9]{40}$' -or
            $env:GITHUB_RUN_ID -cnotmatch '^\d+$' -or $env:GITHUB_RUN_ATTEMPT -cnotmatch '^\d+$') {
            throw 'Missing hosted revision identity.'
        }
        $head=& git -C $NativeIsarRepository rev-parse HEAD
        if ($LASTEXITCODE -ne 0 -or $head -cne $env:GITHUB_SHA) { throw 'Hosted checkout identity mismatch.' }
    }
    Write-ColdRunnerProgress 'sdk'
    . "$PSScriptRoot/foundation-sdk.ps1" *> (Join-Path $run 'sdk.private.txt')
    Push-Location $NativeIsarRepository
    try {
        Invoke-ColdRunnerStep 'dependencies-root' {
            Invoke-FoundationCommand $FoundationFlutter @('pub','get','--enforce-lockfile')
        }
        foreach ($package in @('serverdeck_protocol','serverdeck_windows','serverdeck_locald','serverdeck_mcp')) {
            Push-Location (Join-Path $NativeIsarRepository ('packages/'+$package))
            try {
                Invoke-ColdRunnerStep ('dependencies-'+$package) { Invoke-FoundationCommand $FoundationDart @('pub','get','--enforce-lockfile') }
            } finally { Pop-Location }
        }
        Invoke-ColdRunnerStep 'source-build' { $script:coldCandidate=& "$PSScriptRoot/build-native-isar.ps1" }
        $candidate=$script:coldCandidate
        Invoke-ColdRunnerStep 'supplements' { $script:coldSupplements=& "$PSScriptRoot/collect-native-isar-supplements.ps1" -Candidate $candidate }
        $supplements=$script:coldSupplements
        Invoke-ColdRunnerStep 'rust-material' { $script:coldRust=@(& "$PSScriptRoot/collect-native-isar-rust.ps1" -Candidate $candidate) }
        if ($script:coldRust.Count -ne 2) { throw 'Invalid Rust material output.' }
        $rust=$script:coldRust[0]
        $prepared=$script:coldRust[1]
        Invoke-ColdRunnerStep 'sources' {
            $script:coldSources=& "$PSScriptRoot/collect-native-isar-sources.ps1" -Candidate $candidate -SupplementDirectory $supplements -RustDirectory $rust -ArchiveCache (Join-Path $prepared 'archives')
        }
        Invoke-ColdRunnerStep 'assembly' {
            $script:coldArtifact=& "$PSScriptRoot/assemble-native-isar-artifact.ps1" -Candidate $candidate -SourceDirectory $script:coldSources.output -NoticeDirectory $script:coldSources.notices
        }
        $artifact=$script:coldArtifact
        $qualification=Invoke-ColdRunnerStep 'qualification' { & "$PSScriptRoot/test-native-isar.ps1" -Artifact $artifact } 'native-qualification'
        Write-ColdRunnerProgress 'validation'
        $verified=Get-NativeArtifactCompatibility (Join-Path $qualification 'compatibility-receipt.json') -RequireCurrentSource
        Write-NativeIsarJson (Join-Path $run 'safe-proof.json') ([ordered]@{
            schemaVersion=1;status='compatibility-passed-unreviewed';hosted=$hosted
            revision=$(if($hosted){$env:GITHUB_SHA}else{$null})
            runId=$(if($hosted){$env:GITHUB_RUN_ID}else{$null})
            runAttempt=$(if($hosted){$env:GITHUB_RUN_ATTEMPT}else{$null})
            sourceSnapshotSha256=$verified.record.sourceSnapshotSha256
            receiptSha256=Get-NativeIsarDigest $verified.receipt
            artifactManifestSha256=(Get-NativeIsarCandidateArtifact $artifact).manifestSha256
            compiledRuntimeDiagnostics=$true;fullAcceptance=$false;distributionReady=$false;activated=$false
        })
        'COLD_SOURCE_BUILD_CURRENT_COMPATIBILITY_AND_RUNTIME_DIAGNOSTICS_PASSED'
        'COLD_RUNNER_SAFE_PROOF='+ (Join-Path $run 'safe-proof.json')
    } finally { Pop-Location }
} catch {
    Write-NativeIsarJson (Join-Path $run 'safe-failure.json') ([ordered]@{
        schemaVersion=1;status='failed';phase=$script:coldPhase;hosted=$hosted
        fullAcceptance=$false;distributionReady=$false;activated=$false
    })
    throw "Cold source-build pipeline failed during $script:coldPhase; retained private evidence: $run"
}
