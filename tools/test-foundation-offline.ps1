[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Prepare','Verify')][string]$Phase,[string]$Artifact,[string]$Fixture,[switch]$DisposableEnvironment)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/foundation-sdk.ps1"
. "$PSScriptRoot/native-artifact.ps1"
. "$PSScriptRoot/foundation-offline-facts.ps1"
. "$PSScriptRoot/foundation-environment-facts.ps1"
if (-not $DisposableEnvironment) { throw 'Prepared disposable Windows11 environment required; networking is configured externally.' }
$facts=Get-EnvironmentFacts
if ($Phase -eq 'Prepare') {
    if (-not $Artifact -or $Fixture) { throw 'Prepare requires a complete artifact and creates its own fixture.' }
    Invoke-NativeArtifactCandidateScope $Artifact -PreserveNormalBundles -Action {
        & "$PSScriptRoot/test-foundation-owner-ui.ps1" -PrepareOnly | ForEach-Object {
            if ($_ -is [string] -and $_ -cmatch '^OWNER_UI_PREPARED_FIXTURE=') {
                $prepared=$_.Substring('OWNER_UI_PREPARED_FIXTURE='.Length)
                Write-NativeIsarJson (Join-Path $prepared 'offline-prepared.json') ([ordered]@{schemaVersion=1;facts=$facts;fullAcceptance=$false})
            }
            Write-Output $_
        }
    }
    return
}
if (-not $Fixture -or $Artifact) { throw 'Verify requires the printed prepared fixture only.' }
$root=[IO.Path]::GetFullPath($Fixture,(Get-Location).ProviderPath)
if ([IO.Path]::GetDirectoryName($root) -cne (Join-Path $FoundationRoot '.local') -or
    [IO.Path]::GetFileName($root) -cnotmatch '^foundation-ui-[a-f0-9]{32}$') { throw 'Owned offline fixture required.' }
Assert-NativeIsarPlainPath $root
$prepared=Read-NativeIsarArtifactJson (Join-Path $root 'offline-prepared.json')
if ($prepared.schemaVersion -ne 1 -or $prepared.fullAcceptance -ne $false -or
    $prepared.facts.sid -cne $facts.sid -or $prepared.facts.machineUuid -cne $facts.machineUuid) { throw 'Prepared offline environment identity changed.' }
$before=Get-FoundationOfflineFacts
if ($before.status -cne 'blocked-policy-observed') { 'RUNTIME_OFFLINE_UNPROVEN_EFFECTIVE_POLICY'; exit 2 }
Write-NativeIsarJson (Join-Path $root 'offline-attempt.json') ([ordered]@{schemaVersion=1;status='attempted';policy=$before;fullAcceptance=$false})
# This uses the already compiled application and --no-pub; no dependency/build
# acquisition occurs after the external network block.
& "$PSScriptRoot/test-foundation-owner-ui.ps1" -PreparedFixture $root
$after=Get-FoundationOfflineFacts
if ($after.status -cne 'blocked-policy-observed' -or ($before|ConvertTo-Json -Depth 6 -Compress) -cne ($after|ConvertTo-Json -Depth 6 -Compress)) { throw 'Runtime offline policy changed or was not proved.' }
Write-NativeIsarJson (Join-Path $root 'offline-result.json') ([ordered]@{
    schemaVersion=1;status='passed';facts=$facts;before=$before;after=$after;fullAcceptance=$false;distributionReady=$false;
    scope='compiled-normal-client-locald-owner-recovery-crud-and-reopen';excluded=@('uninstrumented-ui','physical-Q12','foreign-user','reboot','full-Q01-Q12')
})
'RUNTIME_OFFLINE_COMPILED_NORMAL_CLIENT_LOCALD_ACCEPTED'
# No firewall/account/OS changes or cleanup; retain failed attempts.
