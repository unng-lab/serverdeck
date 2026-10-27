[CmdletBinding()]
param([Parameter(Mandatory)][string]$Candidate)
. "$PSScriptRoot/native-isar-inputs.ps1"
$Candidate = [IO.Path]::GetFullPath($Candidate)
$parent = Join-Path $NativeIsarRepository '.local/native-isar'
if ([IO.Path]::GetDirectoryName($Candidate) -cne $parent -or [IO.Path]::GetFileName($Candidate) -cnotmatch '^candidate-[a-f0-9]{32}$') { throw 'Graph requires an owned native candidate.' }
Assert-NativeIsarPlainPath $Candidate
$recipe = Get-NativeIsarRecipe
if (@($recipe.licenseTexts).Count -ne 1) { throw 'Required supplemental MPL license text is missing or ambiguous.' }
$licenseInputs = @()
foreach ($text in $recipe.licenseTexts) {
    if ($text.id -cne 'MPL-2.0' -or $text.file -cne 'licenses/MPL-2.0.txt') { throw 'Unsupported supplemental native license text.' }
    $path = Join-Path (Join-Path $NativeIsarRepository 'native/isar-3.3.2') $text.file
    if ((Get-NativeIsarDigest $path) -cne $text.sha256) { throw 'Pinned supplemental license text mismatch.' }
    $licenseInputs += @{path=$path;descriptor=[ordered]@{id=$text.id;file=$text.file;source=$text.source;sha256=$text.sha256}}
}
$receiptPath = Join-Path $Candidate 'native-build.json'
if ((Get-Item -LiteralPath $receiptPath).Length -gt 1MB) { throw 'Build receipt exceeds limit.' }
$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
if ($receipt.schemaVersion -ne 1 -or $receipt.product -cne $recipe.product -or $receipt.bindingVersion -cne $recipe.bindingVersion -or
    $receipt.target -cne $recipe.target -or $receipt.state -cne 'built-unqualified' -or $receipt.distributionReady -ne $false -or
    $receipt.recipeFileSha256 -cne (Get-NativeIsarDigest (Join-Path $NativeIsarRepository 'native/isar-3.3.2/recipe.json')) -or
    $receipt.cargoLockSha256 -cne $recipe.cargoLockSha256 -or $receipt.dll.file -cne 'libisar.dll' -or
    $receipt.dll.sha256 -cne (Get-NativeIsarDigest (Join-Path $Candidate 'libisar.dll'))) { throw 'Graph candidate receipt mismatch.' }
