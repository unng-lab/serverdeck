[CmdletBinding()]
param([Parameter(Mandatory)][string]$Receipt,[Parameter(Mandatory)][string]$AlternateAvailableResult)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/native-artifact-compatibility.ps1"
$original=Get-NativeArtifactCompatibility $Receipt
$root=[IO.Path]::GetDirectoryName($original.receipt)
$alternate=Read-NativeIsarArtifactJson $AlternateAvailableResult
$originalInputs=Read-NativeIsarArtifactJson (Join-Path $root 'compatibility-inputs.json')
$originalAvailableCount=$originalInputs.availableEvidence.Count - 1
if ($alternate.status -cne 'passed' -or $alternate.completed.Count -notin @(13,14) -or
    $alternate.requiredPhaseCount -ne $alternate.completed.Count -or
    $alternate.completed.Count -ne $originalAvailableCount) { throw 'Alternate suite must be a real completed result matching the historical canonical phase count.' }
$alternateRoot=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($AlternateAvailableResult,(Get-Location).ProviderPath))
if ($original.currentSourceMatches) { throw 'This historical-refusal regression requires an outdated receipt after tooling changes.' }
$refused=$false
try { Get-NativeArtifactCompatibility $original.receipt -RequireCurrentSource | Out-Null } catch { $refused=$_.Exception.Message -match 'snapshot is outdated' }
if (-not $refused) { throw 'Outdated compatibility was not refused for current selection.' }
$fixtures=[Collections.Generic.List[string]]::new()
$cases=@('readiness','artifact-path','evidence-path','phase-log','phase-count','phase-order','source-digest','alternate-suite','native-payload','native-manifest')
if ($originalAvailableCount -eq 13) { $cases += 'current-scope-downgrade' }
foreach ($case in $cases) {
    $fixture=Join-Path $NativeIsarRepository ('.local/native-qualification-' + [Guid]::NewGuid().ToString('N'))
    Assert-NativeIsarPlainPath $fixture
    [IO.Directory]::CreateDirectory($fixture) | Out-Null
    foreach ($item in $original.record.evidence) { Copy-Item -LiteralPath (Join-Path $root $item.file) -Destination (Join-Path $fixture $item.file) }
    $inputs=Read-NativeIsarArtifactJson (Join-Path $fixture 'compatibility-inputs.json')
    foreach ($phase in $inputs.phases) { Copy-Item -LiteralPath (Join-Path $root $phase.log) -Destination (Join-Path $fixture $phase.log) }
    $record=$original.record | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    switch ($case) {
        'current-scope-downgrade' {
            $snapshot=Get-NativeArtifactSourceSnapshot
            [IO.File]::WriteAllText((Join-Path $fixture 'source-snapshot.json'),($snapshot|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
            $record.sourceSnapshotSha256=$snapshot.sha256
            $inputs.sourceSnapshotSha256=$snapshot.sha256
            $context=Read-NativeIsarArtifactJson (Join-Path $fixture 'context.json')
            $context.sourceSnapshotSha256=$snapshot.sha256
            [IO.File]::WriteAllText((Join-Path $fixture 'context.json'),($context|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
            $record.evidence[0].sha256=Get-NativeIsarDigest (Join-Path $fixture 'source-snapshot.json')
            $record.evidence[4].sha256=Get-NativeIsarDigest (Join-Path $fixture 'context.json')
        }
        'readiness' { $record.activated=$true }
        'artifact-path' { $record.artifact='../outside' }
        'evidence-path' { $record.evidence[0].file='../outside.json' }
        'phase-log' { [IO.File]::AppendAllText((Join-Path $fixture 'root-analyze.txt'),'synthetic corruption') }
        'phase-count' { $inputs.phases=@($inputs.phases | Select-Object -First 13) }
        'phase-order' { $temporary=$inputs.phases[0];$inputs.phases[0]=$inputs.phases[1];$inputs.phases[1]=$temporary }
        'source-digest' {
            $snapshot=Read-NativeIsarArtifactJson (Join-Path $fixture 'source-snapshot.json')
            $snapshot.files[0].sha256='0' * 64
            [IO.File]::WriteAllText((Join-Path $fixture 'source-snapshot.json'),($snapshot|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
            $record.evidence[0].sha256=Get-NativeIsarDigest (Join-Path $fixture 'source-snapshot.json')
        }
        'alternate-suite' {
            foreach ($item in $inputs.availableEvidence) {
                $path=Join-Path $alternateRoot ([IO.Path]::GetFileName($item.file))
                $item.file=[IO.Path]::GetRelativePath($NativeIsarRepository,$path).Replace('\','/')
                $item.sha256=Get-NativeIsarDigest $path
            }
        }
    }
    if ($case -in @('native-payload','native-manifest')) {
        $bundles=Read-NativeIsarArtifactJson (Join-Path $fixture 'normal-bundles.json')
        [IO.Directory]::CreateDirectory((Join-Path $fixture 'normal-bundles')) | Out-Null
        foreach ($bundle in $bundles) {
            $source=Join-Path $root $bundle.directory
            [void](Get-NativeArtifactBundleSnapshot $source)
            $copy=Join-Path $fixture $bundle.directory
            Copy-Item -LiteralPath $source -Destination $copy -Recurse
            $manifestPath=Join-Path $copy 'foundation.manifest.json'
            $manifest=Read-NativeIsarArtifactJson $manifestPath
            $manifest.appRoot=$copy
            [IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
            $notices=Join-Path $copy 'notices'
            if ($case -eq 'native-manifest') {
                [IO.File]::AppendAllText((Join-Path $notices 'native/native-artifact.json'),"`n")
            } else {
                $payload=Join-Path $notices 'native/licenses/isar/LICENSE'
                [IO.File]::AppendAllText($payload,'synthetic coherent corruption')
                $inventoryPath=Join-Path $notices 'third-party-notices.json'
                $inventory=Read-NativeIsarArtifactJson $inventoryPath
                $item=@($inventory.native.payload | Where-Object file -CEQ 'licenses/isar/LICENSE')[0]
                $item.sha256=Get-NativeIsarDigest $payload
                $item.length=(Get-Item -LiteralPath $payload).Length
                [IO.File]::WriteAllText($inventoryPath,($inventory|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
            }
            $bundle.noticeTreeSha256=Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $notices)
            $bundle.treeSha256=Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $copy)
        }
        [IO.File]::WriteAllText((Join-Path $fixture 'normal-bundles.json'),($bundles|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
        $record.evidence[2].sha256=Get-NativeIsarDigest (Join-Path $fixture 'normal-bundles.json')
    }
    if ($case -in @('phase-count','phase-order','alternate-suite','current-scope-downgrade')) {
        [IO.File]::WriteAllText((Join-Path $fixture 'compatibility-inputs.json'),($inputs|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
        $record.evidence[3].sha256=Get-NativeIsarDigest (Join-Path $fixture 'compatibility-inputs.json')
    }
    $path=Join-Path $fixture 'compatibility-receipt.json'
    Write-NativeIsarJson $path $record
    $pattern=switch ($case) {
        'current-scope-downgrade' {'available evidence invalid'}
        'readiness' {'falsely claims readiness'}
        'artifact-path' {'artifact reference invalid'}
        'evidence-path' {'evidence names/order invalid'}
        'phase-log' {'evidence hash mismatch'}
        'phase-count' {'phase inventory incomplete'}
        'phase-order' {'phase identity/order invalid'}
        'source-digest' {'recorded source digest invalid'}
        'alternate-suite' {'result marker disagrees with evidence'}
        'native-payload' {'notice payload inventory mismatch'}
        'native-manifest' {'evidence hash mismatch'}
    }
    $refused=$false
    try { Get-NativeArtifactCompatibility $path | Out-Null } catch { $refused=$_.Exception.Message -match $pattern }
    if (-not $refused) { throw "Compatibility $case did not refuse with expected reason." }
    $fixtures.Add([IO.Path]::GetRelativePath($NativeIsarRepository,$fixture).Replace('\','/'))
}
if ((Get-NativeIsarDigest $original.receipt) -cne $original.receiptSha256) { throw 'Original compatibility receipt changed.' }
$evidence=Join-Path $NativeIsarRepository ('.local/audits/native-compatibility-validator-' + [Guid]::NewGuid().ToString('N') + '.json')
if ((Get-NativeIsarCandidateArtifact $original.artifact.directory).manifestSha256 -cne $original.artifact.manifestSha256) { throw 'Original artifact changed.' }
Write-NativeIsarJson $evidence ([ordered]@{schemaVersion=1;passed=$true;distributionReady=$false;originalReceiptSha256=$original.receiptSha256;currentSourceMatches=$false;refusalCount=($fixtures.Count+1);fixtures=@($fixtures.ToArray());scope='read-only historical audit, current-source refusal and copied corruption/coherent substitution refusals; includes current-scope downgrade for legacy thirteen-phase evidence; not activation'})
"COMPATIBILITY_HISTORICAL_AUDIT_$($fixtures.Count+1)_REFUSALS_AND_ORIGINAL_PRESERVATION_PASSED"
$evidence
# Preserve evidence without cleanup or active-pointer changes.
