. "$PSScriptRoot/native-isar-inputs.ps1"

function New-EnvironmentAcceptanceClaim {
    param(
        [Parameter(Mandatory)][string]$Fixture,
        [Parameter(Mandatory)][ValidateSet('Baseline','VerifyReboot')][string]$Phase,
        [Parameter(Mandatory)][string]$CheckpointSha256
    )
    $root=[IO.Path]::GetFullPath($Fixture,(Get-Location).ProviderPath)
    if ([IO.Path]::GetDirectoryName($root) -cne (Join-Path $NativeIsarRepository '.local') -or
        [IO.Path]::GetFileName($root) -cnotmatch '^environment-acceptance-[a-f0-9]{32}$' -or
        $CheckpointSha256 -cnotmatch '^[a-f0-9]{64}$' -or -not (Test-Path -LiteralPath $root -PathType Container)) {
        throw 'Existing owned checkpoint fixture and digest required.'
    }
    Assert-NativeIsarPlainPath $root
    # One shared CreateNew claim consumes the checkpoint across BOTH phases.
    # Even a partial write or later launch failure retains the occupied name.
    $claim=Join-Path $root 'checkpoint-attempt.json'
    Write-NativeIsarJson $claim ([ordered]@{
        schemaVersion=1;phase=$Phase;status='attempted';checkpointSha256=$CheckpointSha256;
        fullAcceptance=$false;distributionReady=$false
    })
}
