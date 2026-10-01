# Modules\06-Security.ps1
# Category: Security
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'SEC-01' -Category 'Security' -Name 'Security health check' -Description 'Firewall, AV, UAC, RDP, SMBv1, BitLocker, TPM, updates...' -Action {
    Show-Audit (Get-SecurityAudit)
}

Add-Tool -Id 'SEC-02' -Category 'Security' -Name 'Defender status and threats' -Description 'Protection state, signature age, recent detections' -Action {
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if ($mp.AMRunningMode -ne 'Normal') { throw "Defender is in '$($mp.AMRunningMode)' mode" }
        $mp | Select-Object AMRunningMode, AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, IsTamperProtected,
            AntivirusSignatureLastUpdated, AntivirusSignatureAge, QuickScanEndTime, FullScanEndTime | Format-List | Out-Host
        Write-Section 'Recent detections'
        $t = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Sort-Object InitialDetectionTime -Descending | Select-Object -First 10)
        if ($t.Count) { $t | Select-Object InitialDetectionTime, ThreatID, ActionSuccess, @{n = 'Resources'; e = { $_.Resources -join '; ' } } | Format-Table -AutoSize -Wrap | Out-Host }
        else { Write-Ok 'No threats detected.' }
    } catch {
        Write-Warn 'Microsoft Defender is not active. Installed antivirus products:'
        Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | Select-Object displayName, timestamp | Format-Table -AutoSize | Out-Host
    }
}

Add-Tool -Id 'SEC-03' -Category 'Security' -Name 'Defender update + quick scan' -Admin -Description 'Update signatures and run a quick scan' -Action {
    Write-Info 'Updating signatures...'
    Update-MpSignature -ErrorAction SilentlyContinue
    Write-Info 'Running quick scan (a few minutes)...'
    Start-MpScan -ScanType QuickScan
    Write-Ok 'Quick scan complete.'
    Get-MpThreat -ErrorAction SilentlyContinue | Select-Object ThreatName, SeverityID, IsActive | Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'SEC-04' -Category 'Security' -Name 'Firewall status' -Description 'Profile status; re-enable if off' -Action {
    $p = Get-NetFirewallProfile
    $p | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction, LogFileName | Format-Table -AutoSize | Out-Host
    if (($p | Where-Object { "$($_.Enabled)" -eq 'False' }) -and (Test-IsAdmin) -and (Confirm-Action 'Enable the firewall on all profiles?')) {
        Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True
        Write-Ok 'Firewall enabled on all profiles.'
    }
}

Add-Tool -Id 'SEC-05' -Category 'Security' -Name 'Local administrators' -Description 'Members of the local Administrators group' -Action {
    try { Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | Select-Object Name, ObjectClass, PrincipalSource | Format-Table -AutoSize | Out-Host }
    catch {
        $group = (New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value.Split('\')[1]
        net localgroup "$group" | Out-Host
    }
}

Add-Tool -Id 'SEC-06' -Category 'Security' -Name 'Failed logon attempts' -Admin -Description 'Event 4625 over the last 24 hours, grouped by account' -Action {
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625; StartTime = (Get-Date).AddDays(-1) } -MaxEvents 1000 -ErrorAction SilentlyContinue)
    if (-not $ev.Count) { Write-Ok 'No failed logons in the last 24 hours.'; return }
    Write-Warn "$($ev.Count) failed logon(s)."
    $ev | ForEach-Object {
        [pscustomobject]@{
            Account     = "$($_.Properties[6].Value)\$($_.Properties[5].Value)"
            LogonType   = $_.Properties[10].Value
            Workstation = $_.Properties[13].Value
            SourceIP    = $_.Properties[19].Value
            Time        = $_.TimeCreated
        }
    } | Group-Object Account, SourceIP | Sort-Object Count -Descending |
        Select-Object Count, @{n = 'Account'; e = { $_.Group[0].Account } }, @{n = 'Source IP'; e = { $_.Group[0].SourceIP } }, @{n = 'Workstation'; e = { $_.Group[0].Workstation } }, @{n = 'Last'; e = { $_.Group[0].Time } } |
        Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'SEC-07' -Category 'Security' -Name 'Startup programs' -Description 'Everything that launches at logon' -Action {
    Get-StartupItems | Format-Table -AutoSize -Wrap | Out-Host
}

Add-Tool -Id 'SEC-08' -Category 'Security' -Name 'Non-Microsoft scheduled tasks' -Description 'Third-party scheduled tasks and what they run' -Action {
    Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } | ForEach-Object {
        [pscustomobject]@{
            Task   = "$($_.TaskPath)$($_.TaskName)"
            State  = $_.State
            Runs   = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() }) -join '; '
        }
    } | Format-Table -AutoSize -Wrap | Out-Host
}

