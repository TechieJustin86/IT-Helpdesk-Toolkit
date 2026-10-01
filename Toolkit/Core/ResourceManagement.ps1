<#
.SYNOPSIS
    Core module: Resource monitoring and management
.DESCRIPTION
    Monitors and limits memory, disk, and parallel job resources to prevent hangs.
    Rotates output buffer and manages job lifecycle for stability.
.MONITORING
    - Memory: Warn if process exceeds threshold (default 500MB)
    - Disk: Monitor free space, auto-rotate logs if low
    - Jobs: Limit concurrent operations (default 5)
    - Output: Rotate GUI buffer after N lines (default 10K)
.FUNCTIONS
    - Start-ParallelOperation: Execute jobs with max job limiting
    - Wait-ParallelOperation: Collect results with timeout
    - Get-ActiveJobCount: Count running jobs
    - Stop-AllToolkitJobs: Cleanup all jobs
    - Monitor-MemoryUsage: Warn if memory high
    - Get-MemoryMetrics: Get current memory stats
    - Add-OutputLine: Track output buffer size
    - Get-OutputBufferSize: Current buffer line count
    - Clear-OutputBuffer: Reset buffer
    - Test-DiskSpaceAvailable: Check free space
    - Get-ResourceStats: Overall resource statistics
    - Show-ResourceStats: Display resources in output
.NOTES
    Loaded sixth by HelpdeskToolkit.ps1 and HelpdeskToolkit-GUI.ps1.
    Do not run directly.
#>

$Script:ResourceMonitor = @{
    MaxActiveJobs = (Get-ConfigValue -Category 'Performance' -Setting 'MaxParallelJobs')
    ActiveJobs = @()
    OutputBuffer = New-Object System.Collections.Generic.List[string]
    OutputLineCount = 0
}

function Start-ParallelOperation {
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$InputData,
        [int]$MaxParallel = $null
    )

    if (-not $MaxParallel) {
        $MaxParallel = Get-ConfigValue -Category 'Performance' -Setting 'MaxParallelJobs'
    }

    $jobs = @()
    $processed = 0

    foreach ($item in $InputData) {
        # Wait if we've hit max parallel jobs
        while (@($Script:ResourceMonitor.ActiveJobs | Where-Object { $_.State -ne 'Completed' }).Count -ge $MaxParallel) {
            Start-Sleep -Milliseconds 100
        }

        $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $item
        $Script:ResourceMonitor.ActiveJobs += $job
        $jobs += $job
        $processed++

        Write-Info "Queued job $processed/$($InputData.Count) (parallel limit: $MaxParallel)"
    }

    return $jobs
}

function Wait-ParallelOperation {
    param(
        [Parameter(Mandatory)][object[]]$Jobs,
        [int]$TimeoutSeconds = 300
    )

    $results = @()
    $completed = 0
    $startTime = Get-Date

    foreach ($job in $Jobs) {
        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        if ($elapsed -gt $TimeoutSeconds) {
            Write-Warn "Timeout waiting for jobs; stopping remaining"
            Stop-Job -Job $Jobs -ErrorAction SilentlyContinue
            break
        }

        $result = Receive-Job -Job $job -Wait
        $results += $result
        $completed++

        Write-Info "Completed $completed/$($Jobs.Count)"
        Remove-Job -Job $job
    }

    $Script:ResourceMonitor.ActiveJobs = @($Script:ResourceMonitor.ActiveJobs | Where-Object { $null -ne $_ })
    return $results
}

function Get-ActiveJobCount {
    return @($Script:ResourceMonitor.ActiveJobs | Where-Object { $_.State -ne 'Completed' }).Count
}

function Stop-AllToolkitJobs {
    $jobs = Get-Job -ErrorAction SilentlyContinue
    if ($jobs) {
        Stop-Job -Job $jobs -ErrorAction SilentlyContinue
        Remove-Job -Job $jobs -ErrorAction SilentlyContinue
    }
    $Script:ResourceMonitor.ActiveJobs = @()
}

function Monitor-MemoryUsage {
    param([int]$WarningThresholdMB = 500)

    $process = Get-Process -Id $PID
    $memoryMB = $process.WorkingSet / 1MB

    if ($memoryMB -gt $WarningThresholdMB) {
        Write-Warn "High memory usage: $([math]::Round($memoryMB))MB (threshold: ${WarningThresholdMB}MB)"
        return $false
    }
    return $true
}

function Get-MemoryMetrics {
    $os = Get-CimInstance Win32_OperatingSystem
    $process = Get-Process -Id $PID

    return @{
        ProcessMemoryMB = [math]::Round($process.WorkingSet / 1MB, 2)
        SystemFreeMemoryMB = [math]::Round($os.FreePhysicalMemory / 1024, 2)
        SystemTotalMemoryMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 2)
        MemoryUtilizationPercent = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 2)
    }
}

function Add-OutputLine {
    param([string]$Line)

    $config = Get-ConfigValue -Category 'Resources' -Setting 'OutputRotationLines'

    $Script:ResourceMonitor.OutputBuffer.Add($Line)
    $Script:ResourceMonitor.OutputLineCount++

    if ($Script:ResourceMonitor.OutputLineCount -gt $config) {
        Write-Info "Clearing output buffer (rotated after $($Script:ResourceMonitor.OutputLineCount) lines)"
        $Script:ResourceMonitor.OutputBuffer.Clear()
        $Script:ResourceMonitor.OutputLineCount = 0
    }
}

function Get-OutputBufferSize {
    return $Script:ResourceMonitor.OutputLineCount
}

function Clear-OutputBuffer {
    $Script:ResourceMonitor.OutputBuffer.Clear()
    $Script:ResourceMonitor.OutputLineCount = 0
}

function Test-DiskSpaceAvailable {
    param([double]$RequiredMB = 100)

    $drive = Get-Volume -DriveLetter $env:SystemDrive[0] -ErrorAction SilentlyContinue
    if ($drive) {
        $freeMB = $drive.SizeRemaining / 1MB
        if ($freeMB -lt $RequiredMB) {
            Write-Warn "Insufficient disk space: ${freeMB}MB available (required: ${RequiredMB}MB)"
            return $false
        }
    }
    return $true
}

function Get-ResourceStats {
    $memory = Get-MemoryMetrics
    $jobs = Get-ActiveJobCount
    $outputLines = Get-OutputBufferSize

    return @{
        Memory = $memory
        ActiveJobs = $jobs
        OutputLines = $outputLines
        CacheStats = Get-CacheStats
        Timestamp = Get-Date
    }
}

function Show-ResourceStats {
    $stats = Get-ResourceStats

    Write-Section 'Resource Statistics'
    Write-Info "Process Memory: $($stats.Memory.ProcessMemoryMB)MB"
    Write-Info "System Free: $($stats.Memory.SystemFreeMemoryMB)MB / $($stats.Memory.SystemTotalMemoryMB)MB"
    Write-Info "Memory Utilization: $($stats.Memory.MemoryUtilizationPercent)%"
    Write-Info "Active Parallel Jobs: $($stats.ActiveJobs)"
    Write-Info "Output Buffer Lines: $($stats.OutputLines)"
    Write-Info "Cached Items: Valid=$($stats.CacheStats.ValidItems), Expired=$($stats.CacheStats.ExpiredItems)"
}
