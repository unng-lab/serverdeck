. "$PSScriptRoot/native-isar-inputs.ps1"

function ConvertTo-NativeIsarCanonicalValue {
    param([AllowNull()][object]$Value)
    if ($Value -is [Collections.IDictionary] -or $Value -is [pscustomobject]) {
        $keys = [string[]]@()
        if ($Value -is [Collections.IDictionary]) { $keys = [string[]]@($Value.Keys) } else { $keys = [string[]]@($Value.psobject.Properties | ForEach-Object {$_.Name}) }
        [Array]::Sort($keys,[StringComparer]::Ordinal)
        $result = [ordered]@{}
        foreach ($key in $keys) {
            $item = $null
            if ($Value -is [Collections.IDictionary]) { $item = $Value[$key] } else { $item = $Value.$key }
            $result[$key] = ConvertTo-NativeIsarCanonicalValue $item
        }
        return $result
    }
    if ($Value -is [Array]) {
        $items = [Collections.Generic.List[object]]::new()
        foreach ($item in $Value) { $items.Add((ConvertTo-NativeIsarCanonicalValue $item)) }
        return ,$items.ToArray()
    }
    return $Value
}

function Get-NativeIsarCanonicalDigest {
    param([Parameter(Mandatory)][object]$Value)
    $json = ConvertTo-Json -InputObject (ConvertTo-NativeIsarCanonicalValue $Value) -Depth 64 -Compress
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($json))).ToLowerInvariant()
}

