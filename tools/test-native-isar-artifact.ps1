[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact,[Parameter(Mandatory)][string]$SourceDirectory,[Parameter(Mandatory)][string]$NoticeDirectory,[switch]$Child)
. "$PSScriptRoot/native-isar-artifact-inputs.ps1"
$selection = Get-NativeIsarCandidateArtifact $Artifact
$candidate = [IO.Path]::GetDirectoryName($selection.directory)
if ($Child) {
    & "$PSScriptRoot/assemble-native-isar-artifact.ps1" -Candidate $candidate -SourceDirectory $SourceDirectory -NoticeDirectory $NoticeDirectory
    return
}
$manifestHash = $selection.manifestSha256
$dllHash = Get-NativeIsarDigest $selection.dll
$zipHash = Get-NativeIsarDigest (Join-Path $selection.directory 'NATIVE_SOURCES.zip')
$sample = '{"z":[{"b":2,"a":1}],"n":null,"e":[],"a":"x","nested":[[]],"one":{"solo":[null]},"emptyObject":{}}' | ConvertFrom-Json
$canonical = ConvertTo-Json -InputObject (ConvertTo-NativeIsarCanonicalValue $sample) -Depth 10 -Compress
if ($canonical -cne '{"a":"x","e":[],"emptyObject":{},"n":null,"nested":[[]],"one":{"solo":[null]},"z":[{"a":1,"b":2}]}') { throw 'Canonical native JSON lost array/null shape.' }
$same = '{"emptyObject":{},"one":{"solo":[null]},"nested":[[]],"a":"x","e":[],"z":[{"a":1,"b":2}],"n":null}' | ConvertFrom-Json
if ((Get-NativeIsarCanonicalDigest $sample) -cne (Get-NativeIsarCanonicalDigest $same)) { throw 'Canonical native JSON property-order drift.' }
$repeat = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $PSCommandPath -Child -Artifact $Artifact -SourceDirectory $SourceDirectory -NoticeDirectory $NoticeDirectory
if ($LASTEXITCODE -ne 0 -or $repeat -isnot [string] -or (Get-NativeIsarDigest (Join-Path $repeat 'native-artifact.json')) -cne $manifestHash) { throw 'Native artifact manifest cross-process determinism failed.' }
function New-NativeArtifactClone {
    $root=Join-Path $candidate ('artifact-' + [Guid]::NewGuid().ToString('N'))
    Assert-NativeIsarPlainPath $root
    [IO.Directory]::CreateDirectory($root) | Out-Null
    foreach ($entry in Get-ChildItem -LiteralPath $selection.directory -Force) { Copy-Item -LiteralPath $entry.FullName -Destination $root -Recurse }
    return $root
}
function Save-NativeFixtureJson {
    param([string]$Path,[object]$Value)
    [IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $Value -Depth 64),[Text.UTF8Encoding]::new($false))
}
function Update-NativeFixturePayload {
    param([string]$Root,[object]$Manifest,[string]$Name)
    $path=Join-Path $Root $Name
    $file=$Manifest.files | Where-Object file -CEQ $Name
    $file.sha256=Get-NativeIsarDigest $path;$file.length=(Get-Item -LiteralPath $path).Length
}
function Set-NativeFixtureZipEntry {
    param([string]$Root,[string]$Prefix,[string]$ReplacementName='', [string]$Payload='coherent changed source input')
    $zip=[IO.Compression.ZipFile]::Open((Join-Path $Root 'NATIVE_SOURCES.zip'),[IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry=@($zip.Entries | Where-Object { $_.FullName.StartsWith($Prefix,[StringComparison]::Ordinal) })[0]
        if (-not $entry) { throw 'Fixture ZIP entry not found.' }
        $name=$entry.FullName
        if ($ReplacementName) { $name=$ReplacementName }
        $entry.Delete()
        $replacement=$zip.CreateEntry($name)
        $replacement.ExternalAttributes=0
        $stream=$replacement.Open()
        try { $bytes=[Text.UTF8Encoding]::new($false).GetBytes($Payload);$stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    } finally { $zip.Dispose() }
}
function Update-NativeFixtureSourceChain {
    param([string]$Root,[object]$Manifest)
    Update-NativeFixturePayload $Root $Manifest 'NATIVE_SOURCES.zip'
    $sourcePath=Join-Path $Root 'native-source-receipt.json'
    $source=Read-NativeIsarArtifactJson $sourcePath
    $zip=$Manifest.files | Where-Object file -CEQ 'NATIVE_SOURCES.zip'
    $source.sourceArchive.sha256=$zip.sha256;$source.sourceArchive.length=$zip.length
    $source.reproductionManifestSha256=Get-NativeIsarDigest (Join-Path $Root 'source-reproduction.json')
    Save-NativeFixtureJson $sourcePath $source
    Update-NativeFixturePayload $Root $Manifest 'native-source-receipt.json'
    Update-NativeFixturePayload $Root $Manifest 'source-reproduction.json'
    Save-NativeFixtureJson (Join-Path $Root 'native-artifact.json') $Manifest
}
$fixtures = @()
foreach ($case in @('dll','missing-notice','source-zip','binding','claimed-qualified','coherent-sidecar','unlisted','coherent-source','coherent-vendor','coherent-private','coherent-reproduction-qualified')) {
    $root=New-NativeArtifactClone
    $fixtures += $root
    $manifestPath=Join-Path $root 'native-artifact.json'
    $manifest=Read-NativeIsarArtifactJson $manifestPath
    switch ($case) {
        'dll' { [IO.File]::WriteAllText((Join-Path $root 'libisar.dll'),'corrupted DLL') }
        'missing-notice' { Remove-Item -LiteralPath (Join-Path $root 'licenses/MPL-2.0.txt') }
        'source-zip' { [IO.File]::WriteAllText((Join-Path $root 'NATIVE_SOURCES.zip'),'corrupted source ZIP') }
        'unlisted' { [IO.File]::WriteAllText((Join-Path $root 'unexpected.private.json'),'unlisted diagnostic data') }
        'binding' { $manifest.buildReceiptSha256='0' * 64; Save-NativeFixtureJson $manifestPath $manifest }
        'claimed-qualified' { $manifest.state='qualified';$manifest.distributionReady=$true; Save-NativeFixtureJson $manifestPath $manifest }
        'coherent-source' { Set-NativeFixtureZipEntry $root 'source/';Update-NativeFixtureSourceChain $root $manifest }
        'coherent-vendor' { Set-NativeFixtureZipEntry $root 'vendor/';Update-NativeFixtureSourceChain $root $manifest }
        'coherent-private' { Set-NativeFixtureZipEntry $root 'vendor/' 'unexpected.private.json';Update-NativeFixtureSourceChain $root $manifest }
        'coherent-reproduction-qualified' {
            $path=Join-Path $root 'source-reproduction.json'
            $reproduction=Read-NativeIsarArtifactJson $path
            $reproduction.state='qualified';$reproduction.distributionReady=$true
            Save-NativeFixtureJson $path $reproduction
            Set-NativeFixtureZipEntry $root 'source-reproduction.json' -Payload ([IO.File]::ReadAllText($path))
            Update-NativeFixtureSourceChain $root $manifest
        }
        'coherent-sidecar' {
            # Rewrite both an outside sidecar and its manifest hash. The exact
            # unchanged source ZIP must still expose the contradictory copy.
            $readme=Join-Path $root 'REPRODUCE.txt'
            [IO.File]::AppendAllText($readme,'rewritten outside source metadata')
            $file=$manifest.files | Where-Object file -eq 'REPRODUCE.txt'
            $file.sha256=Get-NativeIsarDigest $readme;$file.length=(Get-Item -LiteralPath $readme).Length
            Save-NativeFixtureJson $manifestPath $manifest
        }
    }
    $refused=$false
    try { Get-NativeIsarCandidateArtifact $root | Out-Null } catch {
        $expected=switch($case) {
            'missing-notice' {'Missing native input file.'}
            'binding' {'Native artifact provenance chain mismatch.'}
            'claimed-qualified' {'Native artifact identity mismatch.'}
            'coherent-sidecar' {'Native artifact embedded source reference mismatch.'}
            'unlisted' {'Native artifact contains an unlisted payload.'}
            'coherent-source' {'Native artifact source archive compiled-input tree mismatch.'}
            'coherent-vendor' {'Native artifact source archive compiled-input tree mismatch.'}
            'coherent-private' {'Native artifact source archive contains an unlisted payload.'}
            'coherent-reproduction-qualified' {'Native artifact component state mismatch.'}
            default {'Native artifact payload mismatch.'}
        }
        if ($_.Exception.Message -cne $expected) { throw }
        $refused=$true
    }
    if (-not $refused) { throw 'Native artifact corruption/qualification claim was accepted.' }
}
if ((Get-NativeIsarDigest (Join-Path $selection.directory 'native-artifact.json')) -cne $manifestHash -or
    (Get-NativeIsarDigest $selection.dll) -cne $dllHash -or (Get-NativeIsarDigest (Join-Path $selection.directory 'NATIVE_SOURCES.zip')) -cne $zipHash) { throw 'Native artifact prior output changed.' }
'NATIVE_ARTIFACT_197_FILES_CANONICAL_ARRAYS_CROSS_PROCESS_AND_ELEVEN_REFUSALS_PRESERVATION_PASSED'
$repeat
$fixtures
