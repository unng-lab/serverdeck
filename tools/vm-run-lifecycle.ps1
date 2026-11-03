[CmdletBinding()]
param(
    [string]$EvidenceDirectory = '',
    [ValidateSet('lifecycle', 'recovery', 'shell', 'acl')][string]$Suite = 'lifecycle'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$kitRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if (!$EvidenceDirectory) {
    $EvidenceDirectory = Join-Path ($kitRoot + '-evidence') ("lifecycle-{0}" -f [guid]::NewGuid())
}
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
$walk = $EvidenceDirectory
while ($walk) {
    if ((Test-Path -LiteralPath $walk) -and
        ((Get-Item -Force -LiteralPath $walk).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Reparse points are forbidden in lifecycle evidence destinations'
    }
    $walk = Split-Path -Parent $walk
}
if (Test-Path -LiteralPath $EvidenceDirectory) { throw 'Use a new lifecycle evidence directory' }
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$preflightPath = Join-Path $EvidenceDirectory 'native-preflight.json'
& (Join-Path $kitRoot 'run-native.ps1') -RequireCleanVm -EvidencePath $preflightPath
$preflightCode = $LASTEXITCODE
$preflight = Get-Content -Raw -Encoding UTF8 -LiteralPath $preflightPath | ConvertFrom-Json
$report = [ordered]@{
    schemaVersion = 1; timestampUtc = [DateTime]::UtcNow.ToString('o')
    scope = 'Real EXE lifecycle/recovery scenarios only; full release acceptance is open'
    suite = $Suite
    productSHA256 = $preflight.productSHA256
    verificationManifestSHA256 = $preflight.verificationManifestSHA256
    environment = $preflight.environment; fullVmAcceptance = $false
    status = 'notRun'; driverStarted = $false; timedOut = $false; exitCode = $null
    stdout = ''; stderr = ''; journalError = ''; events = @()
}
function Save-LifecycleReport {
    $report | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'lifecycle-results.json') -Encoding UTF8
}
if ($preflightCode -ne 0) {
    $report.status = if ($preflightCode -eq 2) { 'blockedByVmPrerequisites' } else { 'nativeContractsFailed' }
    Save-LifecycleReport
    Write-Output "Lifecycle driver was not started. Evidence: $EvidenceDirectory"
    exit $preflightCode
}
if (!$preflight.environment.cleanVmPrerequisitesSatisfied -or $preflight.status -ne 'nativeContractsPassed') {
    throw 'Native preflight did not establish a clean disposable VM'
}
$product = Join-Path $kitRoot 'product/ServerDeck.exe'
$driver = Join-Path $kitRoot 'verification/release_lifecycle.exe'
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $kitRoot 'manifest.json') | ConvertFrom-Json
$entry = @($manifest.files | Where-Object path -EQ 'verification/release_lifecycle.exe')
if ($entry.Count -ne 1 -or
    (Get-FileHash -LiteralPath $driver -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry[0].sha256 -or
    (Get-FileHash -LiteralPath $product -Algorithm SHA256).Hash.ToLowerInvariant() -ne $report.productSHA256) {
    throw 'Lifecycle inputs differ from the verified kit'
}
$journalPath = Join-Path $EvidenceDirectory 'driver.jsonl'
. (Join-Path $kitRoot 'lifecycle-journal.ps1')
if ($product.Contains('"') -or $journalPath.Contains('"')) { throw 'Invalid native path' }
$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = $driver
$mode = switch ($Suite) { 'recovery' { '--run-recovery' }; 'shell' { '--run-shell' }; 'acl' { '--run-acl' }; default { '--run' } }
$start.Arguments = "$mode --exe `"$product`" --output `"$journalPath`""
$start.UseShellExecute = $false; $start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
$start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
$start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
$process = [Diagnostics.Process]::Start($start)
try {
    $report.driverStarted = $true
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $watchdog = switch ($Suite) { 'recovery' { 540000 }; 'shell' { 300000 }; 'acl' { 300000 }; default { 180000 } }
    $report.timedOut = !$process.WaitForExit($watchdog)
    if ($report.timedOut) { $process.Kill(); $process.WaitForExit() }
    $report.exitCode = $process.ExitCode
    $report.stdout = $stdout.Result; $report.stderr = $stderr.Result
    $scenariosMatch = $false
    try {
        $lines = @(Get-Content -Encoding UTF8 -LiteralPath $journalPath -ErrorAction Stop)
        $parsed = Read-LifecycleJournal -Lines $lines -Suite $Suite
        $report.events = $parsed.events; $report.journalError = $parsed.journalError
        $scenariosMatch = $parsed.scenariosMatch
    } catch { $report.journalError = $_.Exception.Message }
    $allPassed = !$report.timedOut -and !$report.journalError -and $report.exitCode -eq 0 -and $scenariosMatch
    $report.status = if ($Suite -eq 'recovery') {
        if ($allPassed) { 'lifecycleAndRecoveryScenariosPassed' } else { 'lifecycleAndRecoveryScenariosFailed' }
    } elseif ($Suite -eq 'shell') {
        if ($allPassed) { 'lifecycleAndShellScenariosPassed' } else { 'lifecycleAndShellScenariosFailed' }
    } elseif ($Suite -eq 'acl') {
        if ($allPassed) { 'lifecycleAndAclScenariosPassed' } else { 'lifecycleAndAclScenariosFailed' }
    } else {
        if ($allPassed) { 'lifecycleScenariosPassed' } else { 'lifecycleScenariosFailed' }
    }
    Save-LifecycleReport
    Write-Output "Lifecycle evidence: $EvidenceDirectory; remaining fault/VM acceptance is open."
    if (!$allPassed) { exit 1 }
} finally { $process.Dispose() }
exit 0
