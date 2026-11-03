[CmdletBinding()]
param(
    [switch]$RequireCleanVm,
    [string]$EvidencePath = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$kitRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if (!$EvidencePath) { $EvidencePath = Join-Path $kitRoot 'native-results.json' }
$manifest = Get-Content -Raw -LiteralPath (Join-Path $kitRoot 'manifest.json') | ConvertFrom-Json
$manifestDigest = (Get-FileHash -LiteralPath (Join-Path $kitRoot 'manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
if ($manifest.schemaVersion -ne 1) { throw 'Unsupported verification kit format' }
foreach ($entry in $manifest.files) {
    $path = [IO.Path]::GetFullPath((Join-Path $kitRoot $entry.path))
    if (!$path.StartsWith($kitRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Manifest path escapes the verification kit'
    }
    $walk = $path
    while ($walk -and $walk.Length -ge $kitRoot.Length) {
        if ((Get-Item -Force -LiteralPath $walk).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Reparse points are forbidden in the verification kit'
        }
        $walk = Split-Path -Parent $walk
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) {
        throw "Verification file checksum mismatch: $($entry.path)"
    }
}

$reasons = [Collections.Generic.List[string]]::new()
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($elevated) { $reasons.Add('The test user is elevated') }
$accountName = ($identity.Name -split '\\')[-1]
if ($accountName -notmatch '^ServerDeckSmoke(?:[-_].+)?$') {
    $reasons.Add('Use a dedicated disposable ServerDeckSmoke test account')
}
if (![Environment]::Is64BitOperatingSystem) { $reasons.Add('Windows x64 is required') }
$model = $null
$os = $null
$architectures = @()
try {
    $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $model = "$($computer.Manufacturer) $($computer.Model)"
    if ($model -notmatch 'Virtual Machine|VMware|VirtualBox|KVM|QEMU|Xen|Parallels') {
        $reasons.Add('A disposable virtual machine could not be established')
    }
} catch { $reasons.Add('Cannot read the VM identity') }
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $architectures = @(Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -ExpandProperty Architecture)
    if ($os.ProductType -ne 1 -or ([version]$os.Version).Major -ne 10 -or [int]$os.BuildNumber -lt 10240) {
        $reasons.Add('A Windows 10/11 workstation is required')
    }
    if ($architectures.Count -eq 0 -or @($architectures | Where-Object { $_ -ne 9 }).Count -gt 0) {
        $reasons.Add('The native OS processor architecture must be x64')
    }
} catch { $reasons.Add('Cannot establish the supported Windows edition/architecture') }
try {
    $defaults = @(Get-NetRoute -ErrorAction Stop | Where-Object DestinationPrefix -In @('0.0.0.0/0', '::/0'))
    if ($defaults.Count -gt 0) { $reasons.Add('Disconnect the VM network: a default route exists') }
} catch { $reasons.Add('Cannot establish offline network state') }
$foundTools = @(@('flutter', 'dart', 'python', 'node', 'ssh') | Where-Object {
    $null -ne (Get-Command $_ -ErrorAction SilentlyContinue)
})
if ($foundTools.Count -gt 0) { $reasons.Add('The clean VM contains development/runtime tools or an SSH client') }
$vcFiles = @(@('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') | Where-Object {
    Test-Path -LiteralPath (Join-Path $env:SystemRoot "System32/$_")
})
if ($vcFiles.Count -gt 0) { $reasons.Add('System-wide VC runtime DLLs are present') }
$vsInstaller = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (Test-Path -LiteralPath $vsInstaller) { $reasons.Add('Visual Studio tooling is present') }
$appData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$appRoot = Join-Path $appData 'ServerDeck'
if (Test-Path -LiteralPath $appRoot) { $reasons.Add('The test profile already contains ServerDeck data; reset the VM snapshot') }
$environmentEvidence = [ordered]@{
    computer = $env:COMPUTERNAME; user = $accountName; accountIdentity = $identity.Name
    userSid = $identity.User.Value
    osVersion = if ($null -ne $os) { $os.Version } else { [Environment]::OSVersion.VersionString }
    osCaption = if ($null -ne $os) { $os.Caption } else { $null }
    processorArchitectures = $architectures
    model = $model; elevated = $elevated; x64 = [Environment]::Is64BitOperatingSystem
    foundTools = @($foundTools); systemVcFiles = @($vcFiles)
    cleanVmPrerequisitesSatisfied = ($reasons.Count -eq 0); unmetPrerequisites = @($reasons.ToArray())
}
$report = [ordered]@{
    schemaVersion = 1; timestampUtc = [DateTime]::UtcNow.ToString('o')
    scope = 'native synthetic contract fixtures only; GUI/fault release acceptance is not executed'
    productSHA256 = $manifest.productSHA256; fullVmAcceptance = $false
    verificationManifestSHA256 = $manifestDigest
    environment = $environmentEvidence; results = @(); status = 'notRun'
}
function Save-Report {
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
}
if ($RequireCleanVm -and $reasons.Count -gt 0) {
    $report.status = 'blockedByVmPrerequisites'
    Save-Report
    Write-Output ($reasons -join '; ')
    exit 2
}
foreach ($fixture in $manifest.nativeFixtures) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $kitRoot $fixture
    if ($fixture -in @('verification/release_observer.exe', 'verification/release_lifecycle.exe')) {
        $start.Arguments = '--self-test'
    }
    $start.WorkingDirectory = $kitRoot
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $timedOut = !$process.WaitForExit(15000)
    if ($timedOut) { $process.Kill(); $process.WaitForExit() }
    $item = [ordered]@{
        fixture = $fixture; timedOut = $timedOut; exitCode = $process.ExitCode
        sha256 = ($manifest.files | Where-Object path -EQ $fixture).sha256
        stdout = $stdout.Result; stderr = $stderr.Result
        passed = (!$timedOut -and $process.ExitCode -eq 0)
    }
    $process.Dispose()
    $report.results += $item
    Save-Report
}
$failed = @($report.results | Where-Object { !$_.passed })
$report.status = if ($failed.Count -eq 0) { 'nativeContractsPassed' } else { 'nativeContractsFailed' }
Save-Report
Write-Output "$($report.results.Count) native fixtures executed; full GUI/VM acceptance remains open."
if ($failed.Count -gt 0) { exit 1 }
exit 0
