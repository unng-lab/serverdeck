$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot
$releaseRoot = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$smokeRoot = Join-Path $repoRoot ('work\locald-process-' + [Guid]::NewGuid().ToString('N'))
$bundleRoot = Join-Path $smokeRoot 'bundle'
$dataRoot = Join-Path $smokeRoot 'data'
New-Item -ItemType Directory -Path $bundleRoot,$dataRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $releaseRoot 'serverdeck_locald.exe') -Destination $bundleRoot
Copy-Item -LiteralPath (Join-Path $releaseRoot 'libisar.dll') -Destination $bundleRoot
$exePath = Join-Path $bundleRoot 'serverdeck_locald.exe'
$startedProcesses = [Collections.Generic.List[Diagnostics.Process]]::new()

function Start-SmokeService {
    $process = Start-Process -FilePath $exePath -ArgumentList @('--data-dir', ('"' + $dataRoot + '"')) -WorkingDirectory $bundleRoot -WindowStyle Hidden -PassThru
    $startedProcesses.Add($process)
    return $process
}
function Read-SmokeEndpoint {
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $endpoint = Get-Content -LiteralPath (Join-Path $dataRoot 'endpoint.json') -Raw | ConvertFrom-Json
            $health = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$($endpoint.port)/v1/health" -Headers @{Authorization="Bearer $($endpoint.proof)"} -Body '{}' -ContentType 'application/json' -TimeoutSec 1
            if ($health.data.service -eq 'serverdeck') { return $endpoint }
        } catch { }
        Start-Sleep -Milliseconds 100
    }
    throw 'Packaged locald did not become healthy'
}
function Call-SmokeApi($endpoint, $operation, $body) {
    $response = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$($endpoint.port)/v1/$operation" -Headers @{Authorization="Bearer $($endpoint.proof)"} -Body ($body | ConvertTo-Json -Depth 8 -Compress) -ContentType 'application/json' -TimeoutSec 5
    return $response.data
}
try {
    # Deliberately permissive old directory and child: startup must remove these ACEs.
    $oldFile = Join-Path $dataRoot 'old-fixture.txt'
    Set-Content -LiteralPath $oldFile -Value 'Synthetic fixture'
    icacls $dataRoot /grant '*S-1-1-0:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'ACL fixture setup failed' }
    icacls $oldFile /grant '*S-1-1-0:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Child ACL fixture setup failed' }
    $first = Start-SmokeService
    $endpoint = Read-SmokeEndpoint
    $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    foreach ($item in @((Get-Item -LiteralPath $dataRoot)) + @(Get-ChildItem -LiteralPath $dataRoot -Recurse -Force)) {
        $acl = Get-Acl -LiteralPath $item.FullName
        $rules = $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])
        foreach ($rule in $rules) {
            if ($rule.IdentityReference.Value -notin @($ownerSid, 'S-1-5-18')) { throw 'Non-owner ACL survived service startup' }
        }
    }
    $profile = @{id='fixture'; name='Persisted subprocess'; endpoint='fixture.invalid'; port=22; user='observer'; tags=@('fixture'); state='unknown'; observedAt='2026-10-05T00:00:00Z'}
    Call-SmokeApi $endpoint 'profiles/initialize' @{profiles=@($profile)} | Out-Null
    $plan = @{hostId='fixture'; hostFingerprint=('SHA256:' + ('A' * 43)); recipe='postgresql'; version='18.6-3.pgdg24.04+1'; recipeDigest=('sha256:' + ('a' * 64)); deviceId='test'; mode='fresh'}
    $job = Call-SmokeApi $endpoint 'jobs/submit' @{plan=$plan; idempotencyKey='subprocess'}
    $second = Start-SmokeService
    if (-not $second.WaitForExit(10000)) { throw 'A competing service did not refuse ownership' }
    if ($second.ExitCode -eq 0) { throw 'Competing service unexpectedly succeeded' }
    Stop-Process -Id $first.Id -Force
    $first.WaitForExit()
    $replacement = Start-SmokeService
    $recovered = Read-SmokeEndpoint
    if ($recovered.proof -eq $endpoint.proof) { throw 'Session proof did not rotate after forced restart' }
    $profiles = @(Call-SmokeApi $recovered 'profiles/list' @{})
    if ($profiles.Count -ne 1 -or $profiles[0].name -ne 'Persisted subprocess') { throw 'Profile not recovered after process kill' }
    $sameJob = Call-SmokeApi $recovered 'jobs/submit' @{plan=$plan; idempotencyKey='subprocess'}
    if ($sameJob -ne $job) { throw 'Idempotency did not survive process kill' }
    $locked = $false
    try { Call-SmokeApi $recovered 'jobs/submit' @{plan=$plan; idempotencyKey='competing'} | Out-Null }
    catch { $locked = $_.ErrorDetails.Message -match 'HostLocked' }
    if (-not $locked) { throw 'Host writer lock did not survive process kill' }
    $events = @(Call-SmokeApi $recovered 'jobs/events' @{id=$job})
    if ($events.Count -ne 1 -or $events[0].sequence -ne 1) { throw 'Duplicate created an extra event' }
    Write-Output 'PASS: packaged service, restrictive DACL, single owner, forced restart, profile/job/event/lock persistence'
} finally {
    foreach ($process in $startedProcesses) {
        $process.Refresh()
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force; $process.WaitForExit() }
    }
    # Retain only synthetic fixture evidence under ignored work/; never remove user data.
}
