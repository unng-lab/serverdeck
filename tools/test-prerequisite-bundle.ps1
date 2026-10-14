[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/prerequisite-bundle.ps1"
$root=Join-Path $NativeIsarRepository ('runner-artifacts/prerequisite-bundle-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
foreach($optional in @($false,$true)){
    $case=Join-Path $root ([string]$optional)
    $source=Join-Path $case 'source'
    $destination=Join-Path $case 'destination'
    [void][IO.Directory]::CreateDirectory((Join-Path $source 'data/空 directory'))
    [void][IO.Directory]::CreateDirectory((Join-Path $source 'data/empty'))
    [void][IO.Directory]::CreateDirectory($destination)
    foreach($name in @('serverdeck.exe','locald.exe','libisar.dll','foundation.manifest.json','flutter_windows.dll','future-runtime.dll','data/icudtl.dat','data/空 directory/asset.bin')){
        [IO.File]::WriteAllBytes((Join-Path $source $name),[byte[]](1,2,3,4))
    }
    if($optional){[IO.File]::WriteAllText((Join-Path $source 'native_assets.json'),'synthetic optional input')}
    $hidden=Join-Path $source 'data/hidden.bin'
    [IO.File]::WriteAllBytes($hidden,[byte[]](5,6,7))
    [IO.File]::SetAttributes($hidden,[IO.FileAttributes]::Hidden)
    Copy-PrerequisiteNormalBundle -Source $source -Destination $destination
    if((Test-Path (Join-Path $destination 'native_assets.json')) -ne $optional -or
        -not (Test-Path (Join-Path $destination 'future-runtime.dll'))){throw 'Complete bundle copy failed.'}
    if((Get-NativeIsarDigest (Join-Path $destination 'data/hidden.bin')) -cne (Get-NativeIsarDigest $hidden) -or
        -not [IO.Directory]::Exists((Join-Path $destination 'data/empty'))){throw 'Hidden file or empty directory omitted.'}
    $before=Get-NativeIsarDigest (Join-Path $destination 'locald.exe')
    $refused=$false
    try{Copy-PrerequisiteNormalBundle -Source $source -Destination $destination}catch{$refused=$true}
    if(-not $refused -or (Get-NativeIsarDigest (Join-Path $destination 'locald.exe')) -cne $before){throw 'Nonempty destination not preserved.'}
    $refused=$false
    try{Copy-PrerequisiteNormalBundle -Source $source -Destination (Join-Path $source 'nested')}catch{$refused=$true}
    if(-not $refused -or (Test-Path (Join-Path $source 'nested'))){throw 'Overlap accepted.'}
    $nested=Join-Path $source 'nested'
    [void][IO.Directory]::CreateDirectory($nested)
    function Get-ControlledInventory {
        @(Get-ChildItem -LiteralPath $source -Recurse -Force|ForEach-Object{
            $_.FullName+':'+$(if($_.PSIsContainer){'directory'}else{Get-NativeIsarDigest $_.FullName})
        }|Sort-Object) -join "`n"
    }
    $inventory=Get-ControlledInventory
    foreach($sourceSuffix in @('',[string][IO.Path]::DirectorySeparatorChar)){
        foreach($destinationSuffix in @('',[string][IO.Path]::DirectorySeparatorChar)){
            foreach($reverse in @($false,$true)){
                $from=if($reverse){$nested}else{$source}
                $to=if($reverse){$source}else{$nested}
                $refused=$false
                try{Copy-PrerequisiteNormalBundle -Source ($from+$sourceSuffix) -Destination ($to+$destinationSuffix)}
                catch{if($_.Exception.Message -cne 'Overlapping prerequisite bundles.'){throw};$refused=$true}
                if(-not $refused -or (Get-ControlledInventory) -cne $inventory){throw 'Trailing-separator overlap changed source.'}
            }
        }
    }
}
'PREREQUISITE_COMPLETE_BUNDLE_OPTIONAL_ABSENCE_AND_EXTRA_RUNTIME_PASSED'
'PREREQUISITE_NONEMPTY_AND_OVERLAP_PRESERVATION_PASSED'
'PREREQUISITE_TRAILING_SEPARATOR_ANCESTOR_DESCENDANT_INVENTORY_PRESERVATION_PASSED'
