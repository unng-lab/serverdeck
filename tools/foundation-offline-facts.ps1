function Test-FoundationOfflinePolicy {
    param([object[]]$Profiles,[int]$EnabledOutboundAllowRuleCount,[string]$BfeStatus,[string]$FirewallStatus)
    if ($Profiles.Count -ne 3 -or $EnabledOutboundAllowRuleCount -ne 0 -or
        $BfeStatus -cne 'Running' -or $FirewallStatus -cne 'Running') { return $false }
    if (Compare-Object @('Domain','Private','Public') @($Profiles.Name | Sort-Object -Unique)) { return $false }
    foreach($profile in $Profiles) {
        if ([string]$profile.Enabled -cne 'True' -or [string]$profile.DefaultOutboundAction -cne 'Block') { return $false }
        if (@($profile.DisabledInterfaceAliases | Where-Object { $_ -and $_ -cne 'NotConfigured' }).Count) { return $false }
    }
    return $true
}

function Get-FoundationOfflineFacts {
    # Read effective policy only. This tool never changes host networking.
    $profiles=@(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop | Sort-Object Name | ForEach-Object {
        [ordered]@{Name=$_.Name;Enabled=[string]$_.Enabled;DefaultOutboundAction=[string]$_.DefaultOutboundAction;DisabledInterfaceAliases=@($_.DisabledInterfaceAliases)}
    })
    $allows=0
    foreach($rule in Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop) {
        $enabled=[string]$rule.Enabled
        $direction=[string]$rule.Direction
        $action=[string]$rule.Action
        if ($enabled -cnotin @('True','False') -or $direction -cnotin @('Inbound','Outbound') -or $action -cnotin @('Allow','Block')) {
            throw 'Effective firewall rule state is unknown; runtime offline is unproven.'
        }
        if ($enabled -ceq 'True' -and $direction -ceq 'Outbound' -and $action -ceq 'Allow') { $allows++ }
    }
    $bfe=[string](Get-Service BFE -ErrorAction Stop).Status
    $firewall=[string](Get-Service MpsSvc -ErrorAction Stop).Status
    $blocked=Test-FoundationOfflinePolicy -Profiles $profiles -EnabledOutboundAllowRuleCount $allows -BfeStatus $bfe -FirewallStatus $firewall
    return [ordered]@{schemaVersion=1;status=$(if($blocked){'blocked-policy-observed'}else{'unproven'});profiles=$profiles;enabledOutboundAllowRuleCount=$allows;bfeStatus=$bfe;firewallStatus=$firewall;fullAcceptance=$false}
}
