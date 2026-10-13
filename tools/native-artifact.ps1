. "$PSScriptRoot/native-isar-artifact-inputs.ps1"
. "$PSScriptRoot/native-artifact-source-snapshot.ps1"
. "$PSScriptRoot/native-artifact-compatibility.ps1"
. "$PSScriptRoot/native-artifact-activation.ps1"

function Get-NativeArtifactBuildSelection {
    $contextPath=$env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT
    if ($contextPath) {
        $contextPath=[IO.Path]::GetFullPath($contextPath,(Get-Location).ProviderPath)
        $root=[IO.Path]::GetDirectoryName($contextPath)
        if ([IO.Path]::GetDirectoryName($root) -cne (Join-Path $NativeIsarRepository '.local') -or
            [IO.Path]::GetFileName($root) -cnotmatch '^native-qualification-[a-f0-9]{32}$' -or
            [IO.Path]::GetFileName($contextPath) -cne 'context.json') { throw 'Invalid native qualification context path.' }
        $context=Read-NativeIsarArtifactJson $contextPath
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        try { $sid=$identity.User.Value } finally { $identity.Dispose() }
        if ($context.schemaVersion -ne 1 -or $context.state -cne 'candidate-validation-running' -or
            $context.distributionReady -isnot [bool] -or $context.distributionReady -ne $false -or $context.preserveNormalBundles -isnot [bool] -or
            $context.ownerSid -cne $sid -or ($context.processId -isnot [int] -and $context.processId -isnot [long]) -or
            $context.processId -le 0 -or $context.processId -gt [int]::MaxValue -or $context.processStartTicks -isnot [long]) { throw 'Invalid native qualification context identity.' }
        try { $process=Get-Process -Id $context.processId -ErrorAction Stop } catch { throw 'Native qualification process is not running.' }
        if ($process.StartTime.ToUniversalTime().Ticks -ne $context.processStartTicks) { throw 'Native qualification process identity changed.' }
        if ($context.artifact -cnotmatch '^\.local/native-isar/candidate-[a-f0-9]{32}/artifact-[a-f0-9]{32}$') { throw 'Invalid native qualification artifact reference.' }
        $artifact=Get-NativeIsarCandidateArtifact (Join-Path $NativeIsarRepository $context.artifact)
        $dllHash=Get-NativeIsarDigest $artifact.dll
        if ($artifact.manifestSha256 -cne $context.artifactManifestSha256 -or $dllHash -cne $context.dllSha256 -or
            (Get-NativeArtifactSourceSnapshot).sha256 -cne $context.sourceSnapshotSha256) { throw 'Native qualification inputs changed.' }
        return [pscustomobject]@{mode='explicit-unqualified-candidate';dll=$artifact.dll;sha256=$dllHash;artifact=$artifact.directory;context=$contextPath;preserveNormalBundles=$context.preserveNormalBundles}
    }
    if (Test-Path -LiteralPath (Join-Path $NativeIsarRepository '.local/native-isar/active.json')) { return Get-NativeArtifactActiveSelection }
    if (Test-Path -LiteralPath (Join-Path $NativeIsarRepository '.local/native-isar-activation-established.json')) { throw 'Previously activated native input is missing; historical cache fallback is forbidden.' }
    $configPath=Join-Path $NativeIsarRepository '.dart_tool/package_config.json'
    Assert-NativeIsarPlainPath $configPath
    $config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $packages=@($config.packages | Where-Object name -CEQ 'isar_community_flutter_libs')
    if ($packages.Count -ne 1) { throw 'Pinned Isar native package missing.' }
    $configUri=[Uri]::new($configPath)
    $packageUri=[Uri]::new($configUri,$packages[0].rootUri)
    if (-not $packageUri.IsFile) { throw 'Expected local native package.' }
    $dll=Join-Path $packageUri.LocalPath 'windows/libisar.dll'
    return [pscustomobject]@{mode='historical-private-development-cache';dll=$dll;sha256=Get-NativeIsarDigest $dll;context=$null}
}

