. "$PSScriptRoot/native-probe-process.ps1"

function Invoke-FoundationEnvironmentActor {
    param([Parameter(Mandatory)][string]$Root,[ValidateSet('seed','verify')][string]$Mode,[string]$Marker)
    Assert-NativeIsarPlainPath $Root
    $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $Root 'checkpoint-actor.exe'))
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true; $start.WorkingDirectory=$Root
    foreach($argument in @($Root,(Join-Path $Root 'application bundle'),$Mode)) {$start.ArgumentList.Add($argument)}
    $child=[Diagnostics.Process]::new(); $child.StartInfo=$start; $started=$false
    try {
        if(-not $child.Start()){throw 'Environment actor start failed.'}; $started=$true; $held=$child.Handle
        $output=$child.StandardOutput.ReadToEndAsync(); $errors=$child.StandardError.ReadToEndAsync()
        if(-not $child.WaitForExit(180000)){throw 'Environment actor deadline exceeded.'}
        $text=$output.GetAwaiter().GetResult(); $errorText=$errors.GetAwaiter().GetResult(); $lines=@($text.Trim() -split '\r?\n')
        if($child.ExitCode -ne 0 -or $errorText.Length -ne 0 -or $lines.Count -ne 2 -or
            $lines[0] -cne 'IsarCore using libmdbx: v0.13.8-temp-upstream-fix' -or $lines[1] -cne $Marker){throw 'Environment actor proof failed; retained fixture requires inspection.'}
    } finally {Close-NativeFixtureChild $child $started}
}
