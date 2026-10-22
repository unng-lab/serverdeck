[CmdletBinding()]
param([string]$Python = 'python')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$fixtureRoot = Split-Path -Parent $PSScriptRoot
$version = & $Python -c 'import platform,sys; print(platform.python_version()+":"+str(sys.maxsize>2**32))'
if ($LASTEXITCODE -ne 0 -or $version -cne '3.12.10:True') { throw 'Trust fixture requires Python3.12.10 x64.' }
$environment = Join-Path $fixtureRoot '.local/trust-probe-python'
& $Python -m venv $environment
if ($LASTEXITCODE -ne 0) { throw 'Trust fixture environment creation failed.' }
$executable = Join-Path $environment 'Scripts/python.exe'
$installLog = Join-Path $environment 'install.private.txt'
& $executable -m pip install --disable-pip-version-check --only-binary=:all: --require-hashes -r (Join-Path $PSScriptRoot 'trust-probe-fixture-requirements.txt') *> $installLog
if ($LASTEXITCODE -ne 0) { throw 'Trust fixture locked installation failed; inspect local install log.' }
& $executable -m pip check *> (Join-Path $environment 'check.private.txt')
if ($LASTEXITCODE -ne 0) { throw 'Trust fixture dependency check failed.' }
$executable
