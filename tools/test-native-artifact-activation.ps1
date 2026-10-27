[CmdletBinding()]
param([Parameter(Mandatory)][string]$HistoricalReceipt,[Parameter(Mandatory)][string]$HistoricalReview)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/native-artifact.ps1"
$active=Join-Path $NativeIsarRepository '.local/native-isar/active.json'
$established=Join-Path $NativeIsarRepository '.local/native-isar-activation-established.json'
if ((Test-Path -LiteralPath $active) -or (Test-Path -LiteralPath $established) -or $env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT) { throw 'Activation refusal regression requires preactivation, sequential private development state.' }
$fixture=Join-Path $NativeIsarRepository ('.local/native-activation-tests-' + [Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $fixture
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$normal=Get-NativeArtifactBuildSelection
if ($normal.mode -cne 'historical-private-development-cache') { throw 'Unexpected preactivation selection.' }
$refusals=0
$prior=$env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT
try {
    $env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT='synthetic-nested-context'
    $refused=$false
    try { Invoke-NativeArtifactActivation $HistoricalReceipt $HistoricalReview | Out-Null } catch {$refused=$_.Exception.Message -match 'inside a candidate scope'}
    if (-not $refused) { throw 'Nested activation not refused.' }
    $refusals++
} finally { $env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT=$prior }
$refused=$false
try { Invoke-NativeArtifactActivation $HistoricalReceipt $HistoricalReview | Out-Null } catch {$refused=$_.Exception.Message -match 'snapshot is outdated'}
if (-not $refused -or (Test-Path -LiteralPath $active) -or (Test-Path -LiteralPath $established)) { throw 'Historical activation mutated selection.' }
$refusals++
$root=Join-Path $NativeIsarRepository ('.local/native-qualification-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
Copy-Item -LiteralPath ([IO.Path]::GetFullPath($HistoricalReceipt,(Get-Location).ProviderPath)) -Destination (Join-Path $root 'compatibility-receipt.json')
$record=Read-NativeIsarArtifactJson (Join-Path $root 'compatibility-receipt.json')
$qualified=Join-Path $root ('qualification-receipt-' + [Guid]::NewGuid().ToString('N') + '.json')
$qualifiedRecord=[ordered]@{schemaVersion=1;state='reviewed-compatibility-qualified';distributionReady=$false;fullAcceptance=$false;approvalScope='native-build-compatibility-only';
    compatibilityReceipt=[IO.Path]::GetRelativePath($NativeIsarRepository,(Join-Path $root 'compatibility-receipt.json')).Replace('\','/');compatibilityReceiptSha256=Get-NativeIsarDigest (Join-Path $root 'compatibility-receipt.json');
    review=[IO.Path]::GetRelativePath($NativeIsarRepository,[IO.Path]::GetFullPath($HistoricalReview,(Get-Location).ProviderPath)).Replace('\','/');reviewSha256=Get-NativeIsarDigest ([IO.Path]::GetFullPath($HistoricalReview,(Get-Location).ProviderPath));
    artifact=$record.artifact;artifactManifestSha256=$record.artifactManifestSha256;dllSha256=$record.dllSha256;sourceSnapshotSha256=$record.sourceSnapshotSha256}
Write-NativeIsarJson $qualified $qualifiedRecord
foreach ($case in @('pointer-state','pointer-ready','pointer-path','missing-receipt','stale-receipt')) {
    $pointer=[ordered]@{schemaVersion=1;state='native-build-input-active';distributionReady=$false;fullAcceptance=$false;qualificationReceipt=[IO.Path]::GetRelativePath($NativeIsarRepository,$qualified).Replace('\','/');qualificationReceiptSha256=Get-NativeIsarDigest $qualified}
    switch ($case) {
        'pointer-state' {$pointer.state='unreviewed'}
        'pointer-ready' {$pointer.distributionReady=$true}
        'pointer-path' {$pointer.qualificationReceipt='../outside.json'}
        'missing-receipt' {$pointer.qualificationReceipt=('.local/native-qualification-' + [Guid]::NewGuid().ToString('N') + '/qualification-receipt-' + [Guid]::NewGuid().ToString('N') + '.json')}
    }
    Write-NativeIsarJson $active $pointer
    $ownedHash=Get-NativeIsarDigest $active
    try {
        $refused=$false
        try { Get-NativeArtifactBuildSelection | Out-Null } catch { $refused=$true; if ($case -eq 'stale-receipt' -and $_.Exception.Message -notmatch 'snapshot is outdated') { throw } }
        if (-not $refused) { throw 'Invalid active input silently selected a native DLL.' }
        $refusals++
    } finally {
        Assert-NativeCompatibilityHash $active $ownedHash
        Move-Item -LiteralPath $active -Destination (Join-Path $fixture ($case + '.json'))
    }
}
Write-NativeIsarJson $established ([ordered]@{schemaVersion=1;state='synthetic-qualified-input-required-test';distributionReady=$false})
$ownedHash=Get-NativeIsarDigest $established
try {
    $refused=$false
    try { Get-NativeArtifactBuildSelection | Out-Null } catch {$refused=$_.Exception.Message -match 'fallback is forbidden'}
    if (-not $refused) { throw 'Missing previously activated pointer fell back to cache.' }
    $refusals++
} finally {
    Assert-NativeCompatibilityHash $established $ownedHash
    Move-Item -LiteralPath $established -Destination (Join-Path $fixture 'established.json')
}
if ((Get-NativeArtifactBuildSelection).sha256 -cne $normal.sha256 -or (Test-Path -LiteralPath $active) -or (Test-Path -LiteralPath $established)) { throw 'Private preactivation state not restored.' }
Write-NativeIsarJson (Join-Path $fixture 'result.json') ([ordered]@{schemaVersion=1;passed=$true;refusalCount=$refusals;distributionReady=$false;activated=$false;scope='eight preactivation/current-source/pointer refusals and restoration; positive current approval/activation still requires fresh full qualification'})
'NATIVE_ACTIVATION_EIGHT_REFUSALS_NO_CACHE_FALLBACK_AND_STATE_RESTORATION_PASSED'
$fixture
# Move only exact owned synthetic files; never recursively delete or bypass denied operations.
