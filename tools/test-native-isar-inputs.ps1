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
Write-Output $fixture
