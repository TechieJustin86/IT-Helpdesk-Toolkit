# Modules\24-Toolkit-Admin.ps1
# Category: Toolkit Administration
# Configuration, maintenance, and troubleshooting for the toolkit itself.

Add-Tool -Id 'TKA-01' -Category 'Toolkit Administration' -Name 'Toolkit configuration' -Description 'View and modify toolkit settings' -Tags @('settings','configuration') -Action {
    Write-Section 'Toolkit Configuration'

    $config = Get-ToolkitConfig

    Write-Host ''
    Write-Section 'Timeout Settings (seconds)'
    $config.Timeouts | Format-Table -AutoSize | Out-Host

    Write-Section 'Resource Limits'
    $config.Resources | Format-Table -AutoSize | Out-Host

    Write-Section 'Performance Settings'
    $config.Performance | Format-Table -AutoSize | Out-Host

    Write-Section 'Security Settings'
    $config.Security | Format-Table -AutoSize | Out-Host

    Write-Info 'To modify settings, contact your administrator or edit Core\Config.ps1'
}

Add-Tool -Id 'TKA-02' -Category 'Toolkit Administration' -Name 'Toolkit integrity check' -Description 'Verify toolkit files are present and not corrupted' -Tags @('maintenance','integrity') -Action {
    Write-Section 'Verifying Toolkit Integrity'

    $coreFiles = @('Common.ps1', 'Config.ps1', 'Dependencies.ps1', 'Validation.ps1', 'Cache.ps1', 'ResourceManagement.ps1', 'ErrorHandling.ps1', 'SecurityManagement.ps1')
    $coreDir = Join-Path $PSScriptRoot 'Core'
    $modulesDir = Join-Path $PSScriptRoot 'Modules'

    $missing = @()
    foreach ($file in $coreFiles) {
        $path = Join-Path $coreDir $file
        if (-not (Test-Path $path)) {
            $missing += $file
            Write-Err "Missing: Core\$file"
        } else {
            Write-Ok "Found: Core\$file"
        }
    }

    $moduleCount = @(Get-ChildItem $modulesDir -Filter *.ps1).Count
    Write-Ok "Modules: $moduleCount files found"

    if ($missing.Count -eq 0) {
        Write-Section 'Result'
        Write-Ok 'Integrity check PASSED - all files present'
    } else {
        Write-Section 'Result'
        Write-Err "Integrity check FAILED - $($missing.Count) file(s) missing"
        Write-Warn 'Restore from backup or reinstall the toolkit'
    }
}

Add-Tool -Id 'TKA-03' -Category 'Toolkit Administration' -Name 'Toolkit diagnostics' -Description 'Detailed diagnostic report of toolkit health' -Tags @('diagnostics','troubleshooting') -Action {
    Write-Section 'Toolkit Diagnostics Report'
    Write-Info "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    Write-Section 'Version Information'
    Write-Check 'INFO' 'Toolkit Version' $Script:Version
    Write-Check 'INFO' 'PowerShell Version' $PSVersionTable.PSVersion.ToString()
    Write-Check 'INFO' 'Execution Policy' (Get-ExecutionPolicy)
    Write-Check 'INFO' 'Running as Admin' $(if (Test-IsAdmin) { 'Yes' } else { 'No' })

    Write-Section 'File Structure'
    $toolkitRoot = Split-Path $PSScriptRoot -Parent
    Write-Check 'INFO' 'Toolkit Root' $toolkitRoot
    Write-Check 'INFO' 'Core Directory' "$(Test-Path (Join-Path $toolkitRoot 'Core'))"
    Write-Check 'INFO' 'Modules Directory' "$(Test-Path (Join-Path $toolkitRoot 'Modules'))"
    Write-Check 'INFO' 'GUI Directory' "$(Test-Path (Join-Path $toolkitRoot 'Gui'))"

    Write-Section 'Tool Registration'
    Write-Check 'INFO' 'Total Tools' $Script:Tools.Count

    $categories = $Script:Tools | Group-Object Category | Sort-Object Count -Descending
    Write-Host ''
    Write-Info 'Tools by category:'
    $categories | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor Cyan }

    Write-Section 'Module Load Errors'
    if ($Script:ModuleErrors.Count -eq 0) {
        Write-Ok 'No module errors'
    } else {
        Write-Err "Found $($Script:ModuleErrors.Count) error(s):"
        $Script:ModuleErrors | ForEach-Object { Write-Err "  $_" }
    }

    Write-Section 'Storage Usage'
    $outDirSize = Get-FolderSize $Script:OutDir
    Write-Check 'INFO' 'Output Directory' $Script:OutDir
    Write-Check 'INFO' 'Size' $(Format-Bytes $outDirSize)

    if (Test-Path $Script:ErrorLogFile) {
        $errorCount = @(Get-Content -LiteralPath $Script:ErrorLogFile -Raw | ConvertFrom-Json).Count
        Write-Check 'WARN' 'Errors Logged' $errorCount
    }

    Write-Section 'Cache Status'
    $cacheStats = Get-CacheStats
    Write-Check 'INFO' 'Cache Items' $cacheStats.CacheSize
    Write-Check 'INFO' 'Valid Items' $cacheStats.ValidItems
    Write-Check 'INFO' 'Expired Items' $cacheStats.ExpiredItems
    Write-Check 'INFO' 'Compiled Regexes' $cacheStats.CompiledRegexes
}