Add-Tool -Id 'SEC-09' -Category 'Security' -Name 'USB storage history' -Description 'USB storage devices ever connected' -Action {
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR' -ErrorAction SilentlyContinue | ForEach-Object {
        Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            [pscustomobject]@{ Device = $p.FriendlyName; Serial = $_.PSChildName }
        }
    } | Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'SEC-10' -Category 'Security' -Name 'Installed certificates expiring' -Description 'Machine/user certs expired or expiring within 30 days' -Action {
    $limit = (Get-Date).AddDays(30)
    Get-ChildItem Cert:\LocalMachine\My, Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
        Select-Object @{n = 'Store'; e = { $_.PSParentPath -replace '.*::' } }, Subject, NotAfter, Thumbprint,
            @{n = 'Status'; e = { if ($_.NotAfter -lt (Get-Date)) { 'EXPIRED' } elseif ($_.NotAfter -lt $limit) { 'Expiring' } else { 'OK' } } } |
        Sort-Object NotAfter | Format-Table -AutoSize -Wrap | Out-Host
}

Add-Tool -Id 'SEC-11' -Category 'Security' -Name 'Browser extensions' -Description 'Extensions installed in Chrome, Edge, Brave and Firefox' -Action {
    $rows = New-Object System.Collections.Generic.List[object]
    $chromium = [ordered]@{
        Chrome = "$env:LOCALAPPDATA\Google\Chrome\User Data"
        Edge   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        Brave  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
    }
    foreach ($browser in $chromium.Keys) {
        if (-not (Test-Path $chromium[$browser])) { continue }
        foreach ($prof in Get-ChildItem $chromium[$browser] -Directory | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }) {
            foreach ($ext in Get-ChildItem (Join-Path $prof.FullName 'Extensions') -Directory -ErrorAction SilentlyContinue) {
                $verDir = Get-ChildItem $ext.FullName -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
                if (-not $verDir) { continue }
                try { $m = Get-Content (Join-Path $verDir.FullName 'manifest.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch { continue }
                $name = "$($m.name)"
                # Localised names look like __MSG_appName__ - look them up in _locales
                if ($name -match '^__MSG_(.+)__$') {
                    $key = $Matches[1]
                    foreach ($loc in @($m.default_locale, 'en', 'en_US') | Where-Object { $_ }) {
                        $msgFile = Join-Path $verDir.FullName "_locales\$loc\messages.json"
                        if (-not (Test-Path $msgFile)) { continue }
                        try {
                            $prop = (Get-Content $msgFile -Raw | ConvertFrom-Json).PSObject.Properties | Where-Object Name -eq $key | Select-Object -First 1
                            if ($prop) { $name = $prop.Value.message; break }
                        } catch { }
                    }
                }
                $rows.Add([pscustomobject]@{ Browser = $browser; Profile = $prof.Name; Extension = $name; Version = $m.version; Id = $ext.Name })
            }
        }
    }
    foreach ($prof in Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue) {
        $f = Join-Path $prof.FullName 'extensions.json'
        if (-not (Test-Path $f)) { continue }
        try { $j = Get-Content $f -Raw | ConvertFrom-Json } catch { continue }
        foreach ($a in @($j.addons | Where-Object { $_.location -eq 'app-profile' })) {
            $label = "$($a.defaultLocale.name)"
            if (-not $a.active) { $label += ' (disabled)' }
            $rows.Add([pscustomobject]@{ Browser = 'Firefox'; Profile = $prof.Name; Extension = $label; Version = $a.version; Id = $a.id })
        }
    }
    if ($rows.Count) {
        $rows | Sort-Object Browser, Profile, Extension | Format-Table -AutoSize | Out-Host
        Write-Info 'Remove anything the user does not recognise - unwanted extensions often cause pop-ups, redirects and data theft.'
    } else { Write-Ok 'No browser extensions found.' }
}

Add-Tool -Id 'SEC-12' -Category 'Security' -Name 'Remote access software check' -Description 'Find TeamViewer, AnyDesk, ScreenConnect etc. (tech-support scam check)' -Action {
    $names = 'TeamViewer', 'AnyDesk', 'ScreenConnect', 'ConnectWise Control', 'Splashtop', 'LogMeIn', 'GoTo Resolve', 'GoToAssist', 'RustDesk',
             'UltraViewer', 'Chrome Remote Desktop', 'RealVNC', 'TightVNC', 'UltraVNC', 'TigerVNC', 'Zoho Assist', 'Supremo', 'Ammyy',
             'Remote Utilities', 'RemotePC', 'BeyondTrust', 'Bomgar', 'DWService', 'AweSun', 'ToDesk', 'HopToDesk', 'Parsec', 'NinjaRemote',
             'Atera', 'Kaseya', 'Action1', 'SimpleHelp', 'Getscreen', 'FixMe.IT', 'ISL Online', 'Radmin', 'NetSupport'
    $procs = 'TeamViewer*', 'AnyDesk*', 'ScreenConnect*', 'Splashtop*', 'SRService', 'SRManager', 'LogMeIn*', 'LMIGuardian*', 'GoTo*', 'rustdesk*',
             'UltraViewer*', 'remoting_host', 'vncserver*', 'winvnc*', 'tvnserver*', 'ZA_Connect*', 'Supremo*', 'AA_v3*', 'rutserv*', 'rfusclient*',
             'dwagent*', 'AweSun*', 'ToDesk*', 'HopToDesk*', 'parsecd*', 'AteraAgent*', 'action1*', 'client32', 'ISLLight*', 'rserver3*', 'Remote Utilities*'
    $found = New-Object System.Collections.Generic.List[object]
    foreach ($app in Get-InstalledSoftware -Raw) {
        foreach ($n in $names) {
            if ($app.DisplayName -like "*$n*") { $found.Add([pscustomobject]@{ Found = 'Installed'; Name = $app.DisplayName; Detail = "$($app.Publisher) $($app.DisplayVersion)".Trim() }); break }
        }
    }
    foreach ($svc in Get-CimInstance Win32_Service) {
        foreach ($n in $names) {
            if ($svc.DisplayName -like "*$n*") { $found.Add([pscustomobject]@{ Found = 'Service'; Name = $svc.DisplayName; Detail = "$($svc.State), start: $($svc.StartMode)" }); break }
        }
    }
    foreach ($p in Get-Process) {
        foreach ($n in $procs) {
            if ($p.ProcessName -like $n) { $found.Add([pscustomobject]@{ Found = 'Running now'; Name = $p.ProcessName; Detail = "PID $($p.Id)  $($p.Path)" }); break }
        }
    }
    if (-not $found.Count) { Write-Ok 'No third-party remote access software found (Windows Quick Assist is built in and not listed).'; return }
    Write-Warn "$($found.Count) remote access item(s) found:"
    $found | Sort-Object Found, Name | Format-Table -AutoSize -Wrap | Out-Host
    Write-Info 'Your own IT tools may be listed. If the user did not ask for any of these - especially after a "support" call - remove them, run SEC-03 and change their passwords.'
}

Add-Tool -Id 'SEC-13' -Category 'Security' -Name 'Defender exclusions' -Admin -Description 'Paths, processes and file types excluded from scanning (malware adds these)' -Action {
    try { $pref = Get-MpPreference -ErrorAction Stop } catch { Write-Err 'Microsoft Defender is not available on this PC.'; return }
    $rows = foreach ($kind in 'ExclusionPath', 'ExclusionProcess', 'ExclusionExtension', 'ExclusionIpAddress') {
        foreach ($v in @($pref.$kind)) {
            if ($v -and "$v" -notlike 'N/A*') { [pscustomobject]@{ Type = $kind -replace '^Exclusion', ''; Value = $v } }
        }
    }
    if ($rows) { Write-Warn 'Exclusions found - make sure each one is expected:'; $rows | Format-Table -AutoSize | Out-Host }
    else { Write-Ok 'No Defender exclusions configured.' }
}

Add-Tool -Id 'SEC-14' -Category 'Security' -Name 'Suspend / resume BitLocker' -Admin -Description 'Suspend for one restart before BIOS or firmware updates' -Action {
    $drive = $env:SystemDrive
    if (-not (Get-Command Suspend-BitLocker -ErrorAction SilentlyContinue)) { Write-Warn 'BitLocker cmdlets are not available on this edition.'; manage-bde -status $drive | Out-Host; return }
    $v = Get-BitLockerVolume -MountPoint $drive
    Write-Info "$drive  Status: $($v.VolumeStatus)   Protection: $($v.ProtectionStatus)"
    if ("$($v.VolumeStatus)" -eq 'FullyDecrypted') { Write-Info 'This drive is not encrypted - nothing to do.'; return }
    Write-Host '  [1] Suspend until after the next restart (before a BIOS/firmware update)'
    Write-Host '  [2] Resume protection now'
    $c = Read-Host '  Choice'
    if ($c -eq '1' -and (Confirm-Action "Suspend BitLocker on $drive for one restart?")) {
        Suspend-BitLocker -MountPoint $drive -RebootCount 1 | Out-Null
        Write-Ok 'Suspended - protection resumes automatically after the next restart.'
    } elseif ($c -eq '2') {
        Resume-BitLocker -MountPoint $drive | Out-Null
        Write-Ok 'Protection resumed.'
    }
}

Add-Tool -Id 'SEC-15' -Category 'Security' -Name 'Password and lockout policy' -Description 'Local password age/length rules and account lockout settings' -Action {
    net accounts | Out-Host
    if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) { Write-Info 'This PC is domain-joined: domain accounts follow the domain policy. Use USR-06 to check a specific user.' }
}

