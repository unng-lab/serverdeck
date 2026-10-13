[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Prepare','Baseline','VerifyReboot')][string]$Phase,
    [string]$Artifact,
    [string]$Fixture,
    [switch]$DisposableEnvironment, [switch]$ForeignUserTarget
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/foundation-sdk.ps1"
. "$PSScriptRoot/native-artifact.ps1"
. "$PSScriptRoot/native-probe-process.ps1"
. "$PSScriptRoot/environment-acceptance-claim.ps1"
. "$PSScriptRoot/foundation-user-ui.ps1"

. "$PSScriptRoot/foundation-environment-facts.ps1"

function Assert-EnvironmentFixture([string]$Path) {
    $resolved=[IO.Path]::GetFullPath($Path,(Get-Location).ProviderPath)
    if ([IO.Path]::GetDirectoryName($resolved) -cne (Join-Path $FoundationRoot '.local') -or
        [IO.Path]::GetFileName($resolved) -cnotmatch '^environment-acceptance-[a-f0-9]{32}$' -or
        ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($resolved))).DriveType -ne [IO.DriveType]::Fixed) {
        throw 'Owned fixed-drive environment fixture required.'
    }
    Assert-NativeIsarPlainPath $resolved
    return $resolved
}

function Invoke-EnvironmentActor([string]$Mode,[string]$Marker) {
    $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $script:root 'checkpoint-actor.exe'))
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $start.WorkingDirectory=$script:root
    foreach($argument in @($script:root,(Join-Path $script:root 'application bundle'),$Mode)) { $start.ArgumentList.Add($argument) }
    $child=[Diagnostics.Process]::new()
    $child.StartInfo=$start
    $started=$false
    try {
        if (-not $child.Start()) { throw 'Environment actor start failed.' }
        $started=$true
        $held=$child.Handle
        $output=$child.StandardOutput.ReadToEndAsync()
        $errors=$child.StandardError.ReadToEndAsync()
        if (-not $child.WaitForExit(180000)) { throw 'Environment actor deadline exceeded.' }
        $text=$output.GetAwaiter().GetResult()
        $errorText=$errors.GetAwaiter().GetResult()
        $lines=@($text.Trim() -split '\r?\n')
        if ($child.ExitCode -ne 0 -or $errorText.Length -ne 0 -or $lines.Count -ne 2 -or
            $lines[0] -cne 'IsarCore using libmdbx: v0.13.8-temp-upstream-fix' -or $lines[1] -cne $Marker) {
            throw 'Environment actor proof failed; retained fixture requires inspection.'
        }
    } finally { Close-NativeFixtureChild $child $started }
}

function Get-DurableInventory {
    $directory=Join-Path $script:root 'profile/ServerDeckNext/v1/workspaces/default'
    $expected=@('receipt-key.dpapi','workspace.isar','workspace.isar-lck','workspace.manifest.json')
    $files=@(Get-ChildItem -LiteralPath $directory -Force | Sort-Object Name)
    if ($files.Count -ne 4 -or @($files | Where-Object PSIsContainer).Count -ne 0 -or
        (Compare-Object $expected @($files.Name))) { throw 'Durable fixture inventory mismatch.' }
    return @($files | ForEach-Object { [ordered]@{file=$_.Name;sha256=Get-NativeIsarDigest $_.FullName} })
}

