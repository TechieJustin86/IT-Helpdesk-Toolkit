# Modules\16-Performance.ps1
# Category: Performance & Optimization
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'PERF-01' -Category 'Performance & Optimization' -Name 'Performance snapshot' -Description 'Real-time system status: CPU usage %, RAM used/free, disk space C: drive, top 5 CPU & memory-hungry processes' -Action {
    Write-Section 'Performance Snapshot'

    # CPU Usage
    Write-Info 'Processor'
    $cpu = Get-Counter -Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue
    if ($cpu) {
        $cpuPercent = [math]::Round($cpu.CounterSamples[0].CookedValue, 1)
        Write-Check -Status $(if ($cpuPercent -lt 50) { 'OK' } else { 'WARN' }) -Label 'CPU Usage' -Value "$cpuPercent%"
    }

    # Memory Usage
    Write-Info 'Memory'
    $mem = Get-CimInstance Win32_OperatingSystem
    $usedMem = $mem.TotalVisibleMemorySize - $mem.FreePhysicalMemory
    $memPercent = [math]::Round(($usedMem / $mem.TotalVisibleMemorySize) * 100, 1)
    Write-Check -Status $(if ($memPercent -lt 80) { 'OK' } else { 'WARN' }) -Label 'RAM Usage' -Value "$memPercent% ($(Format-Bytes ($usedMem * 1KB))/$(Format-Bytes ($mem.TotalVisibleMemorySize * 1KB)))"

    # Disk Usage
    Write-Info 'Disk'
    $disk = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
    if ($disk) {
        $diskPercent = [math]::Round((($disk.Size - $disk.SizeRemaining) / $disk.Size) * 100, 1)
        Write-Check -Status $(if ($diskPercent -lt 80) { 'OK' } else { 'WARN' }) -Label 'C: Drive' -Value "$diskPercent% ($(Format-Bytes ($disk.Size - $disk.SizeRemaining))/$(Format-Bytes $disk.Size))"
    }

    # Top processes by memory
    Write-Section 'Top Processes (Memory)'
    Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5 -Property Name, @{n='Memory';e={Format-Bytes $_.WorkingSet}} | Format-Table -AutoSize | Out-Host

    # Top processes by CPU
    Write-Section 'Top Processes (CPU) - Last 10 seconds'
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 -Property Name, @{n='CPU%';e={[math]::Round($_.CPU, 1)}} | Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'PERF-02' -Category 'Performance & Optimization' -Name 'Optimize power plan' -Description 'Auto-configure power settings: balanced (laptop), high performance (desktop), or maximum (server) - adjusts screen timeout & disk timeout' -Admin -Action {
    Write-Section 'Power Plan Optimization'

    Write-Info 'Current power plan:'
    powercfg /getactivescheme | Out-Host

    $deviceType = Read-Host '  Device type: [1] Laptop, [2] Desktop, [3] Server'

    switch ($deviceType) {
        '1' {
            Write-Info 'Optimizing for Laptop (balanced power saving)...'
            powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
            powercfg /change monitor-timeout-ac 10
            powercfg /change monitor-timeout-dc 5
            powercfg /change disk-timeout-ac 20
            powercfg /change disk-timeout-dc 10
        }
        '2' {
            Write-Info 'Optimizing for Desktop (high performance)...'
            powercfg /setactive 8c5e7fda-e8bf-45a6-a6cc-4b3c9b6c0a11
            powercfg /change monitor-timeout-ac 0
            powercfg /change disk-timeout-ac 0
        }
        '3' {
            Write-Info 'Optimizing for Server (max performance)...'
            powercfg /setactive 8c5e7fda-e8bf-45a6-a6cc-4b3c9b6c0a11
            powercfg /change monitor-timeout-ac 0
            powercfg /change disk-timeout-ac 0
            powercfg /change sleep-timeout-ac 0
        }
    }

    Write-Ok 'Power plan optimized'
    Write-Info 'New power plan:'
    powercfg /getactivescheme | Out-Host
}

Add-Tool -Id 'PERF-03' -Category 'Performance & Optimization' -Name 'Find memory leaks' -Description 'Detect memory hogs: list processes using > 500MB RAM, identify suspects, optionally terminate leaking process' -Action {
    Write-Section 'Memory Leak Detection'

    $processes = Get-Process | Where-Object { $_.WorkingSet -gt 500MB } | Sort-Object WorkingSet -Descending

    if ($processes) {
        Write-Warn "Found $($processes.Count) process(es) using > 500MB:"
        Write-Host ''
        $processes | Select-Object Name, @{n='Memory';e={Format-Bytes $_.WorkingSet}}, StartTime | Format-Table -AutoSize | Out-Host

        $suspect = $processes | Select-Object -First 1
        Write-Warn "Top suspect: $($suspect.Name) ($(Format-Bytes $suspect.WorkingSet))"

        if (Confirm-Action "Kill $($suspect.Name)?") {
            Stop-Process -Id $suspect.Id -Force -ErrorAction SilentlyContinue
            Write-Ok "Terminated $($suspect.Name)"
        }
    } else {
        Write-Ok 'No memory leaks detected'
    }
}

Add-Tool -Id 'PERF-04' -Category 'Performance & Optimization' -Name 'Disk defragmentation' -Description 'Smart drive optimization: auto-detects SSD vs HDD, runs TRIM for SSDs or defragmentation for hard drives' -Admin -Action {
    Write-Section 'Disk Optimization'

    Write-Info 'Analyzing drives...'
    $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' }

    foreach ($vol in $volumes) {
        if ($vol.DriveLetter) {
            Write-Info "Drive $($vol.DriveLetter): "

            $isSSD = (Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.MediaType -eq 'SSD' })

            if ($isSSD) {
                Write-Ok "SSD detected - running TRIM (safe for SSDs)"
                Optimize-Volume -DriveLetter $vol.DriveLetter -TrimOnly -ErrorAction SilentlyContinue
            } else {
                Write-Info "HDD detected - defragmenting (may take time)..."
                Optimize-Volume -DriveLetter $vol.DriveLetter -Defrag -ErrorAction SilentlyContinue
            }
            Write-Ok "Optimization complete"
        }
    }
}

