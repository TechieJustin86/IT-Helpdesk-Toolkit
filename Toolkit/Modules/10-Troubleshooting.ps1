# Modules\10-Troubleshooting.ps1
# Category: Troubleshooting
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'TRB-01' -Category 'Troubleshooting' -Name 'Recent errors (event log)' -Description 'Critical/error events in last 24h, grouped' -Action {
    $e = @(Get-RecentErrors -Hours 24)
    if (-not $e.Count) { Write-Ok 'No critical or error events in the last 24 hours.'; return }
    $e | Select-Object -First 25 | Format-Table -AutoSize -Wrap | Out-Host
    if (Confirm-Action 'Export all to CSV?') { $e | Export-Results -Name 'event-errors.csv' }
}

Add-Tool -Id 'TRB-02' -Category 'Troubleshooting' -Name 'Crash / BSOD history' -Description 'Blue screens, unexpected shutdowns, app crashes (30 days)' -Action {
    $names = @{ 41 = 'Kernel-Power (lost power / hard reset)'; 1001 = 'Blue screen (BugCheck)'; 6008 = 'Unexpected shutdown' }
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41, 1001, 6008; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -ne 1001 -or $_.ProviderName -like '*WER-SystemErrorReporting*' })
    Write-Section 'System crashes (30 days)'
    if ($ev.Count) {
        $ev | Select-Object TimeCreated, Id, @{n = 'Type'; e = { $names[$_.Id] } }, @{n = 'Detail'; e = { ("$($_.Message)" -replace '\s+', ' ').Substring(0, [math]::Min(80, "$($_.Message)".Length)) } } | Format-Table -AutoSize -Wrap | Out-Host
    } else { Write-Ok 'No system crashes.' }

    Write-Section 'Minidump files'
    $dumps = @(Get-ChildItem "$env:SystemRoot\Minidump" -Filter *.dmp -ErrorAction SilentlyContinue)
    if ($dumps.Count) { $dumps | Select-Object Name, LastWriteTime, @{n = 'Size'; e = { Format-Bytes $_.Length } } | Format-Table -AutoSize | Out-Host } else { Write-Info 'None found (or access denied).' }

    Write-Section 'Application crashes (7 days)'
    $apps = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000; StartTime = (Get-Date).AddDays(-7) } -ErrorAction SilentlyContinue)
    if ($apps.Count) {
        $apps | Group-Object { $_.Properties[0].Value } | Sort-Object Count -Descending | Select-Object Count, @{n = 'Application'; e = { $_.Name } }, @{n = 'Last'; e = { $_.Group[0].TimeCreated } } | Format-Table -AutoSize | Out-Host
    } else { Write-Ok 'No application crashes.' }
}

Add-Tool -Id 'TRB-03' -Category 'Troubleshooting' -Name 'Shutdown / restart history' -Description 'Who or what restarted the PC and when' -Action {
    $names = @{ 1074 = 'Restart/shutdown requested'; 6005 = 'Event log started (boot)'; 6006 = 'Clean shutdown'; 6008 = 'Unexpected shutdown'; 41 = 'Kernel-Power (hard reset)' }
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1074, 6005, 6006, 6008, 41 } -MaxEvents 30 -ErrorAction SilentlyContinue | ForEach-Object {
        $detail = ''
        if ($_.Id -eq 1074) { $detail = '{0} by {1} - {2}' -f $_.Properties[4].Value, $_.Properties[6].Value, $_.Properties[2].Value; $detail += " ($(Split-Path $_.Properties[0].Value -Leaf))" }
        [pscustomobject]@{ Time = $_.TimeCreated; Event = $names[$_.Id]; Detail = $detail }
    } | Format-Table -AutoSize -Wrap | Out-Host
}

