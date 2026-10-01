# Modules\20-Developer.ps1
# Category: Developer & Debugging
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'DEV-01' -Category 'Developer & Debugging' -Name 'Tool explorer' -Description 'Browse all tools with categories, descriptions, admin flags - searchable database of toolkit functionality' -Action {
    Write-Section 'Tool Explorer'

    Write-Info "Available tools by category:"
    Write-Host ''

    $categories = $Script:Tools | Group-Object Category | Sort-Object Name

    foreach ($cat in $categories) {
        $count = $cat.Count
        Write-Host "  $($cat.Name) ($count tools)" -ForegroundColor Cyan
        $cat.Group | ForEach-Object {
            $adminMark = if ($_.Admin) { ' [ADMIN]' } else { '' }
            Write-Host "    $($_.Id): $($_.Name)$adminMark" -ForegroundColor Gray
            Write-Host "      $($_.Description)" -ForegroundColor DarkGray
        }
        Write-Host ''
    }

    Write-Info "Total: $($Script:Tools.Count) tools in $($categories.Count) categories"
}

Add-Tool -Id 'DEV-02' -Category 'Developer & Debugging' -Name 'Module diagnostics' -Description 'Check which modules loaded successfully, show any syntax errors or loading warnings' -Action {
    Write-Section 'Module Diagnostics'

    $modulesDir = if ($PSCommandPath) { Split-Path -Path $PSCommandPath } else { Join-Path $Script:ToolkitDir 'Modules' }
    $moduleFiles = Get-ChildItem -Path $modulesDir -Filter *.ps1 | Sort-Object Name

    Write-Info "Checking all modules:"
    $errors = @()

    foreach ($file in $moduleFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw
            $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$null)
            $toolCount = (($content -split 'Add-Tool' | Measure-Object).Count - 1)
            Write-Check -Status OK -Label $file.Name -Value "$toolCount tools defined"
        } catch {
            Write-Check -Status FAIL -Label $file.Name -Value $_.Exception.Message
            $errors += "$($file.Name): $($_.Exception.Message)"
        }
    }

    Write-Host ''
    if ($errors.Count -eq 0) {
        Write-Ok "All modules loaded successfully!"
    } else {
        Write-Section 'Errors found:'
        $errors | ForEach-Object { Write-Err "  $_" }
    }
}

Add-Tool -Id 'DEV-03' -Category 'Developer & Debugging' -Name 'Tool statistics' -Description 'Analytics on toolkit: tools per category, admin vs user tools, module sizes - understand structure' -Action {
    Write-Section 'Toolkit Statistics'

    $totalTools = $Script:Tools.Count
    $adminTools = ($Script:Tools | Where-Object Admin).Count
    $userTools = $totalTools - $adminTools

    Write-Check -Status INFO -Label 'Total tools' -Value $totalTools
    Write-Check -Status INFO -Label 'Admin-only tools' -Value $adminTools
    Write-Check -Status INFO -Label 'User-accessible tools' -Value $userTools

    Write-Section 'Tools by category:'
    $Script:Tools | Group-Object Category | Sort-Object Name | ForEach-Object {
        $adminCount = ($_.Group | Where-Object Admin).Count
        $display = "$($_.Count) tools"
        if ($adminCount -gt 0) { $display += " ($adminCount admin)" }
        Write-Check -Status INFO -Label "  $($_.Name)" -Value $display
    }

    Write-Section 'Module file sizes:'
    $modulesDir = Split-Path -Path $PSCommandPath
    Get-ChildItem -Path $modulesDir -Filter *.ps1 | Sort-Object Name | ForEach-Object {
        $kb = [Math]::Round($_.Length / 1KB, 1)
        Write-Check -Status INFO -Label "  $($_.Name)" -Value "$kb KB"
    }
}

