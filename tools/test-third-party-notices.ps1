[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$fixtureContainer = Join-Path $repoRoot ('.local/notices-fixture-' + [guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $fixtureContainer 'workspace'
$collector = Join-Path $PSScriptRoot 'collect-third-party-notices.ps1'
function Write-FixtureFile {
    param([string]$Relative, [string]$Text)
    $path = Join-Path $fixtureRoot $Relative
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    [IO.File]::WriteAllText($path, $Text, [Text.UTF8Encoding]::new($false))
}
function Assert-True { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "Assertion failed: $Message" } }
function Invoke-Collection { & $collector -WorkspaceRoot $fixtureRoot -SdkDirectory (Join-Path $fixtureRoot 'sdk') }
function Assert-Rejected {
    param([scriptblock]$Action, [string]$MessagePattern)
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $_.Exception.Message -match $MessagePattern }
    Assert-True $rejected "expected rejection: $MessagePattern"
    Assert-True ((Get-FileHash -LiteralPath $previewPath).Hash -eq $previewHash) 'existing preview preserved'
    Assert-True ((Get-FileHash -LiteralPath $inventoryPath).Hash -eq $inventoryHash) 'existing inventory preserved'
}
try {
    foreach ($version in @('1.0.0', '2.0.0')) {
        Write-FixtureFile "hosted/fixturepkg-$version/pubspec.yaml" "name: fixturepkg`nversion: $version`n"
        Write-FixtureFile "hosted/fixturepkg-$version/LICENSE" "Complete copyright $version`nLine one`r`nLine two`nEND`n"
    }
    [void][IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'third_party'))
    Copy-Item -LiteralPath (Join-Path $repoRoot 'third_party/isar_community') -Destination (Join-Path $fixtureRoot 'third_party/isar_community') -Recurse
    foreach ($context in @('', 'packages/serverdeck_locald', 'packages/serverdeck_protocol', 'packages/serverdeck_windows')) {
        $version = if ($context -match 'protocol|windows') { '2.0.0' } else { '1.0.0' }
        $uri = ([Uri]((Join-Path $fixtureRoot "hosted/fixturepkg-$version") + '/')).AbsoluteUri
        $entries=@(@{name = 'fixturepkg'; rootUri = $uri})
        if ($context -in @('','packages/serverdeck_locald')) {
            $relative=if($context){'../../../third_party/isar_community'}else{'../third_party/isar_community'}
            $entries+=@{name='isar_community';rootUri=$relative}
        }
        Write-FixtureFile "$context/.dart_tool/package_config.json" (@{ configVersion = 2; packages = $entries } | ConvertTo-Json -Depth 4)
        Write-FixtureFile "$context/pubspec.lock" "packages:`n  fixturepkg:`n    source: hosted`n    version: `"$version`"`nsdks:`n  dart: '>=3.13.5'`n"
    }
    Write-FixtureFile 'sdk/bin/cache/flutter.version.json' (@{frameworkVersion='3.47.7';dartSdkVersion='3.13.5';frameworkRevision='abaf9c523780a608bd46686fd5e53740a07077f8'} | ConvertTo-Json)
    foreach ($file in @('sdk/LICENSE', 'sdk/bin/cache/dart-sdk/LICENSE', 'sdk/bin/cache/pkg/sky_engine/LICENSE', 'assets/brand/fonts/OFL.txt')) { Write-FixtureFile $file "Complete fixture source $file`n" }
    $nativePath = Join-Path $fixtureRoot 'docs/development/licenses/native'
    New-Item -ItemType Directory -Path $nativePath -Force | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'docs/development/licenses/native') -File | Copy-Item -Destination $nativePath
    $result = Invoke-Collection
    Assert-True ($result.Packages -eq 3 -and $result.Sources -eq 13) 'both hosted versions and pinned local runtime with provenance'
    $previewPath = Join-Path $fixtureRoot 'build/foundation/notices/THIRD_PARTY_NOTICES.preview.txt'
    $inventoryPath = Join-Path $fixtureRoot 'build/foundation/notices/notices.preview.json'
    $previewHash = (Get-FileHash -LiteralPath $previewPath).Hash
    $inventoryHash = (Get-FileHash -LiteralPath $inventoryPath).Hash
    $preview = [IO.File]::ReadAllText($previewPath)
    Assert-True ($preview.Contains([IO.File]::ReadAllText((Join-Path $fixtureRoot 'hosted/fixturepkg-1.0.0/LICENSE')))) 'unabridged license1'
    Assert-True ($preview.Contains([IO.File]::ReadAllText((Join-Path $fixtureRoot 'hosted/fixturepkg-2.0.0/LICENSE')))) 'unabridged license2'
    foreach($file in @('LICENSE','UPSTREAM.md')) {
        Assert-True ($preview.Contains([IO.File]::ReadAllText((Join-Path $fixtureRoot ('third_party/isar_community/'+$file))))) ('unabridged binding '+$file)
    }
    Assert-True (-not $preview.Contains($fixtureRoot)) 'no machine paths in output'
    $inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
    $binding=@($inventory.packages|Where-Object id -CEQ 'isar_community@3.3.2+serverdeck.1')
    Assert-True ($binding.Count -eq 1 -and ($binding[0].contexts -join ',') -ceq 'root,serverdeck_locald') 'local binding deduplicated with exact resolution contexts'
    Assert-True ($inventory.previewSha256 -eq $previewHash.ToLowerInvariant() -and -not $inventory.distributionReady) 'preview hash and explicit incomplete status'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Split-Path $previewPath) 'THIRD_PARTY_NOTICES.txt'))) 'no final distribution artifact'
    Invoke-Collection | Out-Null
    Assert-True ((Get-FileHash -LiteralPath $previewPath).Hash -eq $previewHash -and (Get-FileHash -LiteralPath $inventoryPath).Hash -eq $inventoryHash) 'deterministic text and JSON'
    Write-FixtureFile 'hosted/fixturepkg-1.0.0/pubspec.yaml' "name: fixturepkg`nversion: 9.0.0`n"
    Assert-Rejected { Invoke-Collection } 'identity mismatch'
    Write-FixtureFile 'hosted/fixturepkg-1.0.0/pubspec.yaml' "name: fixturepkg`nversion: 1.0.0`n"
    $licensePath = Join-Path $fixtureRoot 'hosted/fixturepkg-1.0.0/LICENSE'
    $licenseText = [IO.File]::ReadAllText($licensePath)
    Remove-Item -LiteralPath $licensePath
    Assert-Rejected { Invoke-Collection } 'LICENSE missing'
    Write-FixtureFile 'hosted/fixturepkg-1.0.0/LICENSE' ' '
    Assert-Rejected { Invoke-Collection } 'Empty notice'
    Write-FixtureFile 'hosted/fixturepkg-1.0.0/LICENSE' $licenseText
    $bindingPubspec=Join-Path $fixtureRoot 'third_party/isar_community/pubspec.yaml'
    $bindingText=[IO.File]::ReadAllText($bindingPubspec)
    [IO.File]::WriteAllText($bindingPubspec,$bindingText.Replace('3.3.2+serverdeck.1','3.3.2'))
    Assert-Rejected { Invoke-Collection } 'Binding source package identity mismatch'
    [IO.File]::WriteAllText($bindingPubspec,$bindingText)
    $bindingLicense=Join-Path $fixtureRoot 'third_party/isar_community/LICENSE'
    $bindingBytes=[IO.File]::ReadAllBytes($bindingLicense)
    Remove-Item -LiteralPath $bindingLicense
    Assert-Rejected { Invoke-Collection } 'Binding source input missing'
    [IO.File]::WriteAllBytes($bindingLicense,$bindingBytes)
    Assert-Rejected { & $collector -WorkspaceRoot $fixtureRoot -SdkDirectory (Join-Path $fixtureRoot 'sdk') -OutputDirectory $repoRoot } 'output must remain'
    $manifestPath = Join-Path $nativePath 'sources.json'
    $manifestText = [IO.File]::ReadAllText($manifestPath)
    $manifest = $manifestText | ConvertFrom-Json
    $manifest.sources[1] = $manifest.sources[0]
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 4))
    Assert-Rejected { Invoke-Collection } 'Native preview inventory mismatch'
    [IO.File]::WriteAllText($manifestPath, $manifestText)
    # An output hardlink must not overwrite its alias outside selected workspace.
    $outsidePath = Join-Path $fixtureContainer 'outside-target.txt'
    [IO.File]::WriteAllText($outsidePath, 'outside marker')
    foreach ($destination in @($previewPath, $inventoryPath)) {
        Remove-Item -LiteralPath $destination
        New-Item -ItemType HardLink -Path $destination -Target $outsidePath | Out-Null
        Invoke-Collection | Out-Null
        Assert-True ([IO.File]::ReadAllText($outsidePath) -ceq 'outside marker') 'outside hardlink alias untouched'
        Assert-True ((Get-FileHash -LiteralPath $previewPath).Hash -eq $previewHash -and (Get-FileHash -LiteralPath $inventoryPath).Hash -eq $inventoryHash) 'linked output safely replaced'
    }
    # Junctions need no symlink privilege and exercise the destination reparse gate.
    Remove-Item -LiteralPath $inventoryPath
    New-Item -ItemType Junction -Path $inventoryPath -Target $fixtureContainer | Out-Null
    try {
        $rejected = $false
        try { Invoke-Collection | Out-Null } catch { $rejected = $_.Exception.Message -match 'output file cannot be a reparse point' }
        Assert-True $rejected 'output junction rejected before either write'
        Assert-True ((Get-FileHash -LiteralPath $previewPath).Hash -eq $previewHash) 'preview preserved on output junction rejection'
        Assert-True ([IO.File]::ReadAllText($outsidePath) -ceq 'outside marker') 'outside junction marker untouched'
    } finally { Remove-Item -LiteralPath $inventoryPath -Force }
    Invoke-Collection | Out-Null
    $nativeFile = Join-Path $nativePath 'isar-NOTICE.txt'
    [IO.File]::AppendAllText($nativeFile, 'altered')
    Assert-Rejected { Invoke-Collection } 'Pinned notice hash mismatch'
    [pscustomobject]@{Result='PASS';Scope='owned source fixtures, not native/security acceptance'}
} catch {
    Write-Host "Fixture failure: $($_.Exception.Message)"
    throw
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureContainer)
    $allowedFixturePrefix = (Join-Path $repoRoot '.local') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedFixture.StartsWith($allowedFixturePrefix, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolvedFixture -Leaf) -notmatch '^notices-fixture-[a-f0-9]{32}$') { throw 'Unsafe fixture cleanup target.' }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
