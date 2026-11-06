param(
    [string]$Policy = (Join-Path $PSScriptRoot '../release/update-policy.json'),
    [string]$KeyId = 'serverdeck-updates-v1',
    [string]$KeyDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ServerDeckPublisher/keys')
)

# Publisher bootstrap only. Builds never generate or rotate trust roots.
$ErrorActionPreference = 'Stop'
$signer = $null
$phase = 'inputs'
try {
    if (!('ServerDeckPublisherAcl' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class ServerDeckPublisherAcl {
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetFileSecurityW(string name, uint information, byte[] descriptor);
}
'@
    }
    if ($KeyId -cnotmatch '\A[a-z0-9-]{1,32}\z') { throw 'Invalid key identifier' }
    $privateFile = Join-Path $KeyDirectory "$KeyId.pem"
    $checkedPath = [IO.Path]::GetFullPath($privateFile)
    while ($checkedPath) {
        if ((Test-Path -LiteralPath $checkedPath) -and
            ((Get-Item -LiteralPath $checkedPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Publisher path must not use reparse points' }
        $parent = [IO.Path]::GetDirectoryName($checkedPath)
        if ($parent -eq $checkedPath) { break }; $checkedPath = $parent
    }
    $existing = if (Test-Path -LiteralPath $Policy) { Get-Content -LiteralPath $Policy -Raw | ConvertFrom-Json } else { $null }
    if ($existing -and !(Test-Path -LiteralPath $privateFile)) { throw 'Restore original publisher key; refusing trust replacement' }
    $phase = 'directory'
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $systemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    if (!(Test-Path -LiteralPath $KeyDirectory)) {
        $phase = 'directory-create'
        # Elevated Windows tokens may default newly created objects to a group
        # owner. Bind the user and private DACL at creation, not after key writes.
        $newDirectoryAcl = [Security.AccessControl.DirectorySecurity]::new()
        $newDirectoryAcl.SetOwner($sid)
        $newDirectoryAcl.SetAccessRuleProtection($true, $false)
        foreach ($principal in @($sid, $systemSid)) {
            $newDirectoryAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($principal, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        }
        [IO.FileSystemAclExtensions]::Create([IO.DirectoryInfo]::new([IO.Path]::GetFullPath($KeyDirectory)), $newDirectoryAcl)
    }
    $phase = 'directory-owner'
    $acl = Get-Acl -LiteralPath $KeyDirectory
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid.Value) { throw 'Foreign publisher directory' }
    $phase = 'directory-acl'
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) { $acl.RemoveAccessRuleSpecific($rule) }
    foreach ($principal in @($sid, $systemSid)) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($principal, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    if (![ServerDeckPublisherAcl]::SetFileSecurityW([IO.Path]::GetFullPath($KeyDirectory), 0x80000004u, $acl.GetSecurityDescriptorBinaryForm())) { throw 'Directory DACL failed' }
    $phase = 'key'
    $signer = [Security.Cryptography.ECDsa]::Create([Security.Cryptography.ECCurve+NamedCurves]::nistP256)
    if (Test-Path -LiteralPath $privateFile) {
        $signer.ImportFromPem([IO.File]::ReadAllText($privateFile))
    } else {
        $newFileAcl = [Security.AccessControl.FileSecurity]::new()
        $newFileAcl.SetOwner($sid)
        $newFileAcl.SetAccessRuleProtection($true, $false)
        foreach ($principal in @($sid, $systemSid)) {
            $newFileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($principal, 'FullControl', 'Allow'))
        }
        $stream = [IO.FileSystemAclExtensions]::Create([IO.FileInfo]::new([IO.Path]::GetFullPath($privateFile)),
            [IO.FileMode]::CreateNew, [Security.AccessControl.FileSystemRights]::Write,
            [IO.FileShare]::None, 4096, [IO.FileOptions]::None, $newFileAcl)
        try {
            $bytes = [Text.Encoding]::ASCII.GetBytes($signer.ExportPkcs8PrivateKeyPem())
            $stream.Write($bytes); $stream.Flush($true)
        } finally { $stream.Dispose() }
    }
    $phase = 'file-acl'
    $fileAcl = Get-Acl -LiteralPath $privateFile
    if ($fileAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid.Value) { throw 'Foreign publisher key' }
    $fileAcl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($fileAcl.Access)) { $fileAcl.RemoveAccessRuleSpecific($rule) }
    foreach ($principal in @($sid, $systemSid)) {
        $fileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($principal, 'FullControl', 'Allow'))
    }
    if (![ServerDeckPublisherAcl]::SetFileSecurityW([IO.Path]::GetFullPath($privateFile), 0x80000004u, $fileAcl.GetSecurityDescriptorBinaryForm())) { throw 'Key DACL failed' }
    $phase = 'public-policy'
    $parameters = $signer.ExportParameters($false)
    if ($parameters.Curve.Oid.Value -ne '1.2.840.10045.3.1.7') { throw 'P256 required' }
    $point = [Convert]::ToHexString($parameters.Q.X + $parameters.Q.Y).ToLowerInvariant()
    if ($existing) {
        $matching = @($existing.keys | Where-Object { $_.id -ceq $KeyId -and $_.p256 -ceq $point })
        if ($matching.Count -ne 1) { throw 'Explicit trust rotation required' }
    } else {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $format = [regex]::Match((Get-Content -Raw (Join-Path $repoRoot 'lib/storage/store_manifest.dart')), 'const currentStorageFormat = ([0-9]+);')
        if (!$format.Success) { throw 'Missing current storage format' }
        $public = [ordered]@{
            schema = 1; endpoint = 'https://api.github.com/repos/unng-lab/serverdeck/releases/latest'
            downloadHosts = @('github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com', 'github-releases.githubusercontent.com')
            storeFormat = [int]$format.Groups[1].Value
            keys = @(@{ id = $KeyId; p256 = $point })
        }
        $destination = [IO.Path]::GetFullPath($Policy)
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        [IO.File]::WriteAllText($destination, ($public | ConvertTo-Json -Depth 5) + "`n", [Text.UTF8Encoding]::new($false))
    }
    Write-Output 'Publisher key is available locally; public update trust is initialized.'
} catch {
    [Console]::Error.WriteLine("Publisher initialization failed ($phase). Restore the original key for an existing policy; do not replace deployed trust roots.")
    exit 1
} finally { if ($signer) { $signer.Dispose() } }
