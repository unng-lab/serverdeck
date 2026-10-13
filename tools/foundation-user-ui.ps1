. "$PSScriptRoot/foundation-sdk.ps1"
. "$PSScriptRoot/native-artifact.ps1"

function Invoke-FoundationUserUi {
    param([Parameter(Mandatory)][string]$Fixture,[Parameter(Mandatory)][ValidateSet('owner','foreign')][string]$Role,
        [Parameter(Mandatory)][string]$OwnerSid,[Parameter(Mandatory)][string]$OutputRoot)
    $root=[IO.Path]::GetFullPath($Fixture,(Get-Location).ProviderPath)
    if ([IO.Path]::GetDirectoryName($root) -cne (Join-Path $FoundationRoot '.local') -or
        [IO.Path]::GetFileName($root) -cnotmatch '^environment-acceptance-[a-f0-9]{32}$') { throw 'Owned user fixture required.' }
    Assert-NativeIsarPlainPath $root
    $output=[IO.Path]::GetFullPath($OutputRoot,(Get-Location).ProviderPath)
    Assert-NativeIsarPlainPath $output
    if ($Role -eq 'owner') {
        if ($output -cne $root -and -not $output.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Owner output outside fixture.' }
    } else {
        $local=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData))
        if ([IO.Path]::GetDirectoryName($output) -cne (Join-Path $local 'ServerDeckAcceptance') -or
            [IO.Path]::GetFileName($output) -cnotmatch '^foreign-[a-f0-9]{64}$') { throw 'Foreign output outside actual user acceptance namespace.' }
    }
    if (-not (Test-Path -LiteralPath $output -PathType Container)) { throw 'Existing owned output directory required.' }
    $profile=Join-Path $root 'profile'
    if ($Role -eq 'owner') { Assert-NativeIsarPlainPath $profile }
    # Foreign callers must not inspect private owner files before the product
    # verifies access. This target never writes test signals in that profile.
    $saved=@{}
    foreach($name in @('LOCALAPPDATA','SERVERDECK_ACCEPTANCE_OWNER_SID','SERVERDECK_ACCEPTANCE_USER_ROLE')) { $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
    Push-Location $FoundationRoot
    try {
        $env:LOCALAPPDATA=$profile
        $env:SERVERDECK_ACCEPTANCE_OWNER_SID=$OwnerSid
        $env:SERVERDECK_ACCEPTANCE_USER_ROLE=$Role
        $log=Join-Path $output ($Role+'-ui.txt')
        if (Test-Path -LiteralPath $log) { throw 'User UI attempt already recorded.' }
        Invoke-FoundationCommand $FoundationFlutter @('drive','--no-pub','--timeout','120','--driver','test_driver/foreign_user_driver.dart','--target','integration_test/foreign_user_test.dart','--use-application-binary',(Join-Path $root 'application bundle/serverdeck.exe'),'--no-keep-app-running','-d','windows') *> $log
        if ((Get-Item -LiteralPath $log).Length -gt 1MB) { throw 'User acceptance log oversized.' }
        $marker=if($Role -eq 'owner'){'COMPILED_OWNER_USER_BASELINE_PROVED'}else{'COMPILED_ACTUAL_FOREIGN_USER_ACCESS_REFUSAL_PROVED'}
        if (@(Get-Content -LiteralPath $log | Where-Object {$_ -ceq $marker}).Count -ne 1 -or
            (Select-String -LiteralPath $log -SimpleMatch 'synthetic-environment-password-243' -Quiet)) { throw 'User UI proof missing or privacy marker found.' }
    } finally {
        foreach($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
        Pop-Location
    }
}
