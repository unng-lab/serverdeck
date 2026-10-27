# Build-only corresponding-source input. The expected digest must come from the
# source/artifact manifest, not from a mutable directory's self-description.
function Get-NativeIsarVendorSnapshot {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$ExpectedSha256)
    if ($ExpectedSha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid native vendor digest.' }
    Assert-NativeIsarPlainPath $Root
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw 'Missing native vendor source.' }
    $snapshot = @{}
    [long]$length = 0
    foreach ($entry in Get-ChildItem -LiteralPath $Root -Recurse -Force) {
        Assert-NativeIsarPlainPath $entry.FullName
        if ($entry.PSIsContainer) { continue }
        $relative = [IO.Path]::GetRelativePath($Root,$entry.FullName).Replace('\','/')
        $length += $entry.Length
        if ($snapshot.Count -ge 100000 -or $entry.Length -gt 2GB -or $length -gt 8GB) { throw 'Native vendor inventory exceeds limits.' }
        $snapshot[$relative] = Get-NativeIsarDigest $entry.FullName
    }
    if (-not $snapshot.Count -or (Get-NativeIsarSnapshotDigest $snapshot) -cne $ExpectedSha256) { throw 'Native vendor snapshot digest mismatch.' }
    return $snapshot
}

function Copy-NativeIsarVendorSnapshot {
    param([string]$Source, [string]$Destination, [string]$ExpectedSha256, [hashtable]$Snapshot)
    Assert-NativeIsarPlainPath $Destination
    if (Test-Path -LiteralPath $Destination) { throw 'Native vendor destination already exists.' }
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    foreach ($relative in $Snapshot.Keys) {
        $inputFile = Join-Path $Source $relative
        if ((Get-NativeIsarDigest $inputFile) -cne $Snapshot[$relative]) { throw 'Native vendor source changed during copy.' }
        $outputFile = Join-Path $Destination $relative
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFile)) | Out-Null
        Copy-Item -LiteralPath $inputFile -Destination $outputFile
        if ((Get-NativeIsarDigest $outputFile) -cne $Snapshot[$relative]) { throw 'Native vendor copied bytes mismatch.' }
    }
    Get-NativeIsarVendorSnapshot $Source $ExpectedSha256 | Out-Null
    Get-NativeIsarVendorSnapshot $Destination $ExpectedSha256 | Out-Null
}
