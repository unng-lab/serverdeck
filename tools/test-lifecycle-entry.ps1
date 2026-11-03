[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $account = ([Security.Principal.WindowsIdentity]::GetCurrent().Name -split '\\')[-1]
    if ($account -match '^ServerDeckSmoke(?:[-_].+)?$') {
        throw 'This negative entrypoint test runs only on a development account, never the disposable GUI test account'
    }
    $product = (Resolve-Path -LiteralPath output/release/ServerDeck.exe).Path
    $digest = (Get-FileHash -LiteralPath $product -Algorithm SHA256).Hash.ToLowerInvariant()
    $kit = Join-Path (Get-Location) "output/vm-test-kit/$digest"
    $testRoot = Join-Path (Get-Location) ("output/lifecycle-entry-test-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    function Run-CheckedProcess([string]$File, [string]$Arguments) {
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $File; $start.Arguments = $Arguments
        if ($File -eq "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe") {
            # .NET Process.Start does not perform pwsh's Windows-PowerShell
            # compatibility adjustment; avoid inheriting PS7 binary modules.
            $start.EnvironmentVariables['PSModulePath'] = "$env:SystemRoot/System32/WindowsPowerShell/v1.0/Modules"
        }
        $start.UseShellExecute = $false; $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
        $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
        $process = [Diagnostics.Process]::Start($start)
        try {
            $out = $process.StandardOutput.ReadToEndAsync()
            $err = $process.StandardError.ReadToEndAsync()
            if (!$process.WaitForExit(30000)) {
                $process.Kill(); $process.WaitForExit(); throw 'Negative entrypoint check timed out'
            }
            return @{code = $process.ExitCode; stdout = $out.Result; stderr = $err.Result}
        } finally { $process.Dispose() }
    }
    $nativeResults = @()
    foreach ($mode in @('--run', '--run-recovery', '--run-shell', '--run-acl')) {
        $journal = Join-Path $testRoot ($mode.TrimStart('-') + '.jsonl')
        $direct = Run-CheckedProcess "$kit/verification/release_lifecycle.exe" "$mode --exe `"$product`" --output `"$journal`""
        if ($direct.code -ne 1 -or $direct.stderr.Trim() -ne 'DISPOSABLE_ACCOUNT_REQUIRED' -or
            (Test-Path -LiteralPath $journal)) {
            throw 'Direct lifecycle/recovery driver did not reject the development account before work'
        }
        $nativeResults += @{mode = $mode; exitCode = $direct.code; error = $direct.stderr.Trim()}
    }
    $results = @()
    foreach ($shellPath in @((Get-Process -Id $PID).Path, "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe") | Select-Object -Unique) {
      foreach ($suite in @('lifecycle', 'recovery', 'shell', 'acl')) {
        $existing = @(Get-ChildItem -LiteralPath ($kit + '-evidence') -Directory -Filter 'lifecycle-*' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName)
        $blocked = Run-CheckedProcess $shellPath "-NoProfile -File `"$kit/run-lifecycle.ps1`" -Suite $suite"
        if ($blocked.code -ne 2) { throw "Expected blocked lifecycle entry exit2: $($blocked.stderr)" }
        $added = @(Get-ChildItem -LiteralPath ($kit + '-evidence') -Directory -Filter 'lifecycle-*' |
            Where-Object { $_.FullName -notin $existing })
        if ($added.Count -ne 1) { throw 'Expected one default lifecycle evidence directory' }
        $report = Get-Content -Raw -Encoding UTF8 -LiteralPath "$($added[0].FullName)/lifecycle-results.json" | ConvertFrom-Json
        if ($report.status -ne 'blockedByVmPrerequisites' -or $report.driverStarted -or
            $report.fullVmAcceptance -or $report.suite -ne $suite -or $report.events.Count -ne 0 -or
            (Test-Path -LiteralPath "$($added[0].FullName)/driver.jsonl")) {
            throw 'Blocked entrypoint executed or reported GUI scenarios'
        }
        $results += @{shell = $shellPath; suite = $suite; exitCode = $blocked.code; report = $added[0].FullName}
      }
    }
    [ordered]@{
        scope = 'Fail-closed lifecycle entry checks; no GUI product launched'
        productSHA256 = $digest; nativeGuards = $nativeResults
        wrappers = $results; fullVmAcceptance = $false
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$testRoot/results.json" -Encoding UTF8
    Write-Output "Lifecycle/recovery/shell entry checks passed: four native guards and PS7/PS5 preflight for each suite. Evidence: $testRoot"
} finally { Pop-Location }
exit 0
