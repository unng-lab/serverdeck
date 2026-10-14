. "$PSScriptRoot/native-isar-inputs.ps1"

function Copy-PrerequisiteNormalBundle {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)
    $Source=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Source))
    $Destination=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Destination))
    $prefix=$NativeIsarRepository+[IO.Path]::DirectorySeparatorChar
    foreach($path in @($Source,$Destination)){
        if(-not $path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Prerequisite bundle outside workspace.'}
        Assert-NativeIsarPlainPath $path
    }
    if($Source -ieq $Destination -or $Destination.StartsWith($Source+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
        $Source.StartsWith($Destination+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {throw 'Overlapping prerequisite bundles.'}
    if(-not [IO.Directory]::Exists($Source) -or -not [IO.Directory]::Exists($Destination) -or
        [IO.Directory]::GetFileSystemEntries($Destination).Length -ne 0){throw 'Expected source and empty prerequisite destination.'}
    $inventory=@{}
    foreach($entry in Get-ChildItem -LiteralPath $Source -Recurse -Force){
        Assert-NativeIsarPlainPath $entry.FullName
        $relative=[IO.Path]::GetRelativePath($Source,$entry.FullName)
        $inventory[$relative]=$(if($entry.PSIsContainer){'directory'}else{Get-NativeIsarDigest $entry.FullName})
    }
    foreach($entry in Get-ChildItem -LiteralPath $Source -Force){Copy-Item -LiteralPath $entry.FullName -Destination $Destination -Recurse -Force -ErrorAction Stop}
    $copied=@(Get-ChildItem -LiteralPath $Destination -Recurse -Force)
    if($copied.Count -ne $inventory.Count){throw 'Prerequisite bundle inventory mismatch.'}
    foreach($entry in $copied){
        Assert-NativeIsarPlainPath $entry.FullName
        $relative=[IO.Path]::GetRelativePath($Destination,$entry.FullName)
        $value=$(if($entry.PSIsContainer){'directory'}else{Get-NativeIsarDigest $entry.FullName})
        if(-not $inventory.ContainsKey($relative) -or $value -cne $inventory[$relative]){throw 'Prerequisite bundle content mismatch.'}
    }
}
