<#
.SYNOPSIS
    Core module: Centralized configuration management
.DESCRIPTION
    Manages all toolkit settings without code changes. Configures timeouts, retries,
    logging levels, resource limits, performance options, and security policies.
.SETTINGS
    - Timeouts: Remote operations (30s), file scans (60s), network (15s), database (10s)
    - Retry: Max attempts (3), backoff multiplier (2), initial delay (500ms)
    - Logging: Level (Normal), max errors (200), max usage records (1000)
    - Resources: Max output (50K lines), max CSV rows (500K), buffer rotation (10K lines)
    - Performance: Caching enabled, max parallel jobs (5)
    - Security: Confirm destructive ops, mask credentials, log remote ops
.FUNCTIONS
    - Get-ToolkitConfig: Retrieve all or specific config values
    - Set-ToolkitConfig: Update configuration settings
    - Get-ConfigValue: Get specific config category setting
    - Test-ConfigExists: Check if setting exists
.NOTES
    Loaded second by HelpdeskToolkit.ps1 and HelpdeskToolkit-GUI.ps1.
    Do not run directly.
#>

$Script:Config = @{
    # Timeout values (seconds)
    Timeouts = @{
        RemoteOperation      = 30
        LargeFileScan        = 60
        NetworkOperation     = 15
        DatabaseQuery        = 10
        ExternalAPI          = 20
    }

    # Retry policies
    Retry = @{
        MaxAttempts          = 3
        BackoffMultiplier    = 2
        InitialDelayMs       = 500
    }

    # Logging configuration
    Logging = @{
        Level                = 'Normal'  # 'Verbose', 'Normal', 'Minimal'
        MaxErrorsToKeep      = 200
        MaxUsageRecordsToKeep = 1000
        RotateDaysOldFile    = 30
        MaxLogFileSizeMB     = 50
    }

    # Resource limits
    Resources = @{
        MaxResultsOutput     = 50000  # Lines before warning
        MaxResultsMemory     = 100MB  # Memory before warning
        MaxCsvExportRows     = 500000
        OutputRotationLines  = 10000  # GUI output clear threshold
    }

    # Performance settings
    Performance = @{
        EnableCaching        = $true
        CacheDurationMinutes = @{
            SystemInfo       = 60
            ADConnectivity   = 5
            NetworkStatus    = 1
        }
        EnableParallelOps    = $true
        MaxParallelJobs      = 5
    }

    # Security settings
    Security = @{
        RequireConfirmDestructive = $true
        MaskCredentialsInLogs    = $true
        LogRemoteOperations      = $true
        RequireElevationWarning  = $true
    }
}

function Get-ToolkitConfig {
    param([string]$Key)
    if ($Key) { return $Script:Config[$Key] }
    return $Script:Config
}

function Set-ToolkitConfig {
    param([string]$Key, [object]$Value)
    if ($Key) { $Script:Config[$Key] = $Value }
}

function Get-ConfigValue {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Setting
    )
    $Script:Config[$Category][$Setting]
}

function Test-ConfigExists {
    param([string]$Category, [string]$Setting)
    return ($null -ne (Get-ConfigValue -Category $Category -Setting $Setting))
}
