[CmdletBinding()]
param([Parameter(Mandatory)][string]$NativeArtifact)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/native-isar-artifact-inputs.ps1"
$artifact = Get-NativeIsarCandidateArtifact $NativeArtifact
$originalManifest = $artifact.manifestSha256
$fixture = Join-Path $NativeIsarRepository ('.local/bound-notice-tests-' + [Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $fixture
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$collector = Join-Path $PSScriptRoot 'collect-third-party-notices.ps1'
$first = Join-Path $fixture 'first'
$second = Join-Path $fixture 'second'
& $collector -NativeArtifact $artifact.directory -OutputDirectory $first | Out-Null
& (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $collector -NativeArtifact $artifact.directory -OutputDirectory $second *> (Join-Path $fixture 'child.txt')
if ($LASTEXITCODE -ne 0) { throw 'Separate-process notice collection failed.' }
$firstInventory = Read-NativeIsarArtifactJson (Join-Path $first 'third-party-notices.json')
if ($firstInventory.status -cne 'bound-native-notices-unqualified' -or $firstInventory.distributionReady -ne $false -or
    $firstInventory.noticesSha256 -cne (Get-NativeIsarDigest (Join-Path $first 'THIRD_PARTY_NOTICES.txt')) -or
    $firstInventory.native.artifactManifestSha256 -cne $originalManifest -or
    $firstInventory.native.dllSha256 -cne (Get-NativeIsarDigest $artifact.dll) -or
    $firstInventory.native.payload.Count -ne 196) { throw 'Combined notices binding mismatch.' }
$text = [IO.File]::ReadAllText((Join-Path $first 'THIRD_PARTY_NOTICES.txt'))
if (-not $text.Contains([IO.File]::ReadAllText((Join-Path $artifact.directory 'THIRD_PARTY_NATIVE_NOTICES.txt'))) -or
    $text.Contains($NativeIsarRepository) -or $text.Contains('Native transitive dependency coverage remain unverified')) { throw 'Combined native notice text mismatch.' }
$firstSnapshot = @{}
foreach ($file in Get-ChildItem -LiteralPath $first -File -Recurse) {
    $relative = [IO.Path]::GetRelativePath($first,$file.FullName)
    $hash = Get-NativeIsarDigest $file.FullName
    if ((Get-NativeIsarDigest (Join-Path $second $relative)) -cne $hash) { throw 'Combined notices cross-process mismatch.' }
    $firstSnapshot[$relative] = $hash
}
if ($firstSnapshot.Count -ne 199 -or @(Get-ChildItem -LiteralPath $second -File -Recurse).Count -ne 199) { throw 'Combined notices exact output inventory mismatch.' }
foreach ($file in $firstInventory.native.payload) {
    if ((Get-NativeIsarDigest (Join-Path $first ('native/' + $file.file))) -cne $file.sha256) { throw 'Native copied payload mismatch.' }
}
$rejected = $false
try { & $collector -NativeArtifact $artifact.directory -OutputDirectory $first | Out-Null } catch { $rejected = $_.Exception.Message -match 'fresh output' }
if (-not $rejected) { throw 'Existing output was not refused.' }
$corrupt = Join-Path ([IO.Path]::GetDirectoryName($artifact.directory)) ('artifact-' + [Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $corrupt
Copy-Item -LiteralPath $artifact.directory -Destination $corrupt -Recurse
[IO.File]::AppendAllText((Join-Path $corrupt 'THIRD_PARTY_NATIVE_NOTICES.txt'),'synthetic corruption')
$refusedOutput = Join-Path $fixture 'refused'
$rejected = $false
try { & $collector -NativeArtifact $corrupt -OutputDirectory $refusedOutput | Out-Null } catch { $rejected = $_.Exception.Message -match 'payload mismatch' }
if (-not $rejected -or (Test-Path -LiteralPath $refusedOutput)) { throw 'Corrupt native notice did not refuse before output.' }
foreach ($relative in $firstSnapshot.Keys) {
    if ((Get-NativeIsarDigest (Join-Path $first $relative)) -cne $firstSnapshot[$relative]) { throw 'Prior notice output changed after refusal.' }
}
if ((Get-NativeIsarCandidateArtifact $artifact.directory).manifestSha256 -cne $originalManifest) { throw 'Original native artifact changed.' }
$legacy = Join-Path $fixture 'legacy'
$legacyResult = & $collector -OutputDirectory $legacy
if ($legacyResult.Status -cne 'incomplete-native-chain' -or (Test-Path -LiteralPath (Join-Path $legacy 'THIRD_PARTY_NOTICES.txt'))) { throw 'Legacy private preview behavior changed.' }
Write-NativeIsarJson (Join-Path $fixture 'result.json') ([ordered]@{schemaVersion=1;passed=$true;distributionReady=$false;artifactManifestSha256=$originalManifest;outputFileCount=199;nativePayloadCount=196;scope='combined notices, corresponding source copies, cross-process determinism, corrupt/existing refusal and preservation; not qualification or activation'})
'BOUND_NATIVE_NOTICES_SOURCE_COPIES_CROSS_PROCESS_REFUSAL_AND_PRESERVATION_PASSED'
$fixture
# Retain all synthetic outputs; do not retry any previously denied cleanup.
