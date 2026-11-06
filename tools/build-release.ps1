param(
    [string]$OutputDirectory = 'output/release',
    [ValidateSet('developer', 'publishable')][string]$Profile = 'publishable',
    [string]$UpdatePolicy
)

$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    function Run-Checked([string]$Program, [string[]]$Arguments) {
        & $Program @Arguments
        if ($LASTEXITCODE -ne 0) { throw "$Program failed (exit $LASTEXITCODE)" }
    }
    if ($Profile -eq 'publishable' -and !$UpdatePolicy) {
        $UpdatePolicy = Join-Path (Get-Location) 'release/update-policy.json'
    }
    if ($Profile -eq 'publishable' -and !(Test-Path -LiteralPath $UpdatePolicy -PathType Leaf)) {
        throw 'Publishable build requires the checked-in public update policy; developer builds must be requested explicitly'
    }
    $versionMatch = [regex]::Match((Get-Content -Raw pubspec.yaml), '(?m)^version:\s*(\S+)\s*$')
    $storeMatch = [regex]::Match((Get-Content -Raw lib/storage/store_manifest.dart), 'const currentStorageFormat = ([0-9]+);')
    if (!$versionMatch.Success -or !$storeMatch.Success) { throw 'Missing release version/storage format' }
    $version = $versionMatch.Groups[1].Value
    $storeFormat = $storeMatch.Groups[1].Value
    $evidence = Join-Path (Get-Location) 'output/release-evidence'
    New-Item -ItemType Directory -Force -Path $evidence | Out-Null
    $policyArguments = @('--store-format', $storeFormat)
    if ($Profile -eq 'publishable') { $policyArguments += '--publishable' }
    $trustResource = ''
    if ($UpdatePolicy) {
        $policyArguments += @('--policy', (Resolve-Path -LiteralPath $UpdatePolicy).Path)
        Run-Checked python (@('tools/package-installer.py', '--canonicalize-policy', '--output', $evidence) + $policyArguments)
        $trustResource = "$evidence/trust.rc"
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
    Run-Checked cmake @('-S', 'native', '-B', 'build/bootstrap', '-A', 'x64', "-DSERVERDECK_PAYLOAD_RESOURCE=$evidence/payload.rc", "-DSERVERDECK_APP_VERSION=$version",
        "-DSERVERDECK_TRUST_RESOURCE=$trustResource", '-DSERVERDECK_SETUP_RESOURCE=')
    Run-Checked cmake @('--build', 'build/bootstrap', '--config', 'Release', '--target', 'ServerDeck')
    Run-Checked python @('tools/package-release.py', '--bootstrap', 'build/bootstrap/Release/ServerDeck.exe',
        '--output', $evidence, '--system', $systemDirectory)
    $installerArguments = @('tools/package-installer.py', '--application', 'build/bootstrap/Release/ServerDeck.exe',
        '--output', $evidence, '--version', $version) + $policyArguments
    Run-Checked python $installerArguments
    Run-Checked cmake @('-S', 'native', '-B', 'build/setup', '-A', 'x64',
        "-DSERVERDECK_SETUP_RESOURCE=$evidence/setup.rc", '-DSERVERDECK_PAYLOAD_RESOURCE=', '-DSERVERDECK_TRUST_RESOURCE=')
    Run-Checked cmake @('--build', 'build/setup', '--config', 'Release', '--target', 'ServerDeckSetup')
    Run-Checked python ($installerArguments + @('--audit-setup', 'build/setup/Release/ServerDeckSetup.exe'))
    New-Item -ItemType Directory -Force -Path "$evidence/setup-imports" | Out-Null
    Run-Checked python @('tools/package-release.py', '--bootstrap', 'build/setup/Release/ServerDeckSetup.exe',
        '--output', "$evidence/setup-imports", '--system', $systemDirectory)
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $outputExe = Join-Path $OutputDirectory 'ServerDeckSetup.exe'
    Copy-Item -LiteralPath build/setup/Release/ServerDeckSetup.exe -Destination $outputExe
    Get-FileHash -LiteralPath $outputExe -Algorithm SHA256
} finally {
    Pop-Location
}
