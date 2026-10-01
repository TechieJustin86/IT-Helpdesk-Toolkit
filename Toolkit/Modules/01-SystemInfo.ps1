# Modules\01-SystemInfo.ps1
# Category: System Information
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'SYS-01' -Category 'System Information' -Name 'System summary' -Description 'OS, model, serial, uptime, CPU and RAM at a glance' -Action {
    Get-SystemSummary | Format-List | Out-Host
}

Add-Tool -Id 'SYS-02' -Category 'System Information' -Name 'Hardware inventory' -Description 'CPU, memory modules, disks, GPU and monitors' -Action {
    Write-Section 'Processor'
    Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, @{n = 'Max MHz'; e = { $_.MaxClockSpeed } } | Format-Table -AutoSize | Out-Host

    Write-Section 'Memory modules'
    Get-CimInstance Win32_PhysicalMemory | Select-Object BankLabel, DeviceLocator, @{n = 'Capacity'; e = { Format-Bytes $_.Capacity } }, Speed, Manufacturer, PartNumber | Format-Table -AutoSize | Out-Host

    Write-Section 'Physical disks'
    Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object FriendlyName, MediaType, BusType, @{n = 'Size'; e = { Format-Bytes $_.Size } }, HealthStatus | Format-Table -AutoSize | Out-Host

    Write-Section 'Graphics'
    Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, @{n = 'Resolution'; e = { "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)" } } | Format-Table -AutoSize | Out-Host

    Write-Section 'Monitors'
    $mons = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue
    if ($mons) {
        $decode = { param($a) if ($a) { (($a | Where-Object { $_ -ne 0 }) | ForEach-Object { [char]$_ }) -join '' } }
        $mons | ForEach-Object {
            [pscustomobject]@{
                Manufacturer = & $decode $_.ManufacturerName
                Model        = & $decode $_.UserFriendlyName
                Serial       = & $decode $_.SerialNumberID
                Year         = $_.YearOfManufacture
            }
        } | Format-Table -AutoSize | Out-Host
    } else { Write-Info 'No monitor information available.' }
}

Add-Tool -Id 'SYS-03' -Category 'System Information' -Name 'Windows activation status' -Description 'License status, edition and embedded OEM key' -Action {
    $status = @{ 0 = 'Unlicensed'; 1 = 'Licensed'; 2 = 'Out-of-box grace'; 3 = 'Out-of-tolerance grace'; 4 = 'Non-genuine grace'; 5 = 'Notification'; 6 = 'Extended grace' }
    $lic = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue
    foreach ($l in $lic) {
        [pscustomobject]@{
            Product       = $l.Name
            Channel       = $l.ProductKeyChannel
            'Partial key' = $l.PartialProductKey
            Status        = $status[[int]$l.LicenseStatus]
        } | Format-List | Out-Host
    }
    $oem = (Get-CimInstance SoftwareLicensingService -ErrorAction SilentlyContinue).OA3xOriginalProductKey
    if ($oem) { Write-Info "OEM key embedded in firmware: $oem" } else { Write-Info 'No OEM key embedded in firmware.' }
}

Add-Tool -Id 'SYS-04' -Category 'System Information' -Name 'BitLocker status' -Admin -Description 'Encryption status of all volumes, optional recovery key' -Action {
    if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
        Write-Warn 'BitLocker cmdlets not available on this edition. Falling back to manage-bde.'
        manage-bde -status | Out-Host
        return
    }
    $vols = Get-BitLockerVolume
    $vols | Select-Object MountPoint, VolumeType, VolumeStatus, ProtectionStatus, EncryptionPercentage, EncryptionMethod | Format-Table -AutoSize | Out-Host
    if (Confirm-Action 'Show recovery keys?') {
        foreach ($v in $vols) {
            $keys = $v.KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword'
            foreach ($k in $keys) { Write-Host ("  {0}  ID {1}  Key {2}" -f $v.MountPoint, $k.KeyProtectorId, $k.RecoveryPassword) -ForegroundColor Yellow }
        }
    }
}

