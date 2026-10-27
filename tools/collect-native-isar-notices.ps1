[CmdletBinding()]
param([Parameter(Mandatory)][string]$Candidate, [Parameter(Mandatory)][string]$SupplementDirectory, [Parameter(Mandatory)][string]$RustDirectory)
. "$PSScriptRoot/native-isar-supplement-inputs.ps1"
$Candidate = [IO.Path]::GetFullPath($Candidate)
$graphDirectory = & "$PSScriptRoot/collect-native-isar-graph.ps1" -Candidate $Candidate
$buildHash = Get-NativeIsarDigest (Join-Path $Candidate 'native-build.json')
$graphHash = Get-NativeIsarDigest (Join-Path $graphDirectory 'native-dependencies.json')
$graph = Get-Content (Join-Path $graphDirectory 'native-dependencies.json') -Raw | ConvertFrom-Json
$recipe = Get-NativeIsarRecipe
$source = Join-Path $Candidate ('source/isar-community-' + $recipe.isar.commit)
$mdbx = Join-Path $Candidate ('mdbx/libmdbx-' + $recipe.mdbx.commit)
$vendor = Join-Path $Candidate 'vendor'
$supplements = Get-NativeIsarSupplementInputs (Join-Path $NativeIsarRepository 'native/isar-3.3.2') $vendor
$SupplementDirectory = [IO.Path]::GetFullPath($SupplementDirectory)
$RustDirectory = [IO.Path]::GetFullPath($RustDirectory)
foreach ($child in @(@{path=$SupplementDirectory;prefix='supplements'},@{path=$RustDirectory;prefix='rust-material'})) {
    if ([IO.Path]::GetDirectoryName($child.path) -cne $Candidate -or [IO.Path]::GetFileName($child.path) -cnotmatch ('^' + $child.prefix + '-[a-f0-9]{32}$')) { throw 'Native notices require owned component outputs.' }
    Assert-NativeIsarPlainPath $child.path
}
$supplementReceipt = Get-Content (Join-Path $SupplementDirectory 'supplemental-receipt.json') -Raw | ConvertFrom-Json
$rustReceipt = Get-Content (Join-Path $RustDirectory 'rust-material-receipt.json') -Raw | ConvertFrom-Json
foreach ($item in @(@{receipt=$supplementReceipt;state='supplements-collected-unqualified'},@{receipt=$rustReceipt;state='rust-material-collected-unqualified'})) {
    if ($item.receipt.schemaVersion -ne 1 -or $item.receipt.product -cne $recipe.product -or $item.receipt.bindingVersion -cne $recipe.bindingVersion -or
        $item.receipt.state -cne $item.state -or $item.receipt.distributionReady -ne $false -or $item.receipt.buildReceiptSha256 -cne $buildHash -or $item.receipt.graphSha256 -cne $graphHash) { throw 'Native notice component receipt mismatch.' }
}
if ($supplementReceipt.supplementalManifestSha256 -cne $supplements.manifestSha256 -or
    (Get-NativeIsarDigest (Join-Path $SupplementDirectory 'supplemental-licenses.json')) -cne $supplements.manifestSha256) { throw 'Native supplemental manifest mismatch.' }
