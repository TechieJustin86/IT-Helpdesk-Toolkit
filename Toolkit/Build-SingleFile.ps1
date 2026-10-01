<#
.SYNOPSIS
    Builds standalone single-file copies of the toolkit into dist\:
      dist\HelpdeskToolkit.ps1      console version (Core\ and Modules\ inlined)
      dist\HelpdeskToolkit-GUI.ps1  GUI version (Core\, Modules\ and Gui\GuiHost.ps1 embedded)

.DESCRIPTION
    Every source file is syntax-checked first; the build stops without writing anything if one fails.
    Outputs are written as UTF-8 with BOM so Windows PowerShell 5.1 reads them correctly.
    Keep both dist files together: the GUI's "Console version" button opens the console copy next to it.

.PARAMETER OutDir
    Folder to write the builds to. Default: dist

.EXAMPLE
    .\Build-SingleFile.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
# $PSScriptRoot isn't available in param defaults on Windows PowerShell 5.1
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot 'dist' }

$launcher    = Join-Path $PSScriptRoot 'HelpdeskToolkit.ps1'
$guiLauncher = Join-Path $PSScriptRoot 'HelpdeskToolkit-GUI.ps1'
$guiHost     = Get-Item (Join-Path $PSScriptRoot 'Gui\GuiHost.ps1')
$core        = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Core') -Filter *.ps1 | Sort-Object Name)
$modules     = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Modules') -Filter *.ps1 | Sort-Object Name)
$utf8Bom     = New-Object System.Text.UTF8Encoding($true)
$stamp       = Get-Date -Format 'yyyy-MM-dd HH:mm'

function Test-Syntax {
    param([string]$Path)
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
    foreach ($e in $errors) { Write-Host ("  {0}:{1}  {2}" -f (Split-Path $Path -Leaf), $e.Extent.StartLineNumber, $e.Message) -ForegroundColor Red }
    return (-not $errors)
}

# Swaps the text between "#region BUILD:<Tag>" and "#endregion BUILD:<Tag>" for $Replacement
function Set-BuildRegion {
    param([string]$Text, [string]$Tag, [string]$Replacement, [string]$Source)
    $startTag = "#region BUILD:$Tag"
    $endTag   = "#endregion BUILD:$Tag"
    $start = $Text.IndexOf($startTag)
    $end   = $Text.IndexOf($endTag)
    if ($start -lt 0 -or $end -lt $start) { throw "Build markers for $Tag not found in $Source" }
    $Text.Substring(0, $start) + $Replacement + $Text.Substring($end + $endTag.Length)
}

function Write-Build {
    param([string]$Path, [string]$Text)
    [IO.File]::WriteAllText($Path, $Text, $utf8Bom)
    if (-not (Test-Syntax $Path)) { throw "Build output has syntax errors: $Path" }
    Write-Host ("  [+] Built {0} ({1:N0} KB)" -f $Path, ((Get-Item $Path).Length / 1KB)) -ForegroundColor Green
}

# 1. Syntax-check every source file
$ok = $true
foreach ($f in @($launcher, $guiLauncher, $guiHost.FullName) + $core.FullName + $modules.FullName) {
    if (-not (Test-Syntax $f)) { $ok = $false }
}
if (-not $ok) { throw 'Build failed: fix the syntax errors above.' }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

# 2. Console build: inline the sources as code
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# ===== Built $stamp from $($core.Count) core and $($modules.Count) module files. Edit the source files, not this one. =====")
foreach ($f in $core) {
    [void]$sb.AppendLine("`r`n# ----- Source: Core\$($f.Name) -----")
    [void]$sb.AppendLine([IO.File]::ReadAllText($f.FullName).TrimEnd())
}
foreach ($f in $modules) {
    # try{} keeps a module that fails at load time from stopping the rest (same as the launcher)
    [void]$sb.AppendLine("`r`n# ----- Source: Modules\$($f.Name) -----")
    [void]$sb.AppendLine('try {')
    [void]$sb.AppendLine([IO.File]::ReadAllText($f.FullName).TrimEnd())
    [void]$sb.AppendLine("} catch { `$Script:ModuleErrors += '$($f.Name): ' + `$_.Exception.Message }")
}
$console = Set-BuildRegion -Text ([IO.File]::ReadAllText($launcher)) -Tag 'SOURCES' -Replacement $sb.ToString() -Source $launcher
Write-Build -Path (Join-Path $OutDir 'HelpdeskToolkit.ps1') -Text $console

# 3. GUI build: embed the sources as base64 text; the GUI loads them into its background runspace
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# ===== Built $stamp. Embedded copies of Core\, Modules\ and Gui\GuiHost.ps1. Edit the source files, not this one. =====")
[void]$sb.AppendLine('function Get-ToolkitSources {')
foreach ($entry in @($core | ForEach-Object { @{ Name = "Core\$($_.Name)"; File = $_ } }) +
                   @($modules | ForEach-Object { @{ Name = "Modules\$($_.Name)"; File = $_ } }) +
                   @(@{ Name = 'Gui\GuiHost.ps1'; File = $guiHost })) {
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($entry.File.FullName)))
    [void]$sb.AppendLine("    @{ Name = '$($entry.Name)'; Text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64')) }")
}
[void]$sb.AppendLine('}')
$gui = Set-BuildRegion -Text ([IO.File]::ReadAllText($guiLauncher)) -Tag 'GUISOURCES' -Replacement $sb.ToString() -Source $guiLauncher
Write-Build -Path (Join-Path $OutDir 'HelpdeskToolkit-GUI.ps1') -Text $gui