function Read-NativeIsarArtifactJson {
    param([string]$Path)
    Assert-NativeIsarPlainPath $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).Length -gt 1MB) { throw 'Missing or oversized native artifact JSON.' }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-NativeIsarCandidateArtifact {
    param([Parameter(Mandatory)][string]$Directory)
    $Directory = [IO.Path]::GetFullPath($Directory,(Get-Location).ProviderPath)
    $candidate = [IO.Path]::GetDirectoryName($Directory)
    if ([IO.Path]::GetDirectoryName($candidate) -cne (Join-Path $NativeIsarRepository '.local/native-isar') -or
        [IO.Path]::GetFileName($candidate) -cnotmatch '^candidate-[a-f0-9]{32}$' -or
        [IO.Path]::GetFileName($Directory) -cnotmatch '^artifact-[a-f0-9]{32}$') { throw 'Expected an owned unqualified native artifact.' }
    Assert-NativeIsarPlainPath $Directory
    $manifestPath = Join-Path $Directory 'native-artifact.json'
    $manifest = Read-NativeIsarArtifactJson $manifestPath
    $recipe = Get-NativeIsarRecipe
    if ($manifest.schemaVersion -ne 1 -or $manifest.product -cne $recipe.product -or $manifest.bindingVersion -cne $recipe.bindingVersion -or
        $manifest.target -cne $recipe.target -or $manifest.state -cne 'artifact-assembled-unqualified' -or $manifest.distributionReady -ne $false -or
        $manifest.recipeSha256 -cne (Get-NativeIsarCanonicalDigest $recipe) -or $manifest.cargoLockSha256 -cne $recipe.cargoLockSha256) { throw 'Native artifact identity mismatch.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (@($manifest.files).Count -ne 197) { throw 'Native artifact file inventory mismatch.' }
    $files = @{}
    foreach ($file in $manifest.files) {
        Assert-NativeIsarArchiveName $file.file $Directory $seen
        if (($file.length -isnot [int] -and $file.length -isnot [long]) -or $file.length -lt 0 -or $file.length -gt 8GB) { throw 'Native artifact payload length exceeds limits.' }
        if ($file.file -ceq 'native-artifact.json' -or $file.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
            (Get-NativeIsarDigest (Join-Path $Directory $file.file)) -cne $file.sha256 -or
            (Get-Item -LiteralPath (Join-Path $Directory $file.file)).Length -ne $file.length) { throw 'Native artifact payload mismatch.' }
        $files[$file.file] = $file
    }
    foreach ($entry in Get-ChildItem -LiteralPath $Directory -Recurse -Force) {
        Assert-NativeIsarPlainPath $entry.FullName
        if ($entry.PSIsContainer) { continue }
        $relative=[IO.Path]::GetRelativePath($Directory,$entry.FullName).Replace('\','/')
        if ($relative -cne 'native-artifact.json' -and -not $files.ContainsKey($relative)) { throw 'Native artifact contains an unlisted payload.' }
    }
    $fixed = @('libisar.dll','native-build.json','recipe.json','Cargo.lock','mdbx-patch.json','native-dependencies.json','native-notice-inventory.json',
        'THIRD_PARTY_NATIVE_NOTICES.txt','native-source-receipt.json','source-reproduction.json','NATIVE_SOURCES.zip','REPRODUCE.txt','supplemental-licenses.json','rust-license-material.json')
    foreach ($name in $fixed) { if (-not $files.ContainsKey($name)) { throw 'Native artifact required payload missing.' } }
    if ($files['native-build.json'].sha256 -cne (Get-NativeIsarDigest (Join-Path $candidate 'native-build.json')) -or
        $files['libisar.dll'].sha256 -cne (Get-NativeIsarDigest (Join-Path $candidate 'libisar.dll'))) { throw 'Native artifact parent build mismatch.' }
    $build = Read-NativeIsarArtifactJson (Join-Path $Directory 'native-build.json')
    $source = Read-NativeIsarArtifactJson (Join-Path $Directory 'native-source-receipt.json')
    $reproduction = Read-NativeIsarArtifactJson (Join-Path $Directory 'source-reproduction.json')
    $notices = Read-NativeIsarArtifactJson (Join-Path $Directory 'native-notice-inventory.json')
    $graph = Read-NativeIsarArtifactJson (Join-Path $Directory 'native-dependencies.json')
    $copiedRecipe = Read-NativeIsarArtifactJson (Join-Path $Directory 'recipe.json')
    if ($files['recipe.json'].sha256 -cne $build.recipeFileSha256 -or (Get-NativeIsarCanonicalDigest $copiedRecipe) -cne $manifest.recipeSha256 -or
        $files['Cargo.lock'].sha256 -cne $recipe.cargoLockSha256 -or $files['libisar.dll'].sha256 -cne $build.dll.sha256 -or
        $files['mdbx-patch.json'].sha256 -cne $build.patch.sha256 -or $files['native-build.json'].sha256 -cne $manifest.buildReceiptSha256 -or
        $source.buildReceiptSha256 -cne $manifest.buildReceiptSha256 -or $notices.buildReceiptSha256 -cne $manifest.buildReceiptSha256 -or
        $graph.buildReceiptSha256 -cne $manifest.buildReceiptSha256 -or $reproduction.buildReceiptSha256 -cne $manifest.buildReceiptSha256 -or
        $source.graphSha256 -cne $files['native-dependencies.json'].sha256 -or $notices.graphSha256 -cne $source.graphSha256 -or
        $reproduction.graphSha256 -cne $source.graphSha256 -or $source.noticeInventorySha256 -cne $files['native-notice-inventory.json'].sha256 -or
        $reproduction.noticeInventorySha256 -cne $source.noticeInventorySha256 -or $source.reproductionManifestSha256 -cne $files['source-reproduction.json'].sha256 -or
        $source.sourceArchive.file -cne 'NATIVE_SOURCES.zip' -or $source.sourceArchive.sha256 -cne $files['NATIVE_SOURCES.zip'].sha256 -or
        $source.sourceArchive.length -ne $files['NATIVE_SOURCES.zip'].length -or $source.sourceArchive.fileCount -ne 8107 -or
        $notices.notice.file -cne 'THIRD_PARTY_NATIVE_NOTICES.txt' -or $notices.notice.sha256 -cne $files['THIRD_PARTY_NATIVE_NOTICES.txt'].sha256 -or
        $notices.supplementManifestSha256 -cne $files['supplemental-licenses.json'].sha256 -or $notices.rustManifestSha256 -cne $files['rust-license-material.json'].sha256) { throw 'Native artifact provenance chain mismatch.' }
    if ($notices.files.Count -ne 183 -or $notices.packages.Count -ne 91 -or $graph.packages.Count -ne 67 -or
        $build.state -cne 'built-unqualified' -or $source.state -cne 'sources-collected-unqualified' -or
        $notices.state -cne 'notices-collected-unqualified' -or $graph.state -cne 'graph-collected-unqualified' -or
        $reproduction.state -cne 'sources-collected-unqualified' -or $reproduction.distributionReady -isnot [bool] -or $reproduction.distributionReady -ne $false -or
        $build.distributionReady -ne $false -or $source.distributionReady -ne $false -or $notices.distributionReady -ne $false -or $graph.distributionReady -ne $false) { throw 'Native artifact component state mismatch.' }
    $noticeNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $notices.files) {
        if ($item.file -cnotmatch '^licenses/' -or -not $noticeNames.Add($item.file) -or -not $files.ContainsKey($item.file) -or
            $files[$item.file].sha256 -cne $item.sha256 -or $files[$item.file].length -ne $item.length) { throw 'Native artifact notice inventory mismatch.' }
    }
    if ($manifest.source.isarCommit -cne $recipe.isar.commit -or $manifest.source.mdbxCommit -cne $recipe.mdbx.commit -or
        $manifest.source.isarArchiveSha256 -cne $recipe.isar.sha256 -or $manifest.source.mdbxArchiveSha256 -cne $recipe.mdbx.sha256 -or
        $manifest.source.patchSha256 -cne $build.patch.sha256 -or $manifest.compilation.command -cne $build.command -or
        $manifest.compilation.features -cne $build.features -or -not $manifest.compilation.offlineCompilation -or
        (Get-NativeIsarCanonicalDigest $manifest.compilation.rust) -cne (Get-NativeIsarCanonicalDigest $build.compiler) -or
        (Get-NativeIsarCanonicalDigest $manifest.compilation.msvc) -cne (Get-NativeIsarCanonicalDigest $build.msvc) -or
        $manifest.compilation.libclangVersion -cne $build.libclangVersion -or
        (Get-NativeIsarCanonicalDigest $manifest.compiledInputDigests) -cne (Get-NativeIsarCanonicalDigest $build.inputDigests) -or
        $reproduction.sourceSha256 -cne $build.inputDigests.source -or $reproduction.mdbxSha256 -cne $build.inputDigests.mdbx -or
        $reproduction.vendorSha256 -cne $build.inputDigests.vendor -or $reproduction.patchSha256 -cne $build.patch.sha256 -or
        $reproduction.recipeFileSha256 -cne $build.recipeFileSha256 -or $reproduction.cargoLockSha256 -cne $recipe.cargoLockSha256 -or
        $reproduction.rootPathCharacterLimit -ne 80) { throw 'Native artifact compiled input mismatch.' }
    foreach ($component in @($build,$source,$reproduction,$notices,$graph)) {
        if ($component.schemaVersion -ne 1 -or $component.product -cne $recipe.product -or $component.bindingVersion -cne $recipe.bindingVersion -or
            ($component.psobject.Properties['target'] -and $component.target -cne $recipe.target)) { throw 'Native artifact component identity mismatch.' }
    }
    # Bind outside copies to the exact corresponding-source ZIP, not only to
    # mutable sidecars describing it. Never extract while validating a provider.
    $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $Directory 'NATIVE_SOURCES.zip'))
    try {
        if ($archive.Entries.Count -ne 8107) { throw 'Native artifact source archive inventory mismatch.' }
        $zipNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        [long]$expandedLength=0
        foreach ($entry in $archive.Entries) {
            Assert-NativeIsarArchiveName $entry.FullName $Directory $zipNames
            if ($entry.FullName.EndsWith('/') -or $entry.ExternalAttributes -ne 0) { throw 'Unexpected native artifact source entry type.' }
            if ($entry.Length -lt 0 -or $entry.Length -gt 2GB) { throw 'Native artifact source archive resource limit exceeded.' }
            $expandedLength += $entry.Length
            if ($expandedLength -gt 8GB) { throw 'Native artifact source archive resource limit exceeded.' }
        }
        $references = @{}
        foreach ($name in @('mdbx-patch.json','native-dependencies.json','native-notice-inventory.json','THIRD_PARTY_NATIVE_NOTICES.txt','source-reproduction.json','REPRODUCE.txt')) { $references[$name]=$files[$name].sha256 }
        foreach ($name in @('recipe.json','Cargo.lock','supplemental-licenses.json','rust-license-material.json')) { $references['native/isar-3.3.2/' + $name]=$files[$name].sha256 }
        foreach ($item in $notices.files) { $references[$item.file]=$item.sha256 }
        if (@($reproduction.tools).Count -ne 5) { throw 'Native artifact reproduction tools mismatch.' }
        $requiredTools = @('tools/native-isar-inputs.ps1','tools/native-isar-vendor-inputs.ps1','tools/prepare-native-isar.ps1','tools/build-native-isar.ps1','tools/reproduce-native-isar.ps1')
        $toolNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($tool in $reproduction.tools) {
            if ($tool.file -cnotin $requiredTools -or -not $toolNames.Add($tool.file) -or
                (Get-NativeIsarDigest (Join-Path $NativeIsarRepository $tool.file)) -cne $tool.sha256) { throw 'Native artifact reproduction tool drift.' }
            $references[$tool.file]=$tool.sha256
        }
        $references['archives/isar-3.3.2-source.zip']=$recipe.isar.sha256
        $references['archives/libmdbx-source.zip']=$recipe.mdbx.sha256
        $references['source.materialized-links.json']=Get-NativeIsarDigest (Join-Path $candidate 'source.materialized-links.json')
        $supplement=Read-NativeIsarArtifactJson (Join-Path $NativeIsarRepository 'native/isar-3.3.2/supplemental-licenses.json')
        if ($files['supplemental-licenses.json'].sha256 -cne (Get-NativeIsarDigest (Join-Path $NativeIsarRepository 'native/isar-3.3.2/supplemental-licenses.json'))) { throw 'Native artifact supplemental manifest drift.' }
        foreach ($item in @($recipe.licenseTexts) + @($supplement.texts)) { $references['native/isar-3.3.2/' + $item.file]=$item.sha256 }
        $trees=@(
            @{prefix='source/isar-community-' + $recipe.isar.commit + '/';sha256=$build.inputDigests.source;count=738;snapshot=@{}},
            @{prefix='mdbx/libmdbx-' + $recipe.mdbx.commit + '/';sha256=$build.inputDigests.mdbx;count=192;snapshot=@{}},
            @{prefix='vendor/';sha256=$build.inputDigests.vendor;count=6966;snapshot=@{}}
        )
        foreach ($entry in $archive.Entries) {
            $tree=$null
            foreach ($item in $trees) { if ($entry.FullName.StartsWith($item.prefix,[StringComparison]::Ordinal)) { $tree=$item;break } }
            if (-not $tree -and -not $references.ContainsKey($entry.FullName)) { throw 'Native artifact source archive contains an unlisted payload.' }
            if ($tree) {
                $stream=$entry.Open()
                try { $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant() } finally { $stream.Dispose() }
                $tree.snapshot[$entry.FullName.Substring($tree.prefix.Length)]=$hash
            }
        }
        foreach ($tree in $trees) {
            if ($tree.snapshot.Count -ne $tree.count -or (Get-NativeIsarSnapshotDigest $tree.snapshot) -cne $tree.sha256) { throw 'Native artifact source archive compiled-input tree mismatch.' }
        }
        foreach ($name in $references.Keys) {
            $entry=$archive.GetEntry($name)
            if (-not $entry) { throw 'Native artifact embedded source reference missing.' }
            $stream=$entry.Open()
            try { $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant() } finally { $stream.Dispose() }
            if ($hash -cne $references[$name]) { throw 'Native artifact embedded source reference mismatch.' }
        }
    } finally { $archive.Dispose() }
    return [pscustomobject]@{directory=$Directory;manifest=$manifest;manifestSha256=Get-NativeIsarDigest $manifestPath;dll=Join-Path $Directory 'libisar.dll'}
}
