. "$PSScriptRoot/native-artifact-abi.ps1"
. "$PSScriptRoot/native-artifact-source-snapshot.ps1"

function Get-NativeArtifactBundleSnapshot {
    param([Parameter(Mandatory)][string]$Directory)
    Assert-NativeIsarPlainPath $Directory
    $snapshot=@{}
    foreach ($entry in Get-ChildItem -LiteralPath $Directory -Recurse -Force) {
        Assert-NativeIsarPlainPath $entry.FullName
        if ($entry.PSIsContainer) { continue }
        $snapshot[[IO.Path]::GetRelativePath($Directory,$entry.FullName).Replace('\','/')]=Get-NativeIsarDigest $entry.FullName
    }
    return $snapshot
}

function Assert-NativeCompatibilityHash {
    param([string]$Path,[string]$Expected)
    if ($Expected -cnotmatch '^[a-f0-9]{64}$' -or (Get-NativeIsarDigest $Path) -cne $Expected) { throw 'Native compatibility evidence hash mismatch.' }
}

function Get-NativeArtifactCompatibility {
    param([Parameter(Mandatory)][string]$Receipt,[switch]$RequireCurrentSource)
    $Receipt=[IO.Path]::GetFullPath($Receipt,(Get-Location).ProviderPath)
    $root=[IO.Path]::GetDirectoryName($Receipt)
    if ([IO.Path]::GetDirectoryName($root) -cne (Join-Path $NativeIsarRepository '.local') -or
        [IO.Path]::GetFileName($root) -cnotmatch '^native-qualification-[a-f0-9]{32}$' -or
        [IO.Path]::GetFileName($Receipt) -cne 'compatibility-receipt.json') { throw 'Native compatibility receipt is outside owned evidence.' }
    $receiptHash=Get-NativeIsarDigest $Receipt
    $record=Read-NativeIsarArtifactJson $Receipt
    if ($record.schemaVersion -ne 1 -or $record.product -cne 'serverdeck-isar-native' -or $record.state -cne 'compatibility-passed-unreviewed') { throw 'Native compatibility receipt identity mismatch.' }
    foreach ($name in @('distributionReady','fullAcceptance','activated')) {
        if ($record.$name -isnot [bool] -or $record.$name -ne $false) { throw 'Native compatibility receipt falsely claims readiness.' }
    }
    $current=Get-NativeArtifactSourceSnapshot
    $sourceMatches=$current.sha256 -ceq $record.sourceSnapshotSha256
    if ($RequireCurrentSource -and -not $sourceMatches) { throw 'Native compatibility source snapshot is outdated.' }
    if ($record.artifact -cnotmatch '^\.local/native-isar/candidate-[a-f0-9]{32}/artifact-[a-f0-9]{32}$') { throw 'Native compatibility artifact reference invalid.' }
    $artifact=Get-NativeIsarCandidateArtifact (Join-Path $NativeIsarRepository $record.artifact)
    if ($artifact.manifestSha256 -cne $record.artifactManifestSha256 -or (Get-NativeIsarDigest $artifact.dll) -cne $record.dllSha256) { throw 'Native compatibility artifact changed.' }
    $expectedEvidence=@('source-snapshot.json','abi.json','normal-bundles.json','compatibility-inputs.json','context.json','bundle-preservation.json')
    if ($record.evidence.Count -ne 6) { throw 'Native compatibility evidence inventory incomplete.' }
    for ($index=0;$index -lt 6;$index++) {
        $item=$record.evidence[$index]
        if ($item.file -cne $expectedEvidence[$index]) { throw 'Native compatibility evidence names/order invalid.' }
        Assert-NativeCompatibilityHash (Join-Path $root $item.file) $item.sha256
    }
    $context=Read-NativeIsarArtifactJson (Join-Path $root 'context.json')
    if ($context.schemaVersion -ne 1 -or $context.state -cne 'candidate-validation-finished' -or
        $context.distributionReady -isnot [bool] -or $context.distributionReady -ne $false -or
        $context.preserveNormalBundles -isnot [bool] -or $context.preserveNormalBundles -ne $true -or
        $context.artifact -cne $record.artifact -or $context.artifactManifestSha256 -cne $record.artifactManifestSha256 -or
        $context.dllSha256 -cne $record.dllSha256 -or $context.sourceSnapshotSha256 -cne $record.sourceSnapshotSha256) { throw 'Native compatibility context did not finish with matching inputs.' }
    $snapshot=Read-NativeIsarArtifactJson (Join-Path $root 'source-snapshot.json')
    if ($snapshot.schemaVersion -ne 1 -or $snapshot.sha256 -cne $record.sourceSnapshotSha256 -or
        $snapshot.files.Count -lt 1 -or $snapshot.files.Count -gt 100000) { throw 'Native compatibility source snapshot invalid.' }
    $sourceHashes=@{}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $previous=$null
    $total=0L
    foreach ($file in $snapshot.files) {
        Assert-NativeIsarArchiveName $file.file $NativeIsarRepository $seen
        if ($previous -and [StringComparer]::Ordinal.Compare($previous,$file.file) -ge 0) { throw 'Native compatibility source inventory is not sorted.' }
        if ($file.sha256 -cnotmatch '^[a-f0-9]{64}$' -or ($file.length -isnot [int] -and $file.length -isnot [long]) -or
            $file.length -lt 0 -or $file.length -gt 2GB) { throw 'Native compatibility source record invalid.' }
        $total += $file.length
        if ($total -gt 8GB) { throw 'Native compatibility source resource limit exceeded.' }
        $sourceHashes[$file.file]=$file.sha256
        $previous=$file.file
    }
    if ((Get-NativeIsarSnapshotDigest $sourceHashes) -cne $snapshot.sha256) { throw 'Native compatibility recorded source digest invalid.' }
    $inputs=Read-NativeIsarArtifactJson (Join-Path $root 'compatibility-inputs.json')
    if ($inputs.schemaVersion -ne 1 -or $inputs.artifactManifestSha256 -cne $record.artifactManifestSha256 -or
        $inputs.dllSha256 -cne $record.dllSha256 -or $inputs.sourceSnapshotSha256 -cne $record.sourceSnapshotSha256) { throw 'Native compatibility inputs mismatch.' }
    $phases=@('abi','root-format','root-analyze','root-tests','serverdeck_protocol-analyze','serverdeck_protocol-tests',
        'serverdeck_windows-analyze','serverdeck_windows-tests','serverdeck_locald-analyze','serverdeck_locald-tests',
        'bundle-Debug','bundle-Release','available-native-ui','runtime-diagnostics')
    if ($inputs.phases.Count -ne 14) { throw 'Native compatibility phase inventory incomplete.' }
    for ($index=0;$index -lt 14;$index++) {
        $phase=$inputs.phases[$index]
        if ($phase.name -cne $phases[$index] -or $phase.passed -isnot [bool] -or $phase.passed -ne $true -or
            $phase.log -cne ($phases[$index] + '.txt')) { throw 'Native compatibility phase identity/order invalid.' }
        Assert-NativeCompatibilityHash (Join-Path $root $phase.log) $phase.logSha256
    }
    $availableNames=@('compiled-core-storage','compiled-commit-recovery','compiled-api-commit-recovery','compiled-initialization-recovery',
        'compiled-secret-markers','normal-prerequisites','compiled-bootstrap-owner-loss','ui-two-window','ui-three-window',
        'ui-observer-crash','ui-loss-recovery','ui-credential-lifecycle','ui-unknown-inflight')
    # The old canonical scope is retained for historical inspection only.
    # A current-source receipt must include the newly accepted owner UI case.
    if ($inputs.availableEvidence.Count -eq 14 -and -not $sourceMatches) {
        $availablePhaseCount=13
    } else {
        $availableNames += 'ui-normal-owner-recovery'
        $availablePhaseCount=14
    }
    if ($inputs.availableEvidence.Count -ne ($availablePhaseCount + 1) -or $inputs.availableEvidence[0].file -cnotmatch
        '^\.local/available-acceptance-[a-f0-9]{32}/result\.json$') { throw 'Native compatibility available evidence invalid.' }
    $resultMarkers=@(Get-Content -LiteralPath (Join-Path $root 'available-native-ui.txt') | Where-Object {$_ -cmatch '^AVAILABLE_ACCEPTANCE_RESULT='})
    if ($resultMarkers.Count -ne 1) { throw 'Native compatibility available result marker missing or duplicated.' }
    $markerValue=$resultMarkers[0].Substring('AVAILABLE_ACCEPTANCE_RESULT='.Length)
    if (-not [IO.Path]::IsPathFullyQualified($markerValue) -or
        -not [IO.Path]::GetFullPath($markerValue).Equals([IO.Path]::GetFullPath((Join-Path $NativeIsarRepository $inputs.availableEvidence[0].file)),[StringComparison]::OrdinalIgnoreCase)) { throw 'Native compatibility available result marker disagrees with evidence.' }
    $availableRelative=[IO.Path]::GetDirectoryName($inputs.availableEvidence[0].file).Replace('\','/')
    for ($index=0;$index -lt ($availablePhaseCount + 1);$index++) {
        $item=$inputs.availableEvidence[$index]
        $name=if ($index -eq 0) { 'result.json' } else { $availableNames[$index-1] + '.txt' }
        if ($item.file -cne ($availableRelative + '/' + $name)) { throw 'Native compatibility available evidence order invalid.' }
        Assert-NativeCompatibilityHash (Join-Path $NativeIsarRepository $item.file) $item.sha256
    }
    $available=Read-NativeIsarArtifactJson (Join-Path $NativeIsarRepository $inputs.availableEvidence[0].file)
    if ($available.format -ne 1 -or $available.scenario -cne 'available-automated-foundation' -or $available.status -cne 'passed' -or
        $available.requiredPhaseCount -ne $availablePhaseCount -or $available.completed.Count -ne $availablePhaseCount -or
        $available.fullAcceptance -isnot [bool] -or $available.fullAcceptance -ne $false -or $null -ne $available.failedPhase) { throw 'Native compatibility available acceptance incomplete.' }
    for ($index=0;$index -lt $availablePhaseCount;$index++) {
        if ($available.completed[$index].name -cne $availableNames[$index] -or
            $available.completed[$index].completed -isnot [bool] -or $available.completed[$index].completed -ne $true) { throw 'Native compatibility available phase incomplete.' }
    }
    if ((Get-NativeIsarCanonicalDigest @($inputs.excluded)) -cne (Get-NativeIsarCanonicalDigest @($available.excluded))) { throw 'Native compatibility exclusions mismatch.' }
    if (@(Get-Content -LiteralPath (Join-Path $root 'runtime-diagnostics.txt') | Where-Object {$_ -ceq 'COMPILED_UI_RUNTIME_DIAGNOSTICS_ACCEPTANCE_PASSED'}).Count -ne 1) { throw 'Native compatibility diagnostics proof absent.' }
    $abi=Read-NativeIsarArtifactJson (Join-Path $root 'abi.json')
    if ((Get-NativeIsarCanonicalDigest (Get-NativeArtifactAbiEvidence $artifact.directory)) -cne (Get-NativeIsarCanonicalDigest $abi)) { throw 'Native compatibility ABI inputs changed.' }
    $bundles=Read-NativeIsarArtifactJson (Join-Path $root 'normal-bundles.json')
    $preservation=Read-NativeIsarArtifactJson (Join-Path $root 'bundle-preservation.json')
    if (@($bundles).Count -ne 2 -or @($preservation).Count -ne 2) { throw 'Native compatibility bundle inventory incomplete.' }
    for ($index=0;$index -lt 2;$index++) {
        $configuration=@('Debug','Release')[$index]
        $bundle=$bundles[$index]
        if ($bundle.configuration -cne $configuration -or $bundle.directory -cne ('normal-bundles/' + $configuration)) { throw 'Native compatibility bundle identity invalid.' }
        $directory=Join-Path $root $bundle.directory
        if ((Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $directory)) -cne $bundle.treeSha256) { throw 'Native compatibility retained bundle changed.' }
        $manifest=Read-NativeIsarArtifactJson (Join-Path $directory 'foundation.manifest.json')
        if ($manifest.format -ne 1 -or $manifest.configuration -cne $configuration -or $manifest.testOnly -isnot [bool] -or
            $manifest.testOnly -ne $false -or $manifest.appRoot -cne $directory -or $manifest.sha256.'libisar.dll' -cne $record.dllSha256) { throw 'Native compatibility normal manifest invalid.' }
        foreach ($name in @('serverdeck.exe','locald.exe','libisar.dll')) { Assert-NativeCompatibilityHash (Join-Path $directory $name) $manifest.sha256.$name }
        $notices=Join-Path $directory 'notices'
        $noticeTree=Get-NativeArtifactBundleSnapshot $notices
        if ($noticeTree.Count -ne 199 -or (Get-NativeIsarSnapshotDigest $noticeTree) -cne $bundle.noticeTreeSha256) { throw 'Native compatibility notices changed.' }
        $inventory=Read-NativeIsarArtifactJson (Join-Path $notices 'third-party-notices.json')
        if ($inventory.native.artifactManifestSha256 -cne $record.artifactManifestSha256 -or $inventory.native.dllSha256 -cne $record.dllSha256 -or
            $inventory.distributionReady -isnot [bool] -or $inventory.distributionReady -ne $false) { throw 'Native compatibility notice binding invalid.' }
        Assert-NativeCompatibilityHash (Join-Path $notices 'native/native-artifact.json') $artifact.manifestSha256
        $expectedPayload=@($artifact.manifest.files | Where-Object file -CNE 'libisar.dll')
        if ($inventory.format -ne 1 -or $inventory.status -cne 'bound-native-notices-unqualified' -or
            $inventory.native.payload.Count -ne 196 -or
            (Get-NativeIsarCanonicalDigest @($inventory.native.payload)) -cne (Get-NativeIsarCanonicalDigest $expectedPayload)) { throw 'Native compatibility notice payload inventory mismatch.' }
        foreach ($file in $expectedPayload) {
            $copy=Join-Path $notices ('native/' + $file.file)
            Assert-NativeCompatibilityHash $copy $file.sha256
            if ((Get-Item -LiteralPath $copy).Length -ne $file.length) { throw 'Native compatibility copied payload length mismatch.' }
        }
        $combined=Join-Path $notices 'THIRD_PARTY_NOTICES.txt'
        Assert-NativeCompatibilityHash $combined $inventory.noticesSha256
        if (-not [IO.File]::ReadAllText($combined).Contains([IO.File]::ReadAllText((Join-Path $artifact.directory 'THIRD_PARTY_NATIVE_NOTICES.txt')))) { throw 'Native compatibility combined native text mismatch.' }
        $restored=$preservation[$index]
        if ($restored.configuration -cne $configuration -or $restored.restored -isnot [bool] -or $restored.restored -ne $true -or
            $restored.existed -isnot [bool] -or $restored.normal -cne (Join-Path $NativeIsarRepository ('build/windows/x64/runner/' + $configuration))) { throw 'Native compatibility normal outputs were not restored.' }
        # Original output may legitimately be rebuilt after successful restoration.
        # Its historical restoration record is bound; retained qualified inputs above stay immutable.
    }
    if ($bundles[0].noticeTreeSha256 -cne $bundles[1].noticeTreeSha256) { throw 'Native compatibility Debug/Release notices differ.' }
    if ((Get-NativeArtifactSourceSnapshot).sha256 -cne $current.sha256) { throw 'Native compatibility source changed while validating.' }
    if ((Get-NativeIsarDigest $Receipt) -cne $receiptHash) { throw 'Native compatibility receipt changed while validating.' }
    return [pscustomobject]@{receipt=$Receipt;receiptSha256=$receiptHash;record=$record;artifact=$artifact;currentSourceMatches=$sourceMatches;currentSourceSha256=$current.sha256}
}
