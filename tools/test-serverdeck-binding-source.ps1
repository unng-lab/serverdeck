[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/serverdeck-binding-source.ps1"
$repository=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
foreach ($config in @('.dart_tool/package_config.json','packages/serverdeck_locald/.dart_tool/package_config.json')) {
    $actual=Get-ServerDeckBindingSource -WorkspaceRoot $repository -PackageConfig $config
    if ($actual.packageVersion -cne '3.3.2+serverdeck.1' -or $actual.bindingVersion -cne '3.3.2') { throw 'Actual binding identity mismatch.' }
}
$fixture=Join-Path $repository ('.local/binding-source-test-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$root=Join-Path $fixture 'third_party/isar_community'
Copy-Item -LiteralPath (Join-Path $repository 'third_party/isar_community') -Destination $root -Recurse
$configPath=Join-Path $fixture 'packages/locald/.dart_tool/package_config.json'
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($configPath))
function WriteConfig([string]$uri,[int]$count=1) {
    $entries=@(for($i=0;$i -lt $count;$i++){ @{name='isar_community';rootUri=$uri} })
    [IO.File]::WriteAllText($configPath,(@{configVersion=2;packages=$entries}|ConvertTo-Json -Depth 5))
}
function ResolveFixture { Get-ServerDeckBindingSource -WorkspaceRoot $fixture -PackageConfig $configPath }
function Refused([scriptblock]$action,[string]$message) {
    $failed=$false
    try { & $action | Out-Null } catch { if (-not $_.Exception.Message.Contains($message)) { throw }; $failed=$true }
    if (-not $failed) { throw ('Expected binding refusal: '+$message) }
}
try {
    WriteConfig '../../../third_party/isar_community'
    $baseline=ResolveFixture
    if ($baseline.root -cne $root) { throw 'Relative package source resolution failed.' }
    WriteConfig ([Uri]$root).AbsoluteUri
    if ((ResolveFixture).root -cne $root) { throw 'Absolute package source resolution failed.' }
    WriteConfig '../../../third_party/isar_community' 2
    Refused { ResolveFixture } 'missing or duplicated'
    WriteConfig '../../../third_party/isar_community' 0
    Refused { ResolveFixture } 'missing or duplicated'
    WriteConfig 'https://example.invalid/binding'
    Refused { ResolveFixture } 'local file URI'
    WriteConfig '../../../third_party/other'
    Refused { ResolveFixture } 'pinned repository source'
    WriteConfig '../../../third_party/isar_community'
    $pubspec=Join-Path $root 'pubspec.yaml'
    $original=[IO.File]::ReadAllText($pubspec)
    foreach ($version in @('3.3.2','3.3.2+serverdeck.2','3.3.3+serverdeck.1')) {
        [IO.File]::WriteAllText($pubspec,$original.Replace('3.3.2+serverdeck.1',$version))
        Refused { ResolveFixture } 'package identity mismatch'
    }
    [IO.File]::WriteAllText($pubspec,$original)
    $license=Join-Path $root 'LICENSE'
    $bytes=[IO.File]::ReadAllBytes($license)
    Remove-Item -LiteralPath $license
    Refused { ResolveFixture } 'input missing'
    [IO.File]::WriteAllBytes($license,$bytes)
    $other=Join-Path $fixture 'other-source'
    Move-Item -LiteralPath $root -Destination $other
    New-Item -ItemType Junction -Path $root -Target $other | Out-Null
    try { Refused { ResolveFixture } 'reparse point' } finally { Remove-Item -LiteralPath $root -Force }
    Move-Item -LiteralPath $other -Destination $root
    ResolveFixture | Out-Null
    'PINNED_BINDING_ACTUAL_RELATIVE_ABSOLUTE_IDENTITY_MISSING_DUPLICATE_AND_REPARSE_PASSED'
} finally {
    $full=[IO.Path]::GetFullPath($fixture)
    if ([IO.Path]::GetDirectoryName($full) -cne (Join-Path $repository '.local') -or
        [IO.Path]::GetFileName($full) -cnotmatch '^binding-source-test-[a-f0-9]{32}$') { throw 'Unsafe binding fixture cleanup.' }
    Remove-Item -LiteralPath $full -Recurse -Force
}
