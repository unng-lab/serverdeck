[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Python = 'python'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$PythonExecutable = (Get-Command -Name $Python -CommandType Application -ErrorAction Stop |
    Select-Object -First 1).Source
$PythonHome = Split-Path -Parent $PythonExecutable
$ShellExecutable = Join-Path $PSHOME 'pwsh.exe'
if (-not (Test-Path -LiteralPath $ShellExecutable -PathType Leaf)) {
    $ShellExecutable = Join-Path $PSHOME 'powershell.exe'
}

# Preserve fixtures for diagnosis; every run stays below this repository-local root.
$Fixture = Join-Path $Repository ('.local/design-003/wrapper-regression-' + [Guid]::NewGuid().ToString('N'))
$FixtureTools = Join-Path $Fixture 'tools'
$Customizer = Join-Path $Fixture 'customizer'
New-Item -ItemType Directory -Path $FixtureTools, $Customizer -Force | Out-Null
$FixtureWrapper = Join-Path $FixtureTools 'check-design-references.ps1'
Copy-Item -LiteralPath (Join-Path $Repository 'tools/check-design-references.ps1') -Destination $FixtureWrapper

# Two real interpreter launchers, with the original standard library shared as in
# a venv. sys.executable lets the validator prove which PATH entry actually ran.
$Launchers = @()
foreach ($Name in @('first Python', 'second Python')) {
    $Directory = Join-Path $Fixture $Name
    New-Item -ItemType Directory -Path $Directory | Out-Null
    $Executable = Join-Path $Directory 'python.exe'
    Copy-Item -LiteralPath $PythonExecutable -Destination $Executable
    Get-ChildItem -LiteralPath $PythonHome -File -Filter '*.dll' | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Directory
    }
    [IO.File]::WriteAllText((Join-Path $Directory 'pyvenv.cfg'),
        "home = $PythonHome`ninclude-system-site-packages = false`n")
    $Launchers += $Executable
}

$Validator = @'
import json
import os
from pathlib import Path
import sys

Path(os.environ['SERVERDECK_WRAPPER_TEST_RECEIPT']).write_text(
    json.dumps({'executable': sys.executable}), encoding='utf-8'
)
print('wrapper validator stdout marker')
sys.stderr.write('wrapper validator stderr marker\n')
sys.exit(int(os.environ['SERVERDECK_WRAPPER_TEST_EXIT']))
'@
[IO.File]::WriteAllText((Join-Path $FixtureTools 'validate-design.py'), $Validator)
$SiteCustomizer = @'
import os
import sys

if os.environ.get('SERVERDECK_WRAPPER_TEST_OLD_PYTHON') == '1':
    sys.version_info = (3, 9, 0)
    sys.version = '3.9.0 (controlled wrapper regression)'
'@
[IO.File]::WriteAllText((Join-Path $Customizer 'sitecustomize.py'), $SiteCustomizer)

