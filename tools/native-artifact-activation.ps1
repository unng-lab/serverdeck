. "$PSScriptRoot/native-artifact-compatibility.ps1"

function Get-NativeArtifactReviewEvidence {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object]$Compatibility)
    $Path=[IO.Path]::GetFullPath($Path,(Get-Location).ProviderPath)
    if ([IO.Path]::GetDirectoryName($Path) -cne (Join-Path $NativeIsarRepository '.local/audits') -or
        [IO.Path]::GetFileName($Path) -cnotmatch '^t233-compatibility-clean-review-[a-f0-9]{32}\.json$') { throw 'Native approval must be an owned independent review record.' }
    $hash=Get-NativeIsarDigest $Path
    $review=Read-NativeIsarArtifactJson $Path
    $relative=[IO.Path]::GetRelativePath($NativeIsarRepository,$Compatibility.receipt).Replace('\','/')
    if ($review.schemaVersion -ne 1 -or $review.kind -cne 'summary-of-completed-independent-compatibility-review' -or
        $review.reviewer -cnotmatch '^/root/[a-z0-9_]+$' -or
        ($review.findingCount -isnot [int] -and $review.findingCount -isnot [long]) -or $review.findingCount -ne 0 -or
        $review.currentCompatibilityResultVerified -isnot [bool] -or $review.currentCompatibilityResultVerified -ne $true -or
        $review.controllerReadiness -cne 'ready' -or $review.qualifiedNormalProviderReadiness -cne 'ready' -or
        $review.activationWorkflowReadiness -cne 'ready' -or $review.compatibilityReceipt -cne $relative -or
        $review.compatibilityReceiptSha256 -cne $Compatibility.receiptSha256 -or
        $review.sourceSnapshotSha256 -cne $Compatibility.record.sourceSnapshotSha256) { throw 'Native independent review does not approve this current compatibility and activation workflow.' }
    foreach ($name in @('distributionReady','fullAcceptance','activated')) {
        if ($review.$name -isnot [bool] -or $review.$name -ne $false) { throw 'Native review falsely claims product distribution or activation.' }
    }
    $required=@('tools/native-artifact.ps1','tools/native-artifact-compatibility.ps1','tools/native-artifact-activation.ps1',
        'tools/activate-native-isar.ps1','tools/native-artifact-abi.ps1','tools/test-native-isar.ps1','tools/run-foundation.ps1',
        'specs/001-service-foundation/contracts/native-artifact.md')
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $review.scope) {
        Assert-NativeIsarArchiveName $file.file $NativeIsarRepository $seen
        # Operational journals are excluded from the qualification source snapshot.
        if ($file.file -in @('specs/001-service-foundation/tasks.md','specs/001-service-foundation/quickstart.md')) { continue }
        Assert-NativeCompatibilityHash (Join-Path $NativeIsarRepository $file.file) $file.sha256
    }
    foreach ($file in $required) { if (-not $seen.Contains($file)) { throw 'Native review scope omits required activation sources.' } }
    if ((Get-NativeIsarDigest $Path) -cne $hash) { throw 'Native review changed while validating.' }
    return [pscustomobject]@{path=$Path;sha256=$hash;record=$review}
}