Add-Tool -Id 'SEC-16' -Category 'Security' -Name 'Defender and hardening details' -Description 'Defender protection features, Memory Integrity, Credential Guard, LSA protection, licence' -Action {
    Write-Section 'Microsoft Defender'
    $defenderActive = $false
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if ($mp.AMRunningMode -ne 'Normal') {
            # Defender switches itself off when another antivirus is registered - that is expected, not a failure
            $other = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | Where-Object displayName -notlike '*Defender*' | ForEach-Object displayName | Select-Object -Unique)
            Write-Check $(if ($other.Count) { 'OK' } else { 'WARN' }) 'Defender mode' "$($mp.AMRunningMode)$(if ($other.Count) { " - protection provided by $($other -join ', ')" })"
            throw 'passive'
        }
        $defenderActive = $true
        $flag = { param($label, $on, $bad = 'WARN') Write-Check $(if ($on) { 'OK' } else { $bad }) $label $(if ($on) { 'On' } else { 'Off' }) }
        & $flag 'Antivirus' $mp.AntivirusEnabled 'FAIL'
        & $flag 'Real-time protection' $mp.RealTimeProtectionEnabled 'FAIL'
        & $flag 'Behavior monitoring' $mp.BehaviorMonitorEnabled
        & $flag 'Scan downloads (IOAV)' $mp.IoavProtectionEnabled
        & $flag 'Antispyware' $mp.AntispywareEnabled
        & $flag 'Tamper protection' $mp.IsTamperProtected
        Write-Check 'INFO' 'Signatures' "$($mp.AntivirusSignatureVersion), updated $($mp.AntivirusSignatureLastUpdated)"
    } catch { if ("$_" -ne 'passive') { Write-Check 'INFO' 'Defender' 'Not available (third-party antivirus or Defender removed)' } }
    if ($defenderActive) { try {
        $pref = Get-MpPreference -ErrorAction Stop
        Write-Check $(if ($pref.MAPSReporting -ne 0) { 'OK' } else { 'WARN' }) 'Cloud protection' $(if ($pref.MAPSReporting -ne 0) { 'On' } else { 'Off' })
        Write-Check $(if ($pref.PUAProtection -eq 1) { 'OK' } else { 'WARN' }) 'Block unwanted apps (PUA)' $(switch ($pref.PUAProtection) { 1 { 'On' } 2 { 'Audit only' } default { 'Off' } })
    } catch { } }

    Write-Section 'Windows hardening'
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    if ($dg) {
        Write-Check $(if ($dg.SecurityServicesRunning -contains 2) { 'OK' } else { 'INFO' }) 'Memory Integrity (HVCI)' $(if ($dg.SecurityServicesRunning -contains 2) { 'Running' } else { 'Off' })
        Write-Check $(if ($dg.SecurityServicesRunning -contains 1) { 'OK' } else { 'INFO' }) 'Credential Guard' $(if ($dg.SecurityServicesRunning -contains 1) { 'Running' } else { 'Off' })
    } else { Write-Check 'INFO' 'Device Guard' 'Unavailable' }
    $ppl = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -ErrorAction SilentlyContinue).RunAsPPL
    Write-Check $(if ($ppl -in 1, 2) { 'OK' } else { 'INFO' }) 'LSA protection' $(if ($ppl -in 1, 2) { 'On' } else { 'Off' })
    foreach ($s in @(@('wscsvc', 'Security Center'), @('WinRM', 'WinRM (remote management)'))) {
        $svc = Get-Service $s[0] -ErrorAction SilentlyContinue
        if ($svc) { Write-Check $(if ($s[0] -eq 'wscsvc' -and $svc.Status -ne 'Running') { 'WARN' } else { 'INFO' }) $s[1] "$($svc.Status)" }
    }
    $lic = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($lic) { Write-Check $(if ($lic.LicenseStatus -eq 1) { 'OK' } else { 'WARN' }) 'Windows licence' $(if ($lic.LicenseStatus -eq 1) { 'Activated' } else { "Not activated (status $($lic.LicenseStatus))" }) }
    Write-Check 'INFO' 'PowerShell policy (machine)' "$(Get-ExecutionPolicy -Scope LocalMachine)"
    $hosts = Get-Item "$env:SystemRoot\System32\drivers\etc\hosts" -ErrorAction SilentlyContinue
    if ($hosts) { Write-Check 'INFO' 'Hosts file last changed' "$($hosts.LastWriteTime) (NET-14 shows entries)" }
}

