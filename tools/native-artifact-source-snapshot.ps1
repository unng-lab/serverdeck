. "$PSScriptRoot/native-isar-inputs.ps1"

# Build-only qualification input. Never imported by product entry points.
function Get-NativeArtifactSourceSnapshot {
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $fixed=@('pubspec.yaml','pubspec.lock','analysis_options.yaml','windows/CMakeLists.txt','windows/flutter/CMakeLists.txt',
        '.specify/memory/constitution.md','specs/001-service-foundation/spec.md','specs/001-service-foundation/plan.md',
        'specs/001-service-foundation/data-model.md','packages/serverdeck_locald/build.yaml','packages/serverdeck_locald/dart_test.yaml')
    foreach ($name in $fixed) {
        if (-not (Test-Path -LiteralPath (Join-Path $NativeIsarRepository $name) -PathType Leaf)) { throw 'Qualification source input missing.' }
        [void]$paths.Add($name)
    }
    foreach ($name in @('build.yaml','dart_test.yaml')) {
        if (Test-Path -LiteralPath (Join-Path $NativeIsarRepository $name) -PathType Leaf) { [void]$paths.Add($name) }
    }
    $roots=@('lib','test','integration_test','test_driver','assets','windows/runner','native/isar-3.3.2','specs/001-service-foundation/contracts','.github/workflows')
    foreach ($package in @('serverdeck_locald','serverdeck_protocol','serverdeck_windows')) {
        foreach ($name in @('pubspec.yaml','pubspec.lock','analysis_options.yaml','build.yaml','dart_test.yaml')) {
            $path='packages/' + $package + '/' + $name
            if ($name -in @('pubspec.yaml','pubspec.lock') -and -not (Test-Path -LiteralPath (Join-Path $NativeIsarRepository $path) -PathType Leaf)) { throw 'Qualification package manifest missing.' }
            if (Test-Path -LiteralPath (Join-Path $NativeIsarRepository $path) -PathType Leaf) { [void]$paths.Add($path) }
        }
        foreach ($name in @('lib','bin','test')) {
            $path='packages/' + $package + '/' + $name
            if ($name -eq 'lib' -and -not (Test-Path -LiteralPath (Join-Path $NativeIsarRepository $path) -PathType Container)) { throw 'Qualification package source missing.' }
            if (Test-Path -LiteralPath (Join-Path $NativeIsarRepository $path) -PathType Container) { $roots += $path }
        }
    }
    foreach ($root in $roots) {
        $absolute=Join-Path $NativeIsarRepository $root
        Assert-NativeIsarPlainPath $absolute
        if (-not (Test-Path -LiteralPath $absolute -PathType Container)) { throw 'Qualification source directory missing.' }
        foreach ($entry in Get-ChildItem -LiteralPath $absolute -Recurse -Force) {
            Assert-NativeIsarPlainPath $entry.FullName
            if ($entry.PSIsContainer) { continue }
            [void]$paths.Add([IO.Path]::GetRelativePath($NativeIsarRepository,$entry.FullName).Replace('\','/'))
        }
    }
    foreach ($entry in Get-ChildItem -LiteralPath (Join-Path $NativeIsarRepository 'tools') -Filter '*.ps1' -File) {
        [void]$paths.Add('tools/' + $entry.Name)
    }
    if ($paths.Count -eq 0 -or $paths.Count -gt 100000) { throw 'Qualification source inventory exceeds limits.' }
    $names=[string[]]@($paths)
    [Array]::Sort($names,[StringComparer]::Ordinal)
    $snapshot=@{}
    $files=[Collections.Generic.List[object]]::new()
    [long]$total=0
    foreach ($name in $names) {
        $path=Join-Path $NativeIsarRepository $name
        Assert-NativeIsarPlainPath $path
        $length=(Get-Item -LiteralPath $path).Length
        if ($length -gt 2GB) { throw 'Qualification source resource limit exceeded.' }
        $total += $length
        if ($total -gt 8GB) { throw 'Qualification source resource limit exceeded.' }
        $hash=Get-NativeIsarDigest $path
        $snapshot[$name]=$hash
        $files.Add([ordered]@{file=$name;sha256=$hash;length=$length})
    }
    return [ordered]@{schemaVersion=1;sha256=Get-NativeIsarSnapshotDigest $snapshot;files=$files.ToArray()}
}