function Get-NativeArtifactQualifiedSelection {
    param([Parameter(Mandatory)][string]$QualificationReceipt)
    $QualificationReceipt=[IO.Path]::GetFullPath($QualificationReceipt,(Get-Location).ProviderPath)
    $root=[IO.Path]::GetDirectoryName($QualificationReceipt)
    if ([IO.Path]::GetDirectoryName($root) -cne (Join-Path $NativeIsarRepository '.local') -or
        [IO.Path]::GetFileName($root) -cnotmatch '^native-qualification-[a-f0-9]{32}$' -or
        [IO.Path]::GetFileName($QualificationReceipt) -cnotmatch '^qualification-receipt-[a-f0-9]{32}\.json$') { throw 'Native qualification receipt path invalid.' }
    $record=Read-NativeIsarArtifactJson $QualificationReceipt
    if ($record.schemaVersion -ne 1 -or $record.state -cne 'reviewed-compatibility-qualified' -or
        $record.distributionReady -isnot [bool] -or $record.distributionReady -ne $false -or
        $record.fullAcceptance -isnot [bool] -or $record.fullAcceptance -ne $false -or
        $record.approvalScope -cne 'native-build-compatibility-only' -or
        $record.compatibilityReceipt -cne ([IO.Path]::GetRelativePath($NativeIsarRepository,(Join-Path $root 'compatibility-receipt.json')).Replace('\','/')) -or
        $record.review -cnotmatch '^\.local/audits/t233-compatibility-clean-review-[a-f0-9]{32}\.json$') { throw 'Native qualification receipt identity invalid.' }
    $compatibilityPath=Join-Path $NativeIsarRepository $record.compatibilityReceipt
    $reviewPath=Join-Path $NativeIsarRepository $record.review
    Assert-NativeCompatibilityHash $compatibilityPath $record.compatibilityReceiptSha256
    Assert-NativeCompatibilityHash $reviewPath $record.reviewSha256
    $compatibility=Get-NativeArtifactCompatibility $compatibilityPath -RequireCurrentSource
    $review=Get-NativeArtifactReviewEvidence $reviewPath $compatibility
    if ($record.artifact -cne $compatibility.record.artifact -or $record.artifactManifestSha256 -cne $compatibility.record.artifactManifestSha256 -or
        $record.dllSha256 -cne $compatibility.record.dllSha256 -or $record.sourceSnapshotSha256 -cne $compatibility.record.sourceSnapshotSha256) { throw 'Native qualified input binding mismatch.' }
    return [pscustomobject]@{mode='reviewed-qualified-native';dll=$compatibility.artifact.dll;sha256=$record.dllSha256;
        artifact=$compatibility.artifact.directory;context=$null;qualificationReceipt=$QualificationReceipt;qualificationReceiptSha256=Get-NativeIsarDigest $QualificationReceipt}
}

function Get-NativeArtifactActiveSelection {
    $path=Join-Path $NativeIsarRepository '.local/native-isar/active.json'
    $pointer=Read-NativeIsarArtifactJson $path
    if ($pointer.schemaVersion -ne 1 -or $pointer.state -cne 'native-build-input-active' -or
        $pointer.distributionReady -isnot [bool] -or $pointer.distributionReady -ne $false -or
        $pointer.fullAcceptance -isnot [bool] -or $pointer.fullAcceptance -ne $false -or
        $pointer.qualificationReceipt -cnotmatch '^\.local/native-qualification-[a-f0-9]{32}/qualification-receipt-[a-f0-9]{32}\.json$') { throw 'Native active pointer invalid.' }
    $receipt=Join-Path $NativeIsarRepository $pointer.qualificationReceipt
    Assert-NativeCompatibilityHash $receipt $pointer.qualificationReceiptSha256
    return Get-NativeArtifactQualifiedSelection $receipt
}

function Invoke-NativeArtifactActivation {
    param([Parameter(Mandatory)][string]$CompatibilityReceipt,[Parameter(Mandatory)][string]$ReviewEvidence)
    if ($env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT) { throw 'Native activation cannot run inside a candidate scope.' }
    $compatibility=Get-NativeArtifactCompatibility $CompatibilityReceipt -RequireCurrentSource
    $review=Get-NativeArtifactReviewEvidence $ReviewEvidence $compatibility
    $root=[IO.Path]::GetDirectoryName($compatibility.receipt)
    $qualified=Join-Path $root ('qualification-receipt-' + [Guid]::NewGuid().ToString('N') + '.json')
    Write-NativeIsarJson $qualified ([ordered]@{schemaVersion=1;state='reviewed-compatibility-qualified';approvalScope='native-build-compatibility-only';distributionReady=$false;fullAcceptance=$false;
        compatibilityReceipt=[IO.Path]::GetRelativePath($NativeIsarRepository,$compatibility.receipt).Replace('\','/');compatibilityReceiptSha256=$compatibility.receiptSha256;
        review=[IO.Path]::GetRelativePath($NativeIsarRepository,$review.path).Replace('\','/');reviewSha256=$review.sha256;
        artifact=$compatibility.record.artifact;artifactManifestSha256=$compatibility.record.artifactManifestSha256;dllSha256=$compatibility.record.dllSha256;sourceSnapshotSha256=$compatibility.record.sourceSnapshotSha256})
    $selected=Get-NativeArtifactQualifiedSelection $qualified
    $active=Join-Path $NativeIsarRepository '.local/native-isar/active.json'
    Assert-NativeIsarPlainPath $active
    if (Test-Path -LiteralPath $active) {
        if (-not (Test-Path -LiteralPath $active -PathType Leaf) -or (Get-Item -LiteralPath $active).Length -gt 1MB) { throw 'Previous native active pointer is not a bounded regular file.' }
        $oldHash=Get-NativeIsarDigest $active
        $backup=Join-Path $root ('active-before-' + [Guid]::NewGuid().ToString('N') + '.json')
        Copy-Item -LiteralPath $active -Destination $backup
        Assert-NativeCompatibilityHash $backup $oldHash
    }
    $temporary=Join-Path ([IO.Path]::GetDirectoryName($active)) ('.active-' + [Guid]::NewGuid().ToString('N') + '.json')
    Write-NativeIsarJson $temporary ([ordered]@{schemaVersion=1;state='native-build-input-active';distributionReady=$false;fullAcceptance=$false;
        qualificationReceipt=[IO.Path]::GetRelativePath($NativeIsarRepository,$qualified).Replace('\','/');qualificationReceiptSha256=$selected.qualificationReceiptSha256})
    if ((Get-NativeArtifactSourceSnapshot).sha256 -cne $compatibility.record.sourceSnapshotSha256) { throw 'Native activation source changed before publication.' }
    $established=Join-Path $NativeIsarRepository '.local/native-isar-activation-established.json'
    Assert-NativeIsarPlainPath $established
    if (-not (Test-Path -LiteralPath $established)) {
        Write-NativeIsarJson $established ([ordered]@{schemaVersion=1;state='qualified-native-input-required';distributionReady=$false;firstQualificationReceipt=[IO.Path]::GetRelativePath($NativeIsarRepository,$qualified).Replace('\','/');firstQualificationReceiptSha256=$selected.qualificationReceiptSha256})
    }
    Assert-NativeIsarPlainPath $active
    [IO.File]::Move($temporary,$active,$true)
    return $selected
}
