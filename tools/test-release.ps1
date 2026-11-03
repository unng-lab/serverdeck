[CmdletBinding()]
param()
# Compatibility entrypoint: native unit tests only. No product/VM smoke.
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & cmake -S native -B build/native-tests -A x64 -DSERVERDECK_BUILD_TESTS=ON -DSERVERDECK_BUILD_HISTORICAL_INTEGRATION=OFF
    if ($LASTEXITCODE -ne 0) { throw 'Native unit configure failed' }
    & cmake --build build/native-tests --config Release
    if ($LASTEXITCODE -ne 0) { throw 'Native unit build failed' }
    & ctest --test-dir build/native-tests -C Release -L '^unit$' --no-tests=error --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw 'Native unit tests failed' }
    Write-Output 'Native unit tests only; no product, integration, process-kill or VM scenarios executed.'
} finally { Pop-Location }
