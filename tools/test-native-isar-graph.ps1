[CmdletBinding()]
param([Parameter(Mandatory)][string]$Candidate)
. "$PSScriptRoot/native-isar-inputs.ps1"
$Candidate = [IO.Path]::GetFullPath($Candidate)
$priorDll = Get-NativeIsarDigest (Join-Path $Candidate 'libisar.dll')
$priorReceipt = Get-NativeIsarDigest (Join-Path $Candidate 'native-build.json')
$first = & "$PSScriptRoot/collect-native-isar-graph.ps1" -Candidate $Candidate
$pwsh = Join-Path $PSHOME 'pwsh.exe'
$second = & $pwsh -NoProfile -File "$PSScriptRoot/collect-native-isar-graph.ps1" -Candidate $Candidate
if ($LASTEXITCODE -ne 0) { throw 'Separate-process native graph export failed.' }
$firstPath = Join-Path $first 'native-dependencies.json'
$secondPath = Join-Path $second 'native-dependencies.json'
if ((Get-NativeIsarDigest $firstPath) -cne (Get-NativeIsarDigest $secondPath)) { throw 'Native graph export is nondeterministic.' }
if ((Get-NativeIsarDigest (Join-Path $first 'licenses/MPL-2.0.txt')) -cne '3f3d9e0024b1921b067d6f7f88deb4a60cbe7a78e76c64e3f1d7fc3b779b9d04') { throw 'Canonical binding license text missing or modified.' }
$json = Get-Content -LiteralPath $firstPath -Raw
$graph = $json | ConvertFrom-Json
if ($graph.state -cne 'graph-collected-unqualified' -or $graph.distributionReady -ne $false -or
    $graph.packages.Count -ne 67 -or $graph.buildReceiptSha256 -cne $priorReceipt -or
    $json.Contains($NativeIsarRepository) -or $json -match 'file:///|[A-Za-z]:\\\\') { throw 'Invalid graph projection or private path leak.' }
$names = @($graph.packages | ForEach-Object { $_.id })
foreach ($package in $graph.packages) {
    if ($package.dependencies | Where-Object { $_.package -notin $names }) { throw 'Graph has dangling dependency.' }
}
foreach ($name in @('isar','isar-core')) {
    $package = @($graph.packages | Where-Object name -eq $name)[0]
    if ($package.version -cne '0.0.0' -or $null -ne $package.declaredLicense -or $package.sourceLicense -cne 'Apache-2.0' -or
        $package.licenseOrigin -cnotmatch '^inherited pinned project LICENSE') { throw 'Incorrect path crate version or invented Cargo license.' }
}
$failures = 0
foreach ($case in @('metadata','dll')) {
    $fixture = Join-Path $NativeIsarRepository ('.local/native-isar/candidate-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($fixture) | Out-Null
    foreach ($name in @('native-build.json','libisar.dll','metadata.private.json')) { Copy-Item -LiteralPath (Join-Path $Candidate $name) -Destination (Join-Path $fixture $name) }
    if ($case -eq 'metadata') { [IO.File]::AppendAllText((Join-Path $fixture 'metadata.private.json')," `n") }
    else { [IO.File]::WriteAllText((Join-Path $fixture 'libisar.dll'),'corrupt candidate') }
    $failed = $false
    try { & "$PSScriptRoot/collect-native-isar-graph.ps1" -Candidate $fixture | Out-Null } catch {
        $expected = 'Bound native metadata mismatch.'
        if ($case -eq 'dll') { $expected='Graph candidate receipt mismatch.' }
        if ($_.Exception.Message -cne $expected) { throw }
        $failed = $true
    }
    if (-not $failed -or @(Get-ChildItem -LiteralPath $fixture -Directory -Filter 'graph-*').Count) { throw 'Tampered graph input was accepted or published.' }
    $failures++
}
if ((Get-NativeIsarDigest (Join-Path $Candidate 'libisar.dll')) -cne $priorDll -or
    (Get-NativeIsarDigest (Join-Path $Candidate 'native-build.json')) -cne $priorReceipt -or
    (Get-NativeIsarDigest $firstPath) -cne (Get-NativeIsarDigest $secondPath)) { throw 'Graph failure changed previous input/output.' }
Write-Output 'NATIVE_GRAPH_DETERMINISTIC_67_PACKAGES_NO_MACHINE_PATHS_PASSED'
Write-Output "NATIVE_GRAPH_BOUND_METADATA_AND_DLL_REFUSALS_PASSED=$failures"
Write-Output $first