Add-Tool -Id 'SYS-05' -Category 'System Information' -Name 'Battery health report' -Description 'Generate the powercfg battery report (laptops)' -Action {
    if (-not (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)) { Write-Warn 'No battery detected on this device.'; return }
    $file = Get-OutFile 'battery-report.html'
    $null = Invoke-External 'powercfg.exe' "/batteryreport /output `"$file`""
    Open-File $file
}

Add-Tool -Id 'SYS-06' -Category 'System Information' -Name 'Drivers and problem devices' -Description 'Devices with errors plus full driver export' -Action {
    Write-Section 'Devices reporting a problem'
    $bad = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction SilentlyContinue)
    if ($bad.Count) { $bad | Select-Object Name, @{n = 'Code'; e = { $_.ConfigManagerErrorCode } }, @{n = 'Problem'; e = { Get-PnpProblemText $_.ConfigManagerErrorCode } }, PNPClass, DeviceID | Format-Table -AutoSize -Wrap | Out-Host }
    else { Write-Ok 'No problem devices found.' }
    if (Confirm-Action 'Export full driver list to CSV?') {
        Get-CimInstance Win32_PnPSignedDriver | Where-Object DeviceName |
            Select-Object DeviceName, DeviceClass, Manufacturer, DriverVersion, @{n = 'DriverDate'; e = { $_.DriverDate } }, InfName |
            Export-Results -Name 'drivers.csv'
    }
}

Add-Tool -Id 'SYS-07' -Category 'System Information' -Name 'Pending reboot check' -Description 'Checks CBS, Windows Update, file renames, computer rename' -Action {
    $r = @(Get-PendingReboot)
    if ($r.Count) {
        Write-Warn 'A reboot is pending:'
        $r | ForEach-Object { Write-Host "      - $_" -ForegroundColor Yellow }
    } else { Write-Ok 'No reboot pending.' }
}

Add-Tool -Id 'SYS-08' -Category 'System Information' -Name 'Installed updates (hotfixes)' -Description 'Most recent 25 installed Windows updates' -Action {
    Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 25 HotFixID, Description, InstalledOn, InstalledBy | Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'SYS-09' -Category 'System Information' -Name 'Disk space' -Description 'Free space on all local drives with warnings' -Action {
    Get-DiskSpace | Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'SYS-10' -Category 'System Information' -Name 'Environment and PowerShell info' -Description 'PS version, execution policy, PATH, .NET version' -Action {
    $net = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Release
    [pscustomobject]@{
        'PowerShell'        = $PSVersionTable.PSVersion.ToString()
        'Edition'           = $PSVersionTable.PSEdition
        'Execution policy'  = (Get-ExecutionPolicy).ToString()
        '.NET 4.x release'  = $net
        'Temp folder'       = $env:TEMP
        'User profile'      = $env:USERPROFILE
        'Logon server'      = $env:LOGONSERVER
    } | Format-List | Out-Host
    Write-Section 'PATH entries'
    $env:Path -split ';' | Where-Object { $_ } | ForEach-Object {
        $exists = Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($_))
        if ($exists) { Write-Host "    $_" } else { Write-Host "    $_  (missing)" -ForegroundColor Yellow }
    }
}

Add-Tool -Id 'SYS-11' -Category 'System Information' -Name 'Boot performance history' -Admin -Description 'Recent boot times and the apps/drivers slowing startup' -Action {
    $log = 'Microsoft-Windows-Diagnostics-Performance/Operational'
    $getData = { param($e) $d = @{}; foreach ($n in ([xml]$e.ToXml()).Event.EventData.Data) { $d[$n.Name] = $n.'#text' }; $d }
    $boots = @(Get-WinEvent -FilterHashtable @{ LogName = $log; Id = 100 } -MaxEvents 10 -ErrorAction SilentlyContinue)
    if (-not $boots.Count) { Write-Warn 'No boot performance data recorded yet.'; return }
    Write-Section 'Recent boots'
    $boots | ForEach-Object {
        $d = & $getData $_
        [pscustomobject]@{
            Time              = $_.TimeCreated
            'Total (s)'       = [math]::Round([double]$d['BootTime'] / 1000, 1)
            'To desktop (s)'  = [math]::Round([double]$d['MainPathBootTime'] / 1000, 1)
            'After logon (s)' = [math]::Round([double]$d['BootPostBootTime'] / 1000, 1)
        }
    } | Format-Table -AutoSize | Out-Host
    Write-Section 'Items that slowed startup (last 30 days)'
    $slow = @(Get-WinEvent -FilterHashtable @{ LogName = $log; Id = 101..110; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue)
    if ($slow.Count) {
        $slow | ForEach-Object {
            $d = & $getData $_
            $item = if ($d['FriendlyName']) { $d['FriendlyName'] } else { $d['Name'] }
            [pscustomobject]@{ Item = $item; Delay = [int]$d['DegradationTime'] }
        } | Group-Object Item | Sort-Object Count -Descending | Select-Object -First 15 Count, Name,
            @{ n = 'Avg delay (ms)'; e = { [int]($_.Group | Measure-Object Delay -Average).Average } } |
            Format-Table -AutoSize | Out-Host
    } else { Write-Ok 'No startup slowdowns recorded.' }
}

Add-Tool -Id 'SYS-12' -Category 'System Information' -Name 'Warranty / support lookup' -Description 'Copy the serial number and open the manufacturer warranty page' -Action {
    $cs = Get-CimInstance Win32_ComputerSystem
    $serial = "$((Get-CimInstance Win32_BIOS).SerialNumber)".Trim()
    $make = "$($cs.Manufacturer)"
    Write-Info "Manufacturer: $make"
    Write-Info "Model:        $($cs.Model)"
    Write-Info "Serial:       $serial"
    $url = switch -Wildcard ($make) {
        '*Dell*'      { "https://www.dell.com/support/home/product-support/servicetag/$serial/overview"; break }
        '*Lenovo*'    { "https://pcsupport.lenovo.com/products/$serial/warranty"; break }
        '*Hewlett*'   { 'https://support.hp.com/checkwarranty'; break }
        'HP*'         { 'https://support.hp.com/checkwarranty'; break }
        '*Microsoft*' { 'https://mybusinessservice.surface.com/en-US/CheckWarranty/CheckWarranty'; break }
        '*ASUS*'      { 'https://www.asus.com/support/warranty-status-inquiry/'; break }
        '*Acer*'      { 'https://www.acer.com/support/warranty'; break }
        '*Apple*'     { 'https://checkcoverage.apple.com/'; break }
        '*Samsung*'   { 'https://www.samsung.com/us/support/warranty/'; break }
        '*Micro-Star*' { 'https://www.msi.com/support/warranty'; break }
        default       { $null }
    }
    try { Set-Clipboard -Value $serial; Write-Ok 'Serial number copied to the clipboard.' } catch { }
    if (-not $url) { Write-Warn 'No known warranty site for this manufacturer.'; return }
    if (Confirm-Action "Open the $make warranty page?") { Start-Process $url }
}

Add-Tool -Id 'SYS-13' -Category 'System Information' -Name 'Windows optional features' -Admin -Description 'Enabled features: Hyper-V, .NET 3.5, SMB1, WSL, IIS...' -Action {
    Write-Info 'Querying features (a few seconds)...'
    Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object State -eq 'Enabled' | Sort-Object FeatureName |
        Select-Object FeatureName, State | Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'SYS-14' -Category 'System Information' -Name 'Advanced system checks' -Description 'Firmware mode, Secure Boot, TPM, recovery, crash dumps, page file, time, remote access' -Action {
    $admin = Test-IsAdmin
    Write-Section 'Firmware and boot'
    # Windows sets %firmware_type% at boot; the registry value is a fallback
    $fw = switch ("$env:firmware_type") { 'UEFI' { 2 } 'Legacy' { 1 } default { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -ErrorAction SilentlyContinue).PEFirmwareType } }
    Write-Check $(if ($fw -eq 2) { 'OK' } elseif ($fw -eq 1) { 'WARN' } else { 'INFO' }) 'Firmware mode' $(switch ($fw) { 1 { 'Legacy BIOS (Windows 11 needs UEFI)' } 2 { 'UEFI' } default { 'Unknown' } })
    if ($admin) {
        try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop; Write-Check $(if ($sb) { 'OK' } else { 'WARN' }) 'Secure Boot' $(if ($sb) { 'On' } else { 'Off' }) }
        catch { Write-Check 'INFO' 'Secure Boot' 'Not supported' }
        try { $t = Get-Tpm -ErrorAction Stop; Write-Check $(if ($t.TpmReady) { 'OK' } else { 'WARN' }) 'TPM' "Present=$($t.TpmPresent) Ready=$($t.TpmReady) Enabled=$($t.TpmEnabled)" }
        catch { Write-Check 'INFO' 'TPM' 'Unavailable' }
        $re = (reagentc /info 2>$null | Out-String)
        Write-Check $(if ($re -match 'Windows RE status:\s+Enabled') { 'OK' } else { 'WARN' }) 'Windows Recovery (WinRE)' $(if ($re -match 'Windows RE status:\s+Enabled') { 'Enabled' } else { 'Disabled or unavailable' })
    } else {
        Write-Check 'INFO' 'Secure Boot / TPM / WinRE' 'Run as Administrator to check'
    }
    Write-Check 'INFO' 'OS architecture' (Get-CimInstance Win32_OperatingSystem).OSArchitecture

    Write-Section 'Memory, dumps and power'
    $cc = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -ErrorAction SilentlyContinue
    Write-Check $(if ($cc.CrashDumpEnabled -eq 0) { 'WARN' } else { 'INFO' }) 'Crash dump type' $(switch ($cc.CrashDumpEnabled) { 0 { 'Disabled (no dumps for BSOD analysis)' } 1 { 'Complete' } 2 { 'Kernel' } 3 { 'Small (minidump)' } 7 { 'Automatic' } default { 'Unknown' } })
    $dumps = @(Get-ChildItem "$env:SystemRoot\Minidump" -Filter *.dmp -ErrorAction SilentlyContinue).Count
    Write-Check $(if ($dumps) { 'INFO' } else { 'OK' }) 'Minidump files' "$dumps"
    $pf = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)
    if ($pf.Count) { foreach ($p in $pf) { Write-Check 'INFO' 'Page file' ('{0} ({1} MB, peak {2} MB used)' -f $p.Name, $p.AllocatedBaseSize, $p.PeakUsage) } }
    else { Write-Check 'WARN' 'Page file' 'None - apps may crash when memory runs out' }
    Write-Check 'INFO' 'Hibernation' $(if (Test-Path -LiteralPath "$env:SystemDrive\hiberfil.sys") { 'Enabled' } else { 'Disabled' })
    $plan = (powercfg /getactivescheme | Out-String) -replace '^.*\((.+)\).*$', '$1'
    Write-Check 'INFO' 'Active power plan' $plan.Trim()

    Write-Section 'Time and region'
    $ts = Get-Service W32Time -ErrorAction SilentlyContinue
    Write-Check $(if ($ts.Status -eq 'Running') { 'OK' } else { 'INFO' }) 'Windows Time service' "$($ts.Status)"
    if ($ts.Status -eq 'Running') {
        $src = (w32tm /query /source 2>$null | Out-String).Trim()
        Write-Check 'INFO' 'Time source' $(if ($src -and $src -notmatch 'error|denied') { $src } else { 'Run as Administrator to see (MNT-15 shows full status)' })
    }
    Write-Check 'INFO' 'Time zone' (Get-TimeZone).DisplayName
    Write-Check 'INFO' 'Locale / region' "$((Get-Culture).Name) / $((Get-WinHomeLocation -ErrorAction SilentlyContinue).HomeLocation)"

    Write-Section 'Remote access and network'
    $rdp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue).fDenyTSConnections -eq 0
    Write-Check 'INFO' 'Remote Desktop' $(if ($rdp) { 'Enabled' } else { 'Disabled' })
    if ($rdp) {
        $nla = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -ErrorAction SilentlyContinue).UserAuthentication -eq 1
        Write-Check $(if ($nla) { 'OK' } else { 'WARN' }) 'RDP Network Level Auth' $(if ($nla) { 'Required' } else { 'Not required' })
    }
    $ra = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -ErrorAction SilentlyContinue).fAllowToGetHelp -eq 1
    Write-Check 'INFO' 'Remote Assistance' $(if ($ra) { 'Allowed' } else { 'Not allowed' })
    Write-Check 'INFO' 'WinRM service' "$((Get-Service WinRM -ErrorAction SilentlyContinue).Status)"
    $v6 = @(Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue | Where-Object Enabled).Count
    Write-Check 'INFO' 'IPv6' $(if ($v6) { "Enabled on $v6 adapter(s)" } else { 'Disabled' })

    Write-Section 'Stability'
    $u = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 6008; StartTime = (Get-Date).AddDays(-7) } -ErrorAction SilentlyContinue).Count
    Write-Check $(if ($u) { 'WARN' } else { 'OK' }) 'Unexpected shutdowns (7 days)' "$u"
    $bc = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting' } -MaxEvents 1 -ErrorAction SilentlyContinue
    Write-Check $(if ($bc) { 'INFO' } else { 'OK' }) 'Last blue screen' $(if ($bc) { "$($bc.TimeCreated)" } else { 'None recorded' })
}
