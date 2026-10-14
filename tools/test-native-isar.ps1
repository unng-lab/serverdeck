[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/foundation-sdk.ps1"
. "$PSScriptRoot/native-artifact.ps1"
. "$PSScriptRoot/native-artifact-abi.ps1"
$candidate=Get-NativeIsarCandidateArtifact $Artifact
$initial=Get-NativeArtifactSourceSnapshot
$script:qualificationDirectory=''
$script:qualificationPhases=[Collections.Generic.List[object]]::new()
$script:currentQualificationPhase='setup'
function Invoke-NativeQualificationPhase {
    param([ValidateSet('abi','root-format','root-analyze','root-tests','serverdeck_protocol-analyze','serverdeck_protocol-tests','serverdeck_windows-analyze','serverdeck_windows-tests','serverdeck_locald-analyze','serverdeck_locald-tests','bundle-Debug','bundle-Release','available-native-ui','runtime-diagnostics')][string]$Name,[scriptblock]$Action)
    $script:currentQualificationPhase=$Name
    Write-NativeIsarJson (Join-Path $script:qualificationDirectory ('safe-phase-'+$Name+'.json')) ([ordered]@{
        schemaVersion=1;kind='native-qualification-phase';status='started';phase=$Name
        sourceSnapshotSha256=$initial.sha256;artifactManifestSha256=$candidate.manifestSha256
        fullAcceptance=$false;distributionReady=$false;activated=$false
    })
    $log=Join-Path $script:qualificationDirectory ($Name + '.txt')
    Write-Output "START native-qualification-$Name"
    $watch=[Diagnostics.Stopwatch]::StartNew()
    & $Action *> $log
    $script:qualificationPhases.Add([ordered]@{name=$Name;passed=$true;elapsedSeconds=[Math]::Round($watch.Elapsed.TotalSeconds,1);log=[IO.Path]::GetFileName($log);logSha256=Get-NativeIsarDigest $log})
    Write-Output "PASS native-qualification-$Name"
}
try {
    Invoke-NativeArtifactCandidateScope $candidate.directory -PreserveNormalBundles -Action {
        $selection=Get-NativeArtifactBuildSelection
        $script:qualificationDirectory=[IO.Path]::GetDirectoryName($selection.context)
        Write-Output "NATIVE_QUALIFICATION_DIRECTORY=$script:qualificationDirectory"
        Write-NativeIsarJson (Join-Path $script:qualificationDirectory 'source-snapshot.json') $initial
        Push-Location $NativeIsarRepository
        try {
            Invoke-NativeQualificationPhase 'abi' {
                $abi=Get-NativeArtifactAbiEvidence $candidate.directory
                Write-NativeIsarJson (Join-Path $script:qualificationDirectory 'abi.json') $abi
                'NATIVE_ABI_PE64_93_EXPORTS_AND_PINNED_VERSIONS_PASSED'
            }
            Invoke-NativeQualificationPhase 'root-format' { Invoke-FoundationCommand $FoundationDart @('format','--output=none','--set-exit-if-changed','.') }
            Invoke-NativeQualificationPhase 'root-analyze' { Invoke-FoundationCommand $FoundationFlutter @('analyze') }
            Invoke-NativeQualificationPhase 'root-tests' { Invoke-FoundationCommand $FoundationFlutter @('test') }
            foreach ($package in @('serverdeck_protocol','serverdeck_windows','serverdeck_locald')) {
                Push-Location (Join-Path $NativeIsarRepository ('packages/' + $package))
                try {
                    Invoke-NativeQualificationPhase ($package + '-analyze') { Invoke-FoundationCommand $FoundationDart @('analyze') }
                    Invoke-NativeQualificationPhase ($package + '-tests') { Invoke-FoundationCommand $FoundationDart @('test') }
                } finally { Pop-Location }
            }
            $bundles=[Collections.Generic.List[object]]::new()
            foreach ($configuration in @('Debug','Release')) {
                Invoke-NativeQualificationPhase ('bundle-' + $configuration) {
                    & "$PSScriptRoot/run-foundation.ps1" -Configuration $configuration -BuildOnly
                    $bundle=Join-Path $NativeIsarRepository ('build/windows/x64/runner/' + $configuration)
                    $manifest=Read-NativeIsarArtifactJson (Join-Path $bundle 'foundation.manifest.json')
                    if ($manifest.testOnly -ne $false -or $manifest.configuration -cne $configuration -or
                        $manifest.sha256.'libisar.dll' -cne $selection.sha256) { throw 'Qualification normal bundle manifest mismatch.' }
                    foreach ($name in @('serverdeck.exe','locald.exe','libisar.dll')) {
                        if ((Get-NativeIsarDigest (Join-Path $bundle $name)) -cne $manifest.sha256.$name) { throw 'Qualification bundle binary hash mismatch.' }
                    }
                    $retained=Join-Path $script:qualificationDirectory ('normal-bundles/' + $configuration)
                    $bundleSnapshot=Get-NativeArtifactBundleSnapshot $bundle
                    Assert-NativeIsarPlainPath $retained
                    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($retained)) | Out-Null
                    Copy-Item -LiteralPath $bundle -Destination $retained -Recurse
                    if ((Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $retained)) -cne
                        (Get-NativeIsarSnapshotDigest $bundleSnapshot)) { throw 'Qualification normal bundle copy mismatch.' }
                    $manifest.appRoot=$retained
                    [IO.File]::WriteAllText((Join-Path $retained 'foundation.manifest.json'),($manifest|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
                    $notices=Join-Path $retained 'notices'
                    $noticeSnapshot=Get-NativeArtifactBundleSnapshot $notices
                    $inventory=Read-NativeIsarArtifactJson (Join-Path $notices 'third-party-notices.json')
                    if ($noticeSnapshot.Count -ne 199 -or $inventory.native.dllSha256 -cne $selection.sha256 -or
                        $inventory.native.artifactManifestSha256 -cne $candidate.manifestSha256 -or $inventory.distributionReady -ne $false) { throw 'Qualification normal notices mismatch.' }
                    $bundles.Add([ordered]@{configuration=$configuration;directory='normal-bundles/' + $configuration;treeSha256=Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $retained);noticeTreeSha256=Get-NativeIsarSnapshotDigest $noticeSnapshot})
                }
            }
            if ($bundles[0].noticeTreeSha256 -cne $bundles[1].noticeTreeSha256) { throw 'Qualification Debug/Release notice trees differ.' }
            Write-NativeIsarJson (Join-Path $script:qualificationDirectory 'normal-bundles.json') @($bundles.ToArray())
            Invoke-NativeQualificationPhase 'available-native-ui' { & "$PSScriptRoot/test-foundation-available.ps1" }
            $availableLog=Join-Path $script:qualificationDirectory 'available-native-ui.txt'
            $resultLines=@(Get-Content -LiteralPath $availableLog | Where-Object { $_ -cmatch '^AVAILABLE_ACCEPTANCE_RESULT=' })
            if ($resultLines.Count -ne 1) { throw 'Qualification available suite result reference missing.' }
            $availablePath=[IO.Path]::GetFullPath($resultLines[0].Substring('AVAILABLE_ACCEPTANCE_RESULT='.Length))
            $availableRoot=[IO.Path]::GetDirectoryName($availablePath)
            if ([IO.Path]::GetDirectoryName($availableRoot) -cne (Join-Path $NativeIsarRepository '.local') -or
                [IO.Path]::GetFileName($availableRoot) -cnotmatch '^available-acceptance-[a-f0-9]{32}$' -or
                [IO.Path]::GetFileName($availablePath) -cne 'result.json') { throw 'Qualification available result is outside owned evidence.' }
            $available=Read-NativeIsarArtifactJson $availablePath
            $required=@(& "$PSScriptRoot/test-foundation-available.ps1" -ListOnly)
            if ($available.status -cne 'passed' -or $available.requiredPhaseCount -ne 14 -or $available.completed.Count -ne 14 -or
                $available.fullAcceptance -ne $false -or $required.Count -ne 14) { throw 'Qualification available phases incomplete.' }
            $availableEvidence=[Collections.Generic.List[object]]::new()
            $availableEvidence.Add([ordered]@{file=[IO.Path]::GetRelativePath($NativeIsarRepository,$availablePath).Replace('\','/');sha256=Get-NativeIsarDigest $availablePath})
            for ($index=0;$index -lt $required.Count;$index++) {
                if ($available.completed[$index].name -cne $required[$index] -or $available.completed[$index].completed -ne $true) { throw 'Qualification phase order mismatch.' }
                $phaseLog=Join-Path $availableRoot ($required[$index] + '.txt')
                $availableEvidence.Add([ordered]@{file=[IO.Path]::GetRelativePath($NativeIsarRepository,$phaseLog).Replace('\','/');sha256=Get-NativeIsarDigest $phaseLog})
            }
            Invoke-NativeQualificationPhase 'runtime-diagnostics' { & "$PSScriptRoot/test-foundation-runtime-diagnostics.ps1" }
            if (@(Get-Content -LiteralPath (Join-Path $script:qualificationDirectory 'runtime-diagnostics.txt') | Where-Object {$_ -ceq 'COMPILED_UI_RUNTIME_DIAGNOSTICS_ACCEPTANCE_PASSED'}).Count -ne 1) { throw 'Qualification diagnostics marker missing.' }
            if ((Get-NativeArtifactSourceSnapshot).sha256 -cne $initial.sha256 -or (Get-NativeIsarCandidateArtifact $candidate.directory).manifestSha256 -cne $candidate.manifestSha256) { throw 'Qualification inputs changed.' }
            $initialAbi=Read-NativeIsarArtifactJson (Join-Path $script:qualificationDirectory 'abi.json')
            if ((Get-NativeIsarCanonicalDigest (Get-NativeArtifactAbiEvidence $candidate.directory)) -cne (Get-NativeIsarCanonicalDigest $initialAbi)) { throw 'Qualification ABI binding inputs changed.' }
            Write-NativeIsarJson (Join-Path $script:qualificationDirectory 'compatibility-inputs.json') ([ordered]@{schemaVersion=1;artifactManifestSha256=$candidate.manifestSha256;dllSha256=$selection.sha256;sourceSnapshotSha256=$initial.sha256;phases=@($script:qualificationPhases.ToArray());availableEvidence=@($availableEvidence.ToArray());excluded=$available.excluded})
        } finally { Pop-Location }
    }
    $context=Read-NativeIsarArtifactJson (Join-Path $script:qualificationDirectory 'context.json')
    $preservation=Read-NativeIsarArtifactJson (Join-Path $script:qualificationDirectory 'bundle-preservation.json')
    if ($context.state -cne 'candidate-validation-finished' -or @($preservation).Count -ne 2 -or
        @($preservation | Where-Object restored -NE $true).Count -ne 0 -or $script:qualificationPhases.Count -ne 14) { throw 'Qualification scope did not restore normal outputs or complete phases.' }
    foreach ($record in $preservation) {
        if ($record.existed -and (Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $record.normal)) -cne $record.sha256) { throw 'Qualification restored normal output mismatch.' }
    }
    if ((Get-NativeArtifactSourceSnapshot).sha256 -cne $initial.sha256) { throw 'Qualification source changed after scope.' }
    $evidenceNames=@('source-snapshot.json','abi.json','normal-bundles.json','compatibility-inputs.json','context.json','bundle-preservation.json')
    $receipt=[ordered]@{schemaVersion=1;product='serverdeck-isar-native';state='compatibility-passed-unreviewed';distributionReady=$false;fullAcceptance=$false;activated=$false;artifact=[IO.Path]::GetRelativePath($NativeIsarRepository,$candidate.directory).Replace('\','/');artifactManifestSha256=$candidate.manifestSha256;dllSha256=Get-NativeIsarDigest $candidate.dll;sourceSnapshotSha256=$initial.sha256;
        evidence=@($evidenceNames | ForEach-Object {[ordered]@{file=$_;sha256=Get-NativeIsarDigest (Join-Path $script:qualificationDirectory $_)}})}
    Write-NativeIsarJson (Join-Path $script:qualificationDirectory 'compatibility-receipt.json') $receipt
    'NATIVE_CANDIDATE_CURRENT_COMPATIBILITY_AND_NORMAL_OUTPUT_RESTORATION_PASSED_REVIEW_REQUIRED'
    $script:qualificationDirectory
} catch {
    if ($script:qualificationDirectory) {
        Write-NativeIsarJson (Join-Path $script:qualificationDirectory ('failure-' + [Guid]::NewGuid().ToString('N') + '.json')) ([ordered]@{schemaVersion=1;state='compatibility-failed';distributionReady=$false;failedPhase=$script:currentQualificationPhase;completed=@($script:qualificationPhases.ToArray())})
    }
    throw
}
# No activation, publication, cleanup, CI/manual inference or denied-operation retry.