# Startup entries with their Task Manager enabled/disabled state (StartupApproved keys)
function Get-StartupEntries {
    $cv = 'Software\Microsoft\Windows\CurrentVersion'
    $runs = @(
        @{ Scope = 'Current user';       Key = "HKCU:\$cv\Run";                                Approved = "HKCU:\$cv\Explorer\StartupApproved\Run";   Machine = $false },
        @{ Scope = 'All users';          Key = "HKLM:\$cv\Run";                                Approved = "HKLM:\$cv\Explorer\StartupApproved\Run";   Machine = $true },
        @{ Scope = 'All users (32-bit)'; Key = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Approved = "HKLM:\$cv\Explorer\StartupApproved\Run32"; Machine = $true }
    )
    $state = {
        param($approvedKey, $name)
        $v = (Get-ItemProperty -Path $approvedKey -Name $name -ErrorAction SilentlyContinue).$name
        # first byte: even = enabled (02/06), odd = disabled (03/07); no value = enabled
        if ($v -and ($v[0] % 2) -eq 1) { 'Disabled' } else { 'Enabled' }
    }
    foreach ($r in $runs) {
        $props = Get-ItemProperty -Path $r.Key -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' -and $_.Name -ne '(default)' }) {
            [pscustomobject]@{ Name = $p.Name; Command = "$($p.Value)"; Scope = $r.Scope; Source = 'Registry'; Approved = $r.Approved; Machine = $r.Machine; State = & $state $r.Approved $p.Name }
        }
    }
    $folders = @(
        @{ Scope = 'Current user'; Path = [Environment]::GetFolderPath('Startup'); Approved = "HKCU:\$cv\Explorer\StartupApproved\StartupFolder"; Machine = $false },
        @{ Scope = 'All users'; Path = [Environment]::GetFolderPath('CommonStartup'); Approved = "HKLM:\$cv\Explorer\StartupApproved\StartupFolder"; Machine = $true }
    )
    foreach ($f in $folders) {
        Get-ChildItem -LiteralPath $f.Path -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini' | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; Command = $_.FullName; Scope = $f.Scope; Source = 'Startup folder'; Approved = $f.Approved; Machine = $f.Machine; State = & $state $f.Approved $_.Name }
        }
    }
}

