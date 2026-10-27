Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$NativeIsarRepository = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))

function Assert-NativeIsarPlainPath {
    param([Parameter(Mandatory)][string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Native input path contains a reparse point.'
            }
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Get-NativeIsarDigest {
    param([Parameter(Mandatory)][string]$Path)
    Assert-NativeIsarPlainPath $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Missing native input file.' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-NativeIsarRecipe {
    $recipePath = Join-Path $NativeIsarRepository 'native/isar-3.3.2/recipe.json'
    Assert-NativeIsarPlainPath $recipePath
    $recipe = Get-Content -LiteralPath $recipePath -Raw | ConvertFrom-Json
    if ($recipe.schemaVersion -ne 1 -or $recipe.product -cne 'serverdeck-isar-native' -or
        $recipe.bindingVersion -cne '3.3.2' -or $recipe.target -cne 'x86_64-pc-windows-msvc') {
        throw 'Unsupported native recipe.'
    }
    if ((Get-NativeIsarDigest (Join-Path $NativeIsarRepository 'native/isar-3.3.2/Cargo.lock')) -cne $recipe.cargoLockSha256) {
        throw 'Native Cargo.lock digest mismatch.'
    }
    return $recipe
}

function Assert-NativeIsarArchiveName {
    param([string]$Name, [string]$Destination, [Collections.Generic.HashSet[string]]$Seen)
    if (-not $Name -or $Name.Contains('\') -or $Name.StartsWith('/') -or $Name.Length -gt 1024) {
        throw 'Unsafe native archive name.'
    }
    $normalized = $Name.TrimEnd('/')
    foreach ($segment in $normalized.Split('/')) {
        if (-not $segment -or $segment -in @('.', '..') -or $segment -match '[\x00-\x1f<>:"|?*]' -or
            $segment.EndsWith('.') -or $segment.EndsWith(' ') -or
            $segment -match '^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)') {
            throw 'Unsafe native archive component.'
        }
    }
    if (-not $Seen.Add($normalized)) { throw 'Duplicate native archive entry.' }
    $root = [IO.Path]::GetFullPath($Destination) + [IO.Path]::DirectorySeparatorChar
    $target = [IO.Path]::GetFullPath((Join-Path $Destination $normalized))
    if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Native archive escapes destination.' }
}

function Invoke-NativeIsarArchiveProcess {
    param([Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][string[]]$Arguments,
        [ValidateRange(1,300)][int]$TimeoutSeconds = 300)
    Assert-NativeIsarPlainPath $File
    $start=[Diagnostics.ProcessStartInfo]::new($File)
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardInput=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    foreach($argument in $Arguments){$start.ArgumentList.Add($argument)}
    $child=[Diagnostics.Process]::new()
    $child.StartInfo=$start
    $started=$false
    try {
        $started=$child.Start()
        if(-not $started){throw 'Native archive child did not start.'}
        $child.StandardInput.Close()
        # Drain both pipes while waiting, including verbose archive inventories.
        $stdout=$child.StandardOutput.ReadToEndAsync()
        $stderr=$child.StandardError.ReadToEndAsync()
        if(-not $child.WaitForExit($TimeoutSeconds*1000)){
            throw 'Native archive child timed out.'
        }
        if(-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),10000)){
            throw 'Native archive child output did not close.'
        }
        if($child.ExitCode -ne 0){throw 'Native archive child failed.'}
        if($stdout.Result.Length -gt 128MB -or $stderr.Result.Length -gt 128MB){
            throw 'Native archive child output exceeds limit.'
        }
        return $stdout.Result
    } finally {
        if($started -and -not $child.HasExited){
            $child.Kill($true)
            if(-not $child.WaitForExit(10000)){throw 'Native archive owned child did not stop.'}
        }
        $child.Dispose()
    }
}

function Expand-NativeIsarArchive {
    param([string]$Archive, [string]$Destination, [ValidateSet('zip','tar.gz')][string]$Kind,
        [ValidateRange(1,8589934592)][long]$MaximumExpandedBytes = 8GB,
        [scriptblock]$OnTarPhase)
    Assert-NativeIsarPlainPath $Archive
    Assert-NativeIsarPlainPath $Destination
    if (Test-Path -LiteralPath $Destination) { throw 'Native extraction destination must be fresh.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($Kind -eq 'zip') {
        $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
        try {
            [long]$total = 0
            $entries = @{}
            $links = @()
            foreach ($entry in $zip.Entries) {
                Assert-NativeIsarArchiveName $entry.FullName $Destination $seen
                $entries[$entry.FullName.TrimEnd('/')] = $entry
                $unixType = ($entry.ExternalAttributes -shr 16) -band 0xf000
                if ($unixType -eq 0xa000) {
                    if ($entry.Length -gt 1024) { throw 'Native ZIP link target exceeds limit.' }
                    $links += $entry
                } elseif ($unixType -notin @(0,0x8000,0x4000) -or ($entry.ExternalAttributes -band 0x400)) {
                    throw 'Native ZIP link or special entry rejected.'
                }
                $total += $entry.Length
                if ($total -gt $MaximumExpandedBytes -or $entry.Length -gt 2GB -or $seen.Count -gt 100000) { throw 'Native ZIP exceeds extraction bounds.' }
            }
            $materializations = @()
            foreach ($link in $links) {
                $reader = [IO.StreamReader]::new($link.Open(), [Text.UTF8Encoding]::new($false,$true))
                try { $targetName = $reader.ReadToEnd() } finally { $reader.Dispose() }
                # Only same-directory descendant regular-file targets are supported.
                # No filesystem link is created and no OS link permission is needed.
                $linkParent = $link.FullName.Substring(0, $link.FullName.LastIndexOf('/') + 1)
                $target = $linkParent + $targetName
                $targetSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                Assert-NativeIsarArchiveName $target $Destination $targetSeen
                if (-not $entries.ContainsKey($target)) { throw 'Native ZIP link target is absent.' }
                $targetEntry = $entries[$target]
                $targetType = ($targetEntry.ExternalAttributes -shr 16) -band 0xf000
                if ($targetEntry.FullName.EndsWith('/') -or $targetType -notin @(0,0x8000)) { throw 'Native ZIP link target is not a regular file.' }
                $total += $targetEntry.Length - $link.Length
                if ($total -gt $MaximumExpandedBytes) { throw 'Native ZIP materialization exceeds extraction bounds.' }
                $materializations += @{link=$link.FullName;target=$target;targetEntry=$targetEntry}
            }
            [IO.Directory]::CreateDirectory($Destination) | Out-Null
            foreach ($entry in $zip.Entries) {
                $path = Join-Path $Destination $entry.FullName
                if ($entry.FullName.EndsWith('/')) { [IO.Directory]::CreateDirectory($path) | Out-Null; continue }
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
                $payload = $entry
                if ((($entry.ExternalAttributes -shr 16) -band 0xf000) -eq 0xa000) {
                    $payload = ($materializations | Where-Object { $_.link -ceq $entry.FullName }).targetEntry
                }
                $source = $payload.Open()
                $output = [IO.File]::Open($path, [IO.FileMode]::CreateNew)
                try { $source.CopyTo($output) } finally { $output.Dispose(); $source.Dispose() }
            }
            if ($materializations.Count) {
                Write-NativeIsarJson ($Destination + '.materialized-links.json') @($materializations | ForEach-Object { @{link=$_.link;target=$_.target} })
            }
        } finally { $zip.Dispose() }
    } else {
        $tar = Join-Path $env:SystemRoot 'System32/tar.exe'
        if (-not (Test-Path -LiteralPath $tar -PathType Leaf)) { throw 'Windows tar prerequisite missing.' }
        $tarVersion=Invoke-NativeIsarArchiveProcess $tar @('--version')
        if($tarVersion -cnotmatch '\bzlib/'){throw 'Windows tar built-in gzip prerequisite missing.'}
        if($OnTarPhase){& $OnTarPhase 'names'}
        $names = @((Invoke-NativeIsarArchiveProcess $tar @('-tf',$Archive)) -split '\r?\n' | Where-Object {$_ -ne ''})
        if($OnTarPhase){& $OnTarPhase 'types'}
        $details = @((Invoke-NativeIsarArchiveProcess $tar @('-tvf',$Archive)) -split '\r?\n' | Where-Object {$_ -ne ''})
        if ($names.Count -ne $details.Count -or $names.Count -gt 100000) { throw 'Cannot inspect native TAR types.' }
        for ($index = 0; $index -lt $names.Count; $index++) {
            Assert-NativeIsarArchiveName $names[$index] $Destination $seen
            if ($details[$index] -cnotmatch '^[-d]') { throw 'Native TAR link or special entry rejected.' }
        }
        [IO.Directory]::CreateDirectory($Destination) | Out-Null
        if($OnTarPhase){& $OnTarPhase 'extract'}
        [void](Invoke-NativeIsarArchiveProcess $tar @('-xf',$Archive,'-C',$Destination))
    }
    foreach ($entry in Get-ChildItem -LiteralPath $Destination -Recurse -Force) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Native extraction produced a reparse point.' }
    }
}

function Write-NativeIsarJson {
    param([string]$Path, [object]$Value)
    $json = ConvertTo-Json -InputObject $Value -Depth 30
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
    if ($bytes.Length -gt 1MB) { throw 'Native manifest exceeds limit.' }
    Assert-NativeIsarPlainPath $Path
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes); $stream.Flush($true) } finally { $stream.Dispose() }
}

function Get-NativeIsarSnapshotDigest {
    param([Collections.IDictionary]$Snapshot)
    $paths = [string[]]@($Snapshot.Keys)
    [Array]::Sort($paths,[StringComparer]::Ordinal)
    $buffer = [Text.StringBuilder]::new()
    foreach ($path in $paths) { [void]$buffer.Append($path).Append([char]0).Append($Snapshot[$path]).Append("`n") }
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($buffer.ToString()))).ToLowerInvariant()
}