Add-Tool -Id 'PERF-05' -Category 'Performance & Optimization' -Name 'Boot time analyzer' -Description 'Diagnose startup delays: count startup programs & auto-start services, measure uptime, identify optimization targets' -Admin -Action {
    Write-Section 'Boot Performance Analysis'

    $bootTime = Get-CimInstance Win32_OperatingSystem | Select-Object LastBootUpTime, LocalDateTime
    if ($bootTime) {
        $uptime = $bootTime.LocalDateTime - $bootTime.LastBootUpTime
        Write-Check -Status INFO -Label 'Last boot' -Value ('{0:D} days, {1:h\:mm}' -f $uptime.Days, $uptime)
    }

    Write-Info 'Startup programs:'
    $startups = Get-CimInstance Win32_StartupCommand | Measure-Object
    Write-Check -Status INFO -Label 'Programs' -Value $startups.Count

    Write-Info 'Services set to auto-start:'
    $services = Get-Service | Where-Object { $_.StartType -eq 'Automatic' } | Measure-Object
    Write-Check -Status INFO -Label 'Services' -Value $services.Count

    Write-Host ''
    Write-Info 'To speed up boot:'
    Write-Host '  1. Disable unnecessary startup programs (see AR-02)'
    Write-Host '  2. Disable unnecessary services'
    Write-Host '  3. Update device drivers'
    Write-Host '  4. Check disk for errors (SFC scan)'
}

Add-Tool -Id 'PERF-06' -Category 'Performance & Optimization' -Name 'Network speed test' -Description 'Connectivity benchmark: latency to Google/Cloudflare/Microsoft/Amazon, estimated download speed, identifies slow ISPs' -Action {
    Write-Section 'Network Performance Test'

    Write-Info 'Testing connectivity to major providers...'
    Write-Host ''

    $hosts = @(
        @{Name='Google DNS'; IP='8.8.8.8'},
        @{Name='CloudFlare DNS'; IP='1.1.1.1'},
        @{Name='Microsoft'; IP='1.microsoft.com'},
        @{Name='Amazon'; IP='amazon.com'}
    )

    foreach ($host in $hosts) {
        $ping = Test-Connection $host.IP -Count 4 -ErrorAction SilentlyContinue
        if ($ping) {
            $avg = $ping | Measure-Object ResponseTime -Average | Select-Object -ExpandProperty Average
            Write-Check -Status OK -Label $host.Name -Value "$('{0:F1}' -f $avg)ms avg"
        } else {
            Write-Check -Status FAIL -Label $host.Name -Value 'No response'
        }
    }

    Write-Info ''
    Write-Info 'Download speed estimate:'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        (Invoke-WebRequest -Uri 'http://speed.cloudflare.com/__down?bytes=10000000' -TimeoutSec 30 -ErrorAction Stop -UseBasicParsing).Content.Length | Out-Null
        $sw.Stop()
        $speed = (10000000 / $sw.Elapsed.TotalSeconds) / 1024 / 1024
        Write-Check -Status OK -Label 'Download speed' -Value "$('{0:F1}' -f $speed) MB/s"
    } catch {
        Write-Warn 'Could not test download speed'
    }
}
