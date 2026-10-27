[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Python = 'python'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    # Get-Command may return every PATH match (including WindowsApps aliases).
    # Invoke only the first application, preserving normal command precedence.
    $PythonCommand = Get-Command -Name $Python -CommandType Application -ErrorAction Stop |
        Select-Object -First 1
    $PythonExecutable = $PythonCommand.Source
} catch {
    [Console]::Error.WriteLine("Cannot find Python executable '$Python': $($_.Exception.Message)")
    exit 1
}

$PrerequisiteCheck = @'
import sys
if sys.version_info < (3, 10):
    sys.stderr.write('Design reference validation requires Python >=3.10; found ' + sys.version.split()[0] + '\n')
    sys.exit(1)
try:
    import hashlib
    import json
    import re
    from collections import Counter
    from html.parser import HTMLParser
    from pathlib import Path, PurePosixPath, PureWindowsPath
    from urllib.parse import unquote, urlsplit
except Exception as error:
    sys.stderr.write('Python standard library prerequisite failed: ' + str(error) + '\n')
    sys.exit(1)
'@

# Windows PowerShell may expose native stderr as nonterminating errors. Keep
# diagnostics on their original streams and preserve the native exit status.
$ErrorActionPreference = 'Continue'
try {
    & $PythonExecutable -c $PrerequisiteCheck
    $PrerequisiteExitCode = $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine("Cannot run Python executable '$PythonExecutable': $($_.Exception.Message)")
    exit 1
}
if ($PrerequisiteExitCode -ne 0) {
    [Console]::Error.WriteLine('Python prerequisites for design reference validation are unavailable.')
    exit $PrerequisiteExitCode
}

try {
    & $PythonExecutable (Join-Path $PSScriptRoot 'validate-design.py')
    $ValidatorExitCode = $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine("Cannot start design reference validation: $($_.Exception.Message)")
    exit 1
}
exit $ValidatorExitCode