function Invoke-WrapperCase {
    param(
        [string]$Name,
        [string]$ExplicitPython,
        [int]$ValidatorExit = 0,
        [int]$ExpectedExit = 0,
        [string]$ExpectedPython,
        [string]$ExpectedDiagnostic
    )
    $Receipt = Join-Path $Fixture ($Name + '.json')
    $env:SERVERDECK_WRAPPER_TEST_RECEIPT = $Receipt
    $env:SERVERDECK_WRAPPER_TEST_EXIT = [string]$ValidatorExit
    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $StartInfo.FileName = $ShellExecutable
    $StartInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $FixtureWrapper + '"'
    if ($ExplicitPython) {
        $StartInfo.Arguments += ' -Python "' + $ExplicitPython + '"'
    }
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $Process = [System.Diagnostics.Process]::Start($StartInfo)
    try {
        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        $Process.WaitForExit()
        $OutputText = $OutputTask.GetAwaiter().GetResult()
        $ErrorText = $ErrorTask.GetAwaiter().GetResult()
        $ExitCode = $Process.ExitCode
    } finally {
        $Process.Dispose()
    }
    if ($ExitCode -ne $ExpectedExit) {
        throw "$Name expected exit $ExpectedExit, got $ExitCode. stdout: $OutputText stderr: $ErrorText"
    }
    if ($ExpectedPython) {
        if (-not (Test-Path -LiteralPath $Receipt -PathType Leaf)) {
            throw "$Name did not execute the validator. stderr: $ErrorText"
        }
        $Executed = (Get-Content -LiteralPath $Receipt -Raw | ConvertFrom-Json).executable
        if ($Executed -ine $ExpectedPython) {
            throw "$Name executed '$Executed', expected '$ExpectedPython'."
        }
        if (-not $OutputText.Contains('wrapper validator stdout marker') -or
            -not $ErrorText.Contains('wrapper validator stderr marker')) {
            throw "$Name failed to forward validator stdout/stderr. stdout: $OutputText stderr: $ErrorText"
        }
    } elseif (Test-Path -LiteralPath $Receipt) {
        throw "$Name ran the validator after a prerequisite failure."
    }
    if ($ExpectedDiagnostic -and -not $ErrorText.Contains($ExpectedDiagnostic)) {
        throw "$Name omitted diagnostic '$ExpectedDiagnostic'. stderr: $ErrorText"
    }
    Write-Output "PASS $Name exit=$ExitCode"
}

$SavedEnvironment = @{}
foreach ($Name in @('PATH', 'PYTHONHOME', 'PYTHONPATH', 'SERVERDECK_WRAPPER_TEST_RECEIPT',
        'SERVERDECK_WRAPPER_TEST_EXIT', 'SERVERDECK_WRAPPER_TEST_OLD_PYTHON')) {
    $SavedEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
}
Write-Output "Preserved wrapper regression fixtures: $Fixture"
try {
    $env:PATH = (Split-Path -Parent $Launchers[0]) + ';' +
        (Split-Path -Parent $Launchers[1]) + ';' + $env:PATH
    $env:PYTHONHOME = $null
    $env:PYTHONPATH = $Customizer
    $env:SERVERDECK_WRAPPER_TEST_OLD_PYTHON = '0'
    $Applications = @(Get-Command -Name python -CommandType Application -ErrorAction Stop)
    if ($Applications.Count -lt 2 -or $Applications[0].Source -ine $Launchers[0] -or
        $Applications[1].Source -ine $Launchers[1]) {
        throw 'Regression setup did not expose both real Python applications in PATH order.'
    }
    Invoke-WrapperCase -Name 'default-first-path' -ExpectedPython $Launchers[0]
    Invoke-WrapperCase -Name 'explicit-second-path' -ExplicitPython $Launchers[1] -ExpectedPython $Launchers[1]
    Invoke-WrapperCase -Name 'default-validator-exit' -ValidatorExit 37 -ExpectedExit 37 -ExpectedPython $Launchers[0]
    Invoke-WrapperCase -Name 'explicit-validator-exit' -ExplicitPython $Launchers[1] -ValidatorExit 41 -ExpectedExit 41 -ExpectedPython $Launchers[1]
    $env:SERVERDECK_WRAPPER_TEST_OLD_PYTHON = '1'
    Invoke-WrapperCase -Name 'default-version-failure' -ExpectedExit 1 -ExpectedDiagnostic 'requires Python >=3.10; found 3.9.0'
    Invoke-WrapperCase -Name 'explicit-version-failure' -ExplicitPython $Launchers[1] -ExpectedExit 1 -ExpectedDiagnostic 'requires Python >=3.10; found 3.9.0'
    $env:SERVERDECK_WRAPPER_TEST_OLD_PYTHON = '0'
    Invoke-WrapperCase -Name 'missing-executable' -ExplicitPython (Join-Path $Fixture 'missing-python.exe') -ExpectedExit 1 -ExpectedDiagnostic 'Cannot find Python executable'
    Write-Output "DESIGN_WRAPPER_REGRESSION_PASSED shell=$($PSVersionTable.PSVersion) cases=7 pathApplications=$($Applications.Count)"
} finally {
    foreach ($Name in $SavedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($Name, $SavedEnvironment[$Name], 'Process')
    }
}
