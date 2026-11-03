[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $root = Join-Path (Get-Location) ("output/observer-script-test-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path "$root/verification" -Force | Out-Null
    Copy-Item -LiteralPath tools/vm-capture-process.ps1 -Destination "$root/capture-process.ps1"
    Copy-Item -LiteralPath build/native-tests/Release/release_observer.exe -Destination "$root/verification/release_observer.exe"
    # This synthetic kit intentionally uses this test shell as its hash-bound
    # target. It exercises evidence transport without launching the GUI product
    # or touching the real ServerDeck profile.
    $shellPath = (Get-Process -Id $PID).Path
    $digest = (Get-FileHash -LiteralPath $shellPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $helperDigest = (Get-FileHash -LiteralPath "$root/verification/release_observer.exe" -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        schemaVersion = 1; productSHA256 = $digest
        scope = 'Synthetic evidence transport test; target is the test shell, not ServerDeck'
        files = @(
            @{path = 'product/ServerDeck.exe'; sha256 = $digest},
            @{path = 'verification/release_observer.exe'; sha256 = $helperDigest}
        )
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$root/manifest.json" -Encoding UTF8
    function Invoke-Capture([uint32]$TargetId, [string]$OutputName) {
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $shellPath
        $start.Arguments = "-NoProfile -File `"$root/capture-process.ps1`" -ProductProcessId $TargetId -ExePath `"$shellPath`""
        if ($OutputName) { $start.Arguments += " -EvidencePath `"$root/$OutputName`"" }
        $start.UseShellExecute = $false; $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
        $process = [Diagnostics.Process]::Start($start)
        try {
            $out = $process.StandardOutput.ReadToEndAsync()
            $err = $process.StandardError.ReadToEndAsync()
            if (!$process.WaitForExit(30000)) {
                $process.Kill(); $process.WaitForExit()
                throw 'Capture test timed out'
            }
            return @{code = $process.ExitCode; stdout = $out.Result; stderr = $err.Result}
        } finally { $process.Dispose() }
    }
    $positive = Invoke-Capture $PID 'positive.json'
    if ($positive.code -ne 0) { throw "Positive capture failed: $($positive.stderr)" }
    $record = Get-Content -Raw -LiteralPath "$root/positive.json" | ConvertFrom-Json
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($record.snapshot.pid -ne $PID -or $record.snapshot.imagePath -ne $shellPath -or
        $record.snapshot.userSid -ne $sid -or $record.snapshot.modules.Count -eq 0 -or
        $record.fullVmAcceptance -or $record.productSHA256 -ne $digest) {
        throw 'Positive capture identity/provenance mismatch'
    }
    $kitFilesBefore = @(Get-ChildItem -LiteralPath $root -File -Recurse | Select-Object -ExpandProperty FullName)
    if ((Invoke-Capture $PID '').code -ne 0) { throw 'Default evidence capture failed' }
    $defaultReports = @(Get-ChildItem -LiteralPath ($root + '-evidence') -Filter 'process-*.json' -File)
    if ($defaultReports.Count -ne 1 -or
        @(Compare-Object $kitFilesBefore @(Get-ChildItem -LiteralPath $root -File -Recurse | Select-Object -ExpandProperty FullName)).Count -ne 0) {
        throw 'Default capture evidence changed the kit contents'
    }
    $before = (Get-FileHash -LiteralPath "$root/positive.json").Hash
    if ((Invoke-Capture $PID 'positive.json').code -eq 0 -or
        (Get-FileHash -LiteralPath "$root/positive.json").Hash -ne $before) {
        throw 'Existing evidence was overwritten'
    }
    if ((Invoke-Capture 0 'invalid-pid.json').code -eq 0) { throw 'Invalid PID was accepted' }
    $negative = Get-Content -Raw -LiteralPath "$root/invalid-pid.json" | ConvertFrom-Json
    if ($null -ne $negative.snapshot -or $negative.exitCode -ne 2 -or $negative.fullVmAcceptance) {
        throw 'Invalid PID produced successful-looking evidence'
    }
    $manifest.files[1].sha256 = '0' * 64
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$root/manifest.json" -Encoding UTF8
    if ((Invoke-Capture $PID 'bad-hash.json').code -eq 0 -or (Test-Path -LiteralPath "$root/bad-hash.json")) {
        throw 'Mismatched observer hash was accepted'
    }
    Write-Output "Process observer transport checks passed: identity/JSON, evidence outside kit, immutable output, invalid PID, helper hash. Evidence: $root"
} finally { Pop-Location }
exit 0
