# Build-only exact-input ZIP writer. Callers select the corresponding-source
# allowlist; a failed, freshly created archive is retained as diagnostic evidence.
function Write-NativeIsarSourceArchive {
    param([Parameter(Mandatory)][string]$Destination, [Parameter(Mandatory)][object[]]$Files)
    Assert-NativeIsarPlainPath $Destination
    if (Test-Path -LiteralPath $Destination) { throw 'Native source archive output already exists.' }
    if (-not $Files.Count -or $Files.Count -gt 100000) { throw 'Native source archive inventory exceeds limits.' }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $inputs = @{}
    [long]$total = 0
    foreach ($file in $Files) {
        Assert-NativeIsarArchiveName $file.file ([IO.Path]::GetDirectoryName($Destination)) $names
        if ($file.file.EndsWith('/') -or $file.sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid native source archive entry.' }
        if ((Get-NativeIsarDigest $file.path) -cne $file.sha256) { throw 'Native source archive input digest mismatch.' }
        $length = (Get-Item -LiteralPath $file.path -Force).Length
        $total += $length
        if ($length -gt 2GB -or $total -gt 8GB) { throw 'Native source archive byte budget exceeded.' }
        $inputs[$file.file] = $file
    }
    $orderedNames = [string[]]@($inputs.Keys)
    [Array]::Sort($orderedNames,[StringComparer]::Ordinal)
    $stream = [IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true,[Text.UTF8Encoding]::new($false))
        try {
            foreach ($name in $orderedNames) {
                $file = $inputs[$name]
                if ((Get-NativeIsarDigest $file.path) -cne $file.sha256) { throw 'Native source archive input changed.' }
                $entry = $archive.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
                $entry.ExternalAttributes = 0
                $input = [IO.File]::Open($file.path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
                try {
                    $output = $entry.Open()
                    try { $input.CopyTo($output) } finally { $output.Dispose() }
                } finally { $input.Dispose() }
                if ((Get-NativeIsarDigest $file.path) -cne $file.sha256) { throw 'Native source archive input changed.' }
            }
        } finally { $archive.Dispose() }
    } finally { $stream.Dispose() }
}