Add-Tool -Id 'TRB-04' -Category 'Troubleshooting' -Name 'Performance snapshot' -Description 'CPU/RAM load and top processes right now' -Action {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average)
    $memPct = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 1)
    Write-Info ('CPU load: {0}%    Memory used: {1}% of {2}' -f $cpu, $memPct, (Format-Bytes ($os.TotalVisibleMemorySize * 1KB)))
    $cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
    Write-Section 'Top CPU (current)'
    Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.Name -notin '_Total', 'Idle' } |
        Sort-Object PercentProcessorTime -Descending | Select-Object -First 10 Name, @{n = 'PID'; e = { $_.IDProcess } },
            @{n = 'CPU %'; e = { [math]::Round($_.PercentProcessorTime / $cores, 1) } }, @{n = 'Private mem'; e = { Format-Bytes $_.WorkingSetPrivate } } |
        Format-Table -AutoSize | Out-Host
    Write-Section 'Top memory'
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 ProcessName, Id, @{n = 'Memory'; e = { Format-Bytes $_.WorkingSet64 } }, @{n = 'CPU time (s)'; e = { [math]::Round($_.CPU, 1) } } |
        Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'TRB-05' -Category 'Troubleshooting' -Name 'Kill a process' -Description 'End hung (not responding) apps or any process by name' -Action {
    $hung = @(Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and -not $_.Responding })
    if ($hung.Count) {
        Write-Warn 'Not responding:'
        $hung | Select-Object ProcessName, Id, MainWindowTitle | Format-Table -AutoSize | Out-Host
        if (Confirm-Action 'End all not-responding processes?') { $hung | Stop-Process -Force; Write-Ok 'Ended.'; return }
    } else { Write-Ok 'No hung applications detected.' }
    $n = Read-Host '  Or enter a process name to end (blank to cancel)'
    if (-not $n) { return }
    $procs = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
    if (-not $procs.Count) { Write-Err "No process named '$n'."; return }
    if (Confirm-Action "End $($procs.Count) '$n' process(es)?") { $procs | Stop-Process -Force; Write-Ok 'Ended.' }
}

Add-Tool -Id 'TRB-06' -Category 'Troubleshooting' -Name 'Stopped automatic services' -Description 'Auto-start services not running; start them' -Action {
    $s = @(Get-StoppedAutoServices)
    if (-not $s.Count) { Write-Ok 'All automatic services are running.'; return }
    $s | Format-Table -AutoSize | Out-Host
    if ((Test-IsAdmin) -and (Confirm-Action 'Try to start them?')) {
        foreach ($svc in $s) {
            try { Start-Service -Name $svc.Name -ErrorAction Stop; Write-Ok "Started $($svc.Name)" } catch { Write-Err "$($svc.Name): $($_.Exception.Message)" }
        }
    }
}

Add-Tool -Id 'TRB-07' -Category 'Troubleshooting' -Name 'Restart a service' -Admin -Description 'Find a service by name and restart it' -Action {
    $q = Read-Host '  Service name or part of display name'
    if (-not $q) { return }
    $pattern = "*$([WildcardPattern]::Escape($q))*"
    $svc = Select-FromList @(Get-Service | Where-Object { $_.Name -like $pattern -or $_.DisplayName -like $pattern }) { '{0,-28} {1,-8} {2}' -f $_.Name, $_.Status, $_.DisplayName } 'Service'
    if (-not $svc) { return }
    if ($svc.Status -eq 'Running') { Restart-Service -Name $svc.Name -Force } else { Start-Service -Name $svc.Name }
    Write-Ok "$($svc.Name) is now $((Get-Service $svc.Name).Status)."
}

