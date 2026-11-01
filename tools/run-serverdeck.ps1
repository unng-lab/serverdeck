[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release', IgnoreCase = $false)][string]$Configuration = 'Debug',
    [switch]$BuildOnly,
    [string]$Python = 'python'
)
. "$PSScriptRoot/foundation-sdk.ps1"
. "$PSScriptRoot/native-artifact.ps1"
. "$PSScriptRoot/embedded-bundle.ps1"
function Assert-EmbeddedBuildOutput {
    param([Parameter(Mandatory)][string]$Root)
    Assert-NativeIsarPlainPath $Root
    # Validate existing children before Flutter/custom writers can follow them.
    # PowerShell does not follow directory symlinks during this enumeration.
    if (Test-Path -LiteralPath $Root -PathType Container) {
        foreach ($entry in Get-ChildItem -LiteralPath $Root -Recurse -Force) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Build output contains a reparse point.' }
            Assert-NativeIsarPlainPath $entry.FullName
        }
    }
    foreach ($name in @('serverdeck.exe', 'libisar.dll', 'executor-release.json', 'foundation.manifest.json', 'notices')) {
        Assert-NativeIsarPlainPath (Join-Path $Root $name)
    }
    foreach ($legacy in @('locald.exe', 'mcp.exe')) {
        if (Test-Path -LiteralPath (Join-Path $Root $legacy)) { throw 'Incompatible build output: use a clean embedded layout.' }
    }
}
$initialNativeSelection = Get-NativeArtifactBuildSelection
if ($env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT -and -not $initialNativeSelection.preserveNormalBundles) {
    throw 'Candidate bundle build requires a preserved normal-bundle scope.'
}
$layout = [IO.Path]::GetFullPath((Join-Path $FoundationRoot "build/windows/x64/runner/$Configuration"))
Assert-EmbeddedBuildOutput $layout
Push-Location $FoundationRoot
try {
    Invoke-FoundationCommand $FoundationFlutter @('pub', 'get', '--enforce-lockfile')
    foreach ($name in Get-CurrentPackageNames) {
        Push-Location (Join-Path 'packages' $name)
        try { Invoke-FoundationCommand $FoundationDart @('pub', 'get', '--enforce-lockfile') }
        finally { Pop-Location }
    }
    Push-Location (Join-Path $FoundationRoot 'packages/serverdeck_engine')
    try { Invoke-FoundationCommand $FoundationDart @('run', 'build_runner', 'build', '--delete-conflicting-outputs') }
    finally { Pop-Location }
    $flutterBuildArguments = @('build', 'windows', ('--' + $Configuration.ToLowerInvariant()), '--no-pub')
    Invoke-FoundationCommand $FoundationFlutter $flutterBuildArguments
    # A stale multi-executable layout is never relabelled as an embedded bundle.
    # Do not delete or migrate existing output or terminate its possible owner.
    Assert-EmbeddedBuildOutput $layout
    $nativeSelection = Get-NativeArtifactBuildSelection
    Copy-NativeArtifactLibrary -Selection $nativeSelection -Bundle $layout
    Copy-NativeArtifactBundleNotices -Bundle $layout
    $executorOutput = Join-Path $layout 'executor-release.json'
    Assert-NativeIsarPlainPath $executorOutput
    Invoke-FoundationCommand $Python @('tools/build-executor-release.py', '--output', $executorOutput)
    $lockPaths = @(Get-EmbeddedBundleLockPaths)
    $lockHashes = [ordered]@{}
    foreach ($path in $lockPaths) { $lockHashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    $commit = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Build commit unavailable.' }
    $hashes = [ordered]@{}
    foreach ($name in @('serverdeck.exe', 'libisar.dll', 'executor-release.json')) {
        $hashes[$name] = (Get-FileHash -LiteralPath (Join-Path $layout $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $manifest = New-EmbeddedBundleManifest -Commit $commit -Configuration $Configuration -AppRoot ([IO.Path]::GetFullPath($layout)) -LockHashes $lockHashes -Hashes $hashes
    $manifestJson = $manifest | ConvertTo-Json -Depth 5 -Compress
    $manifestOutput = Join-Path $layout 'foundation.manifest.json'
    Assert-NativeIsarPlainPath $manifestOutput
    [IO.File]::WriteAllText($manifestOutput,
        $manifestJson, [Text.UTF8Encoding]::new($false))
    if (-not $BuildOnly) {
        Start-Process -FilePath (Join-Path $layout 'serverdeck.exe') -WorkingDirectory $layout -WindowStyle Hidden | Out-Null
    }
} finally { Pop-Location }