Add-Tool -Id 'SEC-17' -Category 'Security' -Name 'Startup program manager' -Description 'Disable or re-enable startup programs (same switch as Task Manager, nothing deleted)' -Action {
    $entries = @(Get-StartupEntries | Sort-Object State, Name)
    if (-not $entries.Count) { Write-Info 'No startup programs found in the Run keys or Startup folders.'; return }
    $entries | Select-Object State, Name, Scope, Source, Command | Format-Table -AutoSize -Wrap | Out-Host
    Write-Host '  [1] Disable a startup program   [2] Re-enable a startup program'
    $c = Read-Host '  Choice (blank to cancel)'
    $want = switch ($c) { '1' { 'Enabled' } '2' { 'Disabled' } default { $null } }
    if (-not $want) { return }
    $e = Select-FromList @($entries | Where-Object State -eq $want) { '{0,-40} {1}' -f $_.Name, $_.Scope } $(if ($want -eq 'Enabled') { 'Program to disable' } else { 'Program to re-enable' })
    if (-not $e) { return }
    if ($e.Machine -and -not (Test-IsAdmin)) { Write-Warn 'This entry applies to all users - restart the toolkit as Administrator to change it.'; return }
    $enable = ($want -eq 'Disabled')
    if (-not (Confirm-Action "$(if ($enable) { 'Re-enable' } else { 'Disable' }) '$($e.Name)' at startup?")) { return }
    if (-not (Test-Path $e.Approved)) { New-Item -Path $e.Approved -Force | Out-Null }
    $bytes = New-Object byte[] 12
    if ($enable) { $bytes[0] = 2 } else { $bytes[0] = 3; [BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc()).CopyTo($bytes, 4) }
    New-ItemProperty -Path $e.Approved -Name $e.Name -PropertyType Binary -Value $bytes -Force | Out-Null
    Write-Ok "'$($e.Name)' will $(if ($enable) { 'start' } else { 'no longer start' }) at sign-in. This also shows in Task Manager > Startup apps."
    Write-Log "Startup item '$($e.Name)' $(if ($enable) { 'enabled' } else { 'disabled' })"
}

