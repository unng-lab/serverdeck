. "$PSScriptRoot/native-artifact-source-snapshot.ps1"

function New-NativeAvailableFailureProjection {
    param([Parameter(Mandatory)]$SourceSnapshot,
        [Parameter(Mandatory)][Management.Automation.ErrorRecord]$Failure,
        [Parameter(Mandatory)][string]$ArtifactManifestSha256,
        [switch]$ControlledFixture)
    if ($SourceSnapshot.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $ArtifactManifestSha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid diagnostic binding.' }
    $required=@(& "$PSScriptRoot/test-foundation-available.ps1" -ListOnly)
    $phase=$Failure.Exception.Data['ServerDeckAvailablePhase']
    $valid=$phase -is [string] -and ($phase -ceq 'setup' -or $phase -cin $required)
    $known=@{}
    foreach($file in $SourceSnapshot.files){
        if($file.file -cmatch '^tools/[A-Za-z0-9_-]+\.ps1$'){$known[$file.file]=$file.sha256}
    }
    $frames=[Collections.Generic.List[object]]::new()
    $stack=[string]$Failure.ScriptStackTrace
    if($valid -and $stack.Length -le 256KB){
        foreach($match in [regex]::Matches($stack,'(?m)^at [^\r\n]*, (?<path>[^\r\n]+): line (?<line>[0-9]{1,9})\r?$')){
            try {
                $absolute=[IO.Path]::GetFullPath($match.Groups['path'].Value)
                $relative=[IO.Path]::GetRelativePath($NativeIsarRepository,$absolute).Replace('\','/')
                if(-not $known.ContainsKey($relative)){continue}
                Assert-NativeIsarPlainPath $absolute
                if((Get-NativeIsarDigest $absolute) -cne $known[$relative]){continue}
                $line=[long]$match.Groups['line'].Value
                if($line -lt 1 -or $line -gt [IO.File]::ReadAllLines($absolute).Length){continue}
                $frames.Add(@{file=$relative;line=$line})
                if($frames.Count -eq 3){break}
            } catch { continue }
        }
    }
    return [ordered]@{
        schemaVersion=1;kind='qualification-available-failure'
        status=$(if($valid){'failed-phase-details'}else{'unavailable-phase-details'})
        phase='available-native-ui';failedPhase=$(if($valid){$phase}else{$null})
        sourceSnapshotSha256=$SourceSnapshot.sha256;artifactManifestSha256=$ArtifactManifestSha256
        controlledFixture=[bool]$ControlledFixture;sourceFrames=@($frames.ToArray())
        fullAcceptance=$false;distributionReady=$false;activated=$false
    }
}
