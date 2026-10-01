# Core\Menu.ps1
# Menu, search and tool runner.
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

#region ---------------------------------------------------------------- Menu / runner

function Invoke-Tool {
    param($Tool, [switch]$NoPause)
    Write-Host ''
    Write-Host ("  === {0}  {1} ===" -f $Tool.Id, $Tool.Name) -ForegroundColor Cyan
    if ($Tool.Description) { Write-Host "  $($Tool.Description)" -ForegroundColor DarkGray }
    Write-Host ''
    if ($Tool.Admin -and -not (Test-IsAdmin)) {
        Write-Warn 'This tool requires Administrator rights. Restart the toolkit as Administrator.'
    } else {
        Write-Log "RUN $($Tool.Id) $($Tool.Name)"
        Write-ToolUsage -ToolId $Tool.Id -ToolName $Tool.Name -Category $Tool.Category
        try { & $Tool.Action | Out-Host }
        catch { Write-Err $_.Exception.Message; Write-Log "ERROR $($Tool.Id): $($_.Exception.Message)" }
    }
    Write-Host ''
    if (-not $NoPause) { Wait-Key }
}

function Show-Banner {
    Clear-Host
    $role = if (Test-IsAdmin) { 'Administrator' } else { 'Standard user (limited)' }
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
    Write-Host "   IT HELPDESK TOOLKIT  v$Script:Version   ($($Script:Tools.Count) tools)" -ForegroundColor Cyan
    Write-Host ("   {0}  |  {1}\{2}  |  {3}" -f $env:COMPUTERNAME, $env:USERDOMAIN, $env:USERNAME, $role) -ForegroundColor Gray
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
}

function Get-ConsoleWidth {
    try { $Host.UI.RawUI.WindowSize.Width } catch { 120 }
}

function Show-ToolList {
    param([object[]]$Tools)
    $width = Get-ConsoleWidth
    for ($i = 0; $i -lt $Tools.Count; $i++) {
        $t = $Tools[$i]
        $flag = if ($t.Admin) { '*' } else { ' ' }
        $line = '  [{0,2}]{1} {2,-32} {3}' -f ($i + 1), $flag, $t.Name, $t.Description
        if ($line.Length -gt $width - 1) { $line = $line.Substring(0, $width - 4) + '...' }
        Write-Host $line
    }
}

function Find-Tools {
    param([object[]]$Tools, [string]$Query)
    $pattern = "*$([WildcardPattern]::Escape($Query))*"
    @($Tools | Where-Object { $_.Name -like $pattern -or $_.Description -like $pattern -or $_.Id -like $pattern })
}

function Show-Tools {
    param([string]$Title, [object[]]$Tools)
    $filter = ''
    while ($true) {
        $shown = if ($filter) { @(Find-Tools $Tools $filter) } else { @($Tools) }
        Show-Banner
        if ($filter) { Write-Host ("   $Title  -  search '$filter': $($shown.Count) of $($Tools.Count)") -ForegroundColor Yellow }
        else { Write-Host "   $Title" -ForegroundColor Yellow }
        Write-Host ''
        if ($shown.Count) { Show-ToolList $shown } else { Write-Warn 'No tools in this list match your search.' }
        Write-Host ''
        $keys = if ($filter) { '[S] New search   [C] Clear search   [B] Back' } else { '[S] Search this list   [B] Back' }
        Write-Host "   * = requires Administrator      $keys" -ForegroundColor DarkGray
        $c = Read-Host '  Choose'
        if ($c -match '^[bB]$' -or $c -eq '') { return }
        elseif ($c -match '^[sS]$') { $filter = "$(Read-Host '  Search for')".Trim() }
        elseif ($c -match '^[cC]$') { $filter = '' }
        elseif ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $shown.Count) { Invoke-Tool $shown[[int]$c - 1] }
    }
}

function Show-MainMenu {
    while ($true) {
        Show-Banner
        $fav = @($Script:Tools | Where-Object { $_.Id -in @($Script:Favorites) })
        Write-Host ('   [1] Favorites{0}({1} tools)' -f (' ' * 20), $fav.Count)
        Write-Host ('   [2] All tools{0}({1} tools)' -f (' ' * 20), $Script:Tools.Count)
        Write-Host ''
        for ($i = 0; $i -lt $Script:Categories.Count; $i++) {
            $cat = $Script:Categories[$i]
            $n = @($Script:Tools | Where-Object Category -eq $cat).Count
            Write-Host ('   [{0}] {1,-26} ({2} tools)' -f ($i + 3), $cat, $n)
        }
        Write-Host ''
        Write-Host '   [S] Search all tools   [R] Run by ID   [O] Output folder   [Q] Quit' -ForegroundColor DarkGray
        $c = Read-Host '  Choose'
        if ($c -match '^[qQ]$') { return }
        elseif ($c -match '^1$') {
            if ($fav.Count) { Show-Tools -Title 'Favorites' -Tools $fav } else { Write-Warn 'No favorite tools yet.'; Wait-Key }
        }
        elseif ($c -match '^2$') {
            Show-Tools -Title 'All tools' -Tools $Script:Tools
        }
        elseif ($c -match '^\d+$' -and [int]$c -ge 3 -and [int]$c -le ($Script:Categories.Count + 2)) {
            $cat = $Script:Categories[[int]$c - 3]
            Show-Tools -Title $cat -Tools @($Script:Tools | Where-Object Category -eq $cat)
        }
        elseif ($c -match '^[sS]$') {
            $q = "$(Read-Host '  Search all tools for')".Trim()
            if ($q) {
                $hits = @(Find-Tools $Script:Tools $q)
                if ($hits.Count) { Show-Tools -Title "Search: $q" -Tools $hits } else { Write-Warn 'No matches.'; Wait-Key }
            }
        }
        elseif ($c -match '^[rR]$') {
            $id = Read-Host '  Tool ID (e.g. NET-02)'
            $t = $Script:Tools | Where-Object Id -eq $id | Select-Object -First 1
            if ($t) { Invoke-Tool $t } else { Write-Warn 'Unknown ID.'; Wait-Key }
        }
        elseif ($c -match '^[oO]$') {
            if (-not (Test-Path $Script:OutDir)) { New-Item -ItemType Directory -Path $Script:OutDir -Force | Out-Null }
            Invoke-Item $Script:OutDir
        }
    }
}

#endregion
