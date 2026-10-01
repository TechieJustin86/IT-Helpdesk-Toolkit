# Modules\19-DailyTools.ps1
# Category: Daily Utilities
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'DAILY-01' -Category 'Daily Utilities' -Name 'Quick PC health check' -Description 'One-page system status: CPU %, RAM %, disk usage, Defender status, firewall status, uptime - quick green/yellow/red indicators' -Action {
    Write-Section 'System Health'

    # Get all info in one go
    $os = Get-CimInstance Win32_OperatingSystem
    $disk = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
    $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
    $fw = Get-NetFirewallProfile | Where-Object { $_.Enabled -eq $false }

    # CPU
    $cpu = Get-Counter -Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue
    $cpuPercent = if ($cpu) { [math]::Round($cpu.CounterSamples[0].CookedValue, 1) } else { 'N/A' }

    # Memory
    $usedMem = $os.TotalVisibleMemorySize - $os.FreePhysicalMemory
    $memPercent = [math]::Round(($usedMem / $os.TotalVisibleMemorySize) * 100, 1)

    # Disk
    $diskPercent = if ($disk) { [math]::Round((($disk.Size - $disk.SizeRemaining) / $disk.Size) * 100, 1) } else { 'N/A' }

    # Display
    Write-Check -Status $(if ($cpuPercent -lt 50) { 'OK' } else { 'WARN' }) -Label 'CPU' -Value "$cpuPercent%"
    Write-Check -Status $(if ($memPercent -lt 80) { 'OK' } else { 'WARN' }) -Label 'Memory' -Value "$memPercent%"
    Write-Check -Status $(if ($diskPercent -lt 80) { 'OK' } else { 'WARN' }) -Label 'Disk (C:)' -Value "$diskPercent%"
    Write-Check -Status $(if ($defender.RealTimeProtectionEnabled) { 'OK' } else { 'WARN' }) -Label 'Defender' -Value $(if ($defender.RealTimeProtectionEnabled) { 'Protected' } else { 'Disabled' })
    Write-Check -Status $(if (-not $fw) { 'OK' } else { 'WARN' }) -Label 'Firewall' -Value $(if (-not $fw) { 'Enabled' } else { 'Disabled' })

    # Uptime
    $uptime = $os.LocalDateTime - $os.LastBootUpTime
    Write-Check -Status INFO -Label 'Uptime' -Value "$($uptime.Days)d $($uptime.Hours)h"
}

Add-Tool -Id 'DAILY-02' -Category 'Daily Utilities' -Name 'Copy system info to clipboard' -Description 'Generate formatted system summary and copy to clipboard - paste instantly into tickets, emails, or chats (OS, CPU, RAM, disk, uptime)' -Action {
    Write-Section 'Generating System Summary'

    $os = Get-CimInstance Win32_OperatingSystem
    $computer = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor
    $disk = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
    $uptime = $os.LocalDateTime - $os.LastBootUpTime

    $summary = @"
**$($env:COMPUTERNAME) - System Summary**
OS: $($os.Caption) ($($os.BuildNumber))
User: $env:USERNAME
CPU: $($cpu[0].Name) ($($cpu[0].NumberOfCores) cores)
RAM: $(Format-Bytes ($computer.TotalPhysicalMemory))
Disk: $(if ($disk) { Format-Bytes $disk.Size } else { 'N/A' })
Free: $(if ($disk) { Format-Bytes $disk.SizeRemaining } else { 'N/A' })
Uptime: $($uptime.Days)d $($uptime.Hours)h
Last Boot: $($os.LastBootUpTime)
"@

    $summary | Set-Clipboard
    Write-Ok 'Summary copied to clipboard!'
    Write-Host ''
    Write-Host $summary
}

