# Modules\23-Recommendations.ps1
# Category: Recommendations
# Performance diagnostics and improvement recommendations.

Add-Tool -Id 'REC-01' -Category 'Recommendations' -Name 'Runtime diagnostics' -Description 'Show execution time, errors, and memory usage this session' -Action {
    Write-Section 'Session Performance Metrics'
    Show-ExecutionStats

    Write-Section 'Resource Usage'
    Show-ResourceStats

    Write-Section 'Recent Errors (Last 24 Hours)'
    $errors = Get-ErrorLog -LastHours 24
    if ($errors.Count -eq 0) {
        Write-Ok 'No errors in last 24 hours'
    } else {
        $errors | Select-Object -First 5 | ForEach-Object {
            Write-Warn "$($_.ToolId): $($_.ErrorMessage)"
        }
        if ($errors.Count -gt 5) { Write-Info "...and $($errors.Count - 5) more" }
    }
}

Add-Tool -Id 'REC-02' -Category 'Recommendations' -Name 'Recommendations for this PC' -Description 'Automated improvement suggestions based on diagnostics' -Tags @('recommendations','optimization') -Action {
    Write-Section 'System Optimization Recommendations'

    $checks = @()

    # Check disk space
    $disks = Get-DiskSpace | Where-Object { $_.'Free %' -lt 20 }
    if ($disks.Count -gt 0) {
        $checks += "Disk space low on: $($disks.Drive -join ', '). Run NET-22 (Disk Cleanup)"
    }

    # Check for stopped auto services
    $stopped = @(Get-StoppedAutoServices)
    if ($stopped.Count -gt 0 -and $stopped.Count -le 3) {
        $checks += "Auto services not running: $(($stopped.Name -join ', ')). Run TSH-08 (Stopped Services)"
    }

    # Check pending reboot
    $reboot = @(Get-PendingReboot)
    if ($reboot.Count -gt 0) {
        $checks += "Restart pending due to: $($reboot -join ', '). Use System Settings or run MNT-18."
    }

    # Check updates
    $security = Get-SecurityAudit
    $lastUpdate = $security | Where-Object { $_.Check -eq 'Last update' }
    if ($lastUpdate -and $lastUpdate.Status -eq 'WARN') {
        $checks += "$($lastUpdate.Result). Run MNT-09 (Check Updates)"
    }

    # Check firewall
    $firewall = $security | Where-Object { $_.Check -eq 'Firewall' }
    if ($firewall -and $firewall.Status -eq 'WARN') {
        $checks += "Firewall: $($firewall.Result). Enable in Windows Defender."
    }

    # Check antivirus
    $av = $security | Where-Object { $_.Check -like '*Antivirus*' }
    if ($av -and $av.Status -eq 'WARN') {
        $checks += "Antivirus: $($av.Result). Install Microsoft Defender or third-party antivirus."
    }

    # Check SMBv1
    $smb = $security | Where-Object { $_.Check -like '*SMBv1*' }
    if ($smb -and $smb.Status -eq 'WARN') {
        $checks += "SMBv1 is enabled (security risk). Run SEC-10 (Disable SMBv1)."
    }

    # Check temp files
    $tempSize = Get-FolderSize $env:TEMP
    if ($tempSize -gt 500MB) {
        $checks += "Temp folder is large: $(Format-Bytes $tempSize). Run MNT-01 (Cleanup Temps)"
    }

    if ($checks.Count -eq 0) {
        Write-Ok 'No major issues detected. System appears healthy.'
    } else {
        Write-Warn "Found $($checks.Count) recommendation(s):"
        $checks | ForEach-Object { Write-Host "  • $_" -ForegroundColor Cyan }
    }
}

Add-Tool -Id 'REC-03' -Category 'Recommendations' -Name 'Performance baseline' -Description 'Capture current performance snapshot for comparison' -Action {
    Write-Section 'Capturing Performance Baseline'

    $baseline = @{
        Timestamp = Get-Date
        Memory = Get-MemoryMetrics
        Disk = Get-DiskSpace
        Network = Get-NetworkSummary
        Services = @(Get-StoppedAutoServices)
        Startup = @(Get-StartupItems)
        Processes = @(Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 10)
    }

    $file = Get-OutFile 'performance-baseline.json'
    $baseline | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $file -Encoding UTF8

    Write-Ok "Baseline saved: $file"
    Write-Info 'Run this tool again later and compare results to see changes'
}

Add-Tool -Id 'REC-04' -Category 'Recommendations' -Name 'Tool usage analytics' -Description 'Which tools you use most and their error rates' -Tags @('analytics','usage') -Action {
    Write-Section 'Tool Usage Analytics'

    $usage = Get-ToolUsage
    if ($usage.Count -eq 0) {
        Write-Info 'No usage data yet'
        return
    }

    Write-Section 'Most Used Tools'
    $usage | Select-Object -First 10 | ForEach-Object {
        $runs = $_.Count
        Write-Host "  $($_.ToolId.PadRight(10)) $($_.ToolName.PadRight(40)) Runs: $runs" -ForegroundColor Cyan
    }

    Write-Section 'Errors by Tool'
    $errors = $null
    if (Test-Path $Script:ErrorLogFile) {
        $errors = @(Get-Content -LiteralPath $Script:ErrorLogFile -Raw | ConvertFrom-Json)
    }

    if ($errors) {
        $errorsByTool = $errors | Group-Object ToolId | Sort-Object Count -Descending
        $errorsByTool | Select-Object -First 10 | ForEach-Object {
            Write-Warn "  $($_.Name.PadRight(10)) Errors: $($_.Count)"
        }
    }

    Write-Section 'Quick Stats'
    Write-Info "Total tool runs: $($usage | Measure-Object -Property Count -Sum | Select-Object -ExpandProperty Sum)"
    if ($errors) {
        Write-Info "Total errors: $($errors.Count)"
        Write-Info "Error rate: $(if ($usage.Count -gt 0) { [math]::Round($errors.Count / ($usage | Measure-Object -Property Count -Sum | Select-Object -ExpandProperty Sum) * 100, 2) }else{ '0' })%"
    }
}

Add-Tool -Id 'REC-05' -Category 'Recommendations' -Name 'Health check summary' -Description 'Complete system and toolkit health report' -Tags @('health','summary') -Action {
    Write-Section 'System Health Summary'

    $security = Get-SecurityAudit
    Show-Audit $security

    Write-Section 'Toolkit Health'
    $stats = Get-ExecutionStats
    $errors = $null
    if (Test-Path $Script:ErrorLogFile) {
        $errors = @(Get-Content -LiteralPath $Script:ErrorLogFile -Raw | ConvertFrom-Json)
    }

    Write-Check 'INFO' 'Tools Available' $Script:Tools.Count
    Write-Check 'INFO' 'Tools Run (Session)' $stats.ToolsRun
    Write-Check $(if ($stats.ToolsFailed -eq 0) { 'OK' } else { 'WARN' }) 'Failed Tools' $stats.ToolsFailed
    if ($errors) { Write-Check 'WARN' 'Total Errors' $errors.Count }

    Write-Section 'Disk Space'
    Get-DiskSpace | ForEach-Object {
        $status = $_.Status
        Write-Check $status "$($_.Drive)" "$($_.Free) free ($($_.'Free %')%)"
    }
}
