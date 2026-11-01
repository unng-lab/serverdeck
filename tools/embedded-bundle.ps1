# Pure RAM metadata composition. No SDK, file access, process or native dispatch.
. "$PSScriptRoot/current-packages.ps1"
function Get-EmbeddedBundleLockPaths {
    return Get-CurrentBundleLockPaths
}

function New-EmbeddedBundleManifest {
    param(
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$Configuration,
        [Parameter(Mandatory)][string]$AppRoot,
        [Parameter(Mandatory)][Collections.IDictionary]$LockHashes,
        [Parameter(Mandatory)][Collections.IDictionary]$Hashes
    )
    $invalid = 'INVALID_EMBEDDED_BUNDLE_INPUT'
    if ($Commit -cnotmatch '^[a-f0-9]{40}$' -or $Configuration -cnotin @('Debug', 'Release') -or
        $AppRoot.Length -gt 32767 -or $AppRoot.Contains([char]0) -or
        -not [IO.Path]::IsPathFullyQualified($AppRoot)) { throw $invalid }
    try { [void][Text.UTF8Encoding]::new($false, $true).GetByteCount($AppRoot) }
    catch { throw $invalid }
    $lockNames = [string[]]@(Get-EmbeddedBundleLockPaths)
    [Array]::Sort($lockNames, [StringComparer]::Ordinal)
    $fileNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [void]$fileNames.Add('serverdeck.exe')
    [void]$fileNames.Add('libisar.dll')
    if (@($Hashes.Keys | Where-Object { $_ -ceq 'executor-release.json' }).Count -eq 1) {
        [void]$fileNames.Add('executor-release.json')
    }
    if ($LockHashes.Count -ne $lockNames.Count -or $Hashes.Count -ne $fileNames.Count) { throw $invalid }
    foreach ($entry in $LockHashes.Keys) {
        if ($entry -isnot [string] -or $entry -cnotin $lockNames) { throw $invalid }
    }
    $transcript = foreach ($name in $lockNames) {
        $value = $LockHashes[$name]
        if ($value -isnot [string] -or $value -cnotmatch '^[a-f0-9]{64}$') { throw $invalid }
        $name + ':' + $value
    }
    $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes(($transcript -join "`n")))).ToLowerInvariant()
    $checked = [ordered]@{}
    foreach ($name in $Hashes.Keys) {
        if ($name -isnot [string] -or -not $fileNames.Contains($name)) { throw $invalid }
        $value = $Hashes[$name]
        if ($value -isnot [string] -or $value -cnotmatch '^[a-f0-9]{64}$') { throw $invalid }
        $checked[$name] = $value
    }
    $manifest = [ordered]@{
        format = 4; product = 'serverdeck-next'; buildId = "$Commit+$Configuration+$digest"
        configuration = $Configuration; testOnly = $false; appRoot = $AppRoot
        apiMajor = 1; apiMinor = 1; workspaceSchema = 3; sha256 = $checked
    }
    if ([Text.Encoding]::UTF8.GetByteCount(($manifest | ConvertTo-Json -Depth 5 -Compress)) -gt 16384) {
        throw $invalid
    }
    return $manifest
}

# Semantic gate for retained native-qualification bundle metadata. File/receipt/
# source/ABI evidence checks remain the caller's responsibility, never this DTO.
function ConvertTo-EmbeddedBundleManifest {
    param([Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][string]$Configuration,
        [Parameter(Mandatory)][string]$AppRoot,
        [Parameter(Mandatory)][string]$DllSha256,
        [Parameter(Mandatory)][Collections.IDictionary]$LockHashes)
    $invalid = 'INVALID_EMBEDDED_BUNDLE_INPUT'
    try {
        $map = if ($InputObject -is [Collections.IDictionary]) { $InputObject }
            elseif ($InputObject -is [pscustomobject]) {
                $copy = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
                foreach ($p in $InputObject.PSObject.Properties) { $copy[$p.Name] = $p.Value }
                $copy
            } else { throw $invalid }
        $fields = @('format','product','buildId','configuration','testOnly','appRoot','apiMajor','apiMinor','workspaceSchema','sha256')
        if ($map.Count -ne $fields.Count) { throw $invalid }
        foreach ($key in $map.Keys) { if ($key -cnotin $fields) { throw $invalid } }
        foreach ($entry in @{format=4;apiMajor=1;apiMinor=1;workspaceSchema=3}.GetEnumerator()) {
            $value = $map[$entry.Key]
            if (($value -isnot [int] -and $value -isnot [long]) -or $value -ne $entry.Value) { throw $invalid }
        }
        foreach ($name in @('product','configuration','appRoot','buildId')) {
            if ($map[$name] -isnot [string]) { throw $invalid }
        }
        if ($map['testOnly'] -isnot [bool] -or $map['testOnly'] -ne $false -or
            $map['product'] -cne 'serverdeck-next' -or $map['configuration'] -cne $Configuration -or
            $map['appRoot'] -cne $AppRoot -or $map['buildId'] -isnot [string] -or
            $map['buildId'] -cnotmatch '^[a-f0-9]{40}\+(Debug|Release)\+[a-f0-9]{64}$') { throw $invalid }
        $inputHashes = $map['sha256']
        $hashes = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        if ($inputHashes -is [Collections.IDictionary]) {
            foreach ($key in $inputHashes.Keys) { $hashes[$key] = $inputHashes[$key] }
        } elseif ($inputHashes -is [pscustomobject]) {
            foreach ($p in $inputHashes.PSObject.Properties) { $hashes[$p.Name] = $p.Value }
        } else { throw $invalid }
        if ($DllSha256 -cnotmatch '^[a-f0-9]{64}$' -or $hashes['libisar.dll'] -cne $DllSha256) { throw $invalid }
        $expected = New-EmbeddedBundleManifest -Commit ($map['buildId'].Substring(0,40)) -Configuration $Configuration -AppRoot $AppRoot -LockHashes $LockHashes -Hashes $hashes
        if ($expected.buildId -cne $map['buildId']) { throw $invalid }
        return $expected
    } catch { throw $invalid }
}
