$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & dart run build_runner build --delete-conflicting-outputs --force-jit
    if ($LASTEXITCODE -ne 0) { throw "Model generation failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}
