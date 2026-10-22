[CmdletBinding()]
param([string]$Fixture='', [switch]$Child)
. "$PSScriptRoot/native-artifact-source-snapshot.ps1"
$repository=$NativeIsarRepository
if ($Child) {
    $Fixture=[IO.Path]::GetFullPath($Fixture)
    if ([IO.Path]::GetDirectoryName($Fixture) -cne (Join-Path $repository '.local') -or
        [IO.Path]::GetFileName($Fixture) -cnotmatch '^native-snapshot-tests-[a-f0-9]{32}$') { throw 'Expected owned qualification snapshot fixture.' }
    Assert-NativeIsarPlainPath $Fixture
    $NativeIsarRepository=$Fixture
    (Get-NativeArtifactSourceSnapshot).sha256
    return
}
$original=Get-NativeArtifactSourceSnapshot
$Fixture=Join-Path $repository ('.local/native-snapshot-tests-' + [Guid]::NewGuid().ToString('N'))
Assert-NativeIsarPlainPath $Fixture
[IO.Directory]::CreateDirectory($Fixture) | Out-Null
foreach ($file in $original.files) {
    $destination=Join-Path $Fixture $file.file
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repository $file.file) -Destination $destination
}
try {
    $NativeIsarRepository=$Fixture
    $baseline=Get-NativeArtifactSourceSnapshot
    if ($baseline.sha256 -cne $original.sha256) { throw 'Copied qualification snapshot mismatch.' }
    $childHash=& (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $PSCommandPath -Child -Fixture $Fixture
    if ($LASTEXITCODE -ne 0 -or $childHash -cne $baseline.sha256) { throw 'Snapshot cross-process determinism failed.' }
    foreach ($name in @('specs/001-service-foundation/tasks.md','specs/001-service-foundation/quickstart.md','.local/private.log')) {
        $path=Join-Path $Fixture $name
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
        [IO.File]::WriteAllText($path,'mutable evidence excluded')
    }
    if ((Get-NativeArtifactSourceSnapshot).sha256 -cne $baseline.sha256) { throw 'Mutable qualification evidence entered source snapshot.' }
    foreach ($name in @('lib/main.dart','specs/001-service-foundation/contracts/local-api.md','pubspec.lock','tools/run-foundation.ps1',
        'test_driver/integration_test.dart','packages/serverdeck_locald/build.yaml','packages/serverdeck_locald/dart_test.yaml',
        'third_party/isar_community/lib/src/native/txn.dart','third_party/isar_community/lib/src/common/isar_common.dart',
        'third_party/isar_community/pubspec.yaml','third_party/isar_community/LICENSE','third_party/isar_community/UPSTREAM.md')) {
        $path=Join-Path $Fixture $name
        $bytes=[IO.File]::ReadAllBytes($path)
        try {
            [IO.File]::AppendAllText($path,'changed qualification input')
            if ((Get-NativeArtifactSourceSnapshot).sha256 -ceq $baseline.sha256) { throw 'Changed qualification source was not invalidated.' }
        } finally { [IO.File]::WriteAllBytes($path,$bytes) }
    }
    $newPath=Join-Path $Fixture 'lib/new_qualification_input.dart'
    [IO.File]::WriteAllText($newPath,'new qualification input')
    if ((Get-NativeArtifactSourceSnapshot).sha256 -ceq $baseline.sha256) { throw 'Added qualification source was not invalidated.' }
    Remove-Item -LiteralPath $newPath
    foreach ($name in @('dart_test.yaml','packages/serverdeck_protocol/build.yaml','test_driver/new_assertion.dart')) {
        $path=Join-Path $Fixture $name
        if (Test-Path -LiteralPath $path) {
            $bytes=[IO.File]::ReadAllBytes($path)
            try {
                Remove-Item -LiteralPath $path
                if ((Get-NativeArtifactSourceSnapshot).sha256 -ceq $baseline.sha256) { throw 'Removed optional qualification input was not invalidated.' }
            } finally { [IO.File]::WriteAllBytes($path,$bytes) }
            if ((Get-NativeArtifactSourceSnapshot).sha256 -cne $baseline.sha256) { throw 'Restored optional qualification input mismatch.' }
            continue
        }
        [IO.File]::WriteAllText($path,'new qualification configuration or assertion')
        try { if ((Get-NativeArtifactSourceSnapshot).sha256 -ceq $baseline.sha256) { throw 'Added qualification configuration/assertion was not invalidated.' } } finally { Remove-Item -LiteralPath $path }
        if ((Get-NativeArtifactSourceSnapshot).sha256 -cne $baseline.sha256) { throw 'Removed optional qualification input did not restore digest.' }
    }
    foreach ($name in @('pubspec.lock','packages/serverdeck_locald/build.yaml','packages/serverdeck_locald/dart_test.yaml')) {
        $missingPath=Join-Path $Fixture $name
        $bytes=[IO.File]::ReadAllBytes($missingPath)
        try {
            Remove-Item -LiteralPath $missingPath
            $refused=$false
            try { Get-NativeArtifactSourceSnapshot | Out-Null } catch { if ($_.Exception.Message -cne 'Qualification source input missing.') { throw };$refused=$true }
            if (-not $refused) { throw 'Missing required snapshot input accepted.' }
        } finally { [IO.File]::WriteAllBytes($missingPath,$bytes) }
    }
    if ((Get-NativeArtifactSourceSnapshot).sha256 -cne $baseline.sha256) { throw 'Restored fixture snapshot mismatch.' }
} finally { $NativeIsarRepository=$repository }
if ((Get-NativeArtifactSourceSnapshot).sha256 -cne $original.sha256) { throw 'Original qualification source changed.' }
'NATIVE_QUALIFICATION_SOURCE_SNAPSHOT_CROSS_PROCESS_MUTATION_EXCLUSION_AND_PRESERVATION_PASSED'
$Fixture
