[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory)
. "$PSScriptRoot/foundation-sdk.ps1"
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (-not $OutputDirectory.StartsWith($FoundationRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Build output must remain inside the workspace.'
}
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
Push-Location (Join-Path $FoundationRoot 'packages/serverdeck_mcp')
try {
    Invoke-FoundationCommand $FoundationDart @('pub', 'get', '--enforce-lockfile')
    Invoke-FoundationCommand $FoundationDart @('compile', 'exe', 'bin/mcp.dart', '-o', (Join-Path $OutputDirectory 'mcp.exe'))
} finally { Pop-Location }