Add-Tool -Id 'TRB-08' -Category 'Troubleshooting' -Name 'Find large files / folders' -Description 'Biggest files or subfolders under a path' -Action {
    $path = Read-Host "  Folder [$env:USERPROFILE]"
    if (-not $path) { $path = $env:USERPROFILE }
    if (-not (Test-Path -LiteralPath $path)) { Write-Err 'Path not found.'; return }
    Write-Host '  [1] Largest files   [2] Subfolder sizes'
    $c = Read-Host '  Choice'
    Write-Info 'Scanning... this can take a while.'
    if ($c -eq '2') {
        Get-ChildItem -LiteralPath $path -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{ Folder = $_.Name; Bytes = Get-FolderSize $_.FullName }
        } | Sort-Object Bytes -Descending | Select-Object -First 25 Folder, @{n = 'Size'; e = { Format-Bytes $_.Bytes } } | Format-Table -AutoSize | Out-Host
    } else {
        $min = Read-Host '  Minimum size in MB [100]'
        if ($min -notmatch '^\d+$') { $min = 100 }
        Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object Length -ge ([int64]$min * 1MB) |
            Sort-Object Length -Descending | Select-Object -First 30 @{n = 'Size'; e = { Format-Bytes $_.Length } }, LastWriteTime, FullName |
            Format-Table -AutoSize -Wrap | Out-Host
    }
}

Add-Tool -Id 'TRB-09' -Category 'Troubleshooting' -Name 'Disk health (SMART)' -Admin -Description 'Health, temperature, wear and SMART failure prediction' -Action {
    Get-PhysicalDisk | ForEach-Object {
        $rc = $_ | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Disk          = $_.FriendlyName
            Media         = $_.MediaType
            Size          = Format-Bytes $_.Size
            Health        = $_.HealthStatus
            'Temp C'      = $rc.Temperature
            'Wear %'      = $rc.Wear
            'Power-on hrs'= $rc.PowerOnHours
            'Read errors' = $rc.ReadErrorsUncorrected
        }
    } | Format-Table -AutoSize | Out-Host
    $smart = @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue)
    if ($smart | Where-Object PredictFailure) { Write-Err 'SMART predicts a disk FAILURE - back up data and replace the drive!' }
    elseif ($smart.Count) { Write-Ok 'SMART: no failure predicted.' }
}

Add-Tool -Id 'TRB-10' -Category 'Troubleshooting' -Name 'Reliability history' -Description 'Stability index and reliability events (7 days)' -Action {
    $idx = Get-CimInstance Win32_ReliabilityStabilityMetrics -ErrorAction SilentlyContinue | Sort-Object TimeGenerated -Descending | Select-Object -First 1
    if ($idx) { Write-Info ('Stability index: {0:N1} / 10' -f $idx.SystemStabilityIndex) }
    $since = [Management.ManagementDateTimeConverter]::ToDmtfDateTime((Get-Date).AddDays(-7))
    Get-CimInstance Win32_ReliabilityRecords -Filter "TimeGenerated >= '$since'" -ErrorAction SilentlyContinue |
        Select-Object TimeGenerated, SourceName, ProductName, @{n = 'Message'; e = { $m = "$($_.Message)" -replace '\s+', ' '; if ($m.Length -gt 80) { $m.Substring(0, 80) + '...' } else { $m } } } |
        Format-Table -AutoSize -Wrap | Out-Host
    if (Confirm-Action 'Open Reliability Monitor?') { Start-Process perfmon.exe -ArgumentList '/rel' }
}

Add-Tool -Id 'TRB-11' -Category 'Troubleshooting' -Name 'Printer tools' -Description 'List printers, test page, clear queue, set default' -Action {
    $printers = @(Get-CimInstance Win32_Printer)
    $printers | Select-Object Name, Default, PrinterStatus, DriverName, PortName | Format-Table -AutoSize | Out-Host
    $p = Select-FromList $printers { $_.Name } 'Printer to work with'
    if (-not $p) { return }
    Write-Host '  [1] Print test page   [2] Clear print queue   [3] Set as default'
    switch (Read-Host '  Action') {
        '1' { Invoke-CimMethod -InputObject $p -MethodName PrintTestPage | Out-Null; Write-Ok 'Test page sent.' }
        '2' { Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue | Remove-PrintJob; Write-Ok 'Queue cleared.' }
        '3' { Invoke-CimMethod -InputObject $p -MethodName SetDefaultPrinter | Out-Null; Write-Ok 'Default printer set.' }
    }
}

