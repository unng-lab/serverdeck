[CmdletBinding()]
param([Parameter(Mandatory)][string]$ToolchainArchiveCache)
# Entry point inside the standalone corresponding-source package. Toolchain
# binaries are supplied externally; the two original source archives are local.
. "$PSScriptRoot/native-isar-inputs.ps1"
. "$PSScriptRoot/native-isar-vendor-inputs.ps1"
if ($NativeIsarRepository.Length -gt 80) { throw 'Native build repository root exceeds 80 characters.' }
$ToolchainArchiveCache = [IO.Path]::GetFullPath($ToolchainArchiveCache,(Get-Location).ProviderPath)
$manifestPath = Join-Path $NativeIsarRepository 'source-reproduction.json'
Assert-NativeIsarPlainPath $manifestPath
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
    (Get-Item -LiteralPath $manifestPath).Length -gt 1MB) { throw 'Missing or oversized native source reproduction manifest.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$recipe = Get-NativeIsarRecipe
if ($manifest.schemaVersion -ne 1 -or $manifest.product -cne $recipe.product -or
    $manifest.bindingVersion -cne $recipe.bindingVersion -or $manifest.target -cne $recipe.target -or
    $manifest.recipeFileSha256 -cne (Get-NativeIsarDigest (Join-Path $NativeIsarRepository 'native/isar-3.3.2/recipe.json')) -or
    $manifest.cargoLockSha256 -cne $recipe.cargoLockSha256 -or $manifest.rootPathCharacterLimit -ne 80) { throw 'Native source reproduction identity mismatch.' }
$requiredTools = @('tools/native-isar-inputs.ps1','tools/native-isar-vendor-inputs.ps1','tools/prepare-native-isar.ps1','tools/build-native-isar.ps1','tools/reproduce-native-isar.ps1')
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
if (@($manifest.tools).Count -ne $requiredTools.Count -or $manifest.vendorSha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Native source reproduction manifest inventory mismatch.' }
foreach ($tool in $manifest.tools) {
    if ($tool.file -cnotin $requiredTools -or -not $seen.Add($tool.file) -or $tool.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        (Get-NativeIsarDigest (Join-Path $NativeIsarRepository $tool.file)) -cne $tool.sha256) { throw 'Native source reproduction tool mismatch.' }
}
$vendor = Join-Path $NativeIsarRepository 'vendor'
# The builder performs complete bounded vendor validation before preparation.
$inputs = @(
    @{file='isar-3.3.2-source.zip';root=Join-Path $NativeIsarRepository 'archives';sha256=$recipe.isar.sha256},
    @{file='libmdbx-source.zip';root=Join-Path $NativeIsarRepository 'archives';sha256=$recipe.mdbx.sha256},
    @{file='libclang-18.1.1-win64.whl';root=$ToolchainArchiveCache;sha256=$recipe.libclang.sha256}
)
foreach ($component in $recipe.rust.components) {
    $inputs += @{file=[IO.Path]::GetFileName(([Uri]$component.url).AbsolutePath);root=$ToolchainArchiveCache;sha256=$component.sha256}
}
foreach ($item in $inputs) {
    if ((Get-NativeIsarDigest (Join-Path $item.root $item.file)) -cne $item.sha256) { throw 'Native source reproduction archive mismatch.' }
}
$cache = Join-Path $NativeIsarRepository ('.local/source-reproduction-' + [Guid]::NewGuid().ToString('N') + '/archives')
Assert-NativeIsarPlainPath $cache
[IO.Directory]::CreateDirectory($cache) | Out-Null
foreach ($item in $inputs) {
    $output = Join-Path $cache $item.file
    Copy-Item -LiteralPath (Join-Path $item.root $item.file) -Destination $output
    if ((Get-NativeIsarDigest $output) -cne $item.sha256) { throw 'Native source reproduction archive copy mismatch.' }
}
$candidate = & "$PSScriptRoot/build-native-isar.ps1" -ArchiveCache $cache -VendorSource $vendor -VendorSha256 $manifest.vendorSha256
$receipt = Get-Content -LiteralPath (Join-Path $candidate 'native-build.json') -Raw | ConvertFrom-Json
if ($receipt.product -cne $manifest.product -or $receipt.bindingVersion -cne $manifest.bindingVersion -or
    $receipt.target -cne $manifest.target -or $receipt.state -cne 'built-unqualified' -or $receipt.distributionReady -ne $false -or
    $receipt.inputDigests.source -cne $manifest.sourceSha256 -or $receipt.inputDigests.mdbx -cne $manifest.mdbxSha256 -or
    $receipt.inputDigests.vendor -cne $manifest.vendorSha256 -or $receipt.patch.sha256 -cne $manifest.patchSha256 -or
    $receipt.recipeFileSha256 -cne $manifest.recipeFileSha256 -or $receipt.cargoLockSha256 -cne $manifest.cargoLockSha256 -or
    $receipt.vendorAcquisition -cne 'verified-local-snapshot' -or -not $receipt.offlineCompilation) { throw 'Native reproduced inputs differ from the source manifest.' }
Write-Output $candidate