Add-Tool -Id 'DEV-04' -Category 'Developer & Debugging' -Name 'Run tool by ID' -Description 'Execute any tool by entering its ID directly - useful for scripting or testing specific tools' -Action {
    Write-Section 'Direct Tool Execution'

    $id = Read-Host '  Enter tool ID (or leave blank to list all)'

    if (-not $id) {
        $Script:Tools | Select-Object Id, Category, Name | Format-Table -AutoSize | Out-Host
        return
    }

    $tool = $Script:Tools | Where-Object Id -eq $id | Select-Object -First 1

    if (-not $tool) {
        Write-Err "Tool '$id' not found"
        Write-Info "Use this tool to list all available IDs"
        return
    }

    Write-Info "Running: $($tool.Category) > $($tool.Name)"
    Write-Info "Description: $($tool.Description)"
    Write-Host ''

    if ($tool.Admin -and -not (Test-IsAdmin)) {
        Write-Warn 'This tool requires Administrator rights'
        return
    }

    & $tool.Action 2>&1 | Out-Host
}

Add-Tool -Id 'DEV-05' -Category 'Developer & Debugging' -Name 'Search tools by name' -Description 'Find tools by keyword in name or description - locate the right tool quickly' -Action {
    Write-Section 'Tool Search'

    $search = Read-Host '  Search for (partial name or keyword)'
    if (-not $search) { return }

    $results = $Script:Tools | Where-Object { $_.Name -match $search -or $_.Description -match $search } | Sort-Object Category, Name

    if ($results.Count -eq 0) {
        Write-Info "No tools found matching '$search'"
        return
    }

    Write-Info "Found $($results.Count) matching tool(s):"
    Write-Host ''

    $results | ForEach-Object {
        $adminMark = if ($_.Admin) { ' [ADMIN]' } else { '' }
        Write-Host "  $($_.Id): $($_.Name)$adminMark" -ForegroundColor Cyan
        Write-Host "    $($_.Description)" -ForegroundColor Gray
        Write-Host ''
    }
}

Add-Tool -Id 'DEV-06' -Category 'Developer & Debugging' -Name 'Error log viewer' -Description 'View detailed error logs from failed tools - timestamps, stack traces, and error messages for debugging' -Action {
    Write-Section 'Error Log Viewer'

    $errorLogPath = $Script:ErrorLogFile

    if (-not (Test-Path $errorLogPath)) {
        Write-Info 'No errors logged yet - great job!'
        return
    }

    try {
        $errors = Get-Content -LiteralPath $errorLogPath -Raw | ConvertFrom-Json
    } catch {
        Write-Err "Could not read error log: $_"
        return
    }

    if (-not $errors) {
        Write-Info 'No errors in log'
        return
    }

    Write-Info "Found $(@($errors).Count) error(s) in log:"
    Write-Host ''

    # Display recent errors (last 10)
    @($errors) | Select-Object -Last 10 | ForEach-Object {
        Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor DarkRed
        Write-Check -Status FAIL -Label 'Time' -Value $_.Timestamp
        Write-Check -Status FAIL -Label 'Tool' -Value "$($_.ToolId): $($_.ToolName)"
        Write-Check -Status FAIL -Label 'User' -Value $_.User
        Write-Check -Status FAIL -Label 'Error Type' -Value $_.ErrorType
        Write-Host "Message:" -ForegroundColor Red
        Write-Host "  $($_.ErrorMessage)" -ForegroundColor Yellow

        if ($_.StackTrace) {
            Write-Host "Stack Trace:" -ForegroundColor Red
            $_.StackTrace -split "`n" | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
        }

        if ($_.InvocationInfo) {
            Write-Host "Location:" -ForegroundColor Red
            Write-Host "  File: $($_.InvocationInfo.ScriptName)" -ForegroundColor DarkYellow
            Write-Host "  Line: $($_.InvocationInfo.LineNumber)" -ForegroundColor DarkYellow
            Write-Host "  Code: $($_.InvocationInfo.Line)" -ForegroundColor DarkYellow
        }
        Write-Host ''
    }

    Write-Ok "Error log: $errorLogPath"
}

