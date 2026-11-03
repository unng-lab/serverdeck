[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $product = (Resolve-Path -LiteralPath output/release/ServerDeck.exe).Path
    $digest = (Get-FileHash -LiteralPath $product -Algorithm SHA256).Hash.ToLowerInvariant()
    $kit = Join-Path (Get-Location) "output/vm-test-kit/$digest"
    if (!(Test-Path -LiteralPath "$kit/capture-process.ps1")) { throw 'Build the VM kit before its reuse integration test' }
    $reportRoot = $kit + '-evidence'
    $before = @(Get-ChildItem -LiteralPath $reportRoot -File -Filter 'process-*.json' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName)
    # Invalid PID deliberately creates failed observation evidence without
    # launching or inspecting a GUI product. Its persistence is the regression.
    & "$kit/capture-process.ps1" -ProductProcessId 0
    if ($LASTEXITCODE -ne 1) { throw 'Expected a recorded invalid-PID observation' }
    $new = @(Get-ChildItem -LiteralPath $reportRoot -File -Filter 'process-*.json' |
        Where-Object { $_.FullName -notin $before })
    if ($new.Count -ne 1) { throw 'Expected exactly one new default evidence file outside kit' }
    $captureHash = (Get-FileHash -LiteralPath $new[0].FullName -Algorithm SHA256).Hash
    $sidecarPath = (Resolve-Path -LiteralPath output/release-evidence/identities.json).Path
    $sidecarBytes = [IO.File]::ReadAllBytes($sidecarPath)
    try {
        [IO.File]::WriteAllText($sidecarPath, '{"regressionMarker":"deliberately unrelated build"}')
        & ./tools/build-vm-test-kit.ps1 -ReuseCandidate
        if ($LASTEXITCODE -ne 0) { throw 'Same-candidate repackage failed' }
        $probe = Get-Content -Raw -LiteralPath output/release-evidence/local-probes.json | ConvertFrom-Json
        $identities = Get-Content -Raw -LiteralPath "$kit/build-identities.json" | ConvertFrom-Json
        if ($probe.exeSHA256 -ne $digest -or
            ($identities | ConvertTo-Json -Depth 20 -Compress) -ne
            ($probe.embeddedBuildIdentities | ConvertTo-Json -Depth 20 -Compress) -or
            $null -ne $identities.PSObject.Properties['regressionMarker']) {
            throw 'Reused kit identities are not those embedded in the selected EXE'
        }
        if ((Get-FileHash -LiteralPath $new[0].FullName -Algorithm SHA256).Hash -ne $captureHash) {
            throw 'Same-candidate repackage changed existing capture evidence'
        }
    } finally { [IO.File]::WriteAllBytes($sidecarPath, $sidecarBytes) }
    [ordered]@{
        scope = 'VM kit reuse integration; no GUI/VM acceptance'
        productSHA256 = $digest; mismatchedSidecarIgnored = $true
        embeddedIdentitiesPreserved = $true; captureEvidencePreserved = $true
        captureEvidencePath = $new[0].FullName; captureEvidenceSHA256 = $captureHash.ToLowerInvariant()
        fullVmAcceptance = $false
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath output/release-evidence/reuse-integration.json -Encoding UTF8
    Write-Output 'VM kit reuse integration passed: default capture evidence preserved; conflicting sidecar cannot replace embedded identities.'
} finally { Pop-Location }
exit 0
