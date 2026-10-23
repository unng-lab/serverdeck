[CmdletBinding()]
param(
    [string]$Python = 'python',
    [ValidateSet('Debug','Release')][string]$Configuration = 'Debug',
    [switch]$KeepFixture
)
# Actual core scenario, not an alias for full feature acceptance or root suites.
. "$PSScriptRoot/mcp-fixture.ps1"
. "$PSScriptRoot/native-artifact-source-snapshot.ps1"
$source = Get-NativeArtifactSourceSnapshot
$fixtureId = [Guid]::NewGuid().ToString('N')
$fixtureRoot = Resolve-McpFixtureRoot (Join-Path $McpFixtureRepository ".local/mcp-acceptance-$fixtureId")
if (Test-Path -LiteralPath $fixtureRoot) { throw 'Fresh fixture required.' }
[void](New-Item -ItemType Directory -Path $fixtureRoot)
Protect-McpFixtureRoot $fixtureRoot
Write-McpFixtureDocument $fixtureRoot 'fixture.json' ([ordered]@{
    format=1;fixtureId=$fixtureId;sourceSnapshotSha256=$source.sha256
})
[void](New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'profile'))
$driver = $null
$stdoutFile = $stderrFile = $null
$stdoutCopy = $stderrCopy = $null
$failure = $null
try {
    $pythonPath = (Get-Command $Python -CommandType Application -ErrorAction Stop).Source
    $pythonVersion = & $pythonPath -I -c 'import sys; print("%d.%d" % sys.version_info[:2])'
    if ($LASTEXITCODE -ne 0 -or $pythonVersion -cne '3.12') { throw 'Python 3.12 required.' }
    & $pythonPath -I -m venv (Join-Path $fixtureRoot 'client-python')
    if ($LASTEXITCODE -ne 0) { throw 'Private client environment failed.' }
    $clientPython = Join-Path $fixtureRoot 'client-python/Scripts/python.exe'
    & $clientPython -I -m pip install --disable-pip-version-check --require-hashes -r (Join-Path $PSScriptRoot 'mcp_clients/requirements.lock')
    if ($LASTEXITCODE -ne 0) { throw 'Locked client installation failed.' }
    & $clientPython -I -m pip check
    if ($LASTEXITCODE -ne 0) { throw 'Client dependency closure failed.' }
    & "$PSScriptRoot/run-serverdeck.ps1" -Configuration $Configuration -BuildOnly -Python $pythonPath -IntegrationTarget 'integration_test/mcp_test.dart'
    $layout = Join-Path $McpFixtureRepository "build/windows/x64/runner/$Configuration"
    $bundle = Join-Path $fixtureRoot 'application bundle'
    # Fixed destination is new and beneath the verified owned fixture. Copying
    # never resets or moves an existing workspace or installed application.
    Copy-Item -LiteralPath $layout -Destination $bundle -Recurse -ErrorAction Stop
    foreach ($entry in Get-ChildItem -LiteralPath $bundle -Force -Recurse) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Bundle redirection refused.' }
    }
    $manifestPath = Join-Path $bundle 'foundation.manifest.json'
    $manifest = ConvertFrom-McpFixtureJson ([IO.File]::ReadAllText($manifestPath))
    if ($manifest.format -ne 3 -or $manifest.testOnly -or $manifest.apiMajor -ne 1 -or
        $manifest.apiMinor -ne 1 -or $manifest.workspaceSchema -ne 3) { throw 'Production format3 bundle required.' }
    $manifest.appRoot = $bundle
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    & "$PSScriptRoot/test-mcp-vm.ps1" -Mode Create -FixtureRoot $fixtureRoot

    $start = [Diagnostics.ProcessStartInfo]::new((Get-Command pwsh -CommandType Application).Source)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $start.WorkingDirectory = $McpFixtureRepository
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'mcp-drive.ps1'),'-FixtureRoot',$fixtureRoot)) {
        $start.ArgumentList.Add($argument)
    }
    $start.Environment['LOCALAPPDATA'] = Join-Path $fixtureRoot 'profile'
    $stdoutFile = [IO.File]::Open((Join-Path $fixtureRoot 'driver.private.stdout'), [IO.FileMode]::CreateNew)
    $stderrFile = [IO.File]::Open((Join-Path $fixtureRoot 'driver.private.stderr'), [IO.FileMode]::CreateNew)
    $driver = [Diagnostics.Process]::Start($start)
    $stdoutCopy = $driver.StandardOutput.BaseStream.CopyToAsync($stdoutFile)
    $stderrCopy = $driver.StandardError.BaseStream.CopyToAsync($stderrFile)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $enrolled = $false
    while (-not $driver.HasExited) {
        if ($clock.Elapsed.TotalMinutes -gt 15 -or $stdoutFile.Length -gt 32MB -or
            $stderrFile.Length -gt 32MB -or $stdoutCopy.IsFaulted -or $stderrCopy.IsFaulted) {
            throw 'Owned core driver failed its time/output bound.'
        }
        $workspacePath = Join-Path $fixtureRoot 'workspace.json'
        if (-not $enrolled -and (Test-Path -LiteralPath $workspacePath)) {
            $file = Get-Item -LiteralPath $workspacePath -Force
            if ($file.Length -gt 16384 -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Workspace signal refused.' }
            $workspace = ConvertFrom-McpFixtureJson ([IO.File]::ReadAllText($workspacePath))
            if ($workspace.format -ne 1 -or $workspace.fixtureId -cne $fixtureId -or
                $workspace.workspaceId -cnotmatch '^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$') {
                throw 'Actual owner workspace signal required.'
            }
            & "$PSScriptRoot/test-mcp-vm.ps1" -Mode Enroll -FixtureRoot $fixtureRoot -WorkspaceId $workspace.workspaceId
            $enrolled = $true
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $stdoutCopy.Wait(10000) -or -not $stderrCopy.Wait(10000)) { throw 'Driver pipe close unconfirmed.' }
    $stdoutCopy.GetAwaiter().GetResult()
    $stderrCopy.GetAwaiter().GetResult()
    if ($stdoutFile.Length -gt 32MB -or $stderrFile.Length -gt 32MB) { throw 'Private driver output limit exceeded.' }
    $stdoutFile.Dispose(); $stdoutFile = $null
    $stderrFile.Dispose(); $stderrFile = $null
    if ($driver.ExitCode -ne 0 -or -not $enrolled) { throw 'Actual core scenario failed; private diagnostics retained.' }
    # Inspect private logs in memory. Never echo the marker or raw log.
    $clear = $null
    try {
        $clear = [Security.Cryptography.ProtectedData]::Unprotect(
            [IO.File]::ReadAllBytes((Join-Path $fixtureRoot 'seed.dpapi')),
            [Text.Encoding]::UTF8.GetBytes("ServerDeck-MCP-fixture`n$fixtureId"),
            [Security.Cryptography.DataProtectionScope]::CurrentUser)
        $seed = ConvertFrom-McpFixtureJson ([Text.Encoding]::UTF8.GetString($clear))
        foreach ($name in @('driver.private.stdout','driver.private.stderr')) {
            $raw = [IO.File]::ReadAllText((Join-Path $fixtureRoot $name))
            if ($raw.Contains([string]$seed.password)) { throw 'Secret marker found in private driver output.' }
        }
    } finally { if ($clear) { [Array]::Clear($clear, 0, $clear.Length) } }
    $proofPath = Join-Path $fixtureRoot 'core-proof.json'
    $proofFile = Get-Item -LiteralPath $proofPath -Force
    if ($proofFile.Length -gt 16384 -or $proofFile.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Core proof refused.' }
    $proof = ConvertFrom-McpFixtureJson ([IO.File]::ReadAllText($proofPath))
    $required = @('empty-workspace-author-cas-replay','actual-owner-trust-connect-enrollment',
        'two-clients-scoped-reads-logs-shared-catalog','owner-approval-actual-effect-durable-replay',
        'exact-version-delegation-desired-state','sdk-job-object-close-keeps-shared-service',
        'current-grant-revoke','owner-control-after-grant-revoke')
    if ($proof.format -ne 1 -or $proof.fixtureId -cne $fixtureId -or
        $proof.sourceSnapshotSha256 -cne $source.sha256 -or $proof.fullAcceptance -ne $false -or
        $proof.scenario -cne 'native-owner-two-independent-mcp-clients' -or
        $proof.cases.Count -ne $required.Count) { throw 'Core proof identity refused.' }
    for ($index = 0; $index -lt $required.Count; $index++) {
        if ($proof.cases[$index] -cne $required[$index]) { throw 'Required core case missing.' }
    }
    if ((Get-NativeArtifactSourceSnapshot).sha256 -cne $source.sha256) { throw 'Source changed during scenario.' }
} catch {
    $failure = 'MCP core scenario failed; owned private fixture retained.'
} finally {
    if ($driver) {
        if (-not $driver.HasExited) {
            $driver.Kill($true)
            if (-not $driver.WaitForExit(10000)) { $failure = 'Owned driver termination unconfirmed.' }
        }
        $driver.Dispose()
    }
    if ($stdoutFile) { $stdoutFile.Dispose() }
    if ($stderrFile) { $stderrFile.Dispose() }
    # Keep failure evidence and its exact disposable server for diagnosis.
    # Successful cleanup removes only the separately revalidated owned Docker
    # resources; this script never recursively deletes the fixture directory.
    if (-not $failure -and -not $KeepFixture) {
        try { & "$PSScriptRoot/test-mcp-vm.ps1" -Mode Remove -FixtureRoot $fixtureRoot }
        catch { $failure = 'Owned Docker cleanup failed.' }
    }
}
if ($failure) { throw $failure }
Write-Output 'MCP_CORE_SCENARIO_PASSED_FULL_ACCEPTANCE_FALSE'
