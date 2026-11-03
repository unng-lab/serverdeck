[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][uint32]$ProductProcessId,
    [string]$ExePath = '',
    [string]$EvidencePath = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$kitRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if (!$ExePath) { $ExePath = Join-Path $kitRoot 'product/ServerDeck.exe' }
if (!$EvidencePath) {
    $EvidencePath = Join-Path ($kitRoot + '-evidence') ("process-{0}.json" -f [guid]::NewGuid())
}
function Assert-PlainPath([string]$Path) {
    $walk = [IO.Path]::GetFullPath($Path)
    while ($walk) {
        if ((Test-Path -LiteralPath $walk) -and
            ((Get-Item -Force -LiteralPath $walk).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Reparse points are forbidden for process evidence inputs and output'
        }
        $walk = Split-Path -Parent $walk
    }
}
$manifestPath = Join-Path $kitRoot 'manifest.json'
$observerPath = Join-Path $kitRoot 'verification/release_observer.exe'
foreach ($path in @($manifestPath, $observerPath, $ExePath, $EvidencePath)) { Assert-PlainPath $path }
if (Test-Path -LiteralPath $EvidencePath) { throw 'Process evidence must use a new output file' }
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) { throw 'Unsupported verification kit format' }
$observerEntry = @($manifest.files | Where-Object path -EQ 'verification/release_observer.exe')
$productEntry = @($manifest.files | Where-Object path -EQ 'product/ServerDeck.exe')
if ($observerEntry.Count -ne 1 -or $productEntry.Count -ne 1) { throw 'Missing or duplicated process evidence inputs' }
$observerDigest = (Get-FileHash -LiteralPath $observerPath -Algorithm SHA256).Hash.ToLowerInvariant()
$productDigest = (Get-FileHash -LiteralPath $ExePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($observerDigest -ne $observerEntry[0].sha256 -or
    $productDigest -ne $productEntry[0].sha256 -or $productDigest -ne $manifest.productSHA256) {
    throw 'Process evidence inputs differ from the verification kit'
}
$evidenceParent = Split-Path -Parent ([IO.Path]::GetFullPath($EvidencePath))
New-Item -ItemType Directory -Force -Path $evidenceParent | Out-Null
$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = $observerPath
$absoluteExe = [IO.Path]::GetFullPath($ExePath)
# Windows filenames cannot contain a quote; reject rather than invent an
# escaping convention for arbitrary command-line text. No shell is involved.
if ($absoluteExe.Contains('"')) { throw 'Invalid executable path' }
$start.Arguments = "--pid $ProductProcessId --exe `"$absoluteExe`""
$start.UseShellExecute = $false; $start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
$start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
$start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
$begin = [DateTime]::UtcNow
$process = [Diagnostics.Process]::Start($start)
try {
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $timedOut = !$process.WaitForExit(15000)
    if ($timedOut) { $process.Kill(); $process.WaitForExit() }
    $result = [ordered]@{
        schemaVersion = 1; scope = 'Read-only process evidence; no GUI/VM acceptance conclusion'
        startedUtc = $begin.ToString('o'); completedUtc = [DateTime]::UtcNow.ToString('o')
        productSHA256 = $productDigest; observerSHA256 = $observerDigest
        verificationManifestSHA256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        requestedPid = $ProductProcessId; requestedExe = $absoluteExe
        timedOut = $timedOut; exitCode = $process.ExitCode
        stderr = $stderr.Result; snapshot = $null; fullVmAcceptance = $false
    }
    if (!$timedOut -and $process.ExitCode -eq 0) {
        $snapshot = $stdout.Result | ConvertFrom-Json
        if ($snapshot.schemaVersion -ne 1 -or $snapshot.pid -ne $ProductProcessId -or
            $snapshot.imagePath -ne $absoluteExe) { throw 'Invalid process observer response' }
        $result.snapshot = $snapshot
    }
    $json = $result | ConvertTo-Json -Depth 10
    # CreateNew prevents overwriting an earlier observation even if a second
    # capture races between the existence check and publication.
    $stream = [IO.File]::Open([IO.Path]::GetFullPath($EvidencePath), [IO.FileMode]::CreateNew,
                             [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    Write-Output "Process evidence: $EvidencePath"
    if ($timedOut -or $process.ExitCode -ne 0) { exit 1 }
} finally { $process.Dispose() }
exit 0
