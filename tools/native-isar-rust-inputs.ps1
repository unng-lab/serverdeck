. "$PSScriptRoot/native-isar-inputs.ps1"
function Get-NativeIsarRustMaterials {
    param([string]$PreparedDirectory, [string]$ExpectedRustDigest)
    Assert-NativeIsarPlainPath $PreparedDirectory
    $manifestPath = Join-Path $NativeIsarRepository 'native/isar-3.3.2/rust-license-material.json'
    Assert-NativeIsarPlainPath $manifestPath
    if ((Get-Item -LiteralPath $manifestPath).Length -gt 1MB) { throw 'Rust material manifest exceeds limit.' }
    $manifestDigest = Get-NativeIsarDigest $manifestPath
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $recipe = Get-NativeIsarRecipe
    if ($manifest.schemaVersion -ne 1 -or $manifest.product -cne $recipe.product -or $manifest.bindingVersion -cne $recipe.bindingVersion -or
        $manifest.rustVersion -cne $recipe.rust.version -or $manifest.target -cne $recipe.target -or $manifest.files.Count -ne 8 -or $manifest.archives.Count -ne 3 -or
        $ExpectedRustDigest -cnotmatch '^[a-f0-9]{64}$') { throw 'Unsupported Rust material inputs.' }
    $archiveNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($archive in $manifest.archives) {
        $pinned = @($recipe.rust.components | Where-Object name -CEQ $archive.name)
        if ($pinned.Count -ne 1 -or -not $archiveNames.Add($archive.name) -or $archive.url -cne $pinned[0].url -or $archive.sha256 -cne $pinned[0].sha256) { throw 'Rust material archive identity mismatch.' }
        $fileName = [IO.Path]::GetFileName(([Uri]$archive.url).AbsolutePath)
        if ((Get-NativeIsarDigest (Join-Path $PreparedDirectory ('archives/' + $fileName))) -cne $archive.sha256) { throw 'Rust material archive hash mismatch.' }
    }
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $destinations = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $materials = @()
    [long]$total = 0
    foreach ($file in $manifest.files) {
        if (-not $ids.Add($file.id) -or -not $archiveNames.Contains($file.sourceArchive) -or
            $file.sourceRelative -cnotmatch '^rust-(rustc|rust-std|cargo)/[A-Za-z0-9_.-]+/[A-Za-z0-9_/.-]+$' -or
            $file.destination -cnotmatch '^licenses/rust/(runtime|build-tools)/[A-Za-z0-9_.-]+$' -or
            -not $destinations.Add($file.destination) -or $file.sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Unsafe Rust material reference.' }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        Assert-NativeIsarArchiveName $file.sourceRelative $PreparedDirectory $seen
        $path = Join-Path $PreparedDirectory $file.sourceRelative
        if ((Get-NativeIsarDigest $path) -cne $file.sha256) { throw 'Rust license material hash mismatch.' }
        $bytes = [IO.File]::ReadAllBytes($path)
        $total += $bytes.Length
        if ($bytes.Length -ne $file.length -or $total -gt 64MB -or -not [Text.UTF8Encoding]::new($false,$true).GetString($bytes).Trim()) { throw 'Invalid Rust license material.' }
        $materials += @{descriptor=$file;path=$path}
    }
    # The same assembled SDK bytes, including the std libraries, must match the build receipt.
    $rust = Join-Path $PreparedDirectory 'rust'
    Assert-NativeIsarPlainPath $rust
    $snapshot = @{}
    foreach ($file in Get-ChildItem -LiteralPath $rust -Recurse -File -Force) {
        $relative = [IO.Path]::GetRelativePath($rust,$file.FullName).Replace('\','/')
        $snapshot[$relative] = Get-NativeIsarDigest $file.FullName
    }
    if ((Get-NativeIsarSnapshotDigest $snapshot) -cne $ExpectedRustDigest) { throw 'Rust license SDK differs from the compiled SDK.' }
    if ((Get-NativeIsarDigest $manifestPath) -cne $manifestDigest) { throw 'Rust material manifest changed during validation.' }
    return @{manifest=$manifest;manifestPath=$manifestPath;manifestSha256=$manifestDigest;materials=$materials;rustDigest=$ExpectedRustDigest}
}
