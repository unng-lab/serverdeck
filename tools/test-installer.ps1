param([string]$Installer, [string]$Compiler = 'wix')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
if (-not $Installer) { $Installer = Get-ChildItem (Join-Path $repo 'output\dist') -Filter '*windows-x64.msi' | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName }
if (-not $Installer) { throw 'Build a Windows MSI first.' }
$uninstallRoots = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall')
$installed = @(Get-ChildItem $uninstallRoots -ErrorAction SilentlyContinue | Get-ItemProperty | Where-Object DisplayName -EQ 'ServerDeck')
if ($installed.Count) { throw 'A user installation exists; run smoke in a clean account to avoid modifying it.' }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('serverdeck-installer-' + [guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $testRoot 'app'
$dataRoot = Join-Path $testRoot 'data'
$productCode = $null
New-Item -ItemType Directory $dataRoot -Force | Out-Null
Set-Content -LiteralPath (Join-Path $dataRoot 'preserved.fixture') 'isolated profile sentinel'
function Invoke-Installer([string[]]$Arguments) {
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $Arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) { throw "Windows Installer failed: $($process.ExitCode)" }
}
try {
    $olderSource = Join-Path $testRoot 'older-fixture.wxs'
    $olderInstaller = Join-Path $testRoot 'older-fixture.msi'
    python (Join-Path $PSScriptRoot 'windows_installer.py') --bundle (Join-Path $repo 'build\windows\x64\runner\Release') --output $olderSource --test-version '0.0.0+0'
    if ($LASTEXITCODE -ne 0) { throw 'Older fixture source failed' }
    & $Compiler build -arch x64 -pdbtype none -o $olderInstaller $olderSource
    if ($LASTEXITCODE -ne 0) { throw 'Older fixture compilation failed' }
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $selected = if ($attempt -eq 0) { $olderInstaller } else { $Installer }
        $arguments = @('/i', "`"$selected`"", '/qn', '/norestart', "INSTALLFOLDER=`"$installRoot`"", '/L*v', "`"$(Join-Path $testRoot "install-$attempt.log")`"")
        if ($attempt -eq 2) { $arguments += @('REINSTALL=ALL', 'REINSTALLMODE=vomus') }
        Invoke-Installer $arguments
        $entry = Get-ChildItem $uninstallRoots -ErrorAction SilentlyContinue | Get-ItemProperty | Where-Object DisplayName -EQ 'ServerDeck' | Select-Object -First 1
        if (-not $entry) { throw 'User uninstall registration missing' }
        $productCode = $entry.PSChildName
        foreach ($file in @('serverdeck.exe', 'serverdeck_locald.exe', 'libisar.dll', 'flutter_windows.dll', 'vcruntime140.dll', 'msvcp140.dll', 'data\flutter_assets')) {
            if (-not (Test-Path -LiteralPath (Join-Path $installRoot $file))) { throw "Missing installed file: $file" }
        }
    $helper = Start-Process -FilePath (Join-Path $installRoot 'serverdeck_locald.exe') -ArgumentList @('--data-dir', "`"$dataRoot`"") -WindowStyle Hidden -PassThru
    try {
        $endpointPath = Join-Path $dataRoot 'endpoint.json'
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        while (-not (Test-Path -LiteralPath $endpointPath) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
        if (-not (Test-Path -LiteralPath $endpointPath)) { throw 'Installed locald startup failed' }
        $endpoint = Get-Content -LiteralPath $endpointPath -Raw | ConvertFrom-Json
        $headers = @{ Authorization = "Bearer $($endpoint.proof)" }
        $base = "http://127.0.0.1:$($endpoint.port)/v1"
        $health = Invoke-RestMethod -Method Post -Uri "$base/health" -Headers $headers -ContentType 'application/json' -Body '{}'
        if ($health.data.service -ne 'serverdeck') { throw 'Invalid helper response' }
        if ($attempt -eq 0) {
            Invoke-RestMethod -Method Post -Uri "$base/settings/set" -Headers $headers -ContentType 'application/json' -Body '{"theme":"light","updateAutoCheck":false}' | Out-Null
        } else {
            $settings = Invoke-RestMethod -Method Post -Uri "$base/settings/get" -Headers $headers -ContentType 'application/json' -Body '{}'
            if ($settings.data.theme -ne 'light' -or $settings.data.updateAutoCheck -ne $false) { throw 'Upgrade/repair did not preserve settings' }
        }
        Invoke-RestMethod -Method Post -Uri "$base/service/stop" -Headers $headers -ContentType 'application/json' -Body '{}' | Out-Null
        if (-not $helper.WaitForExit(10000)) { throw 'Graceful helper stop failed' }
    } finally {
        if (-not $helper.HasExited) { Stop-Process -Id $helper.Id -Force }
    }
    }
    Invoke-Installer @('/x', $productCode, '/qn', '/norestart', '/L*v', "`"$(Join-Path $testRoot 'uninstall.log')`"")
    $productCode = $null
    if (-not (Test-Path -LiteralPath (Join-Path $dataRoot 'preserved.fixture')) -or -not (Test-Path -LiteralPath (Join-Path $dataRoot 'database\serverdeck.isar'))) { throw 'Data preservation failed' }
    Write-Output 'PASS: isolated older-version MSI upgrade/repair, bundled locald/storage, graceful stop, uninstall/data preservation.'
} finally {
    if ($productCode) { Invoke-Installer @('/x', $productCode, '/qn', '/norestart') }
    Write-Output "Smoke evidence: $testRoot"
}
