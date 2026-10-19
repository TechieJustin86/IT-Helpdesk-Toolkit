<#
.SYNOPSIS
    Core module: Prerequisite tracking and validation
.DESCRIPTION
    Tracks which tools require optional modules (Active Directory, Microsoft Graph).
    Validates prerequisites before tool execution and provides installation guidance.
.PREREQUISITES
    - ActiveDirectory: RSAT module for the AD tools (21 gated tools)
    - GraphPowerShell: Microsoft.Graph for the M365 tools (13 gated tools)
.FUNCTIONS
    - Test-ModuleAvailable: Check if module is installed
    - Test-DependencyMet: Check if dependency is satisfied (memoised per session)
    - Get-DependencyInfo: Get dependency details
    - Get-ToolDependencies: Get all dependencies for a tool
    - Test-ToolPrerequisites: Validate tool can run
    - Show-MissingDependencies: Display missing requirements with install instructions
    - Get-UnmetToolDependency: The dependency blocking a tool, or $null - used by the
      tool runners in Menu.ps1 and Gui\GuiHost.ps1 to gate a tool before it runs
.NOTES
    Loaded third by HelpdeskToolkit.ps1 and HelpdeskToolkit-GUI.ps1.
    Do not run directly.
#>

# ToolIds lists every tool the dependency gate blocks when the dependency is missing.
# The status and installer tools for a dependency must NOT be listed: AD-01 and M365-01
# report whether the module is there, and AD-02 and M365-02 install it, so gating them
# would make the problem unfixable from inside the toolkit.
#
# There is deliberately no WinRM entry. It used to name the Windows feature
# 'WinRM-IIS-Ext', which is the IIS extension for WinRM, not WinRM itself - gating the
# RMT tools on it would have blocked all ten on machines where remoting works fine.
# The remote tools report their own connection failures, which is the better signal.
$Script:Dependencies = @{
    'ActiveDirectory' = @{
        Module = 'ActiveDirectory'
        MinVersion = '1.0'
        OSEditions = @('Professional', 'Enterprise', 'Education')
        InstallNote = 'Run AD-02 to install the RSAT ActiveDirectory module (AD-01 shows the current status).'
        ToolIds = @('AD-03', 'AD-04', 'AD-05', 'AD-06', 'AD-07', 'AD-08', 'AD-09',
                    'AD-20', 'AD-21', 'AD-22', 'AD-23', 'AD-24', 'AD-25', 'AD-26',
                    'AD-27', 'AD-28', 'AD-29', 'AD-30', 'AD-31', 'AD-32', 'AD-33')
    }
    'GraphPowerShell' = @{
        Module = 'Microsoft.Graph'
        MinVersion = '2.0'
        OSEditions = @('*')
        InstallNote = 'Run M365-02 to install the Microsoft Graph modules (M365-01 shows the current status).'
        ToolIds = @('M365-03', 'M365-04', 'M365-05', 'M365-06', 'M365-07', 'M365-08',
                    'M365-09', 'M365-10', 'M365-11', 'M365-12', 'M365-13', 'M365-14', 'M365-15')
    }
}

function Test-ModuleAvailable {
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [string]$MinVersion
    )
    try {
        $module = Get-Module -Name $ModuleName -ErrorAction Stop
        if ($null -eq $module) {
            $module = Import-Module -Name $ModuleName -PassThru -ErrorAction Stop
        }

        if ($MinVersion -and $module.Version -lt [version]$MinVersion) {
            return $false
        }
        return $true
    } catch {
        return $false
    }
}

# Checking a module dependency imports it, and importing Microsoft.Graph takes seconds,
# so the answer is remembered for the rest of the session. AD-02 and M365-02 clear it
# after installing, so a freshly installed module is picked up without a restart.
$Script:DependencyState = @{}

function Clear-DependencyState {
    param([string]$DependencyKey)
    if ($DependencyKey) { $Script:DependencyState.Remove($DependencyKey) | Out-Null }
    else { $Script:DependencyState.Clear() }
}

function Test-DependencyMet {
    param([Parameter(Mandatory)][string]$DependencyKey, [switch]$NoCache)
    $dep = $Script:Dependencies[$DependencyKey]
    if (-not $dep) { return $false }

    if (-not $NoCache -and $Script:DependencyState.ContainsKey($DependencyKey)) {
        return $Script:DependencyState[$DependencyKey]
    }

    if ($dep.Module) {
        $result = Test-ModuleAvailable -ModuleName $dep.Module -MinVersion $dep.MinVersion
        $Script:DependencyState[$DependencyKey] = $result
        return $result
    }

    if ($dep.Feature) {
        try {
            $feature = Get-WindowsOptionalFeature -FeatureName $dep.Feature -ErrorAction SilentlyContinue
            return $feature.State -eq 'Enabled'
        } catch {
            return $false
        }
    }

    return $false
}

function Get-DependencyInfo {
    param([Parameter(Mandatory)][string]$DependencyKey)
    return $Script:Dependencies[$DependencyKey]
}

function Get-ToolDependencies {
    param([Parameter(Mandatory)][string]$ToolId)
    $deps = @()
    foreach ($dep in $Script:Dependencies.Values) {
        if ($ToolId -in $dep.ToolIds) {
            $deps += $dep
        }
    }
    return $deps
}

function Test-ToolPrerequisites {
    param([Parameter(Mandatory)][string]$ToolId)
    $deps = Get-ToolDependencies -ToolId $ToolId
    $results = @()

    foreach ($key in @($Script:Dependencies.Keys | Where-Object { $Script:Dependencies[$_].ToolIds -contains $ToolId })) {
        $dep = $Script:Dependencies[$key]
        $met = Test-DependencyMet -DependencyKey $key
        $results += [pscustomobject]@{
            Dependency = $key
            Met = $met
            Module = $dep.Module
            InstallNote = $dep.InstallNote
        }
    }

    return $results
}

function Show-MissingDependencies {
    param([Parameter(Mandatory)][string]$ToolId)
    $deps = Test-ToolPrerequisites -ToolId $ToolId
    $missing = $deps | Where-Object { -not $_.Met }

    if ($missing.Count -gt 0) {
        Write-Warn "Tool $ToolId requires prerequisites:"
        foreach ($m in $missing) {
            Write-Warn "  - $($m.Module): $($m.InstallNote)"
        }
        return $true
    }
    return $false
}

function Get-UnmetToolDependency {
    <#
        Returns the dependency record blocking this tool, or $null when the tool is not
        gated or its dependency is present. The tool runners call this before running a
        tool, so a missing optional module produces one clear line and an install hint
        instead of a raw "term is not recognized" error from deep inside the tool.
    #>
    param([Parameter(Mandatory)][string]$ToolId)

    foreach ($key in $Script:Dependencies.Keys) {
        $dep = $Script:Dependencies[$key]
        if ($dep.ToolIds -and ($ToolId -in $dep.ToolIds)) {
            if (-not (Test-DependencyMet -DependencyKey $key)) {
                return [pscustomobject]@{
                    Key         = $key
                    Module      = $dep.Module
                    InstallNote = $dep.InstallNote
                }
            }
        }
    }
    return $null
}