$rustManifestPath = Join-Path $NativeIsarRepository 'native/isar-3.3.2/rust-license-material.json'
$rustManifestHash = Get-NativeIsarDigest $rustManifestPath
if ($rustReceipt.inputManifestSha256 -cne $rustManifestHash -or (Get-NativeIsarDigest (Join-Path $RustDirectory 'rust-license-material.json')) -cne $rustManifestHash) { throw 'Native Rust manifest mismatch.' }
$build = Get-Content (Join-Path $Candidate 'native-build.json') -Raw | ConvertFrom-Json
if ($rustReceipt.compiledRustTreeDigest -cne $build.inputDigests.rust) { throw 'Native Rust SDK binding mismatch.' }
$rustManifest = Get-Content $rustManifestPath -Raw | ConvertFrom-Json
foreach ($item in @(@{receipt=$supplementReceipt;root=$SupplementDirectory;file='SUPPLEMENTAL_NATIVE_NOTICES.txt'},@{receipt=$rustReceipt;root=$RustDirectory;file='RUST_NATIVE_NOTICES.txt'})) {
    if ($item.receipt.notice.file -cne $item.file -or (Get-NativeIsarDigest (Join-Path $item.root $item.file)) -cne $item.receipt.notice.sha256) { throw 'Native component notice mismatch.' }
}
$texts = @()
function Add-NativeNoticeInput {
    param([string]$Path,[string]$Destination,[string]$Role,[string]$ExpectedHash='')
    $digest = Get-NativeIsarDigest $Path
    if ($ExpectedHash -and $digest -cne $ExpectedHash) { throw 'Native notice text hash mismatch.' }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -gt 32MB -or -not [Text.UTF8Encoding]::new($false,$true).GetString($bytes).Trim()) { throw 'Invalid native notice text.' }
    $script:texts += @{path=$Path;file=$Destination;role=$Role;sha256=$digest;length=$bytes.Length}
}
$lock = @{}
foreach ($block in ([IO.File]::ReadAllText((Join-Path $source 'Cargo.lock')) -split '\[\[package\]\]') | Select-Object -Skip 1) {
    $fields = @{}
    foreach ($field in @('name','version','source','checksum')) {
        $match = [Regex]::Match($block,'(?m)^' + $field + ' = "([^"\r\n]+)"\r?$')
        if ($match.Success) { $fields[$field] = $match.Groups[1].Value }
    }
    if ($fields.ContainsKey('source')) { $lock[$fields.name + '@' + $fields.version] = $fields }
}
$packages = @()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($directory in Get-ChildItem -LiteralPath $vendor -Directory | Sort-Object Name -CaseSensitive) {
    Assert-NativeIsarPlainPath $directory.FullName
    $toml = [IO.File]::ReadAllText((Join-Path $directory.FullName 'Cargo.toml'))
    $name = [Regex]::Match($toml,'(?m)^name\s*=\s*"([^"]+)"').Groups[1].Value
    $version = [Regex]::Match($toml,'(?m)^version\s*=\s*"([^"]+)"').Groups[1].Value
    $license = [Regex]::Match($toml,'(?m)^license\s*=\s*"([^"]+)"').Groups[1].Value
    $id = $name + '@' + $version
    $checksums = Get-Content (Join-Path $directory.FullName '.cargo-checksum.json') -Raw | ConvertFrom-Json
    if (-not $seen.Add($id) -or -not $lock.ContainsKey($id) -or $checksums.package -cne $lock[$id].checksum -or -not $license) { throw 'Native vendor license inventory mismatch.' }
    $noticeFiles = @(Get-ChildItem -LiteralPath $directory.FullName -Recurse -File | Where-Object { $_.Name -match '^(LICENSE|LICENCE|COPYING|COPYRIGHT|NOTICE)' })
    $references = @()
    foreach ($file in $noticeFiles | Sort-Object FullName -CaseSensitive) {
        $relative = [IO.Path]::GetRelativePath($directory.FullName,$file.FullName).Replace('\','/')
        $destination = 'licenses/vendor/' + $directory.Name + '/' + $relative
        Add-NativeNoticeInput $file.FullName $destination ('vendor source ' + $id)
        $references += $destination
    }
    if (-not $noticeFiles.Count) {
        $supplement = @($supplements.manifest.packages | Where-Object { $_.name -ceq $name -and $_.version -ceq $version })
        if ($supplement.Count -ne 1) { throw 'Vendor source license text missing without a pinned supplement.' }
        foreach ($textId in $supplement[0].textIds) {
            $references += @($supplements.texts | Where-Object { $_.descriptor.id -ceq $textId })[0].descriptor.file
        }
    }
    $packages += [ordered]@{id=$id;declaredLicense=$license;registryChecksum=$checksums.package;scope='full vendor source inventory; may be outside Windows link scope';textFiles=$references}
}
if ($seen.Count -ne $lock.Count) { throw 'Native vendor source inventory does not cover locked registry packages.' }
Add-NativeNoticeInput (Join-Path $source 'LICENSE') 'licenses/isar/LICENSE' 'pinned project Apache license; inherited root crate attribution'
foreach ($file in @('LICENSE','COPYRIGHT','NOTICE')) { Add-NativeNoticeInput (Join-Path $mdbx $file) ('licenses/libmdbx/' + $file) 'separate pinned C libmdbx source' }
Add-NativeNoticeInput (Join-Path $graphDirectory 'licenses/MPL-2.0.txt') 'licenses/MPL-2.0.txt' 'native Rust MDBX binding declaration' $recipe.licenseTexts[0].sha256
foreach ($text in $supplements.texts) { Add-NativeNoticeInput (Join-Path $SupplementDirectory $text.descriptor.file) $text.descriptor.file 'supplemental source text; retain origin and template policy' $text.descriptor.sha256 }
foreach ($file in $rustManifest.files) { Add-NativeNoticeInput (Join-Path $RustDirectory $file.destination) $file.destination $file.role $file.sha256 }
$destinations = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[long]$total = 0
foreach ($text in $texts) {
    $safe = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    Assert-NativeIsarArchiveName $text.file $Candidate $safe
    if (-not $destinations.Add($text.file)) { throw 'Conflicting native notice destinations.' }
    $total += $text.length
}
if ($total -gt 64MB) { throw 'Native notice material exceeds total bound.' }
$output = Join-Path $Candidate ('notices-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($output) | Out-Null
$notice = [Text.StringBuilder]::new()
[void]$notice.AppendLine('ServerDeck native source/runtime license material; unqualified artifact input.')
[void]$notice.AppendLine('Conservative full vendor source inventory plus runtime/build-tool catalogues; not an exact binary linker map.')
[void]$notice.AppendLine('Corresponding sources and compatibility qualification are separate unfinished gates.')
[void]$notice.AppendLine($supplements.manifest.canonicalTemplatePolicy)
foreach ($package in $packages | Sort-Object { $_.id } -CaseSensitive) { [void]$notice.AppendLine($package.id + ' | declared ' + $package.declaredLicense + ' | ' + ($package.textFiles -join ', ')) }
foreach ($package in $supplements.manifest.packages | Sort-Object name -CaseSensitive) {
    [void]$notice.AppendLine($package.name + '@' + $package.version + ' | text origin: ' + $package.licenseTextOrigin + ' | published authors metadata: ' + ($package.declaredAuthors -join ', '))
}
foreach ($text in $texts | Sort-Object { $_.file } -CaseSensitive) {
    $destination = Join-Path $output $text.file
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    Copy-Item -LiteralPath $text.path -Destination $destination
    if ((Get-NativeIsarDigest $destination) -cne $text.sha256) { throw 'Copied aggregate native text mismatch.' }
    [void]$notice.AppendLine().AppendLine('--- ' + $text.file + ' ---').AppendLine('Role: ' + $text.role)
    if (-not $text.file.EndsWith('.html',[StringComparison]::Ordinal)) { [void]$notice.AppendLine([IO.File]::ReadAllText($destination)) }
    else { [void]$notice.AppendLine('Full exact HTML catalogue is supplied at this relative file path.') }
}
$noticePath = Join-Path $output 'THIRD_PARTY_NATIVE_NOTICES.txt'
[IO.File]::WriteAllText($noticePath,$notice.ToString(),[Text.UTF8Encoding]::new($false))
foreach ($file in @('supplemental-licenses.json','rust-license-material.json')) {
    Copy-Item -LiteralPath (Join-Path $NativeIsarRepository ('native/isar-3.3.2/' + $file)) -Destination (Join-Path $output $file)
    $expected = $rustManifestHash
    if ($file -eq 'supplemental-licenses.json') { $expected=$supplements.manifestSha256 }
    if ((Get-NativeIsarDigest (Join-Path $output $file)) -cne $expected) { throw 'Copied aggregate native input manifest mismatch.' }
}
Write-NativeIsarJson (Join-Path $output 'native-notice-inventory.json') ([ordered]@{
    schemaVersion=1;product=$recipe.product;bindingVersion=$recipe.bindingVersion;state='notices-collected-unqualified';distributionReady=$false
    buildReceiptSha256=$buildHash;graphSha256=$graphHash;supplementManifestSha256=$supplements.manifestSha256;rustManifestSha256=$rustManifestHash
    notice=[ordered]@{file='THIRD_PARTY_NATIVE_NOTICES.txt';sha256=Get-NativeIsarDigest $noticePath}
    packages=@($packages | Sort-Object { $_.id } -CaseSensitive)
    files=@($texts | Sort-Object { $_.file } -CaseSensitive | ForEach-Object { [ordered]@{file=$_.file;sha256=$_.sha256;length=$_.length;role=$_.role} })
})
Write-Output $output
