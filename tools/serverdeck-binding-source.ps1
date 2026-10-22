# Build-time source identity only; no native DLL selection or activation.
function Assert-ServerDeckBindingPlainPath {
    param([Parameter(Mandatory)][string]$Path)
    $current=[IO.Path]::GetFullPath($Path)
    while ($current) {
        if ((Test-Path -LiteralPath $current) -and
            ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Binding source path contains a reparse point.'
        }
        $current=[IO.Path]::GetDirectoryName($current)
    }
}

function Get-ServerDeckBindingSource {
    param([Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$PackageConfig)
    $repository=[IO.Path]::GetFullPath($WorkspaceRoot)
    $configPath=[IO.Path]::GetFullPath($PackageConfig,$repository)
    $relativeConfig=[IO.Path]::GetRelativePath($repository,$configPath).Replace('\','/')
    if ([IO.Path]::IsPathRooted($relativeConfig) -or $relativeConfig -eq '..' -or $relativeConfig.StartsWith('../')) {
        throw 'Binding package config must remain in workspace.'
    }
    Assert-ServerDeckBindingPlainPath $configPath
    $config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if ($config.configVersion -ne 2) { throw 'Binding package config version mismatch.' }
    $entries=@($config.packages | Where-Object name -CEQ 'isar_community')
    if ($entries.Count -ne 1) { throw 'Binding package source missing or duplicated.' }
    $uri=[Uri]::new([Uri]$configPath,[string]$entries[0].rootUri)
    if (-not $uri.IsAbsoluteUri -or -not $uri.IsFile -or $uri.Query -or $uri.Fragment -or $uri.UserInfo) {
        throw 'Binding package source must be a local file URI.'
    }
    $root=[IO.Path]::GetFullPath($uri.LocalPath).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $expected=[IO.Path]::GetFullPath((Join-Path $repository 'third_party/isar_community'))
    if (-not $root.Equals($expected,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Binding package must resolve to the pinned repository source.'
    }
    foreach ($relative in @('pubspec.yaml','LICENSE','UPSTREAM.md','analysis_options.yaml','lib/isar.dart',
        'lib/src/native/bindings.dart','lib/src/native/isar_core.dart','lib/src/native/txn.dart','lib/src/common/isar_common.dart')) {
        $path=Join-Path $root $relative
        Assert-ServerDeckBindingPlainPath $path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Binding source input missing.' }
        if ((Get-Item -LiteralPath $path).Length -gt 1MB) { throw 'Binding source input oversized.' }
    }
    $text=[IO.File]::ReadAllText((Join-Path $root 'pubspec.yaml'))
    if ($text -notmatch '(?m)^name:\s*isar_community\s*$' -or
        $text -notmatch '(?m)^version:\s*3\.3\.2\+serverdeck\.1\s*$') {
        throw 'Binding source package identity mismatch.'
    }
    return [ordered]@{root=$root;packageVersion='3.3.2+serverdeck.1';bindingVersion='3.3.2'}
}
