<#
.SYNOPSIS
    Core module: Prerequisite tracking and validation
.DESCRIPTION
    Tracks which tools require optional modules (Active Directory, Microsoft Graph).
    Validates prerequisites before tool execution and provides installation guidance.
.PREREQUISITES
    - ActiveDirectory: RSAT module for AD tools (9 tools)
    - GraphPowerShell: Microsoft.Graph for M365 tools (15 tools)
    - WinRM: Remote PowerShell operations (10 tools)
.FUNCTIONS
    - Test-ModuleAvailable: Check if module is installed
    - Test-DependencyMet: Check if dependency is satisfied
    - Get-DependencyInfo: Get dependency details
    - Get-ToolDependencies: Get all dependencies for a tool
    - Test-ToolPrerequisites: Validate tool can run
    - Show-MissingDependencies: Display missing requirements with install instructions
.NOTES
    Loaded third by HelpdeskToolkit.ps1 and HelpdeskToolkit-GUI.ps1.
    Do not run directly.
#>

$Script:Dependencies = @{
    'ActiveDirectory' = @{
        Module = 'ActiveDirectory'
        MinVersion = '1.0'
        OSEditions = @('Professional', 'Enterprise', 'Education')
        InstallNote = 'Run AD-02 to install RSAT ActiveDirectory module'
        ToolIds = @('AD-01', 'AD-02', 'AD-03', 'AD-04', 'AD-05', 'AD-06', 'AD-07', 'AD-08', 'AD-09')
    }
    'GraphPowerShell' = @{
        Module = 'Microsoft.Graph'
        MinVersion = '2.0'
        OSEditions = @('*')
        InstallNote = 'Run M365-02 to install Microsoft Graph modules'
        ToolIds = @('M365-01', 'M365-02', 'M365-03', 'M365-04', 'M365-05', 'M365-06', 'M365-07', 'M365-08', 'M365-09', 'M365-10', 'M365-11', 'M365-12', 'M365-13', 'M365-14', 'M365-15')
    }
    'WinRM' = @{
        Feature = 'WinRM-IIS-Ext'
        OSEditions = @('*')
        InstallNote = 'Required for remote PowerShell operations'
        ToolIds = @('RMT-01', 'RMT-02', 'RMT-03', 'RMT-04', 'RMT-05', 'RMT-06', 'RMT-07', 'RMT-08', 'RMT-09', 'RMT-10')
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

function Test-DependencyMet {
    param([Parameter(Mandatory)][string]$DependencyKey)
    $dep = $Script:Dependencies[$DependencyKey]
    if (-not $dep) { return $false }

    if ($dep.Module) {
        return Test-ModuleAvailable -ModuleName $dep.Module -MinVersion $dep.MinVersion
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
