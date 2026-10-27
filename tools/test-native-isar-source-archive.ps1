[CmdletBinding()]
param([switch]$Child, [string]$Fixture = '')
. "$PSScriptRoot/native-isar-inputs.ps1"
. "$PSScriptRoot/native-isar-source-archive.ps1"
if ($Child) {
    $Fixture = [IO.Path]::GetFullPath($Fixture)
    if ([IO.Path]::GetDirectoryName($Fixture) -cne (Join-Path $NativeIsarRepository '.local') -or
        [IO.Path]::GetFileName($Fixture) -cnotmatch '^native-source-archive-tests-[a-f0-9]{32}$') { throw 'Expected owned archive test fixture.' }
} else {
    $Fixture = Join-Path $NativeIsarRepository ('.local/native-source-archive-tests-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($Fixture) | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $Fixture 'first.bin'),[byte[]](0,1,2,255))
    [IO.File]::WriteAllText((Join-Path $Fixture 'second.txt'),'complete source input',[Text.UTF8Encoding]::new($false))
}
$files = @(
    [ordered]@{file='vendor/Unicode/источник.txt';path=Join-Path $Fixture 'second.txt';sha256=Get-NativeIsarDigest (Join-Path $Fixture 'second.txt')},
    [ordered]@{file='archives/first.bin';path=Join-Path $Fixture 'first.bin';sha256=Get-NativeIsarDigest (Join-Path $Fixture 'first.bin')}
)
if ($Child) {
    [Array]::Reverse($files)
    Write-NativeIsarSourceArchive (Join-Path $Fixture 'child.zip') $files
    return
}
$successful = Join-Path $Fixture 'first.zip'
Write-NativeIsarSourceArchive $successful $files
$digest = Get-NativeIsarDigest $successful
& (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $PSCommandPath -Child -Fixture $Fixture
if ($LASTEXITCODE -ne 0 -or (Get-NativeIsarDigest (Join-Path $Fixture 'child.zip')) -cne $digest) { throw 'Source ZIP cross-process determinism failed.' }
$archive = [IO.Compression.ZipFile]::OpenRead($successful)
try {
    if ($archive.Entries.Count -ne 2 -or $archive.Entries[0].FullName -cne 'archives/first.bin') { throw 'Source ZIP entry inventory/order mismatch.' }
    foreach ($file in $files) {
        $entry = $archive.GetEntry($file.file)
        if (-not $entry -or $entry.LastWriteTime.Year -ne 1980) { throw 'Source ZIP metadata mismatch.' }
        $stream = $entry.Open()
        try {
            $hash = [Security.Cryptography.SHA256]::HashData($stream)
            if ([Convert]::ToHexString($hash).ToLowerInvariant() -cne $file.sha256) { throw 'Source ZIP exact bytes mismatch.' }
        } finally { $stream.Dispose() }
    }
} finally { $archive.Dispose() }
foreach ($name in @('../escape','/absolute','C:/drive','input:stream','CON.txt','nested\\file','vendor/Unicode/источник.txt')) {
    $bad = [ordered]@{file=$name;path=$files[0].path;sha256=$files[0].sha256}
    $destination = Join-Path $Fixture ('bad-' + [Guid]::NewGuid().ToString('N') + '.zip')
    $refused = $false
    try { Write-NativeIsarSourceArchive $destination @($files[0],$bad) } catch {
        if ($_.Exception.Message -notmatch 'Unsafe native archive|Duplicate native archive') { throw }
        $refused = $true
    }
    if (-not $refused -or (Test-Path -LiteralPath $destination)) { throw 'Unsafe source ZIP not refused before creation.' }
}
$refused = $false
try { Write-NativeIsarSourceArchive $successful $files } catch {
    if ($_.Exception.Message -cne 'Native source archive output already exists.') { throw }
    $refused = $true
}
if (-not $refused -or (Get-NativeIsarDigest $successful) -cne $digest) { throw 'Source ZIP prior output preservation failed.' }
$bad = [ordered]@{file='valid.txt';path=$files[0].path;sha256='0' * 64}
$destination = Join-Path $Fixture 'bad-digest.zip'
$refused = $false
try { Write-NativeIsarSourceArchive $destination @($bad) } catch {
    if ($_.Exception.Message -cne 'Native source archive input digest mismatch.') { throw }
    $refused = $true
}
if (-not $refused -or (Test-Path -LiteralPath $destination)) { throw 'Source ZIP changed input not refused.' }
'NATIVE_SOURCE_ZIP_EXACT_BYTES_CROSS_PROCESS_ORDER_UNICODE_REFUSAL_PRESERVATION_PASSED'
$Fixture
