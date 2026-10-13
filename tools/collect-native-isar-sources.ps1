[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Candidate,
    [Parameter(Mandatory)][string]$SupplementDirectory,
    [Parameter(Mandatory)][string]$RustDirectory,
    [Parameter(Mandatory)][string]$ArchiveCache
)
. "$PSScriptRoot/native-isar-inputs.ps1"
. "$PSScriptRoot/native-isar-source-archive.ps1"
$Candidate = [IO.Path]::GetFullPath($Candidate,(Get-Location).ProviderPath)
$ArchiveCache = [IO.Path]::GetFullPath($ArchiveCache,(Get-Location).ProviderPath)
if ([IO.Path]::GetDirectoryName($Candidate) -cne (Join-Path $NativeIsarRepository '.local/native-isar') -or
    [IO.Path]::GetFileName($Candidate) -cnotmatch '^candidate-[a-f0-9]{32}$') { throw 'Sources require an owned native candidate.' }
$recipe = Get-NativeIsarRecipe
$archiveInputs = @(@{file='isar-3.3.2-source.zip';sha256=$recipe.isar.sha256},@{file='libmdbx-source.zip';sha256=$recipe.mdbx.sha256})
foreach ($item in $archiveInputs) {
    if ((Get-NativeIsarDigest (Join-Path $ArchiveCache $item.file)) -cne $item.sha256) { throw 'Native corresponding source archive mismatch.' }
}
# Recreate material from checked source/component inputs, rather than trusting
# an arbitrary notice inventory whose hashes could have been rewritten.
$notices = & "$PSScriptRoot/collect-native-isar-notices.ps1" -Candidate $Candidate -SupplementDirectory $SupplementDirectory -RustDirectory $RustDirectory
$buildPath = Join-Path $Candidate 'native-build.json'
$buildHash = Get-NativeIsarDigest $buildPath
$build = Get-Content -LiteralPath $buildPath -Raw | ConvertFrom-Json
$noticeInventory = Get-Content -LiteralPath (Join-Path $notices 'native-notice-inventory.json') -Raw | ConvertFrom-Json
if ($noticeInventory.buildReceiptSha256 -cne $buildHash -or $noticeInventory.files.Count -ne 183 -or $noticeInventory.packages.Count -ne 91) { throw 'Native source notice binding mismatch.' }
$output = Join-Path $Candidate ('sources-' + [Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $output
[IO.Directory]::CreateDirectory($output) | Out-Null
$files = [Collections.Generic.List[object]]::new()
function Add-NativeSourceFile {
    param([string]$Path,[string]$Name,[string]$ExpectedHash='')
    $hash = Get-NativeIsarDigest $Path
    if ($ExpectedHash -and $hash -cne $ExpectedHash) { throw 'Native corresponding source input mismatch.' }
    $files.Add([ordered]@{file=$Name;path=$Path;sha256=$hash})
}
function Add-NativeSourceTree {
    param([string]$Root,[string]$Prefix,[string]$ExpectedHash,[string[]]$Exclude=@())
    $snapshot = @{}
    foreach ($entry in Get-ChildItem -LiteralPath $Root -Recurse -Force) {
        Assert-NativeIsarPlainPath $entry.FullName
        if ($entry.PSIsContainer) { continue }
        $relative = [IO.Path]::GetRelativePath($Root,$entry.FullName).Replace('\','/')
        if ($relative -in $Exclude) { continue }
        # Original checked trees, not an entire worktree/candidate dump.
        if ($relative -match '(^|/)\.git(/|$)') { throw 'Git metadata in native source input.' }
        $hash = Get-NativeIsarDigest $entry.FullName
        $snapshot[$relative] = $hash
        Add-NativeSourceFile $entry.FullName ($Prefix + '/' + $relative) $hash
    }
    if ((Get-NativeIsarSnapshotDigest $snapshot) -cne $ExpectedHash) { throw 'Native corresponding source tree mismatch.' }
}
$sourceName = 'isar-community-' + $recipe.isar.commit
$mdbxName = 'libmdbx-' + $recipe.mdbx.commit
Add-NativeSourceTree (Join-Path $Candidate ('source/' + $sourceName)) ('source/' + $sourceName) $build.inputDigests.source
Add-NativeSourceTree (Join-Path $Candidate ('mdbx/' + $mdbxName)) ('mdbx/' + $mdbxName) $build.inputDigests.mdbx @('src/version.c')
Add-NativeSourceTree (Join-Path $Candidate 'vendor') 'vendor' $build.inputDigests.vendor
$materializationPath = Join-Path $Candidate 'source.materialized-links.json'
$materializations = @(Get-Content -LiteralPath $materializationPath -Raw | ConvertFrom-Json)
if ($materializations.Count -ne 1 -or $materializations[0].link -cne ($sourceName + '/README.md') -or
    $materializations[0].target -cne ($sourceName + '/packages/isar_community/README.md') -or
    (Get-NativeIsarDigest (Join-Path $Candidate ('source/' + $materializations[0].link))) -cne
    (Get-NativeIsarDigest (Join-Path $Candidate ('source/' + $materializations[0].target)))) { throw 'Native source materialization record mismatch.' }
Add-NativeSourceFile (Join-Path $Candidate 'source.materialized-links.json') 'source.materialized-links.json'
if ($build.patch.file -cne 'mdbx-patch.json') { throw 'Unexpected native source patch reference.' }
Add-NativeSourceFile (Join-Path $Candidate 'mdbx-patch.json') 'mdbx-patch.json' $build.patch.sha256
$patch = Get-Content -LiteralPath (Join-Path $Candidate 'mdbx-patch.json') -Raw | ConvertFrom-Json
if ($patch.path -cne 'packages/mdbx_sys/build.rs' -or $patch.patchedSha256 -cne
    (Get-NativeIsarDigest (Join-Path $Candidate ('source/' + $sourceName + '/packages/mdbx_sys/build.rs')))) { throw 'Native corresponding source patch mismatch.' }
foreach ($item in $archiveInputs) {
    Add-NativeSourceFile (Join-Path $ArchiveCache $item.file) ('archives/' + $item.file) $item.sha256
}
$nativeRoot = Join-Path $NativeIsarRepository 'native/isar-3.3.2'
foreach ($item in @(
    @{file='recipe.json';sha256=$build.recipeFileSha256},@{file='Cargo.lock';sha256=$build.cargoLockSha256},
    @{file='supplemental-licenses.json';sha256=$noticeInventory.supplementManifestSha256},@{file='rust-license-material.json';sha256=$noticeInventory.rustManifestSha256}
)) {
    Add-NativeSourceFile (Join-Path $nativeRoot $item.file) ('native/isar-3.3.2/' + $item.file) $item.sha256
}
foreach ($item in @($recipe.licenseTexts) + @((Get-Content -LiteralPath (Join-Path $nativeRoot 'supplemental-licenses.json') -Raw | ConvertFrom-Json).texts)) {
    Add-NativeSourceFile (Join-Path $nativeRoot $item.file) ('native/isar-3.3.2/' + $item.file) $item.sha256
}
foreach ($item in $noticeInventory.files) {
    if ($item.file -cnotmatch '^licenses/') { throw 'Unexpected native source notice reference.' }
    Add-NativeSourceFile (Join-Path $notices $item.file) $item.file $item.sha256
}
Add-NativeSourceFile (Join-Path $notices 'THIRD_PARTY_NATIVE_NOTICES.txt') 'THIRD_PARTY_NATIVE_NOTICES.txt' $noticeInventory.notice.sha256
Add-NativeSourceFile (Join-Path $notices 'native-notice-inventory.json') 'native-notice-inventory.json'
$graphPath = $null
foreach ($dir in Get-ChildItem -LiteralPath $Candidate -Directory -Filter 'graph-*') {
    $path = Join-Path $dir.FullName 'native-dependencies.json'
    if ((Get-NativeIsarDigest $path) -ceq $noticeInventory.graphSha256) { $graphPath = $path; break }
}
if (-not $graphPath) { throw 'Bound native source graph missing.' }
Add-NativeSourceFile $graphPath 'native-dependencies.json' $noticeInventory.graphSha256
$tools = @()
foreach ($name in @('native-isar-inputs.ps1','native-isar-vendor-inputs.ps1','prepare-native-isar.ps1','build-native-isar.ps1','reproduce-native-isar.ps1')) {
    $path = Join-Path $PSScriptRoot $name
    $hash = Get-NativeIsarDigest $path
    Add-NativeSourceFile $path ('tools/' + $name) $hash
    $tools += [ordered]@{file='tools/' + $name;sha256=$hash}
}
$reproductionPath = Join-Path $output 'source-reproduction.json'
Write-NativeIsarJson $reproductionPath ([ordered]@{
    schemaVersion=1;product=$recipe.product;bindingVersion=$recipe.bindingVersion;target=$recipe.target
    state='sources-collected-unqualified';distributionReady=$false;buildReceiptSha256=$buildHash
    recipeFileSha256=$build.recipeFileSha256;cargoLockSha256=$build.cargoLockSha256
    sourceSha256=$build.inputDigests.source;mdbxSha256=$build.inputDigests.mdbx;vendorSha256=$build.inputDigests.vendor
    patchSha256=$build.patch.sha256;graphSha256=$noticeInventory.graphSha256
    noticeInventorySha256=Get-NativeIsarDigest (Join-Path $notices 'native-notice-inventory.json')
    tools=$tools
    command='pwsh -NoProfile -File tools/reproduce-native-isar.ps1 -ToolchainArchiveCache <checked-toolchain-archives>'
    runtimePrerequisites=$recipe.msvc
    rootPathCharacterLimit=80
})
Add-NativeSourceFile $reproductionPath 'source-reproduction.json'
$readme = Join-Path $output 'REPRODUCE.txt'
$instructions = @'
ServerDeck Isar native corresponding-source input; unqualified, no activation.
Extract the complete ZIP into a fresh directory whose absolute root path
contains at most 80 UTF16 characters; spaces are supported. This short-root
budget keeps the pinned MSVC linker paths below its legacy path limit.
Requires Windows x64,
PowerShell 7, and the exact VS/MSVC/Windows SDK versions in recipe.json.
Supply the three pinned Rust archives and pinned libclang wheel from their
recipe.json URLs in an external ToolchainArchiveCache directory. The original
Isar/MDBX archives and all vendored dependencies are already inside this ZIP.
Run from the extracted root:
pwsh -NoProfile -File tools/reproduce-native-isar.ps1 -ToolchainArchiveCache <checked-toolchain-archives>
Archive hashes and tool hashes are verified. Cargo metadata/build are frozen
and offline, with a fresh Cargo home; no cargo vendor is used. No global SDK
installation, active provider, user-data migration or publication is performed.
The new candidate and its logs remain in .local/native-isar. Byte equality
across hosts/compilers is not promised. Product qualification is separate.
source/ and mdbx/ contain the checked patched input trees for inspection;
reproduction freshly extracts the two original archives and applies the same
recorded acquisition-only patch. Generated MDBX version.c is excluded from
the original-input tree; the original build records it separately.
Original GNU vendor import-library .a files are preserved as vendor inputs,
not generated target products. Runtime/build-tool copyright catalogues and
all native source notices are retained; no SDK binaries are distributed here.
'@
[IO.File]::WriteAllText($readme,$instructions,[Text.UTF8Encoding]::new($false))
Add-NativeSourceFile $readme 'REPRODUCE.txt'
$zip = Join-Path $output 'NATIVE_SOURCES.zip'
Write-NativeIsarSourceArchive $zip $files.ToArray()
if ((Get-NativeIsarDigest $buildPath) -cne $buildHash -or
    (Get-NativeIsarDigest (Join-Path $nativeRoot 'recipe.json')) -cne $build.recipeFileSha256) { throw 'Native source binding changed during assembly.' }
Write-NativeIsarJson (Join-Path $output 'native-source-receipt.json') ([ordered]@{
    schemaVersion=1;product=$recipe.product;bindingVersion=$recipe.bindingVersion;target=$recipe.target
    state='sources-collected-unqualified';distributionReady=$false;buildReceiptSha256=$buildHash
    graphSha256=$noticeInventory.graphSha256;noticeInventorySha256=Get-NativeIsarDigest (Join-Path $notices 'native-notice-inventory.json')
    reproductionManifestSha256=Get-NativeIsarDigest $reproductionPath
    sourceArchive=[ordered]@{file='NATIVE_SOURCES.zip';sha256=Get-NativeIsarDigest $zip;length=(Get-Item -LiteralPath $zip).Length;fileCount=$files.Count}
})
Write-Output ([pscustomobject]@{output=$output;notices=$notices})
