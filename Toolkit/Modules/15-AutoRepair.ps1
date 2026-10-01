# Modules\15-AutoRepair.ps1
# Category: Auto-Repair
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'AR-01' -Category 'Auto-Repair' -Name 'One-click PC tune-up' -Description 'Interactive system cleanup: clear temp files/browser cache, empty recycle bin, restart Windows Update/networking/audio services' -Admin -Action {
    Write-Section 'Running Auto PC Tune-up'

    if (-not (Confirm-Action 'This will clear caches, temp files, and restart services. Continue?')) { return }

    $freed = 0

    # Clear temp files
    Write-Info 'Clearing temp files...'
    $tempPaths = @($env:TEMP, $env:WINDIR + '\Temp', $env:LOCALAPPDATA + '\Temp')
    foreach ($path in $tempPaths) {
        if (Test-Path $path) {
            $size = (Get-FolderSize $path)
            Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
            $freed += $size
            Write-Ok "Cleared $path"
        }
    }

    # Empty Recycle Bin
    Write-Info 'Emptying Recycle Bin...'
    try {
        $shell = New-Object -ComObject Shell.Application
        $shell.Namespace(10).Self.InvokeVerb('Empty Recycle Bin')
        Write-Ok 'Recycle Bin emptied'
    } catch { }

    # Clear browser caches
    Write-Info 'Clearing browser caches...'
    $browserPaths = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    )
    foreach ($path in $browserPaths) {
        if (Test-Path $path) {
            $size = (Get-FolderSize $path)
            Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
            $freed += $size
        }
    }
    Write-Ok 'Browser caches cleared'

    # Restart Windows Update service
    Write-Info 'Restarting Windows Update service...'
    try {
        Restart-Service wuauserv -Force -ErrorAction SilentlyContinue
        Write-Ok 'Windows Update restarted'
    } catch { }

    # Restart networking
    Write-Info 'Restarting network services...'
    try {
        Restart-Service Dnscache -Force -ErrorAction SilentlyContinue
        Restart-Service DHCP -Force -ErrorAction SilentlyContinue
        Write-Ok 'Network services restarted'
    } catch { }

    # Rebuild icon cache
    Write-Info 'Rebuilding icon cache...'
    try {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
        Start-Process explorer
        Write-Ok 'Icon cache rebuilt'
    } catch { }

    Write-Check -Status OK -Label 'Space freed' -Value (Format-Bytes $freed)
    Write-Section 'Auto tune-up complete! PC should feel faster.'
}

Add-Tool -Id 'AR-02' -Category 'Auto-Repair' -Name 'Disable startup bloat' -Description 'View and disable unnecessary programs launching at startup (Cortana, OneDrive, Skype, etc.) - safe to manage, Task Manager integrated' -Admin -Action {
    Write-Section 'Startup Program Manager'
    $startups = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User

    if (-not $startups) {
        Write-Info 'No startup programs found'
        return
    }

    Write-Info "Found $($startups.Count) startup programs"
    $startups | Format-Table Name, User -AutoSize | Out-Host

    Write-Host ''
    Write-Info 'Common bloat (safe to disable):'
    Write-Host '  Cortana, OneDrive, Skype, Adobe Reader, Quick Start'

    if (Confirm-Action 'Open Task Manager Startup tab?') {
        Start-Process taskmgr -ArgumentList '/tab', 'startup'
    }
}

Add-Tool -Id 'AR-03' -Category 'Auto-Repair' -Name 'Fix network issues' -Description 'Complete network reset: flush DNS cache, release/renew IP, reset TCP/IP stack, reset Winsock - fixes connectivity problems' -Admin -Action {
    Write-Section 'Network Reset'

    if (-not (Confirm-Action 'This will flush DNS, reset TCP/IP, and renew IP. Continue?')) { return }

    Write-Info 'Flushing DNS cache...'
    ipconfig /flushdns | Out-Host

    Write-Info 'Renewing IP address...'
    ipconfig /release | Out-Host
    ipconfig /renew | Out-Host

    Write-Info 'Resetting TCP/IP stack...'
    netsh int ip reset resetlog.txt | Out-Host

    Write-Info 'Resetting Winsock...'
    netsh winsock reset catalog | Out-Host

    Write-Ok 'Network reset complete - restart may be required'
}

Add-Tool -Id 'AR-04' -Category 'Auto-Repair' -Name 'Fix Windows Update' -Description 'Repair broken Windows Update: stop services, clear cache, restart services, trigger update check - resolves stuck/failed updates' -Admin -Action {
    Write-Section 'Windows Update Repair'

    if (-not (Confirm-Action 'This will reset Windows Update services. Continue?')) { return }

    Write-Info 'Stopping Windows Update services...'
    Stop-Service wuauserv, bits, cryptsvc -Force -ErrorAction SilentlyContinue

    Write-Info 'Clearing Windows Update cache...'
    Remove-Item "$env:WINDIR\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Info 'Restarting services...'
    Start-Service wuauserv, bits, cryptsvc -ErrorAction SilentlyContinue

    Write-Ok 'Windows Update reset complete'
    Write-Info 'Checking for updates...'
    powershell -Command "(New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow()"
    Write-Ok 'Update check initiated'
}

Add-Tool -Id 'AR-05' -Category 'Auto-Repair' -Name 'Diagnose & fix common issues' -Description 'Automatic PC health scan: checks disk space, Windows Update status, network, Defender, disk health - suggests specific fixes for detected problems' -Action {
    Write-Section 'Smart Diagnostics'

    $issues = @()
    $fixes = @()

    # Check disk space
    Write-Info 'Checking disk space...'
    $disk = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
    if ($disk -and ($disk.SizeRemaining / $disk.Size) -lt 0.1) {
        $issues += ‘Low disk space (< 10% free)’
        $fixes += ‘> Run AR-01 (Auto tune-up) to free space’
    }

    # Check Windows Update status
    Write-Info ‘Checking Windows Update...’
    $wu = Get-Service wuauserv -ErrorAction SilentlyContinue
    if ($wu.Status -ne ‘Running’) {
        $issues += ‘Windows Update service not running’
        $fixes += ‘> Run AR-04 (Fix Windows Update)’
    }

    # Check network
    Write-Info ‘Checking network...’
    if (-not (Test-Connection 8.8.8.8 -Count 1 -Quiet)) {
        $issues += ‘No internet connectivity’
        $fixes += ‘> Run AR-03 (Fix network issues)’
    }

    # Check Defender
    Write-Info ‘Checking Windows Defender...’
    $defender = Get-Service WinDefend -ErrorAction SilentlyContinue
    if ($defender.Status -ne ‘Running’) {
        $issues += ‘Windows Defender not running’
        $fixes += ‘> Start Windows Defender service’
    }

    # Check disk health
    Write-Info ‘Checking disk health...’
    try {
        $smart = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
        if ($smart -and $smart.PredictFailure) {
            $issues += ‘Disk failure predicted - URGENT’
            $fixes += ‘> Back up data immediately, consider replacement’
        }
    } catch { }

    # Display results
    Write-Host ''
    if ($issues.Count -eq 0) {
        Write-Ok "No issues detected - system is healthy!"
    } else {
        Write-Warn "Found $($issues.Count) issue(s):"
        Write-Host ''
        for ($i = 0; $i -lt $issues.Count; $i++) {
            Write-Host "  [$($i+1)] $($issues[$i])" -ForegroundColor Yellow
            Write-Host "      $($fixes[$i])" -ForegroundColor Cyan
        }
    }
}
