$ErrorActionPreference = 'Stop'
flutter test test_design/components
if ($LASTEXITCODE -ne 0) { throw 'Component tests failed' }
