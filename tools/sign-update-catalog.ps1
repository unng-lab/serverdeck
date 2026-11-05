param(
    [Parameter(Mandatory)][string]$Payload,
    [Parameter(Mandatory)][string]$PrivateKey,
    [Parameter(Mandatory)][string]$KeyId,
    [Parameter(Mandatory)][string]$Catalog
)

# Operator tool: only the public catalog is emitted. Never print key contents or
# paths, including exceptions originating in PEM import/file access.
$ErrorActionPreference = 'Stop'
$signer = $null
$temporary = $null
try {
    if ($KeyId -cnotmatch '\A[a-z0-9-]{1,32}\z') { throw 'Invalid key identifier' }
    $source = [IO.File]::OpenRead((Resolve-Path -LiteralPath $Payload).Path)
    try {
        $buffer = [byte[]]::new(131073)
        $length = 0
        while ($length -lt $buffer.Length) {
            $read = $source.Read($buffer, $length, $buffer.Length - $length)
            if (!$read) { break }
            $length += $read
        }
        if ($length -eq 0 -or $length -gt 131072) { throw 'Payload bounds' }
        $bytes = [byte[]]::new($length)
        [Array]::Copy($buffer, $bytes, $length)
    } finally { $source.Dispose() }
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    $protocol = if ($text.StartsWith("SDRELEASES002`n")) { '002' } else { '001' }
    if (!$text.StartsWith("SDRELEASES$protocol`n") -or !$text.EndsWith("`n") -or
        ($bytes | Where-Object { $_ -eq 0 -or $_ -eq 13 -or $_ -gt 127 }).Count) { throw 'Payload encoding' }
    $signer = [Security.Cryptography.ECDsa]::Create()
    $signer.ImportFromPem([IO.File]::ReadAllText((Resolve-Path -LiteralPath $PrivateKey).Path))
    $parameters = $signer.ExportParameters($false)
    if ($parameters.Curve.Oid.Value -ne '1.2.840.10045.3.1.7' -or $signer.KeySize -ne 256) { throw 'P256 required' }
    $signature = $signer.SignData($bytes, [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.DSASignatureFormat]::IeeeP1363FixedFieldConcatenation)
    if ($signature.Length -ne 64 -or !$signer.VerifyData($bytes, $signature,
        [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.DSASignatureFormat]::IeeeP1363FixedFieldConcatenation)) { throw 'Signature verification' }
    $hex = [Convert]::ToHexString($signature).ToLowerInvariant()
    $envelope = [Text.Encoding]::ASCII.GetBytes("SDCATALOG$protocol`n$KeyId`n$hex`n$text")
    if ($envelope.Length -gt 131072) { throw 'Catalog bounds' }
    $destination = [IO.Path]::GetFullPath($Catalog)
    $temporary = $destination + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllBytes($temporary, $envelope)
    [IO.File]::Move($temporary, $destination, $true)
    $temporary = $null
} catch {
    # Suppress the underlying exception: it may contain a private-key path.
    [Console]::Error.WriteLine('Catalog signing failed. Check payload, P256 key and output access.')
    exit 1
} finally {
    if ($null -ne $signer) { $signer.Dispose() }
    if ($null -ne $temporary -and [IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
}
