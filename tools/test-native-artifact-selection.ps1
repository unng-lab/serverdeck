[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact)
. "$PSScriptRoot/native-artifact.ps1"
$prior=$env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT
$normal=Get-NativeArtifactBuildSelection
$candidate=Get-NativeIsarCandidateArtifact $Artifact
$manifestHash=$candidate.manifestSha256
$dllHash=Get-NativeIsarDigest $candidate.dll
$script:finishedContext=''
Invoke-NativeArtifactCandidateScope $Artifact {
    $selected=Get-NativeArtifactBuildSelection
    if ($selected.mode -cne 'explicit-unqualified-candidate' -or $selected.dll -cne $candidate.dll -or $selected.sha256 -cne $dllHash) { throw 'Candidate scope chose a different DLL.' }
    $script:finishedContext=$env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT
    $child=& (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File "$PSScriptRoot/resolve-native-artifact.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'Child native selection failed.' }
    $child=$child | ConvertFrom-Json
    if ($child.mode -cne $selected.mode -or $child.dll -cne $selected.dll -or $child.sha256 -cne $dllHash) { throw 'Child selected a different native artifact.' }
    $validContext=Read-NativeIsarArtifactJson $script:finishedContext
    foreach ($case in @('state','owner','process','start','source','dll','artifact','preservation-type')) {
        $root=Join-Path $NativeIsarRepository ('.local/native-qualification-' + [Guid]::NewGuid().ToString('N'))
        Assert-NativeIsarPlainPath $root
        [IO.Directory]::CreateDirectory($root) | Out-Null
        $path=Join-Path $root 'context.json'
        $context=$validContext | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        switch ($case) {
            'state' {$context.state='qualified'}
            'owner' {$context.ownerSid='S-1-0-0'}
            'process' {$context.processId=2147483647}
            'start' {$context.processStartTicks=[long]($context.processStartTicks + 1)}
            'source' {$context.sourceSnapshotSha256='0' * 64}
            'dll' {$context.dllSha256='0' * 64}
            'artifact' {$context.artifact='../outside'}
            'preservation-type' {$context.preserveNormalBundles='true'}
        }
        Write-NativeIsarJson $path $context
        try {
            $env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT=$path
            $refused=$false
            try { Get-NativeArtifactBuildSelection | Out-Null } catch {
                $expected=switch ($case) {
                    'process' {'Native qualification process is not running.'}
                    'start' {'Native qualification process identity changed.'}
                    'source' {'Native qualification inputs changed.'}
                    'dll' {'Native qualification inputs changed.'}
                    'artifact' {'Invalid native qualification artifact reference.'}
                    default {'Invalid native qualification context identity.'}
                }
                if ($_.Exception.Message -cne $expected) { throw }
                $refused=$true
            }
            if (-not $refused) { throw 'Invalid candidate context was accepted.' }
        } finally { $env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT=$script:finishedContext }
    }
}
if ($env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT -cne $prior -or (Read-NativeIsarArtifactJson $script:finishedContext).state -cne 'candidate-validation-finished') { throw 'Candidate scope did not finish and restore selection.' }
$restored=Get-NativeArtifactBuildSelection
if ($restored.mode -cne $normal.mode -or $restored.sha256 -cne $normal.sha256) { throw 'Normal development selection changed.' }
$failedContext=''
$failed=$false
try {
    Invoke-NativeArtifactCandidateScope $Artifact {
        $script:failedContext=$env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT
        throw 'Controlled candidate action failure.'
    }
} catch { if ($_.Exception.Message -cne 'Controlled candidate action failure.') { throw };$failed=$true }
if (-not $failed -or $env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT -cne $prior -or
    (Read-NativeIsarArtifactJson $script:failedContext).state -cne 'candidate-validation-failed') { throw 'Failed scope did not restore selection.' }
if ((Get-NativeIsarCandidateArtifact $candidate.directory).manifestSha256 -cne $manifestHash -or (Get-NativeIsarDigest $candidate.dll) -cne $dllHash) { throw 'Candidate artifact changed.' }
$originalBundles=@{}
foreach ($configuration in @('Debug','Release')) {
    $normal=Join-Path $NativeIsarRepository ('build/windows/x64/runner/' + $configuration)
    $originalBundles[$configuration]=if (Test-Path -LiteralPath $normal) { Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $normal) } else { $null }
}
$controlledFailure=$false
try {
    Invoke-NativeArtifactCandidateScope $Artifact -PreserveNormalBundles -Action {
        $partial=Join-Path $NativeIsarRepository 'build/windows/x64/runner/Debug'
        Assert-NativeIsarPlainPath $partial
        [IO.Directory]::CreateDirectory($partial) | Out-Null
        [IO.File]::WriteAllText((Join-Path $partial 'partial-candidate.txt'),'controlled failed build output')
        throw 'Controlled partial bundle failure.'
    }
} catch { if ($_.Exception.Message -cne 'Controlled partial bundle failure.') { throw };$controlledFailure=$true }
if (-not $controlledFailure -or $env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT -cne $prior) { throw 'Partial build scope did not fail/restore selection.' }
foreach ($configuration in @('Debug','Release')) {
    $normal=Join-Path $NativeIsarRepository ('build/windows/x64/runner/' + $configuration)
    if ($null -eq $originalBundles[$configuration]) {
        if (Test-Path -LiteralPath $normal) { throw 'Initially absent normal bundle was not restored as absent.' }
    } elseif ((Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $normal)) -cne $originalBundles[$configuration]) { throw 'Partial build changed the original normal bundle.' }
}
'NATIVE_CANDIDATE_SELECTION_CHILD_EIGHT_REFUSALS_SCOPE_AND_PARTIAL_BUNDLE_RESTORATION_PASSED'
