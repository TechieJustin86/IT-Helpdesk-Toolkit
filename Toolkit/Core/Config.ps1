<#
.SYNOPSIS
    Core module: configuration defaults
.DESCRIPTION
    The settings the toolkit reads. To change one, edit its value here; TKA-01 shows
    the current values. There is no settings file - these defaults are the configuration.

    This file used to also define Timeouts, Retry, Resources, Performance and Security
    sections, and several more Logging values. No code read any of them, so they were
    removed rather than left implying they could be tuned.
.FUNCTIONS
    - Get-ToolkitConfig: all settings, or one section
    - Get-ConfigValue: one setting
.NOTES
    Loaded second by HelpdeskToolkit.ps1 and HelpdeskToolkit-GUI.ps1.
    Do not run directly.
#>

$Script:Config = @{
    Logging = @{
        MaxErrorsToKeep = 200   # entries kept in Logs\toolkit-errors.json
    }
}

function Get-ToolkitConfig {
    param([string]$Key)
    if ($Key) { return $Script:Config[$Key] }
    return $Script:Config
}

function Get-ConfigValue {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Setting
    )
    $Script:Config[$Category][$Setting]
}
