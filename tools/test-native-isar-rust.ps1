[CmdletBinding()]
param([Parameter(Mandatory)][string]$Candidate, [Parameter(Mandatory)][string]$ArchiveCache)
. "$PSScriptRoot/native-isar-rust-inputs.ps1"
$Candidate = [IO.Path]::GetFullPath($Candidate)
$priorDll = Get-NativeIsarDigest (Join-Path $Candidate 'libisar.dll')
$priorReceipt = Get-NativeIsarDigest (Join-Path $Candidate 'native-build.json')
$results = @(& "$PSScriptRoot/collect-native-isar-rust.ps1" -Candidate $Candidate -ArchiveCache $ArchiveCache)
if ($results.Count -ne 2) { throw 'Unexpected Rust collector output.' }
$output = $results[0]
$prepared = $results[1]
$receipt = Get-Content -LiteralPath (Join-Path $Candidate 'native-build.json') -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath (Join-Path $output 'rust-license-material.json') -Raw | ConvertFrom-Json
$noticePath = Join-Path $output 'RUST_NATIVE_NOTICES.txt'
$noticeDigest = Get-NativeIsarDigest $noticePath
$notice = [IO.File]::ReadAllText($noticePath)
foreach ($file in $manifest.files) {
    $destination = Join-Path $output $file.destination
    if ((Get-NativeIsarDigest $destination) -cne $file.sha256 -or (Get-Item -LiteralPath $destination).Length -ne $file.length) { throw 'Rust material copy incomplete.' }
    if (-not $notice.Contains($file.destination)) { throw 'Rust notice reference missing.' }
    if (-not $file.destination.EndsWith('.html') -and -not $notice.Contains([IO.File]::ReadAllText($destination))) { throw 'Rust plain notice text incomplete.' }
}
if ((Get-Item (Join-Path $output 'licenses/rust/runtime/LICENSE-MIT')).Length -ne 1068 -or
    (Get-Item (Join-Path $output 'licenses/rust/build-tools/CARGO-LICENSE-MIT')).Length -ne 1023) { throw 'Cargo license incorrectly substituted for Rust runtime.' }
$fixture = Join-Path $NativeIsarRepository ('.local/native-rust-license-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $fixture 'archives')) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $fixture 'rust')) | Out-Null
foreach ($archive in $manifest.archives) {
    $name = [IO.Path]::GetFileName(([Uri]$archive.url).AbsolutePath)
    Copy-Item -LiteralPath (Join-Path $prepared ('archives/' + $name)) -Destination (Join-Path $fixture ('archives/' + $name))
}
foreach ($file in $manifest.files) {
    $destination = Join-Path $fixture $file.sourceRelative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $prepared $file.sourceRelative) -Destination $destination
}
$changed = Join-Path $fixture $manifest.files[0].sourceRelative
[IO.File]::AppendAllText($changed,'changed notice')
$failed = $false
try { Get-NativeIsarRustMaterials $fixture $receipt.inputDigests.rust | Out-Null } catch {
    if ($_.Exception.Message -cne 'Rust license material hash mismatch.') { throw }
    $failed = $true
}
if (-not $failed) { throw 'Changed Rust copyright accepted.' }
Copy-Item -LiteralPath (Join-Path $prepared $manifest.files[0].sourceRelative) -Destination $changed -Force
$failed = $false
try { Get-NativeIsarRustMaterials $fixture $receipt.inputDigests.rust | Out-Null } catch {
    if ($_.Exception.Message -cne 'Rust license SDK differs from the compiled SDK.') { throw }
    $failed = $true
}
if (-not $failed) { throw 'Different Rust SDK accepted.' }
$archive = $manifest.archives[0]
$name = [IO.Path]::GetFileName(([Uri]$archive.url).AbsolutePath)
[IO.File]::AppendAllText((Join-Path $fixture ('archives/' + $name)),'changed archive')
$failed = $false
try { Get-NativeIsarRustMaterials $fixture $receipt.inputDigests.rust | Out-Null } catch {
    if ($_.Exception.Message -cne 'Rust material archive hash mismatch.') { throw }
    $failed = $true
}
if (-not $failed -or (Get-NativeIsarDigest $noticePath) -cne $noticeDigest -or
    (Get-NativeIsarDigest (Join-Path $Candidate 'libisar.dll')) -cne $priorDll -or
    (Get-NativeIsarDigest (Join-Path $Candidate 'native-build.json')) -cne $priorReceipt) { throw 'Rust refusal did not preserve previous output.' }
Write-Output 'NATIVE_RUST_8_EXACT_MATERIAL_FILES_RUNTIME_AND_TOOL_SCOPES_PASSED'
Write-Output 'NATIVE_RUST_MATERIAL_ARCHIVE_AND_COMPILED_SDK_REFUSALS_PASSED'
Write-Output $output
Write-Output $fixture