Add-Tool -Id 'TRB-12' -Category 'Troubleshooting' -Name 'Windows troubleshooters' -Description 'Launch built-in troubleshooters (network, audio, printer...)' -Action {
    $items = @(
        @{ Name = 'Network adapter'; Id = 'NetworkDiagnosticsNetworkAdapter' },
        @{ Name = 'Internet connections'; Id = 'NetworkDiagnosticsWeb' },
        @{ Name = 'Playing audio'; Id = 'AudioPlaybackDiagnostic' },
        @{ Name = 'Printer'; Id = 'PrinterDiagnostic' },
        @{ Name = 'Windows Update'; Id = 'WindowsUpdateDiagnostic' },
        @{ Name = 'Hardware and devices'; Id = 'DeviceDiagnostic' },
        @{ Name = 'Power'; Id = 'PowerDiagnostic' }
    )
    $t = Select-FromList $items { $_.Name } 'Troubleshooter'
    if ($t) { Start-Process msdt.exe -ArgumentList "/id $($t.Id)" -ErrorAction SilentlyContinue; Write-Info 'If nothing opens, use Settings > System > Troubleshoot.' }
}

Add-Tool -Id 'TRB-13' -Category 'Troubleshooting' -Name 'Energy / sleep diagnostics' -Description 'What blocks sleep, last wake source, power report' -Action {
    Write-Section 'Last wake source'
    powercfg /lastwake | Out-Host
    Write-Section 'Devices allowed to wake the PC'
    powercfg /devicequery wake_armed | Out-Host
    Write-Section 'Active sleep blockers'
    powercfg /requests | Out-Host
    if ((Test-IsAdmin) -and (Confirm-Action 'Generate a 60-second energy efficiency report?')) {
        $file = Get-OutFile 'energy-report.html'
        $null = Invoke-External 'powercfg.exe' "/energy /output `"$file`" /duration 60"
        Open-File $file
    }
}

Add-Tool -Id 'TRB-14' -Category 'Troubleshooting' -Name 'Windows Update history' -Description 'Recent update installs, including failures and error codes' -Action {
    $results = @{ 0 = 'Not started'; 1 = 'In progress'; 2 = 'Succeeded'; 3 = 'Succeeded with errors'; 4 = 'Failed'; 5 = 'Aborted' }
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $count = $searcher.GetTotalHistoryCount()
        if (-not $count) { Write-Info 'No update history.'; return }
        $hist = @($searcher.QueryHistory(0, [math]::Min($count, 40)) | Where-Object { $_.Title })
    } catch { Write-Err "Could not read update history: $($_.Exception.Message)"; return }
    $rows = @($hist | ForEach-Object {
        [pscustomobject]@{
            Date   = $_.Date.ToLocalTime()
            Result = $results[[int]$_.ResultCode]
            Error  = if ([int]$_.ResultCode -ge 4) { '0x{0:X8}' -f $_.HResult } else { '' }
            Title  = $_.Title
        }
    })
    $rows | Format-Table -AutoSize -Wrap | Out-Host
    $failed = @($rows | Where-Object { $_.Result -in 'Failed', 'Aborted' })
    if ($failed.Count) { Write-Warn "$($failed.Count) failed update(s). Try MNT-09 (Reset Windows Update), then search the error code." }
    else { Write-Ok 'No failed updates in recent history.' }
}

Add-Tool -Id 'TRB-15' -Category 'Troubleshooting' -Name 'Memory (RAM) test' -Description 'Show previous results or schedule Windows Memory Diagnostic' -Action {
    Write-Section 'Previous results'
    $r = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } -MaxEvents 5 -ErrorAction SilentlyContinue)
    if ($r.Count) { $r | Select-Object TimeCreated, @{ n = 'Result'; e = { "$($_.Message)" -replace '\s+', ' ' } } | Format-Table -AutoSize -Wrap | Out-Host }
    else { Write-Info 'No memory test has been run on this PC.' }
    if (Confirm-Action 'Open Windows Memory Diagnostic? The test runs during a restart and takes 10-20 minutes.') { Start-Process mdsched.exe }
}

Add-Tool -Id 'TRB-16' -Category 'Troubleshooting' -Name 'Sleep study (battery drain)' -Admin -Description 'What drained the battery while the laptop was asleep' -Action {
    $file = Get-OutFile 'sleepstudy.html'
    $null = Invoke-External 'powercfg.exe' "/sleepstudy /output `"$file`""
    if (Test-Path $file) { Open-File $file } else { Write-Warn 'Sleep study is only available on devices that support Modern Standby.' }
}

Add-Tool -Id 'TRB-17' -Category 'Troubleshooting' -Name 'Hardware errors (WHEA)' -Description 'CPU, memory, PCIe and bus errors logged by Windows (30 days)' -Action {
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue)
    if (-not $ev.Count) { Write-Ok 'No hardware errors logged in the last 30 days.'; return }
    Write-Warn "$($ev.Count) hardware error event(s):"
    $ev | Group-Object Id | Sort-Object Count -Descending | ForEach-Object {
        $m = "$($_.Group[0].Message)" -replace '\s+', ' '
        if ($m.Length -gt 110) { $m = $m.Substring(0, 110) + '...' }
        [pscustomobject]@{ Count = $_.Count; EventId = $_.Name; Last = $_.Group[0].TimeCreated; Detail = $m }
    } | Format-Table -AutoSize -Wrap | Out-Host
    Write-Info 'Repeated errors usually point to failing hardware, a bad driver or unstable overclocking/XMP settings.'
}

