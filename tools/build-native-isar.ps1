[CmdletBinding()]
param([string]$ArchiveCache = '', [string]$VendorSource = '', [string]$VendorSha256 = '')
. "$PSScriptRoot/native-isar-inputs.ps1"
. "$PSScriptRoot/native-isar-vendor-inputs.ps1"
if ($NativeIsarRepository.Length -gt 80) { throw 'Native build repository root exceeds 80 characters.' }
if ([bool]$VendorSource -ne [bool]$VendorSha256) { throw 'Vendor source and digest must be supplied together.' }
$verifiedVendor = $null
if ($VendorSource) {
    $VendorSource = [IO.Path]::GetFullPath($VendorSource, (Get-Location).ProviderPath)
    $verifiedVendor = Get-NativeIsarVendorSnapshot $VendorSource $VendorSha256
}
$recipe = Get-NativeIsarRecipe
$recipePath = Join-Path $NativeIsarRepository 'native/isar-3.3.2/recipe.json'
$recipeFileDigest = Get-NativeIsarDigest $recipePath
$progress=Join-Path $NativeIsarRepository ('.local/native-build-progress-'+[Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $progress
[void][IO.Directory]::CreateDirectory($progress)
function Write-NativeBuildPhase {
    param([ValidateSet('preparation','source-extraction','msvc','vendoring','snapshots','metadata','compilation','verification')][string]$Name)
    Write-NativeIsarJson (Join-Path $progress ('safe-phase-'+$Name+'.json')) ([ordered]@{
        schemaVersion=1;kind='native-build-phase';status='started';phase=$Name
        recipeFileSha256=$recipeFileDigest
        fullAcceptance=$false;distributionReady=$false;activated=$false
    })
}
Write-NativeBuildPhase 'preparation'
# Re-extract checked archives instead of trusting a mutable prepared toolchain.
$prepared = & "$PSScriptRoot/prepare-native-isar.ps1" -ArchiveCache $ArchiveCache
if ($prepared -isnot [string] -or -not (Test-Path -LiteralPath (Join-Path $prepared 'prepared.json'))) { throw 'Native preparation did not produce an owned input directory.' }
$candidate = Join-Path $NativeIsarRepository ('.local/native-isar/candidate-' + [Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $candidate
[IO.Directory]::CreateDirectory($candidate) | Out-Null
$source = Join-Path $candidate ('source/isar-community-' + $recipe.isar.commit)
$mdbx = Join-Path $candidate ('mdbx/libmdbx-' + $recipe.mdbx.commit)
Write-NativeBuildPhase 'source-extraction'
Expand-NativeIsarArchive (Join-Path $prepared 'archives/isar-3.3.2-source.zip') (Join-Path $candidate 'source') zip
Expand-NativeIsarArchive (Join-Path $prepared 'archives/libmdbx-source.zip') (Join-Path $candidate 'mdbx') zip
Copy-Item -LiteralPath (Join-Path $NativeIsarRepository 'native/isar-3.3.2/Cargo.lock') -Destination (Join-Path $source 'Cargo.lock')
$patchPath = Join-Path $source 'packages/mdbx_sys/build.rs'
$originalDigest = Get-NativeIsarDigest $patchPath
$original = [IO.File]::ReadAllText($patchPath)
$pattern = '(?s)fn ensure_libmdbx\(out_dir: &Path\) -> PathBuf \{.*?\r?\n\}\r?\n\r?\nfn parse_semver'
$replacement = @'
fn ensure_libmdbx(_out_dir: &Path) -> PathBuf {
    let source = PathBuf::from(env::var("SERVERDECK_BUILD_MDBX_SOURCE")
        .expect("verified local MDBX source is required"));
    assert!(source.join("mdbx.h").is_file(), "verified MDBX header missing");
    source
}

fn parse_semver
'@
if ([Regex]::Matches($original, $pattern).Count -ne 1) { throw 'Unexpected MDBX patch input.' }
[IO.File]::WriteAllText($patchPath, [Regex]::Replace($original, $pattern, $replacement), [Text.UTF8Encoding]::new($false))
Write-NativeIsarJson (Join-Path $candidate 'mdbx-patch.json') ([ordered]@{
    path='packages/mdbx_sys/build.rs'; originalSha256=$originalDigest; patchedSha256=Get-NativeIsarDigest $patchPath
    match=$pattern; replacement=$replacement
})

function Get-BuildTreeSnapshot {
    param([string]$Root, [string[]]$ExcludedNames = @())
    Assert-NativeIsarPlainPath $Root
    $snapshot = @{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force) {
        $relative = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\','/')
        if ($relative -in $ExcludedNames) { continue }
        $snapshot[$relative] = Get-NativeIsarDigest $file.FullName
    }
    return $snapshot
}
function Assert-BuildTreeSnapshot {
    param([hashtable]$Expected, [hashtable]$Actual)
    if ($Expected.Count -ne $Actual.Count) { throw 'Native immutable input inventory changed.' }
    foreach ($key in $Expected.Keys) {
        if (-not $Actual.ContainsKey($key) -or $Expected[$key] -cne $Actual[$key]) { throw 'Native immutable input bytes changed.' }
    }
}

Write-NativeBuildPhase 'msvc'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) { throw 'MSVC discovery prerequisite missing.' }
$installations = @(& $vswhere -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json | Out-String | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'MSVC discovery failed.' }
$matches = @($installations | Where-Object installationVersion -eq $recipe.msvc.vsInstallationVersion)
if ($matches.Count -ne 1) { throw 'Pinned MSVC installation unavailable or ambiguous.' }
$devcmd = Join-Path $matches[0].installationPath 'Common7/Tools/VsDevCmd.bat'
if ($devcmd -match '["\r\n&|<>^]' -or -not (Test-Path -LiteralPath $devcmd -PathType Leaf)) { throw 'Unsafe or missing MSVC environment command.' }
$vsKeys = @('PATH','INCLUDE','LIB','LIBPATH','WindowsSdkDir','WindowsSDKVersion','VCToolsInstallDir','VCToolsVersion','UniversalCRTSdkDir','UCRTVersion','VSINSTALLDIR')
$buildKeys = @('RUSTC','CARGO_HOME','CARGO_TARGET_DIR','LIBCLANG_PATH','ISAR_VERSION','SERVERDECK_BUILD_MDBX_SOURCE','RUSTFLAGS','CARGO_ENCODED_RUSTFLAGS','CARGO_NET_OFFLINE')
$ambientKeys = @(Get-ChildItem Env: | Where-Object {
    $_.Name -match '^(CARGO_|RUST|CC($|_)|CXX($|_)|CXXSTDLIB($|_)|CFLAGS($|_)|CXXFLAGS($|_)|AR($|_)|ARFLAGS($|_)|HOST_|TARGET_|BINDGEN_|LIBCLANG_|CLANG_|LLVM_|CRATE_CC_|CL$|_CL_$|LINK$|_LINK_$|VSCMD_|__VSCMD_)'
} | Select-Object -ExpandProperty Name)
$keys = @($vsKeys + $buildKeys + $ambientKeys | Select-Object -Unique)
$saved = @{}
foreach ($key in $keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key,'Process') }
try {
    foreach ($key in $ambientKeys) { [Environment]::SetEnvironmentVariable($key,$null,'Process') }
    foreach ($key in $vsKeys | Where-Object { $_ -ne 'PATH' }) { [Environment]::SetEnvironmentVariable($key,$null,'Process') }
    if (-not $env:ComSpec -or -not (Test-Path -LiteralPath $env:ComSpec -PathType Leaf)) { throw 'Native command interpreter prerequisite missing.' }
    $command = '"' + $devcmd + '" -no_logo -arch=x64 -host_arch=x64 -vcvars_ver=' + $recipe.msvc.vcToolsVersion + ' -winsdk=' + $recipe.msvc.windowsSdkVersion + ' >nul && set'
    $vsEnvironment = @(& $env:ComSpec /d /s /c $command)
    if ($LASTEXITCODE -ne 0) { throw 'Pinned MSVC environment unavailable.' }
    foreach ($line in $vsEnvironment) {
        if ($line -match '^([^=]+)=(.*)$' -and $Matches[1] -in $vsKeys) { [Environment]::SetEnvironmentVariable($Matches[1],$Matches[2],'Process') }
    }
    if (-not $env:VCToolsVersion -or -not $env:WindowsSDKVersion -or
        $env:VCToolsVersion.TrimEnd('\') -cne $recipe.msvc.vcToolsVersion -or
        $env:WindowsSDKVersion.TrimEnd('\') -cne $recipe.msvc.windowsSdkVersion) { throw 'MSVC/SDK identity mismatch.' }
    $rust = Join-Path $prepared 'rust'
    $env:PATH = (Join-Path $rust 'bin') + ';' + $env:PATH
    $env:RUSTC = Join-Path $rust 'bin/rustc.exe'
    $env:CARGO_HOME = Join-Path $candidate 'cargo-home'
    $env:CARGO_TARGET_DIR = Join-Path $candidate 'target'
    $env:LIBCLANG_PATH = Split-Path (Join-Path (Join-Path $prepared 'libclang') $recipe.libclang.dllEntry) -Parent
    $env:ISAR_VERSION = $recipe.bindingVersion
    $env:SERVERDECK_BUILD_MDBX_SOURCE = $mdbx
    $env:CARGO_ENCODED_RUSTFLAGS = "--remap-path-prefix=$candidate=/serverdeck/native" + [char]0x1f + "--remap-path-prefix=$prepared=/serverdeck/toolchain"
    $cargo = Join-Path $rust 'bin/cargo.exe'
    Push-Location $source
    try {
        # Reject inherited ancestor configuration; only the fresh local vendor config is supported.
        $ancestor = $source
        while ($ancestor) {
            foreach ($configName in @('.cargo/config','.cargo/config.toml')) {
                if (Test-Path -LiteralPath (Join-Path $ancestor $configName)) { throw 'Unexpected ancestor Cargo configuration.' }
            }
            $ancestor = [IO.Path]::GetDirectoryName($ancestor)
        }
        Write-NativeBuildPhase 'vendoring'
        if ($verifiedVendor) {
            Copy-NativeIsarVendorSnapshot $VendorSource (Join-Path $candidate 'vendor') $VendorSha256 $verifiedVendor
        } else {
            & $cargo vendor --locked (Join-Path $candidate 'vendor') > (Join-Path $candidate 'vendor-config.original.toml') 2> (Join-Path $candidate 'vendor.log')
            if ($LASTEXITCODE -ne 0) { throw 'Native vendor preparation failed.' }
        }
        [IO.Directory]::CreateDirectory((Join-Path $source '.cargo')) | Out-Null
        $config = "[source.crates-io]`nreplace-with = 'vendored-sources'`n[source.vendored-sources]`ndirectory = '../../vendor'`n"
        [IO.File]::WriteAllText((Join-Path $source '.cargo/config.toml'),$config,[Text.UTF8Encoding]::new($false))
        Write-NativeBuildPhase 'snapshots'
        $sourceBefore = Get-BuildTreeSnapshot $source
        $mdbxBefore = Get-BuildTreeSnapshot $mdbx @('src/version.c')
        $vendorBefore = Get-BuildTreeSnapshot (Join-Path $candidate 'vendor')
        $rustBefore = Get-BuildTreeSnapshot $rust
        $clangBefore = Get-BuildTreeSnapshot (Join-Path $prepared 'libclang')
        $env:CARGO_NET_OFFLINE = 'true'
        Write-NativeBuildPhase 'metadata'
        & $cargo metadata --frozen --format-version 1 --filter-platform $recipe.target > (Join-Path $candidate 'metadata.private.json') 2> (Join-Path $candidate 'metadata.log')
        if ($LASTEXITCODE -ne 0) { throw 'Frozen native metadata failed.' }
        Write-NativeBuildPhase 'compilation'
        & $cargo build --frozen -p isar --target $recipe.target --release *> (Join-Path $candidate 'build.log')
        if ($LASTEXITCODE -ne 0) { throw 'Frozen native build failed.' }
        Write-NativeBuildPhase 'verification'
        Assert-BuildTreeSnapshot $sourceBefore (Get-BuildTreeSnapshot $source)
        Assert-BuildTreeSnapshot $mdbxBefore (Get-BuildTreeSnapshot $mdbx @('src/version.c'))
        Assert-BuildTreeSnapshot $vendorBefore (Get-BuildTreeSnapshot (Join-Path $candidate 'vendor'))
        Assert-BuildTreeSnapshot $rustBefore (Get-BuildTreeSnapshot $rust)
        Assert-BuildTreeSnapshot $clangBefore (Get-BuildTreeSnapshot (Join-Path $prepared 'libclang'))
        if ((Get-NativeIsarDigest $recipePath) -cne $recipeFileDigest -or
            (Get-NativeIsarDigest (Join-Path $source 'Cargo.lock')) -cne $recipe.cargoLockSha256) { throw 'Native recipe or lock changed during build.' }
        $dll = Join-Path $candidate ('target/' + $recipe.target + '/release/isar.dll')
        $bytes = [IO.File]::ReadAllBytes($dll)
        if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) { throw 'Native output lacks PE header.' }
        $pe = [BitConverter]::ToInt32($bytes,0x3c)
        if ($pe -lt 64 -or $pe -gt $bytes.Length-6 -or [BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550 -or
            [BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664) { throw 'Native output target mismatch.' }
        Copy-Item -LiteralPath $dll -Destination (Join-Path $candidate 'libisar.dll')
        # Build receipt is deliberately distinct from complete artifact/qualification receipts.
        Write-NativeIsarJson (Join-Path $candidate 'native-build.json') ([ordered]@{
            schemaVersion=1; product=$recipe.product; bindingVersion=$recipe.bindingVersion; target=$recipe.target
            state='built-unqualified'; distributionReady=$false; recipeFileSha256=$recipeFileDigest
            cargoLockSha256=$recipe.cargoLockSha256; isarCommit=$recipe.isar.commit; mdbxCommit=$recipe.mdbx.commit
            dll=@{file='libisar.dll';sha256=Get-NativeIsarDigest (Join-Path $candidate 'libisar.dll');length=$bytes.Length}
            patch=@{file='mdbx-patch.json';sha256=Get-NativeIsarDigest (Join-Path $candidate 'mdbx-patch.json')}
            compiler=$recipe.rust; msvc=$recipe.msvc; libclangVersion=$recipe.libclang.version
            features='default'; command='cargo build --frozen -p isar --target x86_64-pc-windows-msvc --release'
            offlineCompilation=$true; immutableInputsVerified=$true
            compilerFlagTransport='CARGO_ENCODED_RUSTFLAGS-U001F'
            vendorAcquisition= $(if ($verifiedVendor) { 'verified-local-snapshot' } else { 'cargo-vendor-locked' })
            metadata=@{file='metadata.private.json';sha256=Get-NativeIsarDigest (Join-Path $candidate 'metadata.private.json')}
            inputDigests=@{
                source=Get-NativeIsarSnapshotDigest $sourceBefore
                mdbx=Get-NativeIsarSnapshotDigest $mdbxBefore
                vendor=Get-NativeIsarSnapshotDigest $vendorBefore
                rust=Get-NativeIsarSnapshotDigest $rustBefore
                libclang=Get-NativeIsarSnapshotDigest $clangBefore
            }
            generatedMdbxVersion=@{file='src/version.c';sha256=Get-NativeIsarDigest (Join-Path $mdbx 'src/version.c')}
        })
        Write-Output $candidate
    } finally { Pop-Location }
} finally {
    foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') }
}
