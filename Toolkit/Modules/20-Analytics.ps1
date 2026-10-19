# Modules\20-Analytics.ps1
# Category: Analytics & Shortcuts
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'ANA-01' -Category 'Analytics' -Name 'Tool usage analytics' -Description 'Most-used tools, runs today, last used, usage by category, and errors per tool' -Aliases @('REC-04') -Action {
    # Merged from REC-04 "Tool usage analytics", which printed the same report under the
    # same section title; its errors-per-tool and error rate are the last section here.
    Write-Section 'Tool Usage Analytics'

    $rows = @(Get-ToolUsage)
    if ($rows.Count -eq 0) {
        Write-Info 'No usage data recorded yet. Tools will be tracked after they are run.'
        return
    }

    # The usage log holds one row per tool per day, so roll it up per tool. Both former
    # tools listed the raw rows - a tool used on three days appeared three times and
    # "tracked tools" counted rows - and the "Today" column here was a hard-coded 1.
    # Rows logged under a retired ID are folded into the tool that replaced it, and named
    # after the current tool, so a merged tool's history is not split across two rows.
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $perTool = @($rows | Where-Object { $_.ToolId } | Group-Object { Resolve-ToolId $_.ToolId } | ForEach-Object {
        $days = @($_.Group)
        $latest = $days | Sort-Object { "$($_.LastRun)" } -Descending | Select-Object -First 1
        $current = Get-ToolById $_.Name
        [pscustomobject]@{
            ToolId   = $_.Name
            ToolName = if ($current) { $current.Name } else { "$($latest.ToolName)" }
            Category = if ($current) { $current.Category } else { "$($latest.Category)" }
            Runs     = [int](($days | Measure-Object -Property Count -Sum).Sum)
            Today    = [int](($days | Where-Object { $_.Date -eq $today } | Measure-Object -Property Count -Sum).Sum)
            LastRun  = "$($latest.LastRun)"
        }
    } | Sort-Object Runs -Descending)
    $total = [int](($perTool | Measure-Object -Property Runs -Sum).Sum)

    Write-Host ''
    Write-Host "  Total tool runs recorded: $total"
    Write-Host "  Tools used: $($perTool.Count)"
    Write-Host ''

    Write-Host '  Top Tools by Usage:' -ForegroundColor Cyan
    Write-Host '  ──────────────────────────────────────────────────────────────────────'
    Write-Host ('  {0,-6} {1,-6} {2,-10} {3,-32} {4}' -f 'Runs', 'Today', 'ID', 'Tool', 'Last used') -ForegroundColor DarkGray
    Write-Host '  ──────────────────────────────────────────────────────────────────────'
    $perTool | Select-Object -First 15 | ForEach-Object {
        $color = if ($_.Runs -gt 10) { 'Green' } elseif ($_.Runs -gt 5) { 'Yellow' } else { 'White' }
        $name = $_.ToolName
        if ($name.Length -gt 32) { $name = $name.Substring(0, 29) + '...' }
        $last = if ($_.LastRun.Length -ge 16) { $_.LastRun.Substring(0, 16) } else { $_.LastRun }
        Write-Host ('  {0,-6} {1,-6} {2,-10} {3,-32} {4}' -f $_.Runs, $_.Today, $_.ToolId, $name, $last) -ForegroundColor $color
    }

    Write-Host ''
    Write-Host '  Category Breakdown:' -ForegroundColor Cyan
    $perTool | Group-Object Category | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Runs = [int](($_.Group | Measure-Object -Property Runs -Sum).Sum) }
    } | Sort-Object Runs -Descending | ForEach-Object {
        $pct = if ($total) { [math]::Round($_.Runs / $total * 100, 1) } else { 0 }
        Write-Host ('  {0,-26} {1,6} runs  ({2}%)' -f $_.Name, $_.Runs, $pct) -ForegroundColor Gray
    }

    Write-Host ''
    Write-Host '  Errors by Tool:' -ForegroundColor Cyan
    $errors = @(Get-JsonLogEntries -Path $Script:ErrorLogFile | Where-Object { $_.ToolId })
    if ($errors.Count) {
        $errors | Group-Object { Resolve-ToolId $_.ToolId } | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
            Write-Host ('  {0,-10} {1} error(s)' -f $_.Name, $_.Count) -ForegroundColor Yellow
        }
        $rate = if ($total) { [math]::Round($errors.Count / $total * 100, 1) } else { 0 }
        Write-Host ('  Error rate: {0}% ({1} logged errors / {2} runs)' -f $rate, $errors.Count, $total)
    } else {
        Write-Host '  No errors logged.' -ForegroundColor Green
    }
    Write-Host ''

    if (Confirm-Action 'Export to CSV?') {
        $file = Get-OutFile 'tool-usage.csv'
        $perTool | Select-Object ToolId, ToolName, Category, Runs, Today, LastRun | Export-Csv -LiteralPath $file -NoTypeInformation
        Write-Ok "Exported to $file"
    }
}

