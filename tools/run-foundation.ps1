[CmdletBinding()]
param([ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug', [switch]$BuildOnly, [switch]$BootstrapAcceptance, [switch]$FoundationAcceptance, [switch]$LossAcceptance, [switch]$CredentialAcceptance, [switch]$UnknownInflightAcceptance, [switch]$RuntimeDiagnosticsAcceptance, [switch]$OwnerRecoveryAcceptance, [switch]$ForeignUserAcceptance)
$acceptanceTargets = @($BootstrapAcceptance, $FoundationAcceptance, $LossAcceptance, $CredentialAcceptance, $UnknownInflightAcceptance, $RuntimeDiagnosticsAcceptance, $OwnerRecoveryAcceptance, $ForeignUserAcceptance) | Where-Object { $_ }
if (@($acceptanceTargets).Count -gt 1) { throw 'Choose one acceptance target.' }
. "$PSScriptRoot/foundation-sdk.ps1"
. "$PSScriptRoot/native-artifact.ps1"
$initialNativeSelection=Get-NativeArtifactBuildSelection
if ($env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT -and -not $initialNativeSelection.preserveNormalBundles) { throw 'Candidate bundle build requires a preserved normal-bundle scope.' }
Push-Location $FoundationRoot
try {
    Invoke-FoundationCommand $FoundationFlutter @('pub', 'get', '--enforce-lockfile')
    foreach ($name in @('serverdeck_protocol', 'serverdeck_windows')) {
        Push-Location (Join-Path 'packages' $name)
        try { Invoke-FoundationCommand $FoundationDart @('pub', 'get', '--enforce-lockfile') } finally { Pop-Location }
    }
    $mode = $Configuration.ToLowerInvariant()
    $buildArguments = @('build', 'windows', "--$mode")
    if ($BootstrapAcceptance) { $buildArguments += @('--target', 'integration_test/bootstrap_test.dart') }
    if ($FoundationAcceptance) { $buildArguments += @('--target', 'integration_test/foundation_test.dart') }
    if ($LossAcceptance) { $buildArguments += @('--target', 'integration_test/loss_recovery_test.dart') }
    if ($CredentialAcceptance) { $buildArguments += @('--target', 'integration_test/credential_journey_test.dart') }
    if ($UnknownInflightAcceptance) { $buildArguments += @('--target', 'integration_test/unknown_inflight_test.dart') }
    if ($RuntimeDiagnosticsAcceptance) { $buildArguments += @('--target', 'integration_test/runtime_diagnostics_test.dart') }
    if ($OwnerRecoveryAcceptance) { $buildArguments += @('--target', 'integration_test/owner_recovery_test.dart') }
    if ($ForeignUserAcceptance) { $buildArguments += @('--target', 'integration_test/foreign_user_test.dart') }
    Invoke-FoundationCommand $FoundationFlutter $buildArguments
    $layout = Join-Path $FoundationRoot "build/windows/x64/runner/$Configuration"
    & "$PSScriptRoot/build-locald.ps1" -OutputDirectory $layout
    $nativeSelection = Get-NativeArtifactBuildSelection
    Copy-NativeArtifactLibrary -Selection $nativeSelection -Bundle $layout
    Copy-NativeArtifactBundleNotices -Bundle $layout
    $lockPaths = @('pubspec.lock', 'packages/serverdeck_locald/pubspec.lock', 'packages/serverdeck_protocol/pubspec.lock', 'packages/serverdeck_windows/pubspec.lock') | Sort-Object
    $lockTranscript = ($lockPaths | ForEach-Object { $_ + ':' + (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant() }) -join "`n"
    $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($lockTranscript))).ToLowerInvariant()
    $commit = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Build commit unavailable.' }
    $hashes = [ordered]@{}
    foreach ($name in @('serverdeck.exe', 'locald.exe', 'libisar.dll')) { $hashes[$name] = (Get-FileHash -LiteralPath (Join-Path $layout $name) -Algorithm SHA256).Hash.ToLowerInvariant() }
    $manifest = [ordered]@{ format = 1; buildId = "$commit+$Configuration+$digest"; configuration = $Configuration; testOnly = $false; appRoot = [IO.Path]::GetFullPath($layout); sha256 = $hashes }
    [IO.File]::WriteAllText((Join-Path $layout 'foundation.manifest.json'), ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    if (-not $BuildOnly) { Start-Process -FilePath (Join-Path $layout 'serverdeck.exe') -WorkingDirectory $layout -WindowStyle Hidden | Out-Null }
} finally { Pop-Location }