Add-Tool -Id 'TRB-18' -Category 'Troubleshooting' -Name 'Smart diagnosis' -Description 'Automatic triage: finds common problems and says what to do next' -Action {
    $issues = New-Object System.Collections.Generic.List[object]
    $add = { param($sev, $area, $finding, $fix) $issues.Add([pscustomobject]@{ Severity = $sev; Area = $area; Finding = $finding; Fix = $fix }) }
    Write-Info 'Checking memory, disk, updates, network, security and event logs...'

    $os = Get-CimInstance Win32_OperatingSystem
    $mem = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 1)
    if ($mem -ge 90) { & $add 'FAIL' 'Memory' "Memory use is critically high ($mem%)." 'Check TRB-04 for the heaviest processes; close or restart them.' }
    elseif ($mem -ge 80) { & $add 'WARN' 'Memory' "Memory use is high ($mem%)." 'Check TRB-04 and watch whether it stays high.' }

    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    $free = if ($d.Size) { [math]::Round($d.FreeSpace / $d.Size * 100, 1) } else { 100 }
    if ($free -lt 10) { & $add 'FAIL' 'Storage' "$env:SystemDrive has only $free% free." 'Run MNT-01 (temp cleanup) and TRB-08 (large files).' }
    elseif ($free -lt 20) { & $add 'WARN' 'Storage' "$env:SystemDrive is below 20% free ($free%)." 'Plan a cleanup with MNT-01 before it becomes critical.' }

    $up = (Get-Date) - $os.LastBootUpTime
    if ($up.TotalDays -ge 14) { & $add 'WARN' 'Uptime' "Not restarted for $([int]$up.TotalDays) days." 'A restart clears many slowdowns and finishes pending updates.' }
    $pr = @(Get-PendingReboot)
    if ($pr.Count) { & $add 'WARN' 'Windows' "A restart is pending ($($pr -join ', '))." 'Restart after saving work (MNT-19 can schedule it).' }

    $wu = Get-Service wuauserv -ErrorAction SilentlyContinue
    if ($wu -and $wu.StartType -eq 'Disabled') { & $add 'WARN' 'Windows Update' 'The Windows Update service is disabled.' 'Check whether this is company policy; TRB-19 shows update health.' }

    $gw = (Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object IPv4DefaultGateway | Select-Object -First 1).IPv4DefaultGateway.NextHop
    $inet = Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction SilentlyContinue
    $dns = $true
    try { Resolve-DnsName www.microsoft.com -ErrorAction Stop | Out-Null } catch { $dns = $false }
    if (-not $gw) { & $add 'FAIL' 'Network' 'No default gateway - the PC is not connected to a network.' 'Check the cable or Wi-Fi, then NET-03 to renew the IP.' }
    elseif (-not $inet) { & $add 'FAIL' 'Network' 'The internet cannot be reached.' 'Run NET-02 to see which step fails (gateway, internet, DNS).' }
    elseif (-not $dns) { & $add 'FAIL' 'DNS' 'Internet works but name lookups fail.' 'Run NET-16 to compare DNS servers, then NET-03 to flush DNS.' }

    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if ($mp.AMRunningMode -eq 'Normal' -and (-not $mp.AntivirusEnabled -or -not $mp.RealTimeProtectionEnabled)) { & $add 'FAIL' 'Security' 'Defender real-time protection is off.' 'Turn it back on in Windows Security, or run SEC-02 for details.' }
        elseif ($mp.AMRunningMode -eq 'Normal' -and $mp.AntivirusSignatureAge -gt 7) { & $add 'WARN' 'Security' "Defender signatures are $($mp.AntivirusSignatureAge) days old." 'Run SEC-03 to update and scan.' }
    } catch { }

    $errs = @(Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = (Get-Date).AddHours(-24) } -ErrorAction SilentlyContinue).Count
    if ($errs -ge 25) { & $add 'WARN' 'Event logs' "$errs critical/error events in the last 24 hours." 'Run TRB-01 to see which sources repeat.' }
    $crash = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41, 6008; StartTime = (Get-Date).AddDays(-7) } -ErrorAction SilentlyContinue).Count
    if ($crash) { & $add 'WARN' 'Stability' "$crash unexpected shutdown(s) or crash(es) in 7 days." 'Run TRB-02 (crash history) and TRB-17 (hardware errors).' }

    $b = Get-BatteryHealthData
    if ($b.Present -and $null -ne $b.HealthPercent -and $b.HealthPercent -lt 60) { & $add 'WARN' 'Battery' "Battery holds only $($b.HealthPercent)% of its design capacity." 'Consider a battery replacement (HW-10).' }

    $overall = if (-not $issues.Count) { 'HEALTHY' } elseif ($issues | Where-Object Severity -eq 'FAIL') { 'CRITICAL' } else { 'NEEDS ATTENTION' }
    $color = switch ($overall) { 'HEALTHY' { 'Green' } 'CRITICAL' { 'Red' } default { 'Yellow' } }
    Write-Host ''
    Write-Host "  Overall: $overall" -ForegroundColor $color
    Write-Host ''
    if (-not $issues.Count) { Write-Ok 'No common problems found.'; return }
    foreach ($i in ($issues | Sort-Object { if ($_.Severity -eq 'FAIL') { 0 } else { 1 } })) {
        Write-Check $i.Severity $i.Area $i.Finding
        Write-Host "           Next step: $($i.Fix)" -ForegroundColor DarkGray
    }
}

