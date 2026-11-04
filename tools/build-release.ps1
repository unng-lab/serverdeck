param([string]$OutputDirectory = 'output/release')

$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    function Run-Checked([string]$Program, [string[]]$Arguments) {
        & $Program @Arguments
        if ($LASTEXITCODE -ne 0) { throw "$Program failed (exit $LASTEXITCODE)" }
    }
    $sdk = & flutter --version --machine | ConvertFrom-Json
    if ($sdk.frameworkVersion -ne '3.47.7' -or $sdk.dartSdkVersion -ne '3.13.5') {
        throw 'Use Flutter 3.47.7 / Dart 3.13.5'
    }
    Run-Checked python @('tools/check-ssh-vendor.py')
    Run-Checked flutter @('pub', 'get', '--enforce-lockfile')
    Run-Checked flutter @('build', 'windows', '--release', '--no-tree-shake-icons')
    $flutterRoot = Split-Path -Parent (Split-Path -Parent (Get-Command flutter).Source)
    Run-Checked python @('tools/check-release-font.py',
        '--bundled', 'build/windows/x64/runner/Release/data/flutter_assets/fonts/MaterialIcons-Regular.otf',
        '--expected', "$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf")
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (!$vs) { throw 'VS2022 Desktop C++ tools required' }
    $toolset = (Get-Content (Join-Path $vs 'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt')).Trim()
    $compiler = Join-Path $vs "VC/Tools/MSVC/$toolset/bin/Hostx64/x64/cl.exe"
    $tree = Join-Path (Get-Location) 'build/windows/x64/runner/Release'
    $evidence = Join-Path (Get-Location) 'output/release-evidence'
    New-Item -ItemType Directory -Force -Path $evidence | Out-Null
    $identities = @{
        flutter = $sdk; toolset = $toolset
        compilerSHA256 = (Get-FileHash -LiteralPath $compiler -Algorithm SHA256).Hash.ToLowerInvariant()
        cmake = (& cmake --version | Select-Object -First 1)
        python = (& python --version)
        windowsSdk = ([xml](Get-Content -Raw 'build/windows/x64/runner/serverdeck.vcxproj')).Project.PropertyGroup.WindowsTargetPlatformVersion | Where-Object { $_ } | Select-Object -First 1
        pubLockSHA256 = (Get-FileHash pubspec.lock -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $identities | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$evidence/identities.json" -Encoding utf8
    $licenseDirectory = Join-Path $tree 'licenses'
    New-Item -ItemType Directory -Force -Path $licenseDirectory | Out-Null
    Copy-Item -LiteralPath LICENSE -Destination "$licenseDirectory/ServerDeck.txt"
    Copy-Item -LiteralPath "$flutterRoot/bin/cache/pkg/sky_engine/LICENSE" -Destination "$licenseDirectory/Flutter-engine.txt"
    $packageConfig = Get-Content -Raw .dart_tool/package_config.json | ConvertFrom-Json
    foreach ($name in @('isar_community', 'isar_community_flutter_libs', 'asn1lib', 'convert', 'meta', 'pointycastle', 'pinenacl')) {
        $package = $packageConfig.packages | Where-Object name -EQ $name
        $packageRoot = ([uri]$package.rootUri).LocalPath
        Copy-Item -LiteralPath (Join-Path $packageRoot 'LICENSE') -Destination "$licenseDirectory/$name.txt"
    }
    Copy-Item -LiteralPath third_party/dartssh2/LICENSE -Destination "$licenseDirectory/dartssh2.txt"
    Copy-Item -LiteralPath third_party/dartssh2/THIRD_PARTY_NOTICES.txt -Destination "$licenseDirectory/dartssh2-notices.txt"
    Copy-Item -LiteralPath pubspec.lock -Destination "$evidence/pubspec.lock"
    $packageConfig.packages | Select-Object name,languageVersion | ConvertTo-Json -Depth 3 |
        Set-Content -LiteralPath "$evidence/package-inventory.json" -Encoding utf8
    $systemDirectory = Join-Path $env:SystemRoot 'System32'
    $redistVersion = (Get-Content (Join-Path $vs 'VC/Auxiliary/Build/Microsoft.VCRedistVersion.default.txt')).Trim()
    $redist = Join-Path $vs "VC/Redist/MSVC/$redistVersion"
    Run-Checked python @('tools/package-release.py', '--tree', $tree, '--output', $evidence,
        '--identities', "$evidence/identities.json", '--redist', $redist, '--system', $systemDirectory)
    Run-Checked cmake @('-S', 'native', '-B', 'build/bootstrap', '-A', 'x64', "-DSERVERDECK_PAYLOAD_RESOURCE=$evidence/payload.rc")
    Run-Checked cmake @('--build', 'build/bootstrap', '--config', 'Release')
    Run-Checked python @('tools/package-release.py', '--bootstrap', 'build/bootstrap/Release/ServerDeck.exe',
        '--output', $evidence, '--system', $systemDirectory)
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $outputExe = Join-Path $OutputDirectory 'ServerDeck.exe'
    Copy-Item -LiteralPath build/bootstrap/Release/ServerDeck.exe -Destination $outputExe
    Get-FileHash -LiteralPath $outputExe -Algorithm SHA256
} finally {
    Pop-Location
}