Add-Tool -Id 'SEC-15' -Category 'Security' -Name 'BitLocker status' -Admin -Description 'Encryption status for all volumes and recovery key management' -Action {
    Write-Section 'BitLocker Encryption Status'

    try {
        $volumes = Get-BitLockerVolume -ErrorAction SilentlyContinue
        if (-not $volumes) {
            Write-Info 'No volumes found or BitLocker not available'
            return
        }

        $volumes | ForEach-Object {
            $encStatus = $_.VolumeStatus
            $protStatus = $_.ProtectionStatus
            $encMethod = $_.EncryptionMethod

            $statusColor = if ($protStatus -eq 'On') { 'OK' } elseif ($protStatus -eq 'Off') { 'WARN' } else { 'INFO' }

            Write-Check $statusColor 'Volume' "$($_.MountPoint)"
            Write-Check 'INFO' 'Status' "$encStatus - Protection: $protStatus"
            Write-Check 'INFO' 'Method' $encMethod
            Write-Check 'INFO' 'Recovery Password' $(if ($_.KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword') { 'Protected' } else { 'Not Protected' })
            Write-Check 'INFO' 'TPM Protection' $(if ($_.KeyProtector | Where-Object KeyProtectorType -eq 'Tpm') { 'Yes' } else { 'No' })

            Write-Host ''
        }

        Write-Info 'To save recovery key: manage-bde -protectors -get'
    } catch {
        Write-Err "BitLocker information unavailable: $($_.Exception.Message)"
        Write-Info 'Run as Administrator for full BitLocker details'
    }
}

Add-Tool -Id 'SEC-16' -Category 'Security' -Name 'TPM status' -Description 'Trusted Platform Module presence, version and capabilities' -Action {
    Write-Section 'TPM (Trusted Platform Module) Status'

    try {
        $tpm = Get-WmiObject -Namespace root\cimv2\security\microsofttpm -Class Win32_Tpm -ErrorAction SilentlyContinue
        if (-not $tpm) {
            Write-Warn 'No TPM detected or not accessible'
            Write-Info 'Check BIOS settings - TPM may need to be enabled'
            return
        }

        Write-Check 'OK' 'TPM Present' 'Yes'
        Write-Check 'INFO' 'Manufacturer' $tpm.ManufacturerIdTxt
        Write-Check 'INFO' 'Version' "2.0 (driver reported)"
        Write-Check 'INFO' 'Specification Version' $tpm.SpecVersion

        # Check BitLocker readiness
        $bitlocker = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
        if ($bitlocker) {
            $tpmProtection = if ($bitlocker.KeyProtector | Where-Object KeyProtectorType -eq 'Tpm') { 'Yes' } else { 'No' }
            Write-Check 'INFO' 'TPM used for BitLocker' $tpmProtection
        }
    } catch {
        Write-Warn "TPM query failed: $($_.Exception.Message)"
    }
}

Add-Tool -Id 'SEC-17' -Category 'Security' -Name 'Product key retrieval' -Description 'Windows and Office product keys (requires Administrator)' -Action {
    if (-not (Test-Admin)) {
        Write-Warn 'Administrator privileges required'
        return
    }

    Write-Section 'Product Keys'

    # Windows product key
    Write-Host 'Windows:'
    try {
        $productKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name 'ProductId' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProductId
        if ($productKey) {
            Write-Check 'INFO' 'Product ID' $productKey
        } else {
            Write-Info 'Product ID not available in registry'
        }
    } catch { }

    # Office product keys
    Write-Host 'Office Products:'
    $officeVersions = @(
        'HKLM:\SOFTWARE\Microsoft\Office\16.0',
        'HKLM:\SOFTWARE\Microsoft\Office\15.0',
        'HKLM:\SOFTWARE\Microsoft\Office\14.0'
    )

    foreach ($path in $officeVersions) {
        if (Test-Path $path) {
            Get-ChildItem -Path $path | ForEach-Object {
                $name = $_.PSChildName
                $version = if ($name -like '16.*') { 'Office 2016/2019' } elseif ($name -like '15.*') { 'Office 2013' } else { "Version $name" }
                Write-Check 'INFO' $version $name
            }
        }
    }

    Write-Host ''
    Write-Info 'Note: Keys stored in registry may not be in standard format. For detailed information, use third-party key recovery tools or contact Microsoft Support.'
}