Add-Tool -Id 'TKA-04' -Category 'Toolkit Administration' -Name 'Clear error log' -Description 'Remove old error logs to free space' -Tags @('maintenance','cleanup') -Action {
    Write-Section 'Error Log Management'

    if (-not (Test-Path $Script:ErrorLogFile)) {
        Write-Info 'No error log found'
        return
    }

    $errors = @(Get-Content -LiteralPath $Script:ErrorLogFile -Raw | ConvertFrom-Json)
    Write-Info "Current error log size: $($errors.Count) entries"

    $oldDate = (Get-Date).AddDays(-30)
    $toDelete = @($errors | Where-Object { [datetime]$_.Timestamp -lt $oldDate })

    if ($toDelete.Count -eq 0) {
        Write-Ok 'No errors older than 30 days to clear'
        return
    }

    Write-Warn "Found $($toDelete.Count) errors older than 30 days"
    if (Confirm-Action "Delete $($toDelete.Count) old error entries?") {
        $keep = @($errors | Where-Object { [datetime]$_.Timestamp -ge $oldDate })

        if ($keep.Count -gt 0) {
            $keep | ConvertTo-Json | Set-Content -LiteralPath $Script:ErrorLogFile -Force
        } else {
            Remove-Item -LiteralPath $Script:ErrorLogFile -Force -ErrorAction SilentlyContinue
        }

        Write-Ok "Deleted $($toDelete.Count) entries. $($keep.Count) entries retained."
    }
}

Add-Tool -Id 'TKA-05' -Category 'Toolkit Administration' -Name 'Security audit report' -Description 'View user actions and administrative changes' -Tags @('audit','security') -Action {
    Write-Section 'Security Audit Report'

    if (-not (Test-Path $Script:AuditLog)) {
        Write-Info 'No audit events logged yet'
        return
    }

    $audit = @(Get-Content -LiteralPath $Script:AuditLog -Raw | ConvertFrom-Json)
    Write-Info "Total audit events: $($audit.Count)"

    Write-Section 'Recent Actions (Last 24 Hours)'
    $last24 = @($audit | Where-Object { [datetime]$_.Timestamp -gt (Get-Date).AddDays(-1) } | Sort-Object Timestamp -Descending | Select-Object -First 10)

    if ($last24.Count -eq 0) {
        Write-Info 'No actions in last 24 hours'
    } else {
        $last24 | ForEach-Object {
            Write-Host "  $($_.Timestamp) | $($_.User) | $($_.Action) | $($_.Target)" -ForegroundColor Cyan
        }
    }

    Write-Section 'Summary by User'
    $audit | Group-Object User | Sort-Object Count -Descending | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) actions" -ForegroundColor Cyan
    }

    Write-Section 'Summary by Action'
    $audit | Group-Object Action | Sort-Object Count -Descending | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) events" -ForegroundColor Cyan
    }
}

Add-Tool -Id 'TKA-06' -Category 'Toolkit Administration' -Name 'About this toolkit' -Description 'Version, features, and system requirements' -Tags @('about','information') -Action {
    Write-Section 'IT Helpdesk Toolkit'
    Write-Host ''
    Write-Host '  Version: ' -ForegroundColor Cyan -NoNewline; Write-Host $Script:Version
    Write-Host '  Built for: Windows PowerShell 5.1 & PowerShell 7+'
    Write-Host '  Features: 250+ diagnostic and repair tools in 24 categories'
    Write-Host ''

    Write-Section 'Enhancement Features (v1.5+)'
    Write-Host '  ✓ Advanced error handling and logging'
    Write-Host '  ✓ Dependency tracking and validation'
    Write-Host '  ✓ Performance caching and optimization'
    Write-Host '  ✓ Resource monitoring and management'
    Write-Host '  ✓ Security audit trails'
    Write-Host '  ✓ Configuration management'
    Write-Host '  ✓ Input validation helpers'
    Write-Host '  ✓ Execution statistics tracking'
    Write-Host ''

    Write-Section 'System Info'
    $info = Get-SystemSummary
    Write-Check 'INFO' 'Computer' $info.'Computer name'
    Write-Check 'INFO' 'OS' $info.OS
    Write-Check 'INFO' 'Uptime' $info.Uptime
    Write-Check 'INFO' 'RAM' $info.'RAM total'

    Write-Section 'Troubleshooting'
    Write-Host '  • Run TKA-03 (Toolkit Diagnostics) to check health'
    Write-Host "  • Check $Script:LogDir\toolkit.log for details"
    Write-Host "  • Check $Script:LogDir\toolkit-errors.json for errors"
    Write-Host ''
}
