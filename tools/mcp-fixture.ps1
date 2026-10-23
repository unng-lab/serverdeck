Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$McpFixtureRepository = Split-Path $PSScriptRoot -Parent

function Resolve-McpFixtureRoot {
    param([Parameter(Mandatory)][string]$Path)
    $resolved = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Path))
    $parent = [IO.Path]::GetFullPath((Join-Path $McpFixtureRepository '.local'))
    if ([IO.Path]::GetDirectoryName($resolved) -ine $parent -or
        [IO.Path]::GetFileName($resolved) -cnotmatch '^mcp-acceptance-[a-f0-9]{32}$') {
        throw 'Owned MCP fixture path required.'
    }
    $part = $resolved
    while ($part) {
        if (Test-Path -LiteralPath $part) {
            if ((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Fixture reparse path refused.'
            }
        }
        $part = [IO.Path]::GetDirectoryName($part)
    }
    return $resolved
}

function Protect-McpFixtureRoot {
    param([Parameter(Mandatory)][string]$Path)
    $Path = Resolve-McpFixtureRoot $Path
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $acl = Get-Acl -LiteralPath $Path
        $acl.SetAccessRuleProtection($true, $false)
        $acl.SetOwner($identity.User)
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($identity.User,
            [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow)
        $acl.SetAccessRule($rule)
        Set-Acl -LiteralPath $Path -AclObject $acl
    } finally { $identity.Dispose() }
}

function Read-McpFixtureIdentity {
    param([Parameter(Mandatory)][string]$Path)
    $Path = Resolve-McpFixtureRoot $Path
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $acl = Get-Acl -LiteralPath $Path
        if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $identity.User.Value -or
            -not $acl.AreAccessRulesProtected) { throw 'Fixture owner custody required.' }
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
                $rule.IdentityReference.Value -cne $identity.User.Value) { throw 'Fixture owner custody required.' }
        }
    } finally { $identity.Dispose() }
    $document = Join-Path $Path 'fixture.json'
    $file = Get-Item -LiteralPath $document -Force
    if ($file.Length -gt 16384 -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Fixture identity custody refused.'
    }
    try { $value = Get-Content -LiteralPath $document -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Fixture identity JSON refused.' }
    if ($value.format -ne 1 -or $value.fixtureId -cne ([IO.Path]::GetFileName($Path).Substring(15))) {
        throw 'Fixture identity mismatch.'
    }
    return $value
}

function ConvertFrom-McpFixtureJson {
    param([Parameter(Mandatory)][string]$Value)
    try { return ConvertFrom-Json -InputObject $Value -ErrorAction Stop }
    catch { throw 'Owned fixture JSON refused; raw input not published.' }
}

function Write-McpFixtureDocument {
    param([string]$Root, [ValidateSet('fixture.json','docker.json','enrolled.json')][string]$Name, $Value)
    $Root = Resolve-McpFixtureRoot $Root
    $target = Join-Path $Root $Name
    $pending = $target + '.pending'
    $stream = [IO.File]::Open($pending, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Depth 10 -Compress))
        $stream.Write($bytes)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    [IO.File]::Move($pending, $target, $true)
}

function Write-McpFixtureSeed {
    param([string]$Root, $Value)
    $Root = Resolve-McpFixtureRoot $Root
    $identity = Read-McpFixtureIdentity $Root
    $clear = [Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Depth 10 -Compress))
    $entropy = [Text.Encoding]::UTF8.GetBytes("ServerDeck-MCP-fixture`n$($identity.fixtureId)")
    try {
        $wrapped = [Security.Cryptography.ProtectedData]::Protect($clear, $entropy,
            [Security.Cryptography.DataProtectionScope]::CurrentUser)
        $stream = [IO.File]::Open((Join-Path $Root 'seed.dpapi'), [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($wrapped); $stream.Flush($true) }
        finally { $stream.Dispose() }
    } finally { [Array]::Clear($clear, 0, $clear.Length) }
}

function Invoke-McpFixtureDocker {
    param([Parameter(Mandatory)][string[]]$Arguments, [int]$TimeoutSeconds = 120)
    $start = [Diagnostics.ProcessStartInfo]::new((Get-Command docker.exe -CommandType Application).Source)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    $output = $process.StandardOutput.ReadToEndAsync()
    $errors = $process.StandardError.ReadToEndAsync()
    try {
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            [void]$process.WaitForExit(10000)
            throw 'Owned Docker operation timed out.'
        }
        $result = $output.GetAwaiter().GetResult()
        $diagnostic = $errors.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or $result.Length -gt 2MB -or $diagnostic.Length -gt 2MB) {
            throw 'Owned Docker operation failed; no raw diagnostic published.'
        }
        return $result.Trim()
    } finally { $process.Dispose() }
}