Add-Tool -Id 'ANA-02' -Category 'Analytics' -Name 'Keyboard shortcuts' -Description 'Display all GUI keyboard shortcuts and tips for power users' -Action {
    Write-Section 'Keyboard Shortcuts'
    Write-Host ''
    Write-Host '  GUI Shortcuts:' -ForegroundColor Cyan
    Write-Host '  ────────────────────────────────────────────────────────────'
    Write-Host '  Ctrl+F          Search tools (in current category or all)' -ForegroundColor Gray
    Write-Host '  Ctrl+B          Toggle favorite for selected tool' -ForegroundColor Gray
    Write-Host '  Ctrl+D          Toggle dark/light theme' -ForegroundColor Gray
    Write-Host '  Ctrl+E          Open output folder' -ForegroundColor Gray
    Write-Host '  Enter / F5      Run selected tool' -ForegroundColor Gray
    Write-Host '  Esc             Clear search box' -ForegroundColor Gray
    Write-Host '  Ctrl+L          Clear output pane' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  Tips:' -ForegroundColor Cyan
    Write-Host '  • Star your favorite tools to quick-access them at the top' -ForegroundColor Gray
    Write-Host '  • Use search to find tools across all categories instantly' -ForegroundColor Gray
    Write-Host '  • Background runs stay responsive; long jobs show progress in the status bar' -ForegroundColor Gray
    Write-Host '  • Click "Stop" to cancel long-running operations (SFC, DISM, etc.)' -ForegroundColor Gray
    Write-Host '  • All output is saved to Documents\HelpdeskToolkit automatically' -ForegroundColor Gray
    Write-Host '  • Right-click any tool to star it or copy its ID' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  Console Shortcuts:' -ForegroundColor Cyan
    Write-Host '  ────────────────────────────────────────────────────────────'
    Write-Host '  S                Search within a category' -ForegroundColor Gray
    Write-Host '  S (from menu)    Search all tools' -ForegroundColor Gray
    Write-Host '  Numeric input    Select a tool or category' -ForegroundColor Gray
    Write-Host '  Blank + Enter    Return to previous menu' -ForegroundColor Gray
    Write-Host ''
}

Add-Tool -Id 'ANA-03' -Category 'Analytics' -Name 'Reset usage analytics' -Description 'Clear all stored tool usage data to start fresh tracking' -Action {
    Write-Section 'Reset Tool Usage Analytics'
    Write-Warn 'This will permanently delete all recorded tool usage data.'
    $answer = Read-Host '  Continue? [y/N]'
    if ($answer -match '^y(es)?$') {
        $usageFile = Join-Path $Script:OutDir 'toolkit-usage.json'
        if (Test-Path $usageFile) {
            Remove-Item -LiteralPath $usageFile -Force
            Write-Ok 'Tool usage analytics cleared.'
        } else {
            Write-Info 'No usage data to clear.'
        }
    } else {
        Write-Info 'Cancelled.'
    }
}