Add-Tool -Id 'TRB-19' -Category 'Troubleshooting' -Name 'Windows Update health' -Description 'Update services, last successful check and install, pending restart' -Action {
    foreach ($s in @(@('wuauserv', 'Windows Update'), @('BITS', 'Background Intelligent Transfer'), @('UsoSvc', 'Update Orchestrator'), @('CryptSvc', 'Cryptographic Services'))) {
        $svc = Get-Service $s[0] -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        $st = if ($svc.StartType -eq 'Disabled') { 'FAIL' } elseif ($svc.Status -eq 'Running') { 'OK' } else { 'INFO' }
        Write-Check $st $s[1] "$($svc.Status) (start: $($svc.StartType))"
    }
    try {
        $r = (New-Object -ComObject Microsoft.Update.AutoUpdate).Results
        foreach ($pair in @(@('Last successful check', $r.LastSearchSuccessDate), @('Last successful install', $r.LastInstallationSuccessDate))) {
            $dt = $pair[1]
            if ($dt -and $dt.Year -gt 2000) {
                $age = [int]((Get-Date) - $dt.ToLocalTime()).TotalDays
                Write-Check $(if ($age -gt 30) { 'WARN' } else { 'OK' }) $pair[0] "$($dt.ToLocalTime()) ($age days ago)"
            } else { Write-Check 'WARN' $pair[0] 'Never / unknown' }
        }
    } catch { Write-Check 'INFO' 'Update history' 'Unavailable' }
    $pr = @(Get-PendingReboot)
    Write-Check $(if ($pr.Count) { 'WARN' } else { 'OK' }) 'Pending restart' $(if ($pr.Count) { $pr -join ', ' } else { 'None' })
    $policy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
    if ($policy.WUServer) { Write-Check 'INFO' 'Managed by WSUS' $policy.WUServer }
    Write-Section 'Recent updates'
    Get-HotFix -ErrorAction SilentlyContinue | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 8 HotFixID, Description, InstalledOn | Format-Table -AutoSize | Out-Host
    $stopped = @(Get-Service wuauserv, BITS -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Running' -and $_.StartType -ne 'Disabled' })
    if ($stopped.Count -and (Test-IsAdmin) -and (Confirm-Action 'Start the stopped update services?')) {
        $stopped | Start-Service -ErrorAction SilentlyContinue
        Write-Ok 'Services started.'
    }
    Write-Info 'Failures and error codes: TRB-14. Repair: MNT-09.'
}

Add-Tool -Id 'TRB-20' -Category 'Troubleshooting' -Name 'Core services status' -Description 'Health of the Windows services most support issues depend on' -Action {
    $core = [ordered]@{
        'Dhcp' = 'DHCP Client (IP address)'; 'Dnscache' = 'DNS Client (name lookups)'; 'NlaSvc' = 'Network Location Awareness'
        'LanmanWorkstation' = 'Workstation (file shares)'; 'Spooler' = 'Print Spooler'; 'Audiosrv' = 'Windows Audio'
        'wuauserv' = 'Windows Update'; 'BITS' = 'Background Transfer (BITS)'; 'WinDefend' = 'Defender Antivirus'; 'mpssvc' = 'Windows Firewall'
        'EventLog' = 'Event Log'; 'W32Time' = 'Windows Time'; 'WSearch' = 'Windows Search'; 'Winmgmt' = 'WMI'; 'ProfSvc' = 'User Profile Service'
    }
    foreach ($name in $core.Keys) {
        $svc = Get-Service $name -ErrorAction SilentlyContinue
        if (-not $svc) { Write-Check 'INFO' $core[$name] 'Not installed'; continue }
        $st = if ($svc.Status -eq 'Running') { 'OK' } elseif ($svc.StartType -eq 'Disabled') { 'WARN' } elseif ($svc.StartType -eq 'Automatic') { 'FAIL' } else { 'INFO' }
        Write-Check $st $core[$name] "$($svc.Status) (start: $($svc.StartType))"
    }
    Write-Info 'Some services (Windows Update, BITS, Time) start only when needed, so "Stopped" with Manual start is normal. TRB-07 restarts a service.'
}

Add-Tool -Id 'TRB-21' -Category 'Troubleshooting' -Name 'BSOD analysis (detailed)' -Description 'Scan minidump files and extract BugCheck codes' -Action {
    Write-Section 'Blue Screen (BSOD) Analysis'

    $minidumpPath = "$env:SystemRoot\Minidump"
    if (-not (Test-Path $minidumpPath)) {
        Write-Info 'No minidump directory found'
        return
    }

    $dumpFiles = @(Get-ChildItem -Path $minidumpPath -Filter "*.dmp" -ErrorAction SilentlyContinue)
    if (-not $dumpFiles) {
        Write-Ok 'No minidump files found - no recent BSODs'
        return
    }

    Write-Check 'WARN' 'BSOD History' "$($dumpFiles.Count) minidump file(s) found"
    Write-Host ''

    $dumpFiles | Sort-Object LastWriteTime -Descending | ForEach-Object {
        Write-Check 'INFO' 'File' $_.Name
        Write-Check 'INFO' 'Date' $_.LastWriteTime
        Write-Check 'INFO' 'Size' (Format-Bytes $_.Length)
        Write-Host ''
    }

    Write-Section 'Event Log Analysis'
    $bsodEvents = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; ProviderName = 'BugCheck' } -MaxEvents 5 -ErrorAction SilentlyContinue)

    if ($bsodEvents.Count -gt 0) {
        Write-Warn "$($bsodEvents.Count) BSOD event(s) recorded:"
        $bsodEvents | ForEach-Object {
            $msg = $_.Message
            if ($msg -match 'BSOD.*?(?=\s|$|\\)') {
                Write-Host "  - $($matches[0])"
            }
            Write-Check 'INFO' 'Timestamp' $_.TimeCreated
        }
    } else {
        Write-Info 'No BSOD events in System log'
    }

    Write-Host ''
    Write-Info 'Note: To debug minidumps, use WinDbg (Windows Debugger) with Windows debugging symbols'
    Write-Info 'Recommendation: Check for driver updates, temperature issues, and RAM failures (MNT-03, HW-10)'
}

