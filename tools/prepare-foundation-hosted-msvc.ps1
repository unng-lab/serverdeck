[CmdletBinding()]
param([switch]$VerifyBootstrapOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/native-isar-inputs.ps1"
$recipe=Get-NativeIsarRecipe
if ($recipe.msvc.vsInstallationVersion -cne '17.14.36811.4') { throw 'Bootstrap recipe version mismatch.' }
if (-not $VerifyBootstrapOnly -and
    ($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
     $env:RUNNER_OS -cne 'Windows' -or -not $env:RUNNER_TEMP)) {
    throw 'Installation is restricted to a disposable GitHub-hosted Windows runner.'
}
$root=Join-Path $NativeIsarRepository ('.local/hosted-msvc-' + [Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $root
[void][IO.Directory]::CreateDirectory($root)
$exe=Join-Path $root 'vs_BuildTools.exe'
$expected='5439781a4deb7951895e041d3d0a5b409034ad56070e5fc5576dda2e0e364faa'
Invoke-WebRequest 'https://download.visualstudio.microsoft.com/download/pr/a80deb24-6a28-4d30-b99f-13b6e89c9727/5439781a4deb7951895e041d3d0a5b409034ad56070e5fc5576dda2e0e364faa/vs_BuildTools.exe' -OutFile $exe
$signature=Get-AuthenticodeSignature -LiteralPath $exe
if ((Get-NativeIsarDigest $exe) -cne $expected -or $signature.Status -ne 'Valid' -or
    $signature.SignerCertificate.Subject -notmatch '^CN=Microsoft Corporation,' -or
    (Get-Item -LiteralPath $exe).VersionInfo.FileVersion -cne $recipe.msvc.vsInstallationVersion) {
    throw 'Pinned Microsoft bootstrap verification failed.'
}
if ($VerifyBootstrapOnly) {
    'PINNED_MICROSOFT_BOOTSTRAP_HASH_SIGNATURE_AND_VERSION_VERIFIED_INSTALLATION_NOT_RUN'
    return
}
$install=Join-Path ([IO.Path]::GetFullPath($env:RUNNER_TEMP)) ('serverdeck-msvc-' + [Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $install
if ($install -match '["\r\n]' -or (Test-Path -LiteralPath $install)) { throw 'Fresh safe installation path required.' }
# Fixed-release bootstrapper; no modify/update/uninstall of preinstalled VS.
$arguments=@('--quiet','--wait','--norestart','--nocache','--installPath',('"'+$install+'"'),
    '--add','Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
    '--add','Microsoft.VisualStudio.Component.Windows11SDK.26100')
$process=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0) { throw 'Pinned Build Tools installation failed or requires reboot.' }
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$instances=@(& $vswhere -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json | Out-String | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'Pinned installation discovery failed.' }
$matches=@($instances | Where-Object installationVersion -EQ $recipe.msvc.vsInstallationVersion)
if ($matches.Count -ne 1 -or $matches[0].installationPath -cne $install -or
    -not (Test-Path -LiteralPath (Join-Path $install ('VC/Tools/MSVC/'+$recipe.msvc.vcToolsVersion)) -PathType Container)) {
    throw 'Installed pinned toolchain identity mismatch.'
}
'PINNED_HOSTED_MSVC_INSTALLED_NATIVE_BUILDER_VALIDATION_REQUIRED'