if ($ForeignUserTarget -and $Phase -ne 'Prepare') { throw 'Foreign target is selected only during preparation.' }
if (-not $DisposableEnvironment) { throw 'Use only an explicitly prepared disposable Windows 11 user/environment. No OS changes are automated.' }
if ($Phase -eq 'Prepare') {
    if (-not $Artifact -or $Fixture) { throw 'Prepare requires Artifact and creates a fresh fixture.' }
    $facts=Get-EnvironmentFacts
    $script:root=Assert-EnvironmentFixture (Join-Path $FoundationRoot ('.local/environment-acceptance-'+[Guid]::NewGuid().ToString('N')))
    if (Test-Path -LiteralPath $script:root) { throw 'Fixture already exists.' }
    [void][IO.Directory]::CreateDirectory($script:root)
    Invoke-NativeArtifactCandidateScope $Artifact -PreserveNormalBundles -Action {
        & "$PSScriptRoot/run-foundation.ps1" -Configuration Debug -BuildOnly -ForeignUserAcceptance:$ForeignUserTarget
        $bundle=Join-Path $script:root 'application bundle'
        Copy-Item -LiteralPath (Join-Path $FoundationRoot 'build/windows/x64/runner/Debug') -Destination $bundle -Recurse
        $manifestPath=Join-Path $bundle 'foundation.manifest.json'
        $manifest=Read-NativeIsarArtifactJson $manifestPath
        if ($manifest.testOnly -ne $false) { throw 'Normal production bundle required.' }
        $manifest.appRoot=$bundle
        [IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
        Push-Location (Join-Path $FoundationRoot 'packages/serverdeck_locald')
        try {
            Invoke-FoundationCommand $FoundationDart @('compile','exe','test/support/environment_checkpoint_child.dart','-o',(Join-Path $script:root 'checkpoint-actor.exe'))
        } finally { Pop-Location }
    }
    Invoke-EnvironmentActor 'seed' 'ENVIRONMENT_DURABLE_CHECKPOINT_CREATED'
    if ($ForeignUserTarget) {
        Invoke-FoundationUserUi -Fixture $script:root -Role owner -OwnerSid $facts.sid -OutputRoot $script:root
        Invoke-EnvironmentActor 'verify' 'ENVIRONMENT_DURABLE_STATE_AND_CREDENTIAL_VERIFIED'
    }
    $source=Get-NativeArtifactSourceSnapshot
    $snapshot=Get-NativeArtifactBundleSnapshot (Join-Path $script:root 'application bundle')
    Write-NativeIsarJson (Join-Path $script:root 'environment-checkpoint.json') ([ordered]@{
        schemaVersion=1;kind='owned-environment-checkpoint';fixture=$script:root;facts=$facts;
        sourceSnapshotSha256=$source.sha256;bundleTreeSha256=Get-NativeIsarSnapshotDigest $snapshot;
        actorSha256=Get-NativeIsarDigest (Join-Path $script:root 'checkpoint-actor.exe');
        durableCheckpointSha256=Get-NativeIsarDigest (Join-Path $script:root 'profile/durable-checkpoint.json');
        files=Get-DurableInventory;foreignUserTarget=[bool]$ForeignUserTarget;fullAcceptance=$false;distributionReady=$false
    })
    'ENVIRONMENT_CHECKPOINT_PREPARED_REBOOT_UNPROVEN'
    $script:root
    return
}
if (-not $Fixture -or $Artifact) { throw 'Verification requires existing Fixture, without Artifact.' }
$script:root=Assert-EnvironmentFixture $Fixture
$checkpoint=Read-NativeIsarArtifactJson (Join-Path $script:root 'environment-checkpoint.json')
$facts=Get-EnvironmentFacts
if ($checkpoint.schemaVersion -ne 1 -or $checkpoint.kind -cne 'owned-environment-checkpoint' -or
    $checkpoint.fixture -cne $script:root -or $checkpoint.fullAcceptance -ne $false -or $checkpoint.distributionReady -ne $false -or
    $checkpoint.facts.sid -cne $facts.sid -or $checkpoint.facts.machineUuid -cne $facts.machineUuid -or
    $checkpoint.sourceSnapshotSha256 -cne (Get-NativeArtifactSourceSnapshot).sha256 -or
    $checkpoint.actorSha256 -cne (Get-NativeIsarDigest (Join-Path $script:root 'checkpoint-actor.exe')) -or
    $checkpoint.bundleTreeSha256 -cne (Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot (Join-Path $script:root 'application bundle'))) -or
    $checkpoint.durableCheckpointSha256 -cne (Get-NativeIsarDigest (Join-Path $script:root 'profile/durable-checkpoint.json'))) {
    throw 'Checkpoint identity, source or binary binding mismatch.'
}
if ($Phase -eq 'VerifyReboot' -and $checkpoint.facts.bootUtcTicks -ceq $facts.bootUtcTicks) {
    'ENVIRONMENT_REBOOT_UNPROVEN_SAME_OS_BOOT'
    exit 2
}
# Compare all closed native bytes before opening them; reopening can update the
# native lock file. Subsequent phases cannot silently reuse this checkpoint.
if (($checkpoint.files | ConvertTo-Json -Depth 4 -Compress) -cne ((Get-DurableInventory) | ConvertTo-Json -Depth 4 -Compress)) {
    throw 'Original closed workspace bytes changed before verification.'
}
$result=Join-Path $script:root ($Phase+'.result.json')
if (Test-Path -LiteralPath $result) { throw 'Verification phase already used.' }
New-EnvironmentAcceptanceClaim -Fixture $script:root -Phase $Phase -CheckpointSha256 (Get-NativeIsarDigest (Join-Path $script:root 'environment-checkpoint.json'))
Invoke-EnvironmentActor 'verify' 'ENVIRONMENT_DURABLE_STATE_AND_CREDENTIAL_VERIFIED'
Write-NativeIsarJson $result ([ordered]@{schemaVersion=1;phase=$Phase;status='passed';facts=$facts;checkpointSha256=Get-NativeIsarDigest (Join-Path $script:root 'environment-checkpoint.json');fullAcceptance=$false;distributionReady=$false;scope='direct-production-workspace-and-dpapi-only';excluded=@('normal-client-ui','foreign-user','runtime-offline','physical-Q12')})
if ($Phase -eq 'VerifyReboot') { 'ENVIRONMENT_REAL_REBOOT_DURABLE_RECOVERY_PASSED' } else { 'ENVIRONMENT_OWNER_BASELINE_PASSED_REBOOT_UNPROVEN' }
# Failed fixtures are retained. No reboot, account/firewall changes or cleanup.