if ($receipt.metadata.file -cne 'metadata.private.json') { throw 'Unexpected raw metadata reference.' }
$metadataPath = Join-Path $Candidate 'metadata.private.json'
if ((Get-Item -LiteralPath $metadataPath).Length -gt 8MB -or (Get-NativeIsarDigest $metadataPath) -cne $receipt.metadata.sha256) { throw 'Bound native metadata mismatch.' }
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$source = Join-Path $Candidate ('source/isar-community-' + $recipe.isar.commit)
$vendor = Join-Path $Candidate 'vendor'
$mdbx = Join-Path $Candidate ('mdbx/libmdbx-' + $recipe.mdbx.commit)
foreach ($tree in @(@{root=$source;digest=$receipt.inputDigests.source;excluded=@()},@{root=$vendor;digest=$receipt.inputDigests.vendor;excluded=@()},@{root=$mdbx;digest=$receipt.inputDigests.mdbx;excluded=@('src/version.c')})) {
    $snapshot = @{}
    foreach ($file in Get-ChildItem -LiteralPath $tree.root -Recurse -File -Force) {
        $relative = [IO.Path]::GetRelativePath($tree.root,$file.FullName).Replace('\','/')
        if ($relative -in $tree.excluded) { continue }
        $snapshot[$relative] = Get-NativeIsarDigest $file.FullName
    }
    if ((Get-NativeIsarSnapshotDigest $snapshot) -cne $tree.digest) { throw 'Bound native source or vendor tree mismatch.' }
}
if ($receipt.generatedMdbxVersion.file -cne 'src/version.c' -or (Get-NativeIsarDigest (Join-Path $mdbx 'src/version.c')) -cne $receipt.generatedMdbxVersion.sha256) { throw 'Generated MDBX source mismatch.' }
$lockPath = Join-Path $source 'Cargo.lock'
if ((Get-NativeIsarDigest $lockPath) -cne $recipe.cargoLockSha256) { throw 'Candidate lock mismatch.' }
$lock = @{}
foreach ($block in ([IO.File]::ReadAllText($lockPath) -split '\[\[package\]\]') | Select-Object -Skip 1) {
    $fields = @{}
    foreach ($field in @('name','version','source','checksum')) {
        $match = [Regex]::Match($block,'(?m)^' + $field + ' = "([^"\r\n]+)"\r?$')
        if ($match.Success) { $fields[$field] = $match.Groups[1].Value }
    }
    if (-not $fields.ContainsKey('name') -or -not $fields.ContainsKey('version')) { throw 'Unsupported lock package.' }
    $key = $fields.name + '@' + $fields.version
    if ($lock.ContainsKey($key)) { throw 'Ambiguous lock package identity.' }
    $lock[$key] = $fields
}
$packages = @($metadata.packages)
if (-not $packages.Count -or $packages.Count -gt 1000 -or $metadata.resolve.nodes.Count -ne $packages.Count) { throw 'Invalid native graph size.' }
$ids = @{}
$descriptors = @{}
foreach ($package in $packages) {
    $id = $package.name + '@' + $package.version
    if ($package.name -cnotmatch '^[A-Za-z0-9_-]+$' -or $package.version -cnotmatch '^[A-Za-z0-9.+_-]+$' -or
        $ids.ContainsKey($package.id) -or $descriptors.ContainsKey($id) -or -not $lock.ContainsKey($id)) { throw 'Invalid native graph package identity.' }
    $pinned = $lock[$id]
    $checksum = $null
    $sourceLicense = $package.license
    $licenseOrigin = 'Cargo metadata declaration'
    if ($package.source) {
        if ($package.source -cne 'registry+https://github.com/rust-lang/crates.io-index' -or $pinned.source -cne $package.source) { throw 'Unexpected registry source.' }
        $manifest = [IO.Path]::GetFullPath($package.manifest_path)
        Assert-NativeIsarPlainPath $manifest
        if (-not $manifest.StartsWith($vendor + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($manifest) -cne 'Cargo.toml') { throw 'Registry manifest outside pinned vendor.' }
        $checksums = Get-Content -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($manifest)) '.cargo-checksum.json') -Raw | ConvertFrom-Json
        if ($checksums.package -cne $pinned.checksum -or $checksums.package -cnotmatch '^[a-f0-9]{64}$' -or -not $package.license) { throw 'Registry checksum or license declaration missing.' }
        $checksum = $checksums.package
        $origin = $package.source
    } else {
        $paths = @{isar='packages/isar_core_ffi/Cargo.toml';'isar-core'='packages/isar_core/Cargo.toml';'mdbx-sys'='packages/mdbx_sys/Cargo.toml'}
        if (-not $paths.ContainsKey($package.name) -or [IO.Path]::GetFullPath($package.manifest_path) -cne (Join-Path $source $paths[$package.name]).Replace('/','\')) { throw 'Unexpected native path package.' }
        if ($pinned.ContainsKey('source') -or $pinned.ContainsKey('checksum')) { throw 'Path package lock source mismatch.' }
        $origin = 'isar-source@' + $recipe.isar.commit
        if ($package.name -in @('isar','isar-core')) { $sourceLicense='Apache-2.0';$licenseOrigin='inherited pinned project LICENSE; Cargo license undeclared' }
    }
    $ids[$package.id] = $id
    $descriptors[$id] = [ordered]@{id=$id;name=$package.name;version=$package.version;source=$origin;checksum=$checksum;declaredLicense=$package.license;sourceLicense=$sourceLicense;licenseOrigin=$licenseOrigin;features=@();dependencies=@()}
}
$nodeIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($node in $metadata.resolve.nodes) {
    if (-not $ids.ContainsKey($node.id) -or -not $nodeIds.Add($node.id)) { throw 'Native graph node mismatch.' }
    $edges = @()
    foreach ($dependency in $node.deps) {
        if (-not $ids.ContainsKey($dependency.pkg)) { throw 'Native graph dependency missing.' }
        foreach ($kind in $dependency.dep_kinds) {
            $role = $kind.kind
            if (-not $role) { $role='normal' }
            if ($role -notin @('normal','build','dev')) { throw 'Unknown declared dependency role.' }
            $edges += [ordered]@{package=$ids[$dependency.pkg];name=$dependency.name;declaredRole=$role;targetCondition=$kind.target}
        }
    }
    $descriptors[$ids[$node.id]].features = @($node.features | Sort-Object -CaseSensitive)
    $descriptors[$ids[$node.id]].dependencies = @($edges | Sort-Object { $_.package },{ $_.name },{ $_.declaredRole },{ $_.targetCondition } -CaseSensitive)
}
$packageKeys = [string[]]@($descriptors.Keys)
[Array]::Sort($packageKeys,[StringComparer]::Ordinal)
$orderedPackages = @($packageKeys | ForEach-Object { $descriptors[$_] })
$output = Join-Path $Candidate ('graph-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($output) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $output 'licenses')) | Out-Null
foreach ($license in $licenseInputs) {
    $destination = Join-Path $output $license.descriptor.file
    Copy-Item -LiteralPath $license.path -Destination $destination
    if ((Get-NativeIsarDigest $destination) -cne $license.descriptor.sha256) { throw 'Copied supplemental license mismatch.' }
}
Write-NativeIsarJson (Join-Path $output 'native-dependencies.json') ([ordered]@{
    schemaVersion=1; product=$recipe.product; bindingVersion=$recipe.bindingVersion; target=$recipe.target
    state='graph-collected-unqualified'; distributionReady=$false; cargoLockSha256=$recipe.cargoLockSha256
    buildReceiptSha256=Get-NativeIsarDigest $receiptPath; rawMetadataSha256=$receipt.metadata.sha256
    scope='Windows-target filtered Cargo resolution; conservative dependency superset, not exact linked-binary inventory'
    roles='declared edge kinds and target conditions; host/target compilation inferred only by Cargo, not asserted as linker evidence'
    supplementalLicenseTexts=@($licenseInputs | ForEach-Object {$_.descriptor})
    packages=$orderedPackages
    cComponent=[ordered]@{name='libmdbx';commit=$recipe.mdbx.commit;tag=$recipe.mdbx.tag;sourceLicense='Apache-2.0';source='pinned MDBX source LICENSE/COPYRIGHT/NOTICE'}
})
Write-Output $output
