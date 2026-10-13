. "$PSScriptRoot/native-isar-inputs.ps1"
function Get-NativeIsarSupplementInputs {
    param([string]$Directory, [string]$Vendor)
    Assert-NativeIsarPlainPath $Directory
    Assert-NativeIsarPlainPath $Vendor
    $manifestPath = Join-Path $Directory 'supplemental-licenses.json'
    if ((Get-Item -LiteralPath $manifestPath).Length -gt 1MB) { throw 'Supplemental manifest exceeds limit.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $recipe = Get-NativeIsarRecipe
    if ($manifest.schemaVersion -ne 1 -or $manifest.product -cne $recipe.product -or $manifest.bindingVersion -cne $recipe.bindingVersion -or
        $manifest.cargoLockSha256 -cne $recipe.cargoLockSha256 -or $manifest.packages.Count -ne 8 -or $manifest.texts.Count -ne 9) { throw 'Unsupported supplemental license inventory.' }
    $ids = @{}
    $files = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $texts = @()
    foreach ($text in $manifest.texts) {
        if ($text.id -cnotmatch '^[A-Za-z0-9_-]+$' -or $ids.ContainsKey($text.id) -or
            $text.file -cnotmatch '^licenses/supplemental/[A-Za-z0-9_-]+\.txt$' -or -not $files.Add($text.file) -or
            $text.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $text.source -cnotmatch '^https://raw\.githubusercontent\.com/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/[a-f0-9]{40}/[A-Za-z0-9_/.-]+$') { throw 'Unsafe or conflicting supplemental text reference.' }
        $path = Join-Path $Directory $text.file
        if ((Get-NativeIsarDigest $path) -cne $text.sha256) { throw 'Supplemental license text hash mismatch.' }
        $bytes = [IO.File]::ReadAllBytes($path)
        if ($bytes.Length -gt 1MB -or -not [Text.UTF8Encoding]::new($false,$true).GetString($bytes).Trim()) { throw 'Invalid supplemental license text.' }
        $ids[$text.id] = $text
        $texts += @{descriptor=$text;path=$path}
    }
    $packageIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($package in $manifest.packages) {
        if ($package.name -cnotmatch '^[A-Za-z0-9_-]+$' -or $package.vendorDirectory -cne $package.name -or
            -not $packageIds.Add($package.name + '@' + $package.version)) { throw 'Invalid supplemental package identity.' }
        $root = Join-Path $Vendor $package.vendorDirectory
        $toml = Join-Path $root 'Cargo.toml'
        if ((Get-NativeIsarDigest $toml) -cne $package.manifestSha256) { throw 'Supplemental package manifest mismatch.' }
        $checksums = Get-Content -LiteralPath (Join-Path $root '.cargo-checksum.json') -Raw | ConvertFrom-Json
        if ($checksums.package -cne $package.registryChecksum) { throw 'Supplemental registry checksum mismatch.' }
        $raw = [IO.File]::ReadAllText($toml)
        foreach ($field in @('name','version','license')) {
            $value = [Regex]::Match($raw,'(?m)^' + $field + '\s*=\s*"([^"\r\n]+)"').Groups[1].Value
            if ($field -eq 'license') { $expected = $package.declaredLicense }
            else { $expected = $package.$field }
            if ($value -cne $expected) { throw 'Supplemental declared package metadata mismatch.' }
        }
        $authorsField = [Regex]::Match($raw,'(?ms)^authors\s*=\s*\[(.*?)\]')
        $authors = @([Regex]::Matches($authorsField.Groups[1].Value,'"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        if ((ConvertTo-Json -InputObject $authors -Compress) -cne (ConvertTo-Json -InputObject @($package.declaredAuthors) -Compress)) { throw 'Supplemental authors metadata mismatch.' }
        if (-not $package.textIds.Count) { throw 'Supplemental package has no text.' }
        foreach ($id in $package.textIds) { if (-not $ids.ContainsKey($id)) { throw 'Supplemental text reference missing.' } }
    }
    return @{manifest=$manifest;manifestPath=$manifestPath;manifestSha256=Get-NativeIsarDigest $manifestPath;texts=$texts}
}