function Copy-NativeArtifactLibrary {
    param([Parameter(Mandatory)][object]$Selection,[Parameter(Mandatory)][string]$Bundle)
    $Bundle=[IO.Path]::GetFullPath($Bundle,(Get-Location).ProviderPath)
    if (-not $Bundle.StartsWith($NativeIsarRepository + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Native library destination must remain inside the workspace.' }
    Assert-NativeIsarPlainPath $Bundle
    if (-not (Test-Path -LiteralPath $Bundle -PathType Container)) { throw 'Native library bundle directory missing.' }
    $destination=Join-Path $Bundle 'libisar.dll'
    Assert-NativeIsarPlainPath $destination
    $source=[IO.Path]::GetFullPath($Selection.dll)
    Assert-NativeIsarPlainPath $source
    if ($source.Equals($destination,[StringComparison]::OrdinalIgnoreCase)) { throw 'Native library source and destination must differ.' }
    Assert-NativeCompatibilityHash $source $Selection.sha256
    $temporary=Join-Path $Bundle ('.native-library-' + [Guid]::NewGuid().ToString('N') + '.dll')
    $inputStream=$null
    $outputStream=$null
    try {
        $inputStream=[IO.FileStream]::new($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $outputStream=[IO.FileStream]::new($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,65536,[IO.FileOptions]::WriteThrough)
        $inputStream.CopyTo($outputStream)
        $outputStream.Flush($true)
    } finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $inputStream) { $inputStream.Dispose() }
    }
    # Failed copies remain beside the bundle for diagnosis; never publish them.
    Assert-NativeCompatibilityHash $temporary $Selection.sha256
    Assert-NativeCompatibilityHash $source $Selection.sha256
    [IO.File]::Move($temporary,$destination,$true)
    Assert-NativeCompatibilityHash $destination $Selection.sha256
}

function Invoke-NativeArtifactCandidateScope {
    param([Parameter(Mandatory)][string]$Artifact,[Parameter(Mandatory)][scriptblock]$Action,[switch]$PreserveNormalBundles)
    if ($env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT) { throw 'Native candidate scope already selected.' }
    $selection=Get-NativeIsarCandidateArtifact $Artifact
    $snapshot=Get-NativeArtifactSourceSnapshot
    $root=Join-Path $NativeIsarRepository ('.local/native-qualification-' + [Guid]::NewGuid().ToString('N'))
    Assert-NativeIsarPlainPath $root
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $path=Join-Path $root 'context.json'
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try { $sid=$identity.User.Value } finally { $identity.Dispose() }
    $process=Get-Process -Id $PID
    $context=[ordered]@{schemaVersion=1;state='candidate-validation-running';distributionReady=$false;preserveNormalBundles=[bool]$PreserveNormalBundles;ownerSid=$sid;processId=$PID;
        processStartTicks=$process.StartTime.ToUniversalTime().Ticks;artifact=[IO.Path]::GetRelativePath($NativeIsarRepository,$selection.directory).Replace('\','/');
        artifactManifestSha256=$selection.manifestSha256;dllSha256=Get-NativeIsarDigest $selection.dll;sourceSnapshotSha256=$snapshot.sha256}
    Write-NativeIsarJson $path $context
    $prior=$env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT
    $backups=[Collections.Generic.List[object]]::new()
    try {
        if ($PreserveNormalBundles) {
            foreach ($configuration in @('Debug','Release')) {
                $normal=Join-Path $NativeIsarRepository ('build/windows/x64/runner/' + $configuration)
                $backup=Join-Path $root ('normal-bundle-backups/' + $configuration)
                Assert-NativeIsarPlainPath $normal
                Assert-NativeIsarPlainPath $backup
                $record=[ordered]@{configuration=$configuration;normal=$normal;backup=$backup;existed=Test-Path -LiteralPath $normal;sha256=$null;captured=$null;restored=$false}
                if ($record.existed) {
                    $record.sha256=Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $normal)
                    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup)) | Out-Null
                    Move-Item -LiteralPath $normal -Destination $backup
                }
                $backups.Add($record)
            }
        }
        $env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT=$path
        & $Action
        if ((Get-NativeArtifactSourceSnapshot).sha256 -cne $snapshot.sha256 -or
            (Get-NativeIsarCandidateArtifact $selection.directory).manifestSha256 -cne $selection.manifestSha256) { throw 'Native candidate scope inputs changed.' }
        $context.state='candidate-validation-finished'
    } catch { $context.state='candidate-validation-failed';throw } finally {
        $env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT=$prior
        $restorationError=$null
        foreach ($record in $backups) {
            try {
                if (Test-Path -LiteralPath $record.normal) {
                    $captured=Join-Path $root ('candidate-bundles/' + $record.configuration)
                    Assert-NativeIsarPlainPath $record.normal
                    Assert-NativeIsarPlainPath $captured
                    if (Test-Path -LiteralPath $captured) { throw 'Candidate bundle capture already exists.' }
                    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($captured)) | Out-Null
                    Move-Item -LiteralPath $record.normal -Destination $captured
                    $record.captured=$captured
                    $manifestPath=Join-Path $captured 'foundation.manifest.json'
                    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
                        $manifest=Read-NativeIsarArtifactJson $manifestPath
                        $manifest.appRoot=$captured
                        [IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
                    }
                }
            } catch { $context.state='candidate-validation-failed';$restorationError=$_ }
            try {
                if ($record.existed) {
                    Assert-NativeIsarPlainPath $record.backup
                    Assert-NativeIsarPlainPath $record.normal
                    if (Test-Path -LiteralPath $record.normal) { throw 'Normal bundle output remains occupied; original backup preserved.' }
                    Move-Item -LiteralPath $record.backup -Destination $record.normal
                    if ((Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $record.normal)) -cne $record.sha256) { throw 'Normal native bundle restoration mismatch.' }
                }
                $record.restored=$true
            } catch { $context.state='candidate-validation-failed';$restorationError=$_ }
        }
        if ($PreserveNormalBundles) { Write-NativeIsarJson (Join-Path $root 'bundle-preservation.json') @($backups.ToArray()) }
        # Context is operational state, unlike the immutable artifact inputs.
        # Write a fresh sibling then atomically replace only our owned record.
        $temporary=Join-Path $root ('context-' + [Guid]::NewGuid().ToString('N') + '.json')
        Write-NativeIsarJson $temporary $context
        Assert-NativeIsarPlainPath $path
        [IO.File]::Move($temporary,$path,$true)
        if ($restorationError) { throw $restorationError }
    }
}

