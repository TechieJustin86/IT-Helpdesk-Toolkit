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

Add-Tool -Id 'TKA-02' -Category 'Toolkit Administration' -Name 'Toolkit integrity check' -Description 'Required files present, every script parses, modules loaded, and tools registered per category' -Tags @('maintenance','integrity') -Aliases @('SET-04', 'DEV-02') -Action {
    # Merged from SET-04 "Verify toolkit integrity" and DEV-02 "Module diagnostics",
    # which ran the same per-module syntax loop. Both counted tools by counting the text
    # "Add-Tool" in each file, which reported 1 for 14-QuickLaunch (one Add-Tool in a
    # loop that registers 24); the counts below come from the live registry instead.
    Write-Section 'Verifying Toolkit Integrity'
    $problems = 0

    Write-Section 'Required files'
    $required = @(
        'HelpdeskToolkit.ps1', 'HelpdeskToolkit-GUI.ps1', 'Gui\GuiHost.ps1',
        'Core\Common.ps1', 'Core\Config.ps1', 'Core\Dependencies.ps1',
        'Core\Validation.ps1', 'Core\SecurityManagement.ps1', 'Core\Menu.ps1'
    )
    foreach ($rel in $required) {
        if (Test-Path -LiteralPath (Join-Path $Script:ToolkitDir $rel)) { Write-Check 'OK' $rel 'Found' }
        else { Write-Check 'FAIL' $rel 'Missing'; $problems++ }
    }
    $moduleFiles = @(Get-ChildItem -Path (Join-Path $Script:ToolkitDir 'Modules') -Filter *.ps1 -ErrorAction SilentlyContinue)
    Write-Check 'INFO' 'Modules folder' "$($moduleFiles.Count) module files"

    Write-Section 'Syntax'
    $scripts = @(Get-ChildItem -Path $Script:ToolkitDir -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)
    $syntaxErrors = 0
    foreach ($file in $scripts) {
        $tokenErrors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $file.FullName -Raw), [ref]$tokenErrors)
        if ($tokenErrors.Count) {
            $syntaxErrors++
            Write-Check 'FAIL' $file.Name "$($tokenErrors[0].Message) (line $($tokenErrors[0].Token.StartLine))"
        }
    }
    if ($syntaxErrors) { $problems += $syntaxErrors }
    else { Write-Check 'OK' 'Scripts parsed' "$($scripts.Count) files, no syntax errors" }

    Write-Section 'Loading'
    $loadErrors = @($Script:ModuleErrors | Where-Object { $_ })
    if ($loadErrors.Count) {
        foreach ($e in $loadErrors) { Write-Check 'FAIL' 'Module' $e }
        $problems += $loadErrors.Count
    } else {
        Write-Check 'OK' 'Modules' 'All loaded without errors'
    }

    Write-Section 'Registered tools'
    $Script:Tools | Group-Object Category | Sort-Object Name | ForEach-Object { Write-Check 'INFO' $_.Name "$($_.Count) tools" }
    Write-Check 'INFO' 'Total' "$($Script:Tools.Count) tools"

    Write-Section 'Result'
    if ($problems) {
        Write-Err "Integrity check FAILED - $problems problem(s) found"
        Write-Warn 'Restore from backup or re-download the toolkit'
    } else {
        Write-Ok 'Integrity check PASSED'
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
    $toolkitRoot = $Script:ToolkitDir
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
        $errorCount = @(Get-JsonLogEntries -Path $Script:ErrorLogFile).Count
        Write-Check 'WARN' 'Errors Logged' $errorCount
    }

    Write-Section 'Memory'
    $mem = Get-MemoryMetrics
    Write-Check 'INFO' 'Toolkit Process' "$($mem.ProcessMemoryMB)MB"
    Write-Check 'INFO' 'System Memory Used' "$($mem.MemoryUtilizationPercent)%"
}

Add-Tool -Id 'TKA-04' -Category 'Toolkit Administration' -Name 'Clear error log' -Description 'Remove error log entries older than 30 days, or clear the whole log' -Tags @('maintenance','cleanup') -Aliases @('DEV-08') -Action {
    # Merged from DEV-08 "Clear error log" (Developer & Debugging), which only offered
    # clearing everything; that is option 2 here.
    Write-Section 'Error Log Management'

    if (-not (Test-Path $Script:ErrorLogFile)) {
        Write-Info 'No error log found'
        return
    }

    $errors = @(Get-JsonLogEntries -Path $Script:ErrorLogFile)
    Write-Info "Current error log size: $($errors.Count) entries"

    $oldDate = (Get-Date).AddDays(-30)
    $toDelete = @($errors | Where-Object { [datetime]$_.Timestamp -lt $oldDate })

    Write-Host "  [1] Remove entries older than 30 days ($($toDelete.Count) of $($errors.Count))"
    Write-Host '  [2] Clear the whole error log'
    $c = Read-Host '  Choice'

    if ($c -eq '2') {
        if (-not (Confirm-Action "Delete all $($errors.Count) error log entries?")) { return }
        try {
            Remove-Item -LiteralPath $Script:ErrorLogFile -Force -ErrorAction Stop
            Write-Ok 'Error log cleared'
        } catch {
            Write-Err "Failed to clear error log: $($_.Exception.Message)"
        }
        return
    }
    if ($c -ne '1') { return }

    if ($toDelete.Count -eq 0) {
        Write-Ok 'No errors older than 30 days to clear'
        return
    }

    if (Confirm-Action "Delete $($toDelete.Count) old error entries?") {
        $keep = @($errors | Where-Object { [datetime]$_.Timestamp -ge $oldDate })

        if ($keep.Count -gt 0) {
            # Not `$keep | ConvertTo-Json`: piping writes a lone entry as a bare object
            # rather than an array, and the default depth of 2 drops InvocationInfo
            Set-JsonLogEntries -Path $Script:ErrorLogFile -Entries $keep -Depth 6
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

    $audit = @(Get-JsonLogEntries -Path $Script:AuditLog)
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
