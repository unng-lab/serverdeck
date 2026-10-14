[CmdletBinding()]
param()
. "$PSScriptRoot/native-isar-inputs.ps1"
$fixture = Join-Path $NativeIsarRepository ('.local/native-isar-input-tests-' + [Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $fixture
[IO.Directory]::CreateDirectory($fixture) | Out-Null

function New-InputZip {
    param([string]$Path, [object[]]$Entries)
    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($definition in $Entries) {
            $entry = $zip.CreateEntry($definition.name)
            if ($definition.ContainsKey('attributes')) { $entry.ExternalAttributes = $definition.attributes }
            $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
            try { $writer.Write($definition.text) } finally { $writer.Dispose() }
        }
    } finally { $zip.Dispose() }
}

$rejected = 0
$cases = @(
    @{name='traversal';entries=@(@{name='../escape';text='x'})},
    @{name='absolute';entries=@(@{name='/escape';text='x'})},
    @{name='ads';entries=@(@{name='safe:stream';text='x'})},
    @{name='device';entries=@(@{name='CON.txt';text='x'})},
    @{name='duplicate';entries=@(@{name='a';text='x'},@{name='A';text='y'})},
    @{name='escaped-link';entries=@(@{name='README';text='../escape';attributes=[int]0xa0000000})},
    @{name='missing-link';entries=@(@{name='README';text='missing';attributes=[int]0xa0000000})},
    @{name='link-chain';entries=@(@{name='a';text='b';attributes=[int]0xa0000000},@{name='b';text='a';attributes=[int]0xa0000000})}
)
foreach ($case in $cases) {
    $archive = Join-Path $fixture ($case.name + '.zip')
    $destination = Join-Path $fixture $case.name
    New-InputZip $archive $case.entries
    $before = Get-NativeIsarDigest $archive
    $failed = $false
    try { Expand-NativeIsarArchive $archive $destination zip } catch { $failed = $true }
    if (-not $failed -or (Test-Path -LiteralPath $destination) -or (Get-NativeIsarDigest $archive) -cne $before) {
        throw 'Unsafe archive acceptance or failed input preservation.'
    }
    $rejected++
}
$good = Join-Path $fixture 'good.zip'
New-InputZip $good @(@{name='root/README';text='docs/README';attributes=[int]0xa0000000},@{name='root/docs/README';text='safe readme'})
$expanded = Join-Path $fixture 'good'
Expand-NativeIsarArchive $good $expanded zip
if ([IO.File]::ReadAllText((Join-Path $expanded 'root/README')) -cne 'safe readme' -or
    (Get-Item -LiteralPath (Join-Path $expanded 'root/README')).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'Contained link was not materialized as a regular file.'
}
$record = Get-Content -LiteralPath ($expanded + '.materialized-links.json') -Raw | ConvertFrom-Json
if ($record.link -cne 'root/README' -or $record.target -cne 'root/docs/README') { throw 'Missing materialization provenance.' }
$alreadyExistsRejected = $false
try { Expand-NativeIsarArchive $good $expanded zip } catch { $alreadyExistsRejected = $true }
if (-not $alreadyExistsRejected -or [IO.File]::ReadAllText((Join-Path $expanded 'root/README')) -cne 'safe readme') { throw 'Existing output was modified.' }
$recipe = Get-NativeIsarRecipe
if ($recipe.bindingVersion -cne '3.3.2') { throw 'Recipe identity check failed.' }
$amplified = Join-Path $fixture 'amplified.zip'
New-InputZip $amplified @(@{name='payload';text=('x' * 24)},@{name='a';text='payload';attributes=[int]0xa0000000},@{name='b';text='payload';attributes=[int]0xa0000000})
$amplifiedDigest = Get-NativeIsarDigest $amplified
$amplifiedDestination = Join-Path $fixture 'amplified'
$budgetFailed = $false
try { Expand-NativeIsarArchive $amplified $amplifiedDestination zip -MaximumExpandedBytes 48 } catch {
    if ($_.Exception.Message -cne 'Native ZIP materialization exceeds extraction bounds.') { throw }
    $budgetFailed = $true
}
if (-not $budgetFailed -or (Test-Path -LiteralPath $amplifiedDestination) -or
    (Get-NativeIsarDigest $amplified) -cne $amplifiedDigest -or
    [IO.File]::ReadAllText((Join-Path $expanded 'root/README')) -cne 'safe readme') { throw 'Materialized ZIP budget failure did not preserve inputs/output.' }
Write-Output "NATIVE_INPUT_ARCHIVE_NEGATIVES_PASSED=$rejected"
Write-Output 'NATIVE_INPUT_CONTAINED_LINK_AND_PRESERVATION_PASSED'
Write-Output 'NATIVE_INPUT_MATERIALIZED_BYTE_BUDGET_REJECTED_BEFORE_EXTRACTION'
$pwsh=(Get-Process -Id $PID).Path
$dualOutput=Join-Path $fixture 'dual-output.ps1'
[IO.File]::WriteAllText($dualOutput,"[Console]::Out.Write(('o'*1048576)); [Console]::Error.Write(('e'*1048576))")
$captured=Invoke-NativeIsarArchiveProcess $pwsh @('-NoProfile','-File',$dualOutput)
if($captured.Length -ne 1048576 -or $captured -cne ('o'*1048576)){throw 'Native archive dual-pipe capture failed.'}
$slowChild=Join-Path $fixture 'slow-child.ps1'
$slowPid=Join-Path $fixture 'slow-child.pid'
[IO.File]::WriteAllText($slowChild,'param([string]$PidFile); [IO.File]::WriteAllText($PidFile,[string]$PID); Start-Sleep -Seconds 30')
$timeoutRejected=$false
try { Invoke-NativeIsarArchiveProcess $pwsh @('-NoProfile','-File',$slowChild,$slowPid) -TimeoutSeconds 1 | Out-Null } catch {
    if($_.Exception.Message -cne 'Native archive child timed out.'){throw}
    $timeoutRejected=$true
}
if(-not $timeoutRejected -or -not (Test-Path -LiteralPath $slowPid)){throw 'Native archive timeout was not exercised.'}
$ownedChildId=[int][IO.File]::ReadAllText($slowPid)
if(Get-Process -Id $ownedChildId -ErrorAction SilentlyContinue){throw 'Timed-out native archive child remains alive.'}
$failedChild=Join-Path $fixture 'failed-child.ps1'
[IO.File]::WriteAllText($failedChild,"[Console]::Error.Write('PRIVATE_SYNTHETIC_ERROR'); exit 7")
$failureRejected=$false
try { Invoke-NativeIsarArchiveProcess $pwsh @('-NoProfile','-File',$failedChild) | Out-Null } catch {
    if($_.Exception.Message -cne 'Native archive child failed.'){throw}
    $failureRejected=$true
}
if(-not $failureRejected){throw 'Native archive child failure accepted.'}
Write-Output 'NATIVE_INPUT_DUAL_PIPE_TIMEOUT_AND_SAFE_FAILURE_PASSED'
$tarCases=@(
    @{name='tar-traversal';entry='../escape';type=[System.Formats.Tar.TarEntryType]::RegularFile},
    @{name='tar-symbolic';entry='link';type=[System.Formats.Tar.TarEntryType]::SymbolicLink},
    @{name='tar-hardlink';entry='link';type=[System.Formats.Tar.TarEntryType]::HardLink},
    @{name='tar-good';entry='root/payload';type=[System.Formats.Tar.TarEntryType]::RegularFile}
)
foreach($tarCase in $tarCases){
    $archivePath=Join-Path $fixture ($tarCase.name+'.tar.gz')
    $file=[IO.File]::Open($archivePath,[IO.FileMode]::CreateNew)
    $gzip=[IO.Compression.GZipStream]::new($file,[IO.Compression.CompressionMode]::Compress)
    $writer=[System.Formats.Tar.TarWriter]::new($gzip)
    $payload=[IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes('owned gzip payload'))
    try {
        $entry=[System.Formats.Tar.PaxTarEntry]::new($tarCase.type,$tarCase.entry)
        if($tarCase.type -eq [System.Formats.Tar.TarEntryType]::RegularFile){$entry.DataStream=$payload}
        else {$entry.LinkName='outside'}
        $writer.WriteEntry($entry)
    } finally {$writer.Dispose();$gzip.Dispose();$file.Dispose();$payload.Dispose()}
    $archiveHash=Get-NativeIsarDigest $archivePath
    $destinationPath=Join-Path $fixture $tarCase.name
    $failed=$false
    try {Expand-NativeIsarArchive $archivePath $destinationPath 'tar.gz'} catch {$failed=$true}
    if($tarCase.name -eq 'tar-good'){
        if($failed -or [IO.File]::ReadAllText((Join-Path $destinationPath 'root/payload')) -cne 'owned gzip payload'){throw 'Gzip TAR positive control failed.'}
    } elseif(-not $failed -or (Test-Path -LiteralPath $destinationPath)){throw 'Unsafe gzip TAR was extracted.'}
    if((Get-NativeIsarDigest $archivePath) -cne $archiveHash){throw 'Gzip TAR test changed its input.'}
}
Write-Output 'NATIVE_INPUT_GZIP_TAR_TRAVERSAL_LINK_PREFLIGHT_AND_POSITIVE_PASSED'
Write-Output $fixture
