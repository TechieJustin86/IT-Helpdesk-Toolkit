<#
.SYNOPSIS
    IT Helpdesk Toolkit - an all-in-one, menu-driven PowerShell toolbox for Windows support.

.DESCRIPTION
    Diagnostic, repair, security, user-management and reporting tools grouped into categories.
    Run it interactively for the menu, or call a single tool by ID for scripting.

    Source layout:
        Core\Common.ps1     shared helpers and Add-Tool
        Core\Menu.ps1       menu and tool runner
        Modules\*.ps1       one file per menu category, loaded in file-name order

    Run Build-SingleFile.ps1 to produce dist\HelpdeskToolkit.ps1, a standalone single-file copy.

.PARAMETER Run
    Run a single tool by ID (e.g. NET-03) or exact name, then exit.

.PARAMETER List
    List every tool with its ID and exit.

.PARAMETER NoElevate
    Do not offer to relaunch as Administrator.

.EXAMPLE
    .\HelpdeskToolkit.ps1
.EXAMPLE
    .\HelpdeskToolkit.ps1 -Run SYS-01
.EXAMPLE
    .\HelpdeskToolkit.ps1 -List
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Run,
    [switch]$List,
    [switch]$NoElevate
)

# Version, output folder and the tool list are defined in Core\Common.ps1

#region BUILD:SOURCES - Build-SingleFile.ps1 replaces this region with the contents of Core\ and Modules\
# Load core modules in dependency order
$coreOrder = @('Common.ps1', 'Config.ps1', 'Dependencies.ps1', 'Validation.ps1', 'Cache.ps1', 'ResourceManagement.ps1', 'ErrorHandling.ps1', 'SecurityManagement.ps1')
foreach ($file in $coreOrder) {
    $filePath = Join-Path (Join-Path $PSScriptRoot 'Core') $file
    if (Test-Path $filePath) {
        try {
            . $filePath
        } catch {
            Write-Warning "Failed to load core module $file : $($_.Exception.Message)"
        }
    }
}

# Load any additional Core files not in core order (for extensibility)
foreach ($file in @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Core') -Filter *.ps1 | Where-Object { $_.Name -notin $coreOrder } | Sort-Object Name)) {
    try {
        . $file.FullName
    } catch {
        Write-Warning "Failed to load core module $($file.Name) : $($_.Exception.Message)"
    }
}

# Load feature modules
foreach ($file in @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Modules') -Filter *.ps1 | Sort-Object Name)) {
    try { . $file.FullName }
    catch { $Script:ModuleErrors += "$($file.Name): $($_.Exception.Message)" }
}
#endregion BUILD:SOURCES

# Menu categories in alphabetical order
$Script:Categories = @($Script:Tools | ForEach-Object Category | Select-Object -Unique | Sort-Object)

foreach ($e in $Script:ModuleErrors) { Write-Warn "Module skipped - $e" }

#region ---------------------------------------------------------------- Entry point

if ($List) {
    $Script:Tools | Select-Object Id, Category, Name, @{n = 'Admin'; e = { if ($_.Admin) { 'Yes' } else { '' } } }, Description | Format-Table -AutoSize | Out-Host
    return
}

if ($Run) {
    $tool = $Script:Tools | Where-Object { $_.Id -eq $Run -or $_.Name -eq $Run } | Select-Object -First 1
    if (-not $tool) { Write-Err "No tool '$Run'. Use -List to see IDs."; exit 1 }
    Invoke-Tool $tool -NoPause
    return
}

if ($Script:ModuleErrors.Count) { Start-Sleep -Seconds 3 }

if (-not (Test-IsAdmin) -and -not $NoElevate) {
    Write-Host ''
    Write-Warn 'Not running as Administrator - some tools will be unavailable.'
    $a = Read-Host '  Relaunch as Administrator? [Y/n]'
    if ($a -notmatch '^(n|no)$') {
        try {
            $exe = (Get-Process -Id $PID).Path
            Start-Process -FilePath $exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") -ErrorAction Stop
            return
        } catch { Write-Warn 'Elevation cancelled - continuing with limited rights.'; Start-Sleep -Seconds 1 }
    }
}

try { $Host.UI.RawUI.WindowTitle = "IT Helpdesk Toolkit - $env:COMPUTERNAME" } catch { }
Show-MainMenu

#endregion
