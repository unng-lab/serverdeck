[CmdletBinding()]
param([switch]$ReuseCandidate)
$ErrorActionPreference = 'Stop'
throw 'Retired integration workflow: project tests are unit-only. Use tools/test-unit.ps1 and tools/test-release.ps1.'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    if (!$ReuseCandidate) { & ./tools/build-release.ps1 }
    & ./tools/test-release.ps1
    & ./tools/test-process-observer.ps1
    & ./tools/test-lifecycle-journal.ps1
    & ./tools/build-durability-fixture.ps1
    $product = (Resolve-Path -LiteralPath output/release/ServerDeck.exe).Path
    $digest = (Get-FileHash -LiteralPath $product -Algorithm SHA256).Hash.ToLowerInvariant()
    $probe = Get-Content -Raw -LiteralPath output/release-evidence/local-probes.json | ConvertFrom-Json
    if ($probe.exeSHA256 -ne $digest -or $null -eq $probe.embeddedBuildIdentities) {
        throw 'Build identities are not bound to the selected candidate'
    }
    $durabilityBuild = Get-Content -Raw -LiteralPath output/durability-fixture/build.json | ConvertFrom-Json
    $fixtureLock = @($durabilityBuild.sources | Where-Object path -EQ 'pubspec.lock')
    if ($fixtureLock.Count -ne 1 -or $fixtureLock[0].sha256 -ne $probe.embeddedBuildIdentities.pubLockSHA256 -or
        $durabilityBuild.dartSdk -ne $probe.embeddedBuildIdentities.flutter.dartSdkVersion) {
        throw 'Durability source dependencies/SDK differ from the selected candidate'
    }
    $kit = Join-Path (Get-Location) "output/vm-test-kit/$digest"
    function Assert-KitDestination([string]$Path) {
        $walk = [IO.Path]::GetFullPath($Path)
        while ($walk) {
            if ((Test-Path -LiteralPath $walk) -and
                ((Get-Item -Force -LiteralPath $walk).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'Reparse points are forbidden in VM kit destinations'
            }
            $walk = Split-Path -Parent $walk
        }
    }
    Assert-KitDestination $kit
    Assert-KitDestination "$kit/product"
    Assert-KitDestination "$kit/verification"
    New-Item -ItemType Directory -Force -Path "$kit/product", "$kit/verification" | Out-Null
    Copy-Item -LiteralPath $product -Destination "$kit/product/ServerDeck.exe"
    $fixtures = @('runtime_contract_test', 'payload_test', 'instance_test', 'security_test',
        'runtime_owners_test', 'platform_channel_test', 'release_observer', 'release_lifecycle')
    $systemDirectory = Join-Path $env:SystemRoot 'System32'
    foreach ($fixture in $fixtures) {
        $binary = "build/native-tests/Release/$fixture.exe"
        $audit = Join-Path $kit "import-audits/$fixture"
        Assert-KitDestination $audit
        New-Item -ItemType Directory -Force -Path $audit | Out-Null
        & python tools/package-release.py --bootstrap $binary --output $audit --system $systemDirectory
        if ($LASTEXITCODE -ne 0) { throw "Verification helper has external runtime imports: $fixture" }
        Copy-Item -LiteralPath $binary -Destination "$kit/verification/$fixture.exe"
    }
    Copy-Item -LiteralPath tools/vm-native-runner.ps1 -Destination "$kit/run-native.ps1"
    Copy-Item -LiteralPath tools/vm-capture-process.ps1 -Destination "$kit/capture-process.ps1"
    Copy-Item -LiteralPath tools/vm-run-lifecycle.ps1 -Destination "$kit/run-lifecycle.ps1"
    Copy-Item -LiteralPath tools/vm-lifecycle-journal.ps1 -Destination "$kit/lifecycle-journal.ps1"
    Copy-Item -LiteralPath tools/vm-run-durability.ps1 -Destination "$kit/run-durability.ps1"
    $durabilityFiles = @(
        @{source = 'output/durability-fixture/store_durability.exe'; target = 'verification/store_durability.exe'},
        @{source = 'output/durability-fixture/build.json'; target = 'durability-build.json'},
        @{source = 'output/durability-fixture/import-audit/bootstrap-imports.json'; target = 'import-audits/store_durability/bootstrap-imports.json'}
    )
    foreach ($entry in $durabilityFiles) {
        Assert-KitDestination "$kit/$($entry.target)"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent "$kit/$($entry.target)") | Out-Null
        Copy-Item -LiteralPath $entry.source -Destination "$kit/$($entry.target)"
    }
    foreach ($name in @('libisar.dll', 'vcruntime140.dll', 'licenses/isar_community.txt', 'licenses/isar_community_flutter_libs.txt')) {
        $runtimeSource = "output/release-evidence/verification-runtime/$name"
        if ((Get-FileHash -LiteralPath $runtimeSource -Algorithm SHA256).Hash.ToLowerInvariant() -ne $probe.verificationRuntimeSHA256.$name) {
            throw 'Durability runtime is not from the verified candidate'
        }
        Assert-KitDestination "$kit/verification/$name"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent "$kit/verification/$name") | Out-Null
        Copy-Item -LiteralPath $runtimeSource -Destination "$kit/verification/$name"
    }
    $probe.embeddedBuildIdentities | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath "$kit/build-identities.json" -Encoding UTF8
    $flutterRoot = Split-Path -Parent (Split-Path -Parent (Get-Command flutter).Source)
    Copy-Item -LiteralPath "$flutterRoot/LICENSE" -Destination "$kit/verification/Flutter-LICENSE.txt"
    Assert-KitDestination "$kit/verification/Dart-LICENSE.txt"
    Copy-Item -LiteralPath "$flutterRoot/bin/cache/dart-sdk/LICENSE" -Destination "$kit/verification/Dart-LICENSE.txt"
    $runtimeAudit = "$kit/import-audits/durability-runtime"
    Assert-KitDestination "$runtimeAudit/closure-imports.json"
    & python tools/package-release.py --verify-tree "$kit/verification" --output $runtimeAudit --system $systemDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Verification private DLL closure is incomplete' }
    $expected = @('product/ServerDeck.exe', 'run-native.ps1', 'capture-process.ps1', 'run-lifecycle.ps1', 'lifecycle-journal.ps1', 'run-durability.ps1',
        'build-identities.json', 'verification/Flutter-LICENSE.txt', 'verification/Dart-LICENSE.txt', 'durability-build.json',
        'verification/store_durability.exe', 'import-audits/store_durability/bootstrap-imports.json',
        'import-audits/durability-runtime/closure-imports.json',
        'verification/libisar.dll', 'verification/vcruntime140.dll',
        'verification/licenses/isar_community.txt', 'verification/licenses/isar_community_flutter_libs.txt')
    $expected += @($fixtures | ForEach-Object { "verification/$_.exe"; "import-audits/$_/bootstrap-imports.json" })
    $files = @(Get-ChildItem -LiteralPath $kit -File -Recurse | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($kit, $_.FullName).Replace('\', '/')
        if ($relative -in @('manifest.json', 'native-results.json')) { return }
        if ($relative -notin $expected) { throw "Unexpected VM kit file: $relative" }
        [ordered]@{
            path = $relative
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    if ($files.Count -ne $expected.Count) { throw 'Verification kit is incomplete' }
    [ordered]@{
        schemaVersion = 1; productSHA256 = $digest
        scope = 'Developer verification kit; not the product distribution or full VM acceptance'
        nativeFixtures = @($fixtures | ForEach-Object { "verification/$_.exe" })
        files = $files
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$kit/manifest.json" -Encoding UTF8
    Write-Output "VM verification kit: $kit"
    Write-Output 'The product deliverable remains output/release/ServerDeck.exe only.'
} finally { Pop-Location }
