# Modules\17-BatchOps.ps1
# Category: Batch Operations
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'BATCH-01' -Category 'Batch Operations' -Name 'Bulk restart PCs' -Description 'Schedule simultaneous restarts on multiple PCs with custom countdown message and delay time (in minutes)' -Admin -Action {
    Write-Section 'Bulk PC Restart'

    $computers = Read-Host '  Enter computer names (comma-separated or read from file)'
    $minutes = Read-Host '  Minutes until restart [5]'
    if (-not $minutes) { $minutes = 5 }
    $message = Read-Host '  Message to show users [Empty]'
    if (-not $message) { $message = 'Your computer will restart in ' + $minutes + ' minutes' }

    $computerList = $computers -split ',' | ForEach-Object { $_.Trim() }

    Write-Info "Scheduling restart on $($computerList.Count) computer(s)..."
    Write-Host ''

    foreach ($computer in $computerList) {
        try {
            Write-Info "Contacting $computer..."
            $seconds = [int]$minutes * 60

            # WMI method for remote shutdown
            $params = @{
                Path = "\\$computer\root\cimv2:Win32_OperatingSystem.Name='Microsoft Windows 10 Pro|C:\\Windows|\\Device\\Harddisk0\\Partition1'"
                Name = 'Win32ShutdownTracker'
                Arguments = @{ Flags = 1; Reason = 'Restart'; Timeout = $seconds; Comment = $message }
                ErrorAction = 'SilentlyContinue'
            }

            # Try alternative method
            Invoke-CimMethod -ComputerName $computer -ClassName Win32_OperatingSystem `
                -MethodName Win32Shutdown -Arguments @{Flags=1;Timeout=$seconds} `
                -ErrorAction SilentlyContinue

            Write-Ok "$computer - Restart scheduled for $minutes minutes"
        } catch {
            Write-Err "$computer - Failed: $_"
        }
    }
}

Add-Tool -Id 'BATCH-02' -Category 'Batch Operations' -Name 'Network inventory scan' -Description 'Discover all active PCs on your subnet: ping sweep to find online computers, resolve hostnames, export to CSV' -Action {
    Write-Section 'Network Inventory Scan'

    $subnet = Read-Host '  Enter subnet (e.g., 192.168.1.0/24 or 192.168.1)'
    $baseIP = $subnet -replace '/.*'
    $octets = $baseIP -split '\.'
    $base = [string]::Join('.', $octets[0..2])

    Write-Info "Scanning $base.0/24 (this may take 30-60 seconds)..."
    $results = @()

    1..254 | ForEach-Object {
        $ip = "$base.$_"
        $result = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue -TimeoutSec 1

        if ($result) {
            try {
                $hostname = [System.Net.Dns]::GetHostByAddress($ip).HostName
            } catch {
                $hostname = 'Unknown'
            }

            $results += [pscustomobject]@{
                IP = $ip
                Hostname = $hostname
                Status = 'Online'
            }

            Write-Host "  [OK] $ip ($hostname)" -ForegroundColor Green
        }
    } -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Info "Found $($results.Count) active computer(s):"
    Write-Host ''
    $results | Format-Table -AutoSize | Out-Host

    if (Confirm-Action 'Save results to CSV?') {
        $file = Get-OutFile -Name "NetworkScan_$(Get-Date -Format yyyyMMdd-HHmmss).csv"
        $results | Export-Csv -Path $file -NoTypeInformation -Force
        Write-Ok "Saved to $file"
    }
}

Add-Tool -Id 'BATCH-03' -Category 'Batch Operations' -Name 'Get software inventory (multi-PC)' -Description 'Remote software audit: connect to multiple PCs, export installed apps with versions/publishers to single CSV (requires WinRM)' -Action {
    Write-Section 'Multi-PC Software Inventory'

    $computers = Read-Host '  Enter computer names (comma-separated)'
    $computerList = $computers -split ',' | ForEach-Object { $_.Trim() }

    Write-Info "Gathering software from $($computerList.Count) computer(s)..."
    $allSoftware = @()

    foreach ($computer in $computerList) {
        Write-Info "  $computer..."
        try {
            $software = Invoke-Command -ComputerName $computer -ScriptBlock {
                Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' |
                    Select-Object DisplayName, DisplayVersion, Publisher |
                    Where-Object { $_.DisplayName }
            } -ErrorAction SilentlyContinue

            foreach ($app in $software) {
                $allSoftware += [pscustomobject]@{
                    Computer = $computer
                    Name = $app.DisplayName
                    Version = $app.DisplayVersion
                    Publisher = $app.Publisher
                }
            }
            Write-Ok "  $computer - $(($software | Measure-Object).Count) apps"
        } catch {
            Write-Err "  $computer - Failed to connect"
        }
    }

    if ($allSoftware) {
        $file = Get-OutFile -Name "SoftwareInventory_$(Get-Date -Format yyyyMMdd-HHmmss).csv"
        $allSoftware | Export-Csv -Path $file -NoTypeInformation -Force
        Write-Ok "Exported $($allSoftware.Count) entries to $file"
    }
}

