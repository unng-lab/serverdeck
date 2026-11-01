# Exact current source inputs. No directory discovery, SDK or filesystem work.
function Get-CurrentPackageNames {
    return [string[]]@('serverdeck_engine', 'serverdeck_mcp', 'serverdeck_protocol', 'serverdeck_windows')
}

function Get-CurrentBundleLockPaths {
    return [string[]](@('pubspec.lock') + @(Get-CurrentPackageNames | ForEach-Object { "packages/$_/pubspec.lock" }))
}
