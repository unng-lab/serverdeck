[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/native-artifact.ps1"
$candidate=Get-NativeIsarCandidateArtifact $Artifact
$fixture=Join-Path $NativeIsarRepository ('.local/native-bundle-notices-' + [Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $fixture
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$bundle=Join-Path $fixture 'bundle'
[IO.Directory]::CreateDirectory($bundle) | Out-Null
Copy-Item -LiteralPath $candidate.dll -Destination (Join-Path $bundle 'libisar.dll')
Invoke-NativeArtifactCandidateScope $candidate.directory -Action {
    $refused=$false
    try { Copy-NativeArtifactBundleNotices -Bundle $bundle } catch { $refused=$_.Exception.Message -match 'preserved candidate scope' }
    if (-not $refused -or (Test-Path -LiteralPath (Join-Path $bundle 'notices'))) { throw 'Unpreserved notice attachment was not refused.' }
}
Invoke-NativeArtifactCandidateScope $candidate.directory -PreserveNormalBundles -Action {
    $contextRoot=[IO.Path]::GetDirectoryName($env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT)
    $refused=$false
    try { Copy-NativeArtifactBundleNotices -Bundle (Join-Path $NativeIsarRepository '.local/native-isar') } catch { $refused=$_.Exception.Message -match 'outside native inputs' }
    if (-not $refused -or @(Get-ChildItem -LiteralPath $contextRoot -Directory -Filter 'notices-*').Count -ne 0 -or
        @(Get-ChildItem -LiteralPath $contextRoot -File -Filter 'notice-attachment-*').Count -ne 0) { throw 'Exact native input root was not refused before notice generation.' }
    Copy-NativeArtifactBundleNotices -Bundle $bundle
    $notices=Join-Path $bundle 'notices'
    $original=Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $notices)
    Copy-NativeArtifactBundleNotices -Bundle $bundle
    if ((Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $notices)) -cne $original) { throw 'Repeated bundle notices changed.' }
    $contextRoot=[IO.Path]::GetDirectoryName($env:SERVERDECK_NATIVE_QUALIFICATION_CONTEXT)
    $receipts=@(Get-ChildItem -LiteralPath $contextRoot -File -Filter 'notice-attachment-*.json' | ForEach-Object {Read-NativeIsarArtifactJson $_.FullName})
    if ($receipts.Count -ne 2) { throw 'Notice attachment receipts missing.' }
    $preserved=@($receipts | Where-Object predecessor -NE $null)
    if ($preserved.Count -ne 1 -or $preserved[0].predecessorSha256 -cne $original -or
        (Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $preserved[0].predecessor)) -cne $original) { throw 'Previous candidate notice bytes were not preserved.' }
    [IO.File]::AppendAllText((Join-Path $bundle 'libisar.dll'),'synthetic mismatch')
    $refused=$false
    try { Copy-NativeArtifactBundleNotices -Bundle $bundle } catch { $refused=$_.Exception.Message -match 'bundle DLL mismatch' }
    if (-not $refused -or (Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $notices)) -cne $original) { throw 'DLL mismatch did not preserve prior notices.' }
    Write-NativeIsarJson (Join-Path $fixture 'result.json') ([ordered]@{schemaVersion=1;passed=$true;distributionReady=$false;noticeTreeSha256=$original;attachmentCount=2;scope='synthetic bundle attachment/repeat/previous-byte preservation and three refusals including exact native root before generation; not actual Debug/Release builds'})
}
'CANDIDATE_NOTICE_ATTACHMENT_REPEAT_PRESERVATION_AND_REFUSALS_PASSED'
$fixture
# Preserve all evidence without recursive cleanup.