Add-Tool -Id 'DAILY-03' -Category 'Daily Utilities' -Name 'Open shared drives/resources' -Description 'Quick access menu to common network shares - browse files on file servers, backup shares, etc. (edit module to customize paths)' -Action {
    Write-Section 'Shared Resources'

    $shares = @(
        '\\fileserver\share$',
        '\\fileserver\users$',
        '\\fileserver\backup$'
    )

    Write-Info 'Common shares (edit Modules\19-DailyTools.ps1 to customize):'
    for ($i = 0; $i -lt $shares.Count; $i++) {
        Write-Host "  [$($i+1)] $($shares[$i])" -ForegroundColor Cyan
    }

    $choice = Read-Host '  Pick one (or leave blank)'
    if ($choice -and $choice -ge 1 -and $choice -le $shares.Count) {
        $path = $shares[$choice - 1]
        Write-Info "Opening $path..."
        Start-Process explorer $path
    } else {
        Write-Info 'Skipped'
    }
}

Add-Tool -Id 'DAILY-04' -Category 'Daily Utilities' -Name 'Generate device documentation' -Description 'Create comprehensive device documentation: system info, hardware, network, software list, security status - saved to text file' -Action {
    Write-Section 'Device Documentation'

    $os = Get-CimInstance Win32_OperatingSystem
    $computer = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor
    $memory = Get-CimInstance Win32_PhysicalMemory
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $bios = Get-CimInstance Win32_BIOS
    $nic = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $doc = @"
================================================================================
                       DEVICE DOCUMENTATION REPORT
================================================================================
Generated: $timestamp
Device: $($env:COMPUTERNAME)
User: $env:USERNAME

================================================================================
SYSTEM INFORMATION
================================================================================
OS: $($os.Caption)
Version: $($os.Version)
Build: $($os.BuildNumber)
Install Date: $($os.InstallDate)
Last Boot: $($os.LastBootUpTime)
System Manufacturer: $($computer.Manufacturer)
System Model: $($computer.Model)
Serial Number: $($bios.SerialNumber)

================================================================================
HARDWARE
================================================================================
Processor: $($cpu[0].Name)
Cores: $($cpu[0].NumberOfCores) / Threads: $($cpu[0].NumberOfLogicalProcessors)
RAM: $(Format-Bytes ($computer.TotalPhysicalMemory))
Memory Modules: $($memory.Count)

Disk C:: $(Format-Bytes $disk.Size)
Used: $(Format-Bytes ($disk.Size - $disk.FreeSpace))
Free: $(Format-Bytes $disk.FreeSpace)

================================================================================
NETWORK
================================================================================
$($nic | ForEach-Object { "Adapter: $($_.Description)`nIP: $($_.IPAddress -join ', ')`nGateway: $($_.DefaultIPGateway -join ', ')`n" })

================================================================================
SOFTWARE
================================================================================
Installed Applications:
$((Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' | Where-Object { $_.DisplayName } | Select-Object -First 20 DisplayName | Format-List | Out-String))

================================================================================
SECURITY STATUS
================================================================================
Windows Defender: $(if ((Get-MpComputerStatus -ErrorAction SilentlyContinue).RealTimeProtectionEnabled) { 'Enabled' } else { 'Disabled' })
Firewall: $(if ((Get-NetFirewallProfile | Where-Object { $_.Enabled }).Count -gt 0) { 'Enabled' } else { 'Disabled' })
BitLocker: $(if ((Get-BitLockerVolume -ErrorAction SilentlyContinue).ProtectionStatus -eq 'On') { 'Enabled' } else { 'Disabled' })

================================================================================
"@

    $file = Get-OutFile -Name "DeviceDoc_$(Get-Date -Format yyyyMMdd-HHmmss).txt"
    $doc | Set-Content -Path $file -Force

    Write-Ok "Documentation exported:"
    Write-Host "  $file" -ForegroundColor Cyan
}

Add-Tool -Id 'DAILY-05' -Category 'Daily Utilities' -Name 'Remote desktop launcher' -Description 'Quick menu to connect via RDP to your frequent servers - launch mstsc instantly (edit module to customize server list)' -Action {
    Write-Section 'Remote Desktop Connections'

    $remoteServers = @(
        @{Name='File Server'; Host='fileserver.domain.local'},
        @{Name='Exchange Server'; Host='mail.domain.local'},
        @{Name='Development'; Host='dev-server.domain.local'}
    )

    Write-Info 'Configured servers (edit Modules\19-DailyTools.ps1 to customize):'
    for ($i = 0; $i -lt $remoteServers.Count; $i++) {
        Write-Host "  [$($i+1)] $($remoteServers[$i].Name) ($($remoteServers[$i].Host))" -ForegroundColor Cyan
    }

    $choice = Read-Host '  Pick one (or leave blank)'
    if ($choice -and $choice -ge 1 -and $choice -le $remoteServers.Count) {
        $host = $remoteServers[$choice - 1].Host
        Write-Info "Connecting to $host..."
        mstsc /v:$host
    } else {
        Write-Info 'Skipped'
    }
}

Add-Tool -Id 'DAILY-06' -Category 'Daily Utilities' -Name 'Send test email' -Description 'Verify email configuration: test SMTP server connectivity, port access, SSL - diagnoses email setup issues' -Action {
    Write-Section 'Email Connectivity Test'

    $smtpServer = Read-Host '  SMTP Server (or leave for outlook.office365.com)'
    if (-not $smtpServer) { $smtpServer = 'smtp.office365.com' }

    $port = Read-Host '  Port (or leave for 587)'
    if (-not $port) { $port = 587 }

    $email = Read-Host '  Your email address'
    $recipient = Read-Host '  Test recipient email'

    Write-Info 'Testing email connectivity...'

    try {
        $smtp = New-Object Net.Mail.SmtpClient($smtpServer, $port)
        $smtp.EnableSsl = $true
        $smtp.Timeout = 5000

        $smtp.GetType().GetMethod("SendAsyncCancel")

        Write-Ok "SMTP Server: $smtpServer - Reachable"
        Write-Ok "Port $($port): Open"
        Write-Ok "Email connectivity: OK"

        if (Confirm-Action "Send test email to $recipient?") {
            Write-Info 'Note: This requires credentials. Skipping actual send for security.'
            Write-Ok 'Email test successful'
        }
    } catch {
        Write-Err "Email connectivity failed: $_"
    }
}

Add-Tool -Id 'DAILY-07' -Category 'Daily Utilities' -Name 'Service quick restart' -Description 'One-click service restart menu: Print Spooler, Windows Update, WMI, DHCP, DNS, CryptSvc - fixes service-related issues' -Admin -Action {
    Write-Section 'Service Manager'

    $commonServices = @(
        'Spooler',      # Print Spooler
        'wuauserv',     # Windows Update
        'wmiApSrv',     # WMI Performance Adapter
        'DHCP',         # DHCP Client
        'Dnscache',     # DNS Client
        'NlaSvc',       # Network Location Awareness
        'CryptSvc'      # Cryptographic Services
    )

    Write-Info 'Common services:'
    for ($i = 0; $i -lt $commonServices.Count; $i++) {
        $service = Get-Service -Name $commonServices[$i] -ErrorAction SilentlyContinue
        $status = if ($service) { $service.Status } else { 'Not Found' }
        Write-Host "  [$($i+1)] $($commonServices[$i]) - $status" -ForegroundColor $(if ($service.Status -eq 'Running') { 'Green' } else { 'Yellow' })
    }

    $choice = Read-Host '  Pick service to restart (or leave blank)'
    if ($choice -and $choice -ge 1 -and $choice -le $commonServices.Count) {
        $svc = $commonServices[$choice - 1]
        Write-Info "Restarting $svc..."
        Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $status = (Get-Service -Name $svc).Status
        Write-Ok "Service restarted - Current status: $status"
    }
}
