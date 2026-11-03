[CmdletBinding()]
param([switch]$RequireCleanVm, [string]$EvidenceDirectory = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$kitRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if (!$EvidenceDirectory) { $EvidenceDirectory = Join-Path ($kitRoot + '-evidence') ("durability-{0}" -f [guid]::NewGuid()) }
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
$walk = $EvidenceDirectory
while ($walk) {
    if ((Test-Path -LiteralPath $walk) -and
        ((Get-Item -Force -LiteralPath $walk).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Reparse point in durability evidence destination'
    }
    $walk = Split-Path -Parent $walk
}
if (Test-Path -LiteralPath $EvidenceDirectory) { throw 'Use a new durability evidence directory' }
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$preflightPath = Join-Path $EvidenceDirectory 'native-preflight.json'
& (Join-Path $kitRoot 'run-native.ps1') -RequireCleanVm:$RequireCleanVm -EvidencePath $preflightPath
$preflightCode = $LASTEXITCODE
$preflight = Get-Content -Raw -Encoding UTF8 -LiteralPath $preflightPath | ConvertFrom-Json
$report = [ordered]@{
    schemaVersion = 1; timestampUtc = [DateTime]::UtcNow.ToString('o')
    scope = 'Synthetic WorkspaceStore/Isar process-termination fixture; GUI/native publication/complete VM acceptance are not tested'
    productSHA256 = $preflight.productSHA256; verificationManifestSHA256 = $preflight.verificationManifestSHA256
    environment = $preflight.environment; requireCleanVm = [bool]$RequireCleanVm
    fullVmAcceptance = $false; fixtureStarted = $false; status = 'notRun'; error = ''; cases = @()
}
function Save-DurabilityReport {
    $report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'durability-results.json') -Encoding UTF8
}
if ($preflightCode -ne 0) {
    $report.status = if ($preflightCode -eq 2) { 'blockedByVmPrerequisites' } else { 'nativeContractsFailed' }
    Save-DurabilityReport
    Write-Output "Durability fixture not started. Evidence: $EvidenceDirectory"
    exit $preflightCode
}
function Start-Captured([string]$File, [string[]]$Arguments) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $File; $start.WorkingDirectory = Join-Path $kitRoot 'verification'
    foreach ($value in $Arguments) { if ($value.Contains('"')) { throw 'Invalid fixture argument' } }
    $start.Arguments = ($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $process = [Diagnostics.Process]::Start($start)
    return @{process = $process; stdout = $process.StandardOutput.ReadToEndAsync(); stderr = $process.StandardError.ReadToEndAsync()}
}
function Stop-OwnedProcess($Capture) {
    if (!$Capture.process.HasExited) {
        $Capture.process.Kill()
        if (!$Capture.process.WaitForExit(5000)) { throw 'Owned fixture cleanup timed out; reset the disposable test environment' }
    }
}
function Complete-Captured([string]$File, [string[]]$Arguments) {
    $capture = Start-Captured $File $Arguments
    try {
        $timedOut = !$capture.process.WaitForExit(30000)
        if ($timedOut) { Stop-OwnedProcess $capture }
        return @{exitCode = $capture.process.ExitCode; timedOut = $timedOut; stdout = $capture.stdout.Result; stderr = $capture.stderr.Result}
    } finally { Stop-OwnedProcess $capture; $capture.process.Dispose() }
}
function Plain-ModulePath([string]$Path) {
    if ($Path.StartsWith('\\?\UNC\')) { $Path = '\\' + $Path.Substring(8) }
    elseif ($Path.StartsWith('\\?\')) { $Path = $Path.Substring(4) }
    return [IO.Path]::GetFullPath($Path)
}
function Fixture-Response([string]$Output) {
    $prefix = 'SERVERDECK_DURABILITY_V1 '
    $lines = @($Output -split '\r?\n' | Where-Object { $_.StartsWith($prefix) })
    if ($lines.Count -ne 1) { throw 'Expected one durability protocol response' }
    return $lines[0].Substring($prefix.Length) | ConvertFrom-Json
}
function Fixture-Tree([string]$Root) {
    $items = @(Get-ChildItem -LiteralPath $Root -Force -Recurse | Sort-Object FullName | ForEach-Object {
        if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse point in fixture data' }
        $relative = $_.FullName.Substring($Root.Length + 1)
        if ($_.PSIsContainer) { 'directory:' + $relative }
        else { 'file:' + $relative + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
    return $items -join "`n"
}
try {
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $kitRoot 'manifest.json') | ConvertFrom-Json
    $fixture = Join-Path $kitRoot 'verification/store_durability.exe'
    $library = Join-Path $kitRoot 'verification/libisar.dll'
    $observer = Join-Path $kitRoot 'verification/release_observer.exe'
    $report['fixtureBuild'] = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $kitRoot 'durability-build.json') | ConvertFrom-Json
    $fixtureDigest = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($fixtureDigest -ne $report.fixtureBuild.executableSHA256) { throw 'Durability executable differs from its build metadata' }
    foreach ($mode in @('uncommitted', 'committed')) {
        $nonce = [guid]::NewGuid().ToString()
        # Keep Isar's scratch path short independently of the evidence location.
        # This is a new private fixture root, never the GUI Known Folder profile.
        $root = Join-Path ([IO.Path]::GetTempPath()) ("ServerDeckDurability-{0}" -f [guid]::NewGuid())
        if ((Get-Item -LiteralPath (Split-Path -Parent $root)).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Reparse point in durability scratch parent'
        }
        New-Item -ItemType Directory -Path $root | Out-Null
        $case = [ordered]@{mode = $mode; root = $root; nonce = $nonce; init = $null; barrier = $null; writerPid = $null;
            writerExitCode = $null; killRequested = $false; writerStdout = ''; writerStderr = ''; loadedRuntime = @(); verification = $null; guards = @(); passed = $false}
        $report.cases += $case
        $report.fixtureStarted = $true
        $case.init = Complete-Captured $fixture @('init', $root, $library, $nonce)
        if ($case.init.timedOut -or $case.init.exitCode -ne 0 -or
            (Fixture-Response $case.init.stdout).status -ne 'initialized') { throw 'Durability initialization failed' }
        $writer = Start-Captured $fixture @("write-$mode", $root, $library, $nonce)
        try {
            $case.writerPid = $writer.process.Id
            $phaseFile = Join-Path $root 'phase.json'
            $expectedPhase = if ($mode -eq 'committed') { 'committed' } else { 'inside-transaction' }
            $timer = [Diagnostics.Stopwatch]::StartNew()
            while ($null -eq $case.barrier -and $timer.ElapsedMilliseconds -lt 30000) {
                if ($writer.process.HasExited) { throw 'Writer exited before its transaction barrier' }
                $phase = $null
                if (Test-Path -LiteralPath $phaseFile) {
                    if ((Get-Item -LiteralPath $phaseFile).Length -gt 4096) { throw 'Oversized writer barrier' }
                    try { $phase = Get-Content -Raw -Encoding UTF8 -LiteralPath $phaseFile | ConvertFrom-Json } catch { $phase = $null }
                }
                if ($null -ne $phase) {
                    if ($phase.schemaVersion -ne 1 -or $phase.nonce -ne $nonce -or
                        $phase.writerPid -ne $writer.process.Id -or $phase.phase -ne $expectedPhase) {
                        throw 'Writer barrier identity/phase mismatch'
                    }
                    $case.barrier = $phase
                } else { Start-Sleep -Milliseconds 25 }
            }
            if ($null -eq $case.barrier) { throw 'Writer transaction barrier timed out' }
            $observed = Complete-Captured $observer @('--pid', [string]$writer.process.Id, '--exe', $fixture)
            if ($observed.timedOut -or $observed.exitCode -ne 0) { throw 'Cannot observe the live fixture runtime' }
            $snapshot = $observed.stdout | ConvertFrom-Json
            foreach ($name in @('libisar.dll', 'vcruntime140.dll')) {
                $paths = @($snapshot.modules | Where-Object { [IO.Path]::GetFileName($_) -eq $name })
                $entries = @($manifest.files | Where-Object path -EQ "verification/$name")
                if ($paths.Count -ne 1 -or $entries.Count -ne 1 -or
                    (Plain-ModulePath $paths[0]) -ne (Join-Path $kitRoot "verification/$name") -or
                    (Get-FileHash -LiteralPath (Plain-ModulePath $paths[0]) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entries[0].sha256) {
                    throw 'Fixture loaded a runtime DLL outside its verified private bundle'
                }
                $case.loadedRuntime += @{path = $paths[0]; sha256 = $entries[0].sha256}
            }
            if ($writer.process.HasExited) { throw 'Writer is no longer suspended at its transaction barrier' }
            $case.killRequested = $true
            # The acceptance action must not silently become the idempotent
            # cleanup path if the writer exits between observations.
            $writer.process.Kill()
            if (!$writer.process.WaitForExit(5000)) { throw 'Owned writer kill timed out' }
            $case.writerExitCode = $writer.process.ExitCode
            if ($case.writerExitCode -ne -1) { throw 'Writer did not end with the expected Windows Process.Kill exit status' }
        } finally {
            Stop-OwnedProcess $writer
            $case.writerStdout = $writer.stdout.Result; $case.writerStderr = $writer.stderr.Result
            $writer.process.Dispose()
            Save-DurabilityReport
        }
        $verifyMode = if ($mode -eq 'committed') { 'verify-new' } else { 'verify-old' }
        $case.verification = Complete-Captured $fixture @($verifyMode, $root, $library, $nonce)
        if ($case.verification.timedOut -or $case.verification.exitCode -ne 0) { throw 'Recovered record verification failed' }
        $actual = Fixture-Response $case.verification.stdout
        $expectedRevision = if ($mode -eq 'committed') { 2 } else { 1 }
        $expectedTheme = if ($mode -eq 'committed') { 'light' } else { 'dark' }
        if ($actual.status -ne $verifyMode -or $actual.values.theme -ne $expectedTheme -or
            $actual.values.settingsRevision -ne $expectedRevision -or $actual.values.dataRevision -ne $expectedRevision) {
            throw 'Recovered fields do not form the complete expected transaction tuple'
        }
        $beforeGuards = Fixture-Tree $root
        $opposite = if ($mode -eq 'committed') { 'verify-old' } else { 'verify-new' }
        $userProfile = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'ServerDeck'
        $guardCases = @(
            @{arguments = @('init', $root, $library, $nonce); error = 'FIXTURE_INIT_REQUIRES_EMPTY_ROOT'},
            @{arguments = @('write-committed', $root, $library, [guid]::NewGuid().ToString()); error = 'FIXTURE_IDENTITY_MISMATCH'},
            @{arguments = @($opposite, $root, $library, $nonce); error = 'FIXTURE_PHASE_MISMATCH'},
            @{arguments = @($verifyMode, $root, 'libisar.dll', $nonce); error = 'INVALID_FIXTURE_PATH_OR_NONCE'},
            @{arguments = @('init', $userProfile, $library, $nonce); error = 'INVALID_FIXTURE_PATH_OR_NONCE'}
        )
        foreach ($guard in $guardCases) {
            $negative = Complete-Captured $fixture $guard.arguments
            if ($negative.timedOut -or $negative.exitCode -ne 1 -or !$negative.stderr.Contains($guard.error)) {
                throw "Durability fixture guard failed: $($guard.error)"
            }
            $case.guards += @{expectedError = $guard.error; result = $negative}
        }
        if ((Fixture-Tree $root) -ne $beforeGuards) { throw 'Rejected fixture commands changed the existing scratch store' }
        $case.passed = $true
        Save-DurabilityReport
    }
    $report.status = 'durabilityFixturesPassed'
    Save-DurabilityReport
    Write-Output "Two AOT durability fixtures passed; full GUI/VM acceptance remains open. Evidence: $EvidenceDirectory"
} catch {
    $report.status = 'durabilityFixturesFailed'; $report.error = $_.Exception.Message
    Save-DurabilityReport
    Write-Output "Durability fixture failed. Evidence: $EvidenceDirectory"
    throw
}
exit 0
