$ErrorActionPreference = 'Stop'
./tools/check-test-boundaries.ps1
dart format --output=none --set-exit-if-changed .
if ($LASTEXITCODE -ne 0) { throw 'Format failed' }
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'Analyze failed' }
flutter test
if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
python -m unittest discover -s test/mcp -p '*_test.py'
if ($LASTEXITCODE -ne 0) { throw 'Offline MCP schema unit tests failed; install tools/unit-requirements.txt' }
