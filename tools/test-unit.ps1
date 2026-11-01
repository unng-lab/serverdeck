[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/foundation-sdk.ps1"

$failedChecks = [Collections.Generic.List[string]]::new()
function Invoke-UnitCheck {
    param([string]$Label, [string]$Executable, [string[]]$Arguments)
    try { Invoke-FoundationCommand $Executable $Arguments }
    catch {
        $failedChecks.Add($Label)
        Write-Output "FAILED: $Label"
    }
}

Push-Location $FoundationRoot
try {
    Invoke-UnitCheck 'repository format' $FoundationDart @('format', '--output=none', '--set-exit-if-changed', '.')
    Invoke-UnitCheck 'Flutter analysis' $FoundationFlutter @('analyze')
    # test/ contains only unit tests for this task, no widget/design tests.
    Invoke-UnitCheck 'application unit suite' $FoundationFlutter @('test')
    try { & "$PSScriptRoot/test-embedded-bundle-unit.ps1" }
    catch { $failedChecks.Add('embedded bundle RAM unit suite'); Write-Output 'FAILED: embedded bundle RAM unit suite' }
    foreach ($package in Get-CurrentPackageNames) {
        Push-Location (Join-Path $FoundationRoot "packages/$package")
        try {
            Invoke-UnitCheck "$package analysis" $FoundationDart @('analyze')
            if (Test-Path -LiteralPath 'test') {
                $unitFiles = @(Get-ChildItem -LiteralPath 'test' -Recurse -File -Filter '*_test.dart')
                if ($unitFiles.Count -gt 0) {
                    Invoke-UnitCheck "$package full unit suite" $FoundationDart @('test', '--reporter', 'expanded')
                } else {
                    Write-Output "${package}: no current-task unit tests yet; no test pass claimed."
                }
            } else {
                Write-Output "${package}: old tests removed; no test pass claimed."
            }
        }
        finally { Pop-Location }
    }
}
finally { Pop-Location }
if ($failedChecks.Count -gt 0) { throw "Unit checks failed: $($failedChecks -join ', ')." }
