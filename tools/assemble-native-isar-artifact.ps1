[CmdletBinding()]
param([Parameter(Mandatory)][string]$Candidate,[Parameter(Mandatory)][string]$SourceDirectory,[Parameter(Mandatory)][string]$NoticeDirectory)
. "$PSScriptRoot/native-isar-artifact-inputs.ps1"
$Candidate = [IO.Path]::GetFullPath($Candidate,(Get-Location).ProviderPath)
$SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory,(Get-Location).ProviderPath)
$NoticeDirectory = [IO.Path]::GetFullPath($NoticeDirectory,(Get-Location).ProviderPath)
if ([IO.Path]::GetDirectoryName($Candidate) -cne (Join-Path $NativeIsarRepository '.local/native-isar') -or [IO.Path]::GetFileName($Candidate) -cnotmatch '^candidate-[a-f0-9]{32}$' -or
    [IO.Path]::GetDirectoryName($SourceDirectory) -cne $Candidate -or [IO.Path]::GetFileName($SourceDirectory) -cnotmatch '^sources-[a-f0-9]{32}$' -or
    [IO.Path]::GetDirectoryName($NoticeDirectory) -cne $Candidate -or [IO.Path]::GetFileName($NoticeDirectory) -cnotmatch '^notices-[a-f0-9]{32}$') { throw 'Artifact assembly requires owned matching component directories.' }
$recipe = Get-NativeIsarRecipe
$buildPath = Join-Path $Candidate 'native-build.json'
$buildHash = Get-NativeIsarDigest $buildPath
$build = Read-NativeIsarArtifactJson $buildPath
$source = Read-NativeIsarArtifactJson (Join-Path $SourceDirectory 'native-source-receipt.json')
$notices = Read-NativeIsarArtifactJson (Join-Path $NoticeDirectory 'native-notice-inventory.json')
if ($source.buildReceiptSha256 -cne $buildHash -or $notices.buildReceiptSha256 -cne $buildHash -or
    $source.noticeInventorySha256 -cne (Get-NativeIsarDigest (Join-Path $NoticeDirectory 'native-notice-inventory.json'))) { throw 'Artifact assembly component binding mismatch.' }
$output = Join-Path $Candidate ('artifact-' + [Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $output
[IO.Directory]::CreateDirectory($output) | Out-Null
$payload = [Collections.Generic.List[object]]::new()
$names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
function Copy-NativeArtifactInput {
    param([string]$Path,[string]$Name,[string]$ExpectedHash='')
    Assert-NativeIsarArchiveName $Name $output $names
    $hash = Get-NativeIsarDigest $Path
    if ($ExpectedHash -and $hash -cne $ExpectedHash) { throw 'Native artifact assembly input mismatch.' }
    $destination = Join-Path $output $Name
    Assert-NativeIsarPlainPath $destination
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    Copy-Item -LiteralPath $Path -Destination $destination
    if ((Get-NativeIsarDigest $destination) -cne $hash) { throw 'Native artifact assembly copied bytes mismatch.' }
    $payload.Add([ordered]@{file=$Name;sha256=$hash;length=(Get-Item -LiteralPath $destination).Length})
}
Copy-NativeArtifactInput (Join-Path $Candidate 'libisar.dll') 'libisar.dll' $build.dll.sha256
Copy-NativeArtifactInput $buildPath 'native-build.json' $buildHash
Copy-NativeArtifactInput (Join-Path $Candidate 'mdbx-patch.json') 'mdbx-patch.json' $build.patch.sha256
$nativeRoot = Join-Path $NativeIsarRepository 'native/isar-3.3.2'
foreach ($item in @(@{file='recipe.json';sha256=$build.recipeFileSha256},@{file='Cargo.lock';sha256=$build.cargoLockSha256},
    @{file='supplemental-licenses.json';sha256=$notices.supplementManifestSha256},@{file='rust-license-material.json';sha256=$notices.rustManifestSha256})) {
    Copy-NativeArtifactInput (Join-Path $nativeRoot $item.file) $item.file $item.sha256
}
foreach ($item in @(@{file='native-source-receipt.json';sha256=''},@{file='source-reproduction.json';sha256=$source.reproductionManifestSha256},
    @{file='NATIVE_SOURCES.zip';sha256=$source.sourceArchive.sha256},@{file='REPRODUCE.txt';sha256=''})) {
    Copy-NativeArtifactInput (Join-Path $SourceDirectory $item.file) $item.file $item.sha256
}
Copy-NativeArtifactInput (Join-Path $NoticeDirectory 'native-notice-inventory.json') 'native-notice-inventory.json' $source.noticeInventorySha256
Copy-NativeArtifactInput (Join-Path $NoticeDirectory 'THIRD_PARTY_NATIVE_NOTICES.txt') 'THIRD_PARTY_NATIVE_NOTICES.txt' $notices.notice.sha256
foreach ($item in $notices.files) {
    if ($item.file -cnotmatch '^licenses/') { throw 'Unexpected native artifact notice path.' }
    Copy-NativeArtifactInput (Join-Path $NoticeDirectory $item.file) $item.file $item.sha256
}
# The graph in the checked source ZIP is the exact component bound by notices.
$archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $output 'NATIVE_SOURCES.zip'))
try {
    $entry = $archive.GetEntry('native-dependencies.json')
    if (-not $entry -or $entry.Length -gt 1MB) { throw 'Source archive normalized graph missing.' }
    $input = $entry.Open()
    try {
        $path = Join-Path $output 'native-dependencies.json'
        $stream = [IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $input.CopyTo($stream) } finally { $stream.Dispose() }
    } finally { $input.Dispose() }
} finally { $archive.Dispose() }
$graphPath = Join-Path $output 'native-dependencies.json'
if ((Get-NativeIsarDigest $graphPath) -cne $source.graphSha256) { throw 'Source archive graph binding mismatch.' }
$payload.Add([ordered]@{file='native-dependencies.json';sha256=$source.graphSha256;length=(Get-Item -LiteralPath $graphPath).Length})
$manifest = [ordered]@{
    schemaVersion=1;product=$recipe.product;bindingVersion=$recipe.bindingVersion;target=$recipe.target
    state='artifact-assembled-unqualified';distributionReady=$false
    recipeSha256=Get-NativeIsarCanonicalDigest $recipe;cargoLockSha256=$recipe.cargoLockSha256;buildReceiptSha256=$buildHash
    source=[ordered]@{isarCommit=$recipe.isar.commit;isarArchiveSha256=$recipe.isar.sha256;mdbxCommit=$recipe.mdbx.commit;mdbxArchiveSha256=$recipe.mdbx.sha256;patchSha256=$build.patch.sha256}
    compiledInputDigests=$build.inputDigests
    compilation=[ordered]@{command=$build.command;features=$build.features;offlineCompilation=$build.offlineCompilation;rust=$build.compiler;msvc=$build.msvc;libclangVersion=$build.libclangVersion}
    files=@($payload | Sort-Object {$_.file} -CaseSensitive)
}
Write-NativeIsarJson (Join-Path $output 'native-artifact.json') $manifest
Get-NativeIsarCandidateArtifact $output | Out-Null
if ((Get-NativeIsarDigest $buildPath) -cne $buildHash) { throw 'Native build changed during artifact assembly.' }
Write-Output $output
