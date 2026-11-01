param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
& $Python (Join-Path $PSScriptRoot 'validate-design.py') --json
exit $LASTEXITCODE