Add-Tool -Id 'DEV-07' -Category 'Developer & Debugging' -Name 'Error statistics' -Description 'Analyze error patterns - which tools fail most, error types, trends over time' -Action {
    Write-Section 'Error Statistics'

    $errorLogPath = $Script:ErrorLogFile

    if (-not (Test-Path $errorLogPath)) {
        Write-Info 'No errors logged yet'
        return
    }

    try {
        $errors = Get-Content -LiteralPath $errorLogPath -Raw | ConvertFrom-Json
    } catch {
        Write-Err "Could not read error log"
        return
    }

    $errors = @($errors)
    if ($errors.Count -eq 0) {
        Write-Info 'No errors recorded'
        return
    }

    Write-Check -Status INFO -Label 'Total errors' -Value $errors.Count
    Write-Host ''

    Write-Section 'Errors by Tool:'
    $errors | Group-Object ToolId | Sort-Object Count -Descending | ForEach-Object {
        Write-Check -Status INFO -Label "  $($_.Name)" -Value "$($_.Count) error(s)"
    }
    Write-Host ''

    Write-Section 'Errors by Type:'
    $errors | Group-Object ErrorType | Sort-Object Count -Descending | ForEach-Object {
        Write-Check -Status INFO -Label "  $($_.Name)" -Value "$($_.Count) occurrence(s)"
    }
    Write-Host ''

    Write-Section 'Most Recent Errors:'
    $errors | Select-Object -Last 5 | ForEach-Object {
        Write-Host "  [$($_.Timestamp)] $($_.ToolId): $($_.ErrorMessage)" -ForegroundColor Gray
    }

    Write-Info "Run DEV-06 (Error log viewer) for detailed error information"
}

Add-Tool -Id 'DEV-08' -Category 'Developer & Debugging' -Name 'Clear error log' -Description 'Clear all logged errors - start fresh error tracking' -Admin -Action {
    Write-Section 'Clear Error Log'

    $errorLogPath = $Script:ErrorLogFile

    if (-not (Test-Path $errorLogPath)) {
        Write-Info 'No error log to clear'
        return
    }

    if (-not (Confirm-Action 'Delete all error logs?')) {
        Write-Info 'Cancelled'
        return
    }

    try {
        Remove-Item -LiteralPath $errorLogPath -Force -ErrorAction Stop
        Write-Ok 'Error log cleared'
    } catch {
        Write-Err "Failed to clear error log: $_"
    }
}

Add-Tool -Id 'DEV-09' -Category 'Developer & Debugging' -Name 'View tool source (manual)' -Description 'Instructions for viewing tool source code in module files - see exactly what a tool does' -Action {
    Write-Section 'View Tool Source Code'

    Write-Info 'To view a tool source code:'
    Write-Host ''
    Write-Host '  1. Open Toolkit/Modules/ folder' -ForegroundColor Cyan
    Write-Host '  2. Find the module file (01-SystemInfo.ps1, 15-AutoRepair.ps1, etc)' -ForegroundColor Cyan
    Write-Host '  3. Open the file in your editor' -ForegroundColor Cyan
    Write-Host '  4. Search for "Add-Tool -Id" and find your tool by ID' -ForegroundColor Cyan
    Write-Host '  5. View the -Action { code block } to see what it does' -ForegroundColor Cyan
    Write-Host ''

    Write-Info 'Or use Dev-04 (Run tool by ID) then Dev-05 (Search) to locate tools'
    Write-Host ''

    $search = Read-Host '  Enter a tool ID to locate it (leave blank to skip)'
    if (-not $search) { return }

    $tool = $Script:Tools | Where-Object Id -eq $search | Select-Object -First 1
    if ($tool) {
        Write-Ok "Found: $($tool.Name)"
        Write-Info "Category: $($tool.Category)"
        Write-Info "Look in Toolkit/Modules/ for the matching category file"
    } else {
        Write-Err "Tool '$search' not found"
    }
}
