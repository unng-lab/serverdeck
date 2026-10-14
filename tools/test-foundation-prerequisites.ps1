[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/foundation-sdk.ps1"
. "$PSScriptRoot/native-probe-process.ps1"
. "$PSScriptRoot/prerequisite-bundle.ps1"

function Assert-PrerequisitePath {
    param([string]$Path)
    $resolved = [IO.Path]::GetFullPath($Path)
    if (-not $resolved.StartsWith($FoundationRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Prerequisite fixture outside workspace.' }
    $component = $resolved
    while ($component) {
        if ((Test-Path -LiteralPath $component) -and ((Get-Item -LiteralPath $component -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Unsafe prerequisite path.' }
        $component = [IO.Path]::GetDirectoryName($component)
    }
}

& "$PSScriptRoot/run-foundation.ps1" -Configuration Debug -BuildOnly
$source = Join-Path $FoundationRoot 'build/windows/x64/runner/Debug'
Assert-PrerequisitePath $source
$sourceManifest = Get-Content -LiteralPath (Join-Path $source 'foundation.manifest.json') -Raw
$verified = $sourceManifest | ConvertFrom-Json
if ($verified.testOnly -or $verified.configuration -ne 'Debug' -or $verified.appRoot -ne $source) { throw 'Normal prerequisite bundle required.' }
foreach ($name in @('serverdeck.exe','locald.exe','libisar.dll')) {
    $sourceFile = Join-Path $source $name
    Assert-PrerequisitePath $sourceFile
    if ((Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $verified.sha256.$name) { throw 'Prerequisite source hash mismatch.' }
}
$fixtureRoot = Join-Path $FoundationRoot ('.local/prerequisite-acceptance-' + [Guid]::NewGuid().ToString('N'))
Assert-PrerequisitePath $fixtureRoot
if (Test-Path -LiteralPath $fixtureRoot) { throw 'Prerequisite fixture already exists.' }
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$completed = @()
foreach ($case in @('missing-dll','invalid-dll','manifest-version','executable-hash','healthy-owner')) {
    Write-Output "START normal-prerequisite-$case"
    $caseRoot = Join-Path $fixtureRoot $case
    $layout = Join-Path $caseRoot 'bundle'
    $caseProfile = Join-Path $caseRoot 'profile'
    Assert-PrerequisitePath $layout
    Assert-PrerequisitePath $caseProfile
    New-Item -ItemType Directory -Path $layout, $caseProfile | Out-Null
    if ($case -eq 'healthy-owner') {
        Copy-PrerequisiteNormalBundle -Source $source -Destination $layout
    } else {
        foreach ($name in @('serverdeck.exe','locald.exe','libisar.dll')) {
            if ($case -eq 'missing-dll' -and $name -eq 'libisar.dll') { continue }
            Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $layout $name)
        }
    }
    $manifest = $sourceManifest | ConvertFrom-Json
    $manifest.appRoot = $layout
    if ($case -eq 'invalid-dll') {
        $dll = Join-Path $layout 'libisar.dll'
        [IO.File]::WriteAllBytes($dll, [Text.Encoding]::ASCII.GetBytes('synthetic-not-a-native-library'))
        $manifest.sha256.'libisar.dll' = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    if ($case -eq 'manifest-version') { $manifest.format = 2 }
    if ($case -eq 'executable-hash') { $manifest.sha256.'locald.exe' = '0' * 64 }
    [IO.File]::WriteAllText((Join-Path $layout 'foundation.manifest.json'), ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    $marker = Join-Path $caseProfile 'preserved.marker'
    [IO.File]::WriteAllText($marker, 'synthetic-prerequisite-preservation', [Text.UTF8Encoding]::new($false))
    $markerHash = (Get-FileHash -LiteralPath $marker -Algorithm SHA256).Hash
    $executable = Join-Path $layout 'locald.exe'
    $start = [Diagnostics.ProcessStartInfo]::new($executable)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $caseRoot
    $start.Environment['LOCALAPPDATA'] = $caseProfile
    foreach ($argument in @('--workspace','default','--app-root',$layout)) { $start.ArgumentList.Add($argument) }
    $child = [Diagnostics.Process]::new()
    $child.StartInfo = $start
    $started = $false
    $uiChild = $null
    $uiStarted = $false
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $child.Start()) { throw 'Prerequisite child start failed.' }
        $started = $true
        $heldHandle = $child.Handle
        $output = $child.StandardOutput.ReadToEndAsync()
        $errors = $child.StandardError.ReadToEndAsync()
        if ($case -eq 'healthy-owner') {
            $uiStart = [Diagnostics.ProcessStartInfo]::new((Join-Path $layout 'serverdeck.exe'))
            $uiStart.UseShellExecute = $false
            $uiStart.CreateNoWindow = $true
            $uiStart.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
            $uiStart.RedirectStandardOutput = $true
            $uiStart.RedirectStandardError = $true
            $uiStart.WorkingDirectory = $layout
            $uiStart.Environment['LOCALAPPDATA'] = $caseProfile
            $uiChild = [Diagnostics.Process]::new()
            $uiChild.StartInfo = $uiStart
            if (-not $uiChild.Start()) { throw 'Normal UI control start failed.' }
            $uiStarted = $true
            $uiHeldHandle = $uiChild.Handle
            $uiOutput = $uiChild.StandardOutput.ReadToEndAsync()
            $uiErrors = $uiChild.StandardError.ReadToEndAsync()
            # An owner without an authenticated client times out at30s. Both
            # retained normal processes must still be alive beyond that bound.
            if ($child.WaitForExit(35000) -or $uiChild.HasExited) { throw 'Normal UI did not retain a live authenticated owner.' }
            Close-NativeFixtureChild $uiChild $uiStarted
            $uiChild = $null
            $uiStarted = $false
            [IO.File]::WriteAllText((Join-Path $caseRoot 'ui.stdout.txt'), $uiOutput.GetAwaiter().GetResult(), [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText((Join-Path $caseRoot 'ui.stderr.txt'), $uiErrors.GetAwaiter().GetResult(), [Text.UTF8Encoding]::new($false))
        }
        if (-not $child.WaitForExit(40000)) { throw 'Prerequisite child deadline expired.' }
        $stdout = $output.GetAwaiter().GetResult()
        $stderr = $errors.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $caseRoot 'stdout.txt'), $stdout, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $caseRoot 'stderr.txt'), $stderr, [Text.UTF8Encoding]::new($false))
        if ($stdout.Length -gt 4096 -or $stderr.Length -gt 4096) { throw 'Prerequisite output exceeded bound.' }
        if ((Get-FileHash -LiteralPath $marker -Algorithm SHA256).Hash -ne $markerHash) { throw 'Prerequisite preserved file changed.' }
        if ($case -eq 'healthy-owner') {
            if ($child.ExitCode -ne 0 -or $stderr.Trim() -or $stdout.Trim() -ne 'IsarCore using libmdbx: v0.13.8-temp-upstream-fix') { throw 'Healthy normal owner failed.' }
            $workspace = Join-Path $caseProfile 'ServerDeckNext/v1/workspaces/default'
            foreach ($name in @('workspace.manifest.json','receipt-key.dpapi','workspace.isar','workspace.isar-lck')) {
                if (-not (Test-Path -LiteralPath (Join-Path $workspace $name) -PathType Leaf)) { throw 'Healthy normal workspace incomplete.' }
            }
        } else {
            $expected = if ($case -in @('missing-dll','invalid-dll')) { 'PREREQUISITE_UNAVAILABLE' } else { 'INCOMPATIBLE' }
            if ($child.ExitCode -ne 1 -or $stdout.Trim() -or $stderr.Trim() -ne $expected -or $watch.Elapsed.TotalSeconds -ge 30) { throw "Normal prerequisite refusal failed: $case" }
            if (Test-Path -LiteralPath (Join-Path $caseProfile 'ServerDeckNext')) { throw 'Refused prerequisite created private namespace.' }
            $entries = @(Get-ChildItem -LiteralPath $caseProfile -Force)
            if ($entries.Count -ne 1 -or $entries[0].Name -ne 'preserved.marker') { throw 'Refused prerequisite modified profile inventory.' }
        }
        $completed += @{ name=$case; exitCode=$child.ExitCode; elapsedSeconds=[Math]::Round($watch.Elapsed.TotalSeconds, 1); preserved=$true }
        Write-Output "PASS normal-prerequisite-$case"
    } finally {
        try { if ($null -ne $uiChild) { Close-NativeFixtureChild $uiChild $uiStarted } }
        finally { Close-NativeFixtureChild $child $started }
    }
}
$proof = @{ format=1; scenario='normal-prerequisites'; fullAcceptance=$false; cases=$completed; excluded=@('missing-VC-runtime','other-platform','foreign-user','full-Q04') }
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'accepted.json'), ($proof | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
Write-Output 'NORMAL_PREREQUISITES_ACCEPTED'
# Retain only ignored synthetic evidence; no cleanup, upload or privilege change.