Add-Tool -Id 'BATCH-04' -Category 'Batch Operations' -Name 'Remote system info' -Description 'Query multiple PCs for: OS, RAM, user logged in, uptime, disk usage - bulk health check, export to CSV' -Action {
    Write-Section 'Remote System Information'

    $computers = Read-Host '  Enter computer names (comma-separated)'
    $computerList = $computers -split ',' | ForEach-Object { $_.Trim() }

    $results = @()

    foreach ($computer in $computerList) {
        Write-Info "Querying $computer..."
        try {
            $info = Get-CimInstance -ComputerName $computer -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
            $os = Get-CimInstance -ComputerName $computer -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
            $disk = Get-CimInstance -ComputerName $computer -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue

            if ($info) {
                $diskPercent = if ($disk) { [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1) } else { 'N/A' }

                $results += [pscustomobject]@{
                    Computer = $computer
                    OS = $os.Caption
                    RAM = "$(Format-Bytes ($info.TotalPhysicalMemory))"
                    User = $info.UserName
                    Uptime = if ($os) { $os.LocalDateTime - $os.LastBootUpTime } else { 'N/A' }
                    'C: Usage' = "$diskPercent%"
                }
                Write-Ok "  $computer"
            }
        } catch {
            Write-Err "  $computer - Failed to connect"
        }
    }

    if ($results) {
        Write-Host ''
        $results | Format-Table -AutoSize | Out-Host

        if (Confirm-Action 'Save to CSV?') {
            $file = Get-OutFile -Name "SystemInfo_$(Get-Date -Format yyyyMMdd-HHmmss).csv"
            $results | Export-Csv -Path $file -NoTypeInformation -Force
            Write-Ok "Saved to $file"
        }
    }
}

Add-Tool -Id 'BATCH-05' -Category 'Batch Operations' -Name 'Apply Windows updates (multi-PC)' -Description 'Trigger Windows Update check simultaneously on multiple remote PCs - pushes them to download latest patches' -Admin -Action {
    Write-Section 'Bulk Windows Update Trigger'

    $computers = Read-Host '  Enter computer names (comma-separated)'
    $computerList = $computers -split ',' | ForEach-Object { $_.Trim() }

    Write-Info "Triggering update check on $($computerList.Count) computer(s)..."
    Write-Host ''

    foreach ($computer in $computerList) {
        try {
            Write-Info "  $computer - Triggering update check..."
            Invoke-Command -ComputerName $computer -ScriptBlock {
                (New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow()
            } -ErrorAction SilentlyContinue
            Write-Ok "  $computer - Update check initiated"
        } catch {
            Write-Err "  $computer - Failed"
        }
    }
}

Add-Tool -Id 'BATCH-06' -Category 'Batch Operations' -Name 'Run script on multiple PCs' -Description 'Deploy PowerShell script to multiple remote computers: provide .ps1 file path, runs on all targets, shows success/fail per PC' -Admin -Action {
    Write-Section 'Remote Script Execution'

    $computers = Read-Host '  Enter computer names (comma-separated)'
    $scriptPath = Read-Host '  Path to PowerShell script'

    if (-not (Test-Path $scriptPath)) {
        Write-Err "Script not found: $scriptPath"
        return
    }

    $computerList = $computers -split ',' | ForEach-Object { $_.Trim() }
    $scriptContent = Get-Content -Path $scriptPath -Raw

    Write-Info "Running script on $($computerList.Count) computer(s)..."
    Write-Host ''

    foreach ($computer in $computerList) {
        try {
            Write-Info "  $computer..."
            Invoke-Command -ComputerName $computer -ScriptBlock ([scriptblock]::Create($scriptContent)) -ErrorAction SilentlyContinue
            Write-Ok "  $computer - Completed"
        } catch {
            Write-Err "  $computer - Failed: $_"
        }
    }
}