function Copy-NativeArtifactBundleNotices {
    param([Parameter(Mandatory)][string]$Bundle)
    $selection=Get-NativeArtifactBuildSelection
    if ($selection.mode -ceq 'historical-private-development-cache') { return }
    if ($selection.mode -cne 'reviewed-qualified-native' -and
        ($selection.mode -cne 'explicit-unqualified-candidate' -or -not $selection.preserveNormalBundles)) { throw 'Candidate notices require a preserved candidate scope.' }
    $Bundle=[IO.Path]::GetFullPath($Bundle,(Get-Location).ProviderPath)
    $prefix=$NativeIsarRepository + [IO.Path]::DirectorySeparatorChar
    $nativeRoot=Join-Path $NativeIsarRepository '.local/native-isar'
    $nativePrefix=$nativeRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $Bundle.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or
        $Bundle.Equals($nativeRoot,[StringComparison]::OrdinalIgnoreCase) -or
        $Bundle.StartsWith($nativePrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Candidate notice bundle must remain outside native inputs in the workspace.' }
    Assert-NativeIsarPlainPath $Bundle
    if (-not (Test-Path -LiteralPath $Bundle -PathType Container) -or
        (Get-NativeIsarDigest (Join-Path $Bundle 'libisar.dll')) -cne $selection.sha256) { throw 'Candidate notice bundle DLL mismatch.' }
    if ($selection.mode -ceq 'reviewed-qualified-native') {
        $contextRoot=Join-Path $NativeIsarRepository ('.local/native-bundle-notices-' + [Guid]::NewGuid().ToString('N'))
        Assert-NativeIsarPlainPath $contextRoot
        [IO.Directory]::CreateDirectory($contextRoot) | Out-Null
    } else { $contextRoot=[IO.Path]::GetDirectoryName($selection.context) }
    $source=Join-Path $contextRoot ('notices-' + [Guid]::NewGuid().ToString('N'))
    & "$PSScriptRoot/collect-third-party-notices.ps1" -NativeArtifact $selection.artifact -OutputDirectory $source | Out-Null
    $snapshot=Get-NativeArtifactBundleSnapshot $source
    if ($snapshot.Count -ne 199) { throw 'Candidate notice output inventory mismatch.' }
    $destination=Join-Path $Bundle 'notices'
    Assert-NativeIsarPlainPath $destination
    $predecessor=$null
    $predecessorSha256=$null
    if (Test-Path -LiteralPath $destination) {
        if (-not (Test-Path -LiteralPath $destination -PathType Container)) { throw 'Candidate notices destination is not a directory.' }
        $predecessorSha256=Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $destination)
        $predecessor=Join-Path $contextRoot ('notices-predecessor-' + [Guid]::NewGuid().ToString('N'))
        Assert-NativeIsarPlainPath $predecessor
        Move-Item -LiteralPath $destination -Destination $predecessor
        if ((Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $predecessor)) -cne $predecessorSha256) { throw 'Previous candidate notices preservation mismatch.' }
    }
    Copy-Item -LiteralPath $source -Destination $destination -Recurse
    $digest=Get-NativeIsarSnapshotDigest $snapshot
    if ((Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $destination)) -cne $digest -or
        (Get-NativeIsarDigest (Join-Path $Bundle 'libisar.dll')) -cne $selection.sha256 -or
        (Get-NativeArtifactBuildSelection).sha256 -cne $selection.sha256) { throw 'Attached candidate notice bundle mismatch.' }
    $attachmentState=if ($selection.mode -ceq 'reviewed-qualified-native') { 'qualified-notices-attached' } else { 'candidate-notices-attached' }
    Write-NativeIsarJson (Join-Path $contextRoot ('notice-attachment-' + [Guid]::NewGuid().ToString('N') + '.json')) ([ordered]@{
        schemaVersion=1;state=$attachmentState;distributionReady=$false;dllSha256=$selection.sha256;
        source=[IO.Path]::GetRelativePath($NativeIsarRepository,$source).Replace('\','/');
        destination=[IO.Path]::GetRelativePath($NativeIsarRepository,$destination).Replace('\','/');
        noticeTreeSha256=$digest;predecessor=$predecessor;predecessorSha256=$predecessorSha256
    })
}
