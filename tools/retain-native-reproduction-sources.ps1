[CmdletBinding()]
param([Parameter(Mandatory)][string]$CompletionLog)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/native-artifact-compatibility.ps1"

$CompletionLog=[IO.Path]::GetFullPath($CompletionLog,(Get-Location).ProviderPath)
$auditRoot=Join-Path $NativeIsarRepository '.local/audits'
if([IO.Path]::GetDirectoryName($CompletionLog) -cne $auditRoot -or
    [IO.Path]::GetFileName($CompletionLog) -cnotmatch '^[a-zA-Z0-9._-]+-source-tests\.txt$'){
    throw 'Expected owned completed source-test log.'
}
Assert-NativeIsarPlainPath $CompletionLog
$logStream=[IO.File]::Open($CompletionLog,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
try {
    if($logStream.Length -gt 65536){throw 'Source-test completion log exceeds limit.'}
    $reader=[IO.StreamReader]::new($logStream,[Text.UTF8Encoding]::new($false,$true),$true,1024,$true)
    try {$lines=@($reader.ReadToEnd() -split '\r?\n' | Where-Object {$_})} finally {$reader.Dispose()}
} finally {$logStream.Dispose()}
$required=@(
    'NATIVE_COMPLETE_SOURCE_8107_FILES_183_NOTICES_FULL_REPACK_AND_STANDALONE_OFFLINE_BUILD_PASSED',
    'NATIVE_SOURCE_SPACED_ROOT_ENCODED_FLAG_RESTORATION_AND_LONG_ROOT_PREFLIGHT_PASSED'
)
foreach($marker in $required){if(@($lines | Where-Object {$_ -ceq $marker}).Count -ne 1){throw 'Source test has not completed successfully.'}}
if($lines.Count -ne 4){throw 'Unexpected source-test completion output.'}
$fixture=[IO.Path]::GetFullPath($lines[-1])
$reproduced=[IO.Path]::GetFullPath($lines[-2])
$localRoot=Join-Path $NativeIsarRepository '.local'
if([IO.Path]::GetDirectoryName($fixture) -cne $localRoot -or
    [IO.Path]::GetFileName($fixture) -cnotmatch '^native-source-package-tests-[a-f0-9]{32}$'){
    throw 'Expected owned completed source-test fixture.'
}
Assert-NativeIsarPlainPath $fixture
$reproductionRoot=[IO.File]::ReadAllText((Join-Path $fixture 'extracted-root.txt')).Trim()
$reproductionRoot=[IO.Path]::GetFullPath($reproductionRoot)
if([IO.Path]::GetDirectoryName($reproductionRoot) -cne $localRoot -or
    [IO.Path]::GetFileName($reproductionRoot) -cnotmatch '^src space-[a-f0-9]{8}$'){
    throw 'Expected owned standalone reproduction root.'
}
Assert-NativeIsarPlainPath $reproductionRoot
$nestedNative=Join-Path $reproductionRoot '.local/native-isar'
if([IO.Path]::GetDirectoryName($reproduced) -cne $nestedNative -or
    [IO.Path]::GetFileName($reproduced) -cnotmatch '^candidate-[a-f0-9]{32}$'){
    throw 'Reproduced candidate identity mismatch.'
}
$reproducedReceipt=Read-NativeIsarArtifactJson (Join-Path $reproduced 'native-build.json')
if($reproducedReceipt.state -cne 'built-unqualified' -or
    (Get-NativeIsarDigest (Join-Path $reproduced 'libisar.dll')) -cne $reproducedReceipt.dll.sha256){
    throw 'Completed reproduced candidate binding mismatch.'
}
$records=[Collections.Generic.List[object]]::new()
$attemptDirectories=@(Get-ChildItem -LiteralPath $nestedNative -Directory | Where-Object {$_.Name -cmatch '^(candidate|prepared)-[a-f0-9]{32}$'})
$candidateDirectories=@($attemptDirectories | Where-Object {$_.Name.StartsWith('candidate-')})
$preparedDirectories=@($attemptDirectories | Where-Object {$_.Name.StartsWith('prepared-')})
if($candidateDirectories.Count -ne 1 -or $preparedDirectories.Count -ne 1 -or
    $candidateDirectories[0].FullName -cne $reproduced){
    throw 'Ambiguous reproduction attempt directories.'
}
$recordPath=Join-Path $fixture 'source-retention.json'
if(Test-Path -LiteralPath $recordPath){throw 'Source-retention record already exists.'}
foreach($directory in $attemptDirectories){
    $receiptName=if($directory.Name.StartsWith('candidate-')){'native-build.json'}else{'prepared.json'}
    $receiptPath=Join-Path $directory.FullName $receiptName
    if(-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)){throw 'Completed reproduction receipt missing.'}
    $receipt=Read-NativeIsarArtifactJson $receiptPath
    $expectedState=if($receiptName -ceq 'native-build.json'){'built-unqualified'}else{'prepared'}
    if($receipt.state -cne $expectedState -or $receipt.recipeFileSha256 -cne $reproducedReceipt.recipeFileSha256){
        throw 'Completed reproduction preparation binding mismatch.'
    }
    $source=Join-Path $directory.FullName 'source'
    if(-not (Test-Path -LiteralPath $source -PathType Container)){throw 'Completed reproduction source tree missing.'}
    Assert-NativeIsarPlainPath $source
    $snapshot=Get-NativeArtifactBundleSnapshot $source
    $destination=Join-Path $localRoot ('src stash-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
    Assert-NativeIsarPlainPath $destination
    if(Test-Path -LiteralPath $destination){throw 'Source-retention destination already exists.'}
    foreach($relative in $snapshot.Keys){if((Join-Path $destination $relative).Length -gt 250){throw 'Retained source path exceeds short-path budget.'}}
    # Both resolved targets are inside the workspace; never move parent fixtures,
    # runtime files, failed/incomplete attempts or an arbitrary computed path.
    if([IO.Path]::GetDirectoryName($source) -cne $directory.FullName -or
        -not $source.StartsWith($nestedNative+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal) -or
        [IO.Path]::GetDirectoryName($destination) -cne $localRoot){throw 'Source-retention path boundary mismatch.'}
    $records.Add([ordered]@{original=$source;retained=$destination;files=$snapshot.Count;treeSha256=Get-NativeIsarSnapshotDigest $snapshot;receiptSha256=Get-NativeIsarDigest $receiptPath})
}
if($records.Count -ne 2){throw 'Completed reproduction source set incomplete.'}
$proof=[ordered]@{schemaVersion=1;state='retention-started';completionLogSha256=Get-NativeIsarDigest $CompletionLog;reproductionRoot=$reproductionRoot;fullAcceptance=$false;distributionReady=$false;trees=@($records.ToArray())}
Write-NativeIsarJson $recordPath $proof
foreach($record in $records){
    Move-Item -LiteralPath $record.original -Destination $record.retained
    if((Get-NativeIsarSnapshotDigest (Get-NativeArtifactBundleSnapshot $record.retained)) -cne $record.treeSha256){throw 'Retained source tree digest mismatch.'}
}
$proof.state='completed-sources-retained'
$temporary=Join-Path $fixture ('source-retention-'+[Guid]::NewGuid().ToString('N')+'.json')
Write-NativeIsarJson $temporary $proof
[IO.File]::Move($temporary,$recordPath,$true)
'NATIVE_COMPLETED_REPRODUCTION_SOURCE_TREES_RETAINED'
$recordPath
