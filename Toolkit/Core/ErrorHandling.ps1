<#
.SYNOPSIS
    Core module: Safe execution with error handling and retries
.DESCRIPTION
    Wraps tool execution with prerequisite checking, timeouts, retries, and detailed logging.
    Handles errors gracefully with full context for debugging.
.ERROR_HANDLING
    - Prerequisites: Validate all dependencies before running
    - Timeouts: Cancel operations that hang (configurable per type)
    - Retries: Automatic retry with exponential backoff (3x default)
    - Logging: Full error context (stack trace, source line, OS version)
    - Metrics: Track execution time, errors, and statistics
.FUNCTIONS
    - Invoke-ToolSafe: Safe execution with prerequisites and timeouts
    - Invoke-ToolWithRetry: Automatic retry for transient failures
    - Write-VerboseError: Detailed error output
    - Test-ResultSize: Warn if result set too large
    - Test-DiskSpaceForLogging: Prevent disk full
    - Rotate-OldLogs: Clean up old log files
    - Get-ExecutionMetrics: Retrieve per-tool error metrics
.NOTES
    Loaded seventh by HelpdeskToolkit.ps1 and HelpdeskToolkit-GUI.ps1.
    Do not run directly.
#>

function Invoke-ToolSafe {
    param(
        [Parameter(Mandatory)][object]$Tool,
        [switch]$NoPause,
        [int]$TimeoutSeconds = $null
    )

    $startTime = Get-Date
    $toolId = $Tool.Id
    $toolName = $Tool.Name

    try {
        # Check prerequisites
        $missing = Show-MissingDependencies -ToolId $toolId -ErrorAction SilentlyContinue
        if ($missing) {
            Write-Err "Cannot run tool - missing prerequisites"
            return $false
        }

        # Log execution start
        $Script:CurrentTool = $Tool
        Write-Log "Tool execution started: $toolId - $toolName"

        # Execute with timeout if specified
        if ($TimeoutSeconds) {
            $job = Start-Job -ScriptBlock { & $using:Tool.Action }
            $result = Wait-Job -Job $job -Timeout $TimeoutSeconds

            if ($null -eq $result) {
                Stop-Job -Job $job
                Remove-Job -Job $job
                Write-Err "Tool execution timed out after $TimeoutSeconds seconds"
                Write-ErrorLog -ToolId $toolId -ToolName $toolName -ErrorRecord "Timeout after $TimeoutSeconds seconds"
                return $false
            }

            $jobResult = Receive-Job -Job $job
            Remove-Job -Job $job
        } else {
            # Execute directly
            & $Tool.Action
        }

        $duration = (Get-Date) - $startTime
        Write-ToolUsage -ToolId $toolId -ToolName $toolName -Category $Tool.Category
        Write-Log "Tool execution completed: $toolId - $toolName (${duration.TotalSeconds}s)"

        if (-not $NoPause) { Wait-Key }
        return $true

    } catch {
        $duration = (Get-Date) - $startTime
        Write-ErrorLog -ToolId $toolId -ToolName $toolName -ErrorRecord $_
        Write-Err "Tool failed: $_"
        Write-Err "Execution time: ${duration.TotalSeconds}s"

        if (-not $NoPause) { Wait-Key }
        return $false

    } finally {
        $Script:CurrentTool = $null
    }
}

function Invoke-ToolWithRetry {
    param(
        [Parameter(Mandatory)][object]$Tool,
        [int]$MaxAttempts = 3,
        [int]$BackoffMs = 500
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Write-Info "Attempt $attempt of $MaxAttempts..."
            & $Tool.Action
            return $true
        } catch {
            if ($attempt -lt $MaxAttempts) {
                $delay = $BackoffMs * [math]::Pow(2, $attempt - 1)
                Write-Warn "Attempt $attempt failed, retrying in ${delay}ms..."
                Start-Sleep -Milliseconds $delay
            } else {
                Write-Err "All $MaxAttempts attempts failed"
                Write-ErrorLog -ToolId $Tool.Id -ToolName $Tool.Name -ErrorRecord $_
                return $false
            }
        }
    }
}

function Write-VerboseError {
    param(
        [string]$ToolId,
        [string]$ToolName,
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [int]$LineNumber = 0
    )

    Write-Err "Error in $ToolId ($ToolName):"
    Write-Err "  Message: $($ErrorRecord.Exception.Message)"
    Write-Err "  Type: $($ErrorRecord.Exception.GetType().Name)"

    if ($ErrorRecord.InvocationInfo) {
        Write-Err "  Script: $($ErrorRecord.InvocationInfo.ScriptName)"
        Write-Err "  Line $($ErrorRecord.InvocationInfo.ScriptLineNumber): $($ErrorRecord.InvocationInfo.Line)"
    }

    if ($ErrorRecord.ScriptStackTrace) {
        Write-Err "  Stack: $($ErrorRecord.ScriptStackTrace)"
    }
}

function Test-ResultSize {
    param([object[]]$Results)

    $config = Get-ConfigValue -Category 'Resources' -Setting 'MaxResultsOutput'
    $count = @($Results).Count

    if ($count -gt $config) {
        Write-Warn "Large result set: $count items (threshold: $config)"
        Write-Info "Consider adding filters to reduce output"
        return $false
    }
    return $true
}

function Test-DiskSpaceForLogging {
    $driveLetter = $Script:LogFile[0]
    $drive = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue

    if ($drive -and $drive.SizeRemaining -lt 100MB) {
        Write-Warn "Low disk space on logging drive: $('{0:N0}' -f ($drive.SizeRemaining / 1MB)) MB free"
        # Rotate old logs
        Rotate-OldLogs -DaysOld 30
        return $false
    }
    return $true
}

function Rotate-OldLogs {
    param([int]$DaysOld = 30)

    if (-not (Test-Path -LiteralPath $Script:OutDir)) { return }

    $cutoff = (Get-Date).AddDays(-$DaysOld)
    $oldFiles = @(Get-ChildItem -Path $Script:OutDir -Filter 'toolkit*.log' -File | Where-Object { $_.LastWriteTime -lt $cutoff })

    foreach ($file in $oldFiles) {
        try {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            Write-Log "Rotated old log: $($file.Name)"
        } catch {
            Write-Log "Failed to rotate log: $($file.Name)"
        }
    }
}

function Get-ExecutionMetrics {
    param([string]$ToolId)

    if (-not (Test-Path $Script:ErrorLogFile)) { return $null }

    try {
        $errors = Get-Content -LiteralPath $Script:ErrorLogFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        $toolErrors = @($errors | Where-Object { $_.ToolId -eq $ToolId })

        return @{
            TotalErrors = $toolErrors.Count
            RecentErrors = @($toolErrors | Where-Object { [datetime]$_.Timestamp -gt (Get-Date).AddDays(-7) }).Count
            LastError = if ($toolErrors.Count -gt 0) { $toolErrors[-1].Timestamp } else { $null }
        }
    } catch {
        return $null
    }
}
