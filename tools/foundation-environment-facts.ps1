function Get-EnvironmentFacts {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try { $sid=$identity.User.Value } finally { $identity.Dispose() }
    $os=Get-CimInstance Win32_OperatingSystem
    $machine=Get-CimInstance Win32_ComputerSystemProduct
    $profiles=@(Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -ceq $sid -and $_.Loaded })
    if ($os.ProductType -ne 1 -or $os.BuildNumber -notmatch '^\d+$' -or [int]$os.BuildNumber -lt 22000 -or
        -not [Environment]::Is64BitOperatingSystem -or $profiles.Count -ne 1 -or
        $machine.UUID -notmatch '^[a-fA-F0-9-]{36}$' -or $machine.UUID -match '^(0|-)+$') {
        throw 'Loaded ordinary Windows 11 x64 test user and machine identity required.'
    }
    return [ordered]@{sid=$sid;machineUuid=$machine.UUID;bootUtcTicks=$os.LastBootUpTime.ToUniversalTime().Ticks.ToString();build=$os.BuildNumber}
}

