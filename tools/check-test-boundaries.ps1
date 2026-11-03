[CmdletBinding()]
param(
    [string]$TestRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'test')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$forbidden = @(
    '\b(getRect|getSize|getTopLeft|getTopRight|getBottomLeft|getBottomRight)\s*\(',
    '\b(matchesGoldenFile|matchesReferenceImage|compareWithGolden)\s*\(',
    '\bphysicalSize\s*=|\bsetSurfaceSize\s*\(',
    '\b(toImage|takeScreenshot|screenshot)\s*\(',
    '\bProcess\.(start|run|runSync|startSync)\s*\(',
    '\b(initializeIsarCore|DynamicLibrary\.open)\s*\(|\bIsar\.open\s*\(',
    'libisar\.dll|package:integration_test/',
    'test_design[/\\]|componentFrames|DESIGN_(STATE_|STOCK_)?CAPTURE_DIR|COMPONENT_CAPTURE_DIR'
)
$violations = @()
$files = @(Get-ChildItem -LiteralPath $TestRoot -Recurse -File -Filter '*.dart')
foreach ($file in $files) {
    $violations += @(Select-String -LiteralPath $file.FullName -Pattern $forbidden)
}
if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Output "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
    throw 'Unit test boundary violated: no real database/process integration or feature design/layout checks in test/.'
}
Write-Output "Feature test boundaries passed: $($files.Count) Dart files, no process/native database integration or layout/capture checks in test/."
