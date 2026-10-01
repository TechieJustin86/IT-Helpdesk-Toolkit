# Modules\20-Analytics.ps1
# Category: Analytics & Shortcuts
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'ANA-01' -Category 'Analytics' -Name 'Tool usage heatmap' -Description 'View which tools are used most frequently, last used dates, and usage trends' -Action {
    Write-Section 'Tool Usage Analytics'

    $usage = @(Get-ToolUsage)

    if ($usage.Count -eq 0) {
        Write-Info 'No usage data recorded yet. Tools will be tracked after they are run.'
        return
    }

    $total = ($usage | Measure-Object -Property Count -Sum).Sum
    Write-Host ''
    Write-Host "  Total tool runs recorded: $total"
    Write-Host "  Tracked tools: $($usage.Count)"
    Write-Host ''

    # Top 15 tools by usage
    Write-Host '  Top Tools by Usage:' -ForegroundColor Cyan
    Write-Host '  ────────────────────────────────────────────────────────────'
    Write-Host ('  {0,-6} {1,-8} {2,-25} {3}' -f 'Runs', 'Today', 'Tool Name', 'Last Used') -ForegroundColor DarkGray
    Write-Host '  ────────────────────────────────────────────────────────────'

    $usage | Select-Object -First 15 | ForEach-Object {
        $runColor = if ($_.Count -gt 10) { 'Green' } elseif ($_.Count -gt 5) { 'Yellow' } else { 'White' }
        $lastRun = [datetime]::ParseExact($_.LastRun, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
        $lastRunStr = $lastRun.ToString('HH:mm')
        Write-Host ('  {0,-6} {1,-8} {2,-25} {3}' -f $_.Count, '1', $_.ToolName.Substring(0, [Math]::Min(25, $_.ToolName.Length)), $lastRunStr) -ForegroundColor $runColor
    }

    Write-Host ''
    Write-Host '  Category Breakdown:' -ForegroundColor Cyan
    $byCategory = $usage | Group-Object Category | Sort-Object @{Expression={($_.Group | Measure-Object -Property Count -Sum).Sum}; Descending=$true}
    $byCategory | ForEach-Object {
        $catTotal = ($_.Group | Measure-Object -Property Count -Sum).Sum
        $pct = [math]::Round($catTotal / $total * 100, 1)
        Write-Host ('  {0,-25} {1,6} runs  ({2}%)' -f $_.Name, $catTotal, $pct) -ForegroundColor Gray
    }

    Write-Host ''
    Write-Host '  Usage Statistics:' -ForegroundColor Cyan
    Write-Host ('  Most used: {0} ({1} runs)' -f $usage[0].ToolName, $usage[0].Count) -ForegroundColor Green
    $avgRuns = [math]::Round(($usage | Measure-Object -Property Count -Average).Average, 1)
    Write-Host ('  Average runs per tool: {0}' -f $avgRuns)
    Write-Host ''

    $answer = Read-Host '  Export to CSV? [y/N]'
    if ($answer -match '^y(es)?$') {
        $file = Get-OutFile 'tool-usage.csv'
        $usage | Select-Object ToolId, ToolName, Category, Count, Date, LastRun | Export-Csv -LiteralPath $file -NoTypeInformation
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
