<#
.SYNOPSIS
    Loads every Core and feature module and checks that the tool registry is sound.

.DESCRIPTION
    Catches the mistakes that syntax checking cannot see: a module that throws while
    loading, a duplicate or malformed tool ID, a tool with no action, and tool counts
    that have drifted away from what README.md advertises.

    Needs no modules from the gallery, so it runs the same way locally and in CI.
    Exits 0 when everything passes, 1 on the first category of failure.

.EXAMPLE
    .\Tests\Test-ToolRegistration.ps1
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$failures = New-Object System.Collections.Generic.List[string]
function Add-Failure { param([string]$Message) $failures.Add($Message) }

$repoRoot   = Split-Path $PSScriptRoot -Parent
$toolkitDir = Join-Path $repoRoot 'Toolkit'
$coreDir    = Join-Path $toolkitDir 'Core'
$modulesDir = Join-Path $toolkitDir 'Modules'

Write-Host ''
Write-Host 'Tool registration test' -ForegroundColor Cyan
Write-Host '----------------------' -ForegroundColor DarkGray

# --- Load, mirroring the order in HelpdeskToolkit.ps1 ----------------------

$Script:ModuleErrors = @()

$coreOrder = @('Common.ps1', 'Config.ps1', 'Dependencies.ps1', 'Validation.ps1', 'SecurityManagement.ps1')

foreach ($file in $coreOrder) {
    $path = Join-Path $coreDir $file
    if (-not (Test-Path -LiteralPath $path)) { Add-Failure "Core file missing: $file"; continue }
    try { . $path } catch { Add-Failure "Core file failed to load: $file - $($_.Exception.Message)" }
}

foreach ($file in @(Get-ChildItem -Path $coreDir -Filter *.ps1 | Where-Object { $_.Name -notin $coreOrder } | Sort-Object Name)) {
    try { . $file.FullName } catch { Add-Failure "Core file failed to load: $($file.Name) - $($_.Exception.Message)" }
}

foreach ($file in @(Get-ChildItem -Path $modulesDir -Filter *.ps1 | Sort-Object Name)) {
    try { . $file.FullName } catch { Add-Failure "Module failed to load: $($file.Name) - $($_.Exception.Message)" }
}

foreach ($moduleError in $Script:ModuleErrors) { Add-Failure "Module reported an error: $moduleError" }

# --- The registry ----------------------------------------------------------

# Enumerate through the pipeline, not @($Script:Tools): Windows PowerShell 5.1 throws
# "Argument types do not match" when array-wrapping a List[object] (a List[string] is fine).
$tools = @($Script:Tools | ForEach-Object { $_ })

if ($tools.Count -eq 0) {
    Add-Failure 'No tools registered at all - the load order is probably broken.'
} else {
    Write-Host ("  registered: {0} tools in {1} categories" -f $tools.Count,
        @($tools | ForEach-Object Category | Select-Object -Unique).Count)
}

# Duplicate IDs: two tools with one ID means -Run and the menu disagree
$duplicates = @($tools | Group-Object Id | Where-Object Count -gt 1)
foreach ($d in $duplicates) { Add-Failure "Duplicate tool ID '$($d.Name)' ($($d.Count) tools)" }

foreach ($tool in $tools) {
    if (-not $tool.Id)                        { Add-Failure "Tool with no ID: '$($tool.Name)'" ; continue }
    if ($tool.Id -notmatch '^[A-Z0-9]+-\d+$') { Add-Failure "Malformed tool ID: '$($tool.Id)' (expected PREFIX-01)" }
    if (-not $tool.Name)                      { Add-Failure "$($tool.Id) has no Name" }
    if (-not $tool.Category)                  { Add-Failure "$($tool.Id) has no Category" }
    if ($tool.Action -isnot [scriptblock])    { Add-Failure "$($tool.Id) has no runnable Action" }
}

# --- Aliases (former IDs of merged tools) ----------------------------------
# An alias that equals a live ID would make one of the two tools unreachable by ID,
# and one claimed by two tools would resolve unpredictably.

$liveIds = @{}
foreach ($tool in $tools) { $liveIds[$tool.Id] = $true }
$aliasOwner = @{}
$aliasCount = 0

foreach ($tool in $tools) {
    foreach ($alias in @($tool.Aliases)) {
        if (-not $alias) { continue }
        $aliasCount++
        if ($alias -notmatch '^[A-Z0-9]+-\d+$') { Add-Failure "$($tool.Id) has a malformed alias '$alias'" }
        if ($liveIds.ContainsKey($alias))       { Add-Failure "$($tool.Id) alias '$alias' collides with a live tool ID" }
        if ($aliasOwner.ContainsKey($alias))    { Add-Failure "Alias '$alias' is claimed by both $($aliasOwner[$alias]) and $($tool.Id)" }
        else                                    { $aliasOwner[$alias] = $tool.Id }

        $resolved = Get-ToolById $alias
        if (-not $resolved -or $resolved.Id -ne $tool.Id) { Add-Failure "Alias '$alias' does not resolve to $($tool.Id)" }
    }
}
if ($aliasCount) { Write-Host "  aliases: $aliasCount former ID(s) declared" -ForegroundColor DarkGray }

# --- Helpers the modules rely on ------------------------------------------

foreach ($fn in @('Add-Tool', 'Get-ToolById', 'Resolve-ToolId', 'Confirm-Action', 'Confirm-DestructiveAction',
                  'Invoke-External', 'Select-FromList', 'Write-ErrorLog', 'Write-Log', 'Test-IsAdmin')) {
    if (-not (Get-Command $fn -CommandType Function -ErrorAction SilentlyContinue)) {
        Add-Failure "Helper function not available after load: $fn"
    }
}

# --- Counts advertised in README.md ---------------------------------------
# This is what stops the documented totals drifting away from the code again.

$readme = Join-Path $repoRoot 'README.md'
if (Test-Path -LiteralPath $readme) {
    $text = Get-Content -LiteralPath $readme -Raw
    $match = [regex]::Match($text, '(?<tools>\d+)\s*\*{0,2}\s*tools?\s*\*{0,2}\s*in\s*\*{0,2}\s*(?<cats>\d+)\s*\*{0,2}\s*categor')

    if (-not $match.Success) {
        Write-Host '  README.md: no "N tools in N categories" claim found - skipping that check' -ForegroundColor DarkYellow
    } else {
        $claimedTools = [int]$match.Groups['tools'].Value
        $claimedCats  = [int]$match.Groups['cats'].Value
        $actualCats   = @($tools | ForEach-Object Category | Select-Object -Unique).Count

        if ($claimedTools -ne $tools.Count) { Add-Failure "README.md says $claimedTools tools, code registers $($tools.Count)" }
        if ($claimedCats  -ne $actualCats)  { Add-Failure "README.md says $claimedCats categories, code registers $actualCats" }
        if ($claimedTools -eq $tools.Count -and $claimedCats -eq $actualCats) {
            Write-Host "  README.md counts match the code ($claimedTools / $claimedCats)" -ForegroundColor DarkGray
        }
    }
}

# --- Result ----------------------------------------------------------------

Write-Host ''
if ($failures.Count) {
    Write-Host "FAILED - $($failures.Count) problem(s):" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Yellow }
    Write-Host ''
    exit 1
}

Write-Host 'PASSED' -ForegroundColor Green
Write-Host ''
exit 0