Add-Tool -Id 'TRB-22' -Category 'Troubleshooting' -Name 'Event log analysis' -Description 'Scan Application, System, and Security logs for errors and warnings' -Action {
    Write-Section 'Event Log Summary'

    $timeRange = Read-Host "Hours to analyze (default: 24)"
    if (-not $timeRange) { $timeRange = 24 }

    $startTime = (Get-Date).AddHours(-[int]$timeRange)
    $logNames = @('Application', 'System', 'Security')

    foreach ($logName in $logNames) {
        try {
            $errors = @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Level = 2; StartTime = $startTime } -MaxEvents 100 -ErrorAction SilentlyContinue)
            $warnings = @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Level = 3; StartTime = $startTime } -MaxEvents 100 -ErrorAction SilentlyContinue)

            Write-Host "$logName Log:" -ForegroundColor Cyan
            Write-Check 'INFO' 'Errors' $errors.Count
            Write-Check 'INFO' 'Warnings' $warnings.Count

            if ($errors.Count -gt 0) {
                Write-Host '  Top errors:' -ForegroundColor Gray
                $errors | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object {
                    Write-Host "    - $($_.Name): $($_.Count)"
                }
            }
            Write-Host ''
        } catch {
            Write-Warn "$logName : $($_)"
        }
    }

    Write-Host ''
    if (Confirm-Action 'Export detailed error list to CSV?') {
        $allErrors = @()
        foreach ($logName in $logNames) {
            $allErrors += Get-WinEvent -FilterHashtable @{ LogName = $logName; Level = 2, 3; StartTime = $startTime } -MaxEvents 200 -ErrorAction SilentlyContinue |
                Select-Object @{n='LogName';e={$logName}}, TimeCreated, LevelDisplayName, ProviderName, Id, Message
        }
        $allErrors | Sort-Object TimeCreated -Descending | Export-Results -Name 'event-log-analysis.csv'
    }
}
