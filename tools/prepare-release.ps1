param(
    [string]$Installer = 'output/release/ServerDeckSetup.exe',
    [string]$Audit = 'output/release-evidence/setup-audit.json',
    [string]$Policy = 'release/update-policy.json',
    [string]$Notes,
    [string]$PrivateKey = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ServerDeckPublisher/keys/serverdeck-updates-v1.pem'),
    [string]$KeyId = 'serverdeck-updates-v1',
    [string]$PreviousCatalog,
    [switch]$FirstRelease
)

# Prepare public release assets locally. No upload or private-key output.
$ErrorActionPreference = 'Stop'
$signer = $null; $verifier = $null; $previousPayload = $null
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    if ((!$PreviousCatalog -and !$FirstRelease) -or ($PreviousCatalog -and $FirstRelease)) { throw 'Choose previous catalog or explicit first release' }
    $public = Get-Content -LiteralPath $Policy -Raw | ConvertFrom-Json
    $signer = [Security.Cryptography.ECDsa]::Create()
    $signer.ImportFromPem([IO.File]::ReadAllText((Resolve-Path -LiteralPath $PrivateKey).Path))
    $parameters = $signer.ExportParameters($false)
    if ($parameters.Curve.Oid.Value -ne '1.2.840.10045.3.1.7') { throw 'P256 required' }
    $point = [Convert]::ToHexString($parameters.Q.X + $parameters.Q.Y).ToLowerInvariant()
    if (@($public.keys | Where-Object { $_.id -ceq $KeyId -and $_.p256 -ceq $point }).Count -ne 1) { throw 'Signing key differs from embedded trust' }
    $version = (Get-Content -LiteralPath $Audit -Raw | ConvertFrom-Json).version
    if (!$Notes) { $Notes = "release/notes/$version.md" }
    $directory = Split-Path -Parent ([IO.Path]::GetFullPath($Installer))
    $payload = Join-Path $directory 'update-payload.txt'
    $catalog = Join-Path $directory 'serverdeck-update-catalog.txt'
    $arguments = @('tools/prepare-release-payload.py', '--installer', $Installer, '--audit', $Audit,
        '--policy', $Policy, '--notes', $Notes, '--output', $payload)
    if ($PreviousCatalog) {
        $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $PreviousCatalog).Path)
        if ($bytes.Length -gt 131072 -or ($bytes | Where-Object { $_ -eq 0 -or $_ -eq 13 -or $_ -gt 127 }).Count) { throw 'Invalid previous catalog bounds' }
        $parts = [Text.Encoding]::ASCII.GetString($bytes).Split("`n", 4)
        if ($parts.Count -ne 4 -or $parts[0] -cne 'SDCATALOG002' -or $parts[2] -cnotmatch '\A[0-9a-f]{128}\z') { throw 'Invalid previous envelope' }
        $root = @($public.keys | Where-Object { $_.id -ceq $parts[1] })
        if ($root.Count -ne 1) { throw 'Unknown previous signing key' }
        $raw = [Convert]::FromHexString($root[0].p256)
        if ($raw.Length -ne 64) { throw 'Invalid public point' }
        $ec = [Security.Cryptography.ECParameters]::new()
        $ec.Curve = [Security.Cryptography.ECCurve+NamedCurves]::nistP256
        $q = [Security.Cryptography.ECPoint]::new(); $q.X = $raw[0..31]; $q.Y = $raw[32..63]; $ec.Q = $q
        $verifier = [Security.Cryptography.ECDsa]::Create($ec)
        $prior = [Text.Encoding]::ASCII.GetBytes($parts[3])
        if (!$verifier.VerifyData($prior, [Convert]::FromHexString($parts[2]), [Security.Cryptography.HashAlgorithmName]::SHA256,
            [Security.Cryptography.DSASignatureFormat]::IeeeP1363FixedFieldConcatenation)) { throw 'Invalid previous signature' }
        $previousPayload = Join-Path $directory ('previous-payload.' + [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllBytes($previousPayload, $prior)
        $arguments += @('--previous-payload', $previousPayload)
    }
    & python @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Payload preparation failed' }
    & ./tools/sign-update-catalog.ps1 -Payload $payload -PrivateKey $PrivateKey -KeyId $KeyId -Catalog $catalog
    if ($LASTEXITCODE -ne 0) { throw 'Catalog signing failed' }
    Write-Output "Prepared update-enabled release ${version}: installer and signed catalog. Nothing uploaded."
} catch {
    [Console]::Error.WriteLine('Release preparation failed. Choose -PreviousCatalog or -FirstRelease; check audited publishable assets, public policy, original publisher key and release notes.')
    exit 1
} finally {
    if ($signer) { $signer.Dispose() }; if ($verifier) { $verifier.Dispose() }
    if ($previousPayload -and (Test-Path -LiteralPath $previousPayload)) { Remove-Item -LiteralPath $previousPayload }
    Pop-Location
}
