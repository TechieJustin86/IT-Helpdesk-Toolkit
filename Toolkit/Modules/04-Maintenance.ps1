# Modules\04-Maintenance.ps1
# Category: Maintenance & Repair
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'MNT-01' -Category 'Maintenance & Repair' -Name 'Clean temporary files' -Description 'User/Windows temp, crash dumps, error reports' -Action {
    $targets = [ordered]@{
        'User temp'           = $env:TEMP
        'Windows temp'        = "$env:SystemRoot\Temp"
        'User crash dumps'    = "$env:LOCALAPPDATA\CrashDumps"
        'Error report queue'  = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"
        'Error report archive'= "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"
        'Delivery Optimization' = "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization"
    }
    Write-Info 'Measuring...'
    $sizes = foreach ($k in $targets.Keys) { [pscustomobject]@{ Location = $k; Path = $targets[$k]; Size = Get-FolderSize $targets[$k] } }
    $sizes | Select-Object Location, @{n = 'Size'; e = { Format-Bytes $_.Size } }, Path | Format-Table -AutoSize | Out-Host
    Write-Info ('Total: {0}' -f (Format-Bytes ($sizes | Measure-Object Size -Sum).Sum))
    if (-not (Confirm-Action 'Delete these files? (files in use are skipped)')) { return }
    $total = 0
    foreach ($s in $sizes) { $freed = Clear-FolderContents $s.Path; $total += $freed; Write-Ok ('{0}: freed {1}' -f $s.Location, (Format-Bytes $freed)) }
    Write-Ok ('Total freed: {0}' -f (Format-Bytes $total))
}

Add-Tool -Id 'MNT-02' -Category 'Maintenance & Repair' -Name 'Empty Recycle Bin' -Description 'Empty the Recycle Bin on all drives' -Action {
    if (Confirm-Action 'Permanently empty the Recycle Bin?') { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; Write-Ok 'Recycle Bin emptied.' }
}

Add-Tool -Id 'MNT-03' -Category 'Maintenance & Repair' -Name 'System File Checker (SFC)' -Admin -Description 'Scan and repair protected Windows files' -Action {
    Write-Info 'This can take 10-20 minutes.'
    $code = Invoke-External 'sfc.exe' '/scannow'
    Write-Info "SFC finished (exit code $code). Details: $env:SystemRoot\Logs\CBS\CBS.log"
}

Add-Tool -Id 'MNT-04' -Category 'Maintenance & Repair' -Name 'DISM image repair' -Admin -Description 'DISM RestoreHealth - repair the component store' -Action {
    Write-Info 'This can take 10-30 minutes and needs internet access.'
    $code = Invoke-External 'dism.exe' '/Online /Cleanup-Image /RestoreHealth'
    if ($code -eq 0) { Write-Ok 'DISM completed. Run SFC (MNT-03) next.' } else { Write-Err "DISM exit code $code" }
}

Add-Tool -Id 'MNT-05' -Category 'Maintenance & Repair' -Name 'Full repair (DISM + SFC)' -Admin -Description 'Run DISM RestoreHealth then SFC in sequence' -Action {
    if (-not (Confirm-Action 'Run DISM then SFC? This can take 30+ minutes.')) { return }
    $null = Invoke-External 'dism.exe' '/Online /Cleanup-Image /RestoreHealth'
    $null = Invoke-External 'sfc.exe' '/scannow'
    Write-Ok 'Repair sequence complete. Reboot recommended.'
}

Add-Tool -Id 'MNT-06' -Category 'Maintenance & Repair' -Name 'Check disk (CHKDSK)' -Admin -Description 'Online scan, or schedule full repair at next boot' -Action {
    Write-Host '  [1] Online scan (read-only, no reboot)'
    Write-Host '  [2] Schedule full repair (/f /r) at next reboot'
    $c = Read-Host '  Choice'
    $drive = Read-Host "  Drive [$env:SystemDrive]"
    if (-not $drive) { $drive = $env:SystemDrive }
    if ($c -eq '1') { $null = Invoke-External 'chkdsk.exe' "$drive /scan" }
    elseif ($c -eq '2') {
        cmd.exe /c "echo Y| chkdsk $drive /f /r" | Out-Host
        Write-Ok 'CHKDSK will run at the next restart.'
    }
}

Add-Tool -Id 'MNT-07' -Category 'Maintenance & Repair' -Name 'Clear print spooler' -Admin -Description 'Stop spooler, delete stuck jobs, restart' -Action {
    Stop-Service -Name Spooler -Force
    $n = @(Get-ChildItem "$env:SystemRoot\System32\spool\PRINTERS" -File -ErrorAction SilentlyContinue).Count
    Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
    Start-Service -Name Spooler
    Write-Ok "Spooler restarted, $n spool file(s) removed."
}

Add-Tool -Id 'MNT-08' -Category 'Maintenance & Repair' -Name 'Restart Explorer' -Description 'Restart the taskbar/desktop shell' -Action {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Write-Ok 'Explorer restarted.'
}

Add-Tool -Id 'MNT-09' -Category 'Maintenance & Repair' -Name 'Reset Windows Update' -Admin -Description 'Stop services, rename SoftwareDistribution/catroot2, restart' -Action {
    if (-not (Confirm-Action 'Reset Windows Update components? Update history view will be cleared.')) { return }
    $svcs = 'wuauserv', 'bits', 'cryptsvc', 'msiserver', 'usosvc'
    foreach ($s in $svcs) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    foreach ($dir in "$env:SystemRoot\SoftwareDistribution", "$env:SystemRoot\System32\catroot2") {
        if (Test-Path $dir) {
            try { Rename-Item -LiteralPath $dir -NewName ("{0}.old{1}" -f (Split-Path $dir -Leaf), $stamp) -ErrorAction Stop; Write-Ok "Renamed $dir" }
            catch { Write-Warn "Could not rename $dir : $($_.Exception.Message)" }
        }
    }
    foreach ($s in $svcs) { Start-Service -Name $s -ErrorAction SilentlyContinue }
    Write-Ok 'Windows Update components reset. Check for updates again.'
}

Add-Tool -Id 'MNT-10' -Category 'Maintenance & Repair' -Name 'Check for Windows updates' -Description 'List available updates (can take a few minutes)' -Action {
    Write-Info 'Searching for updates...'
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $res = $searcher.Search('IsInstalled=0 and IsHidden=0')
        if ($res.Updates.Count -eq 0) { Write-Ok 'No updates available.' }
        else {
            $res.Updates | ForEach-Object { [pscustomobject]@{ Title = $_.Title; KB = ($_.KBArticleIDs -join ','); Severity = $_.MsrcSeverity; Downloaded = $_.IsDownloaded } } | Format-Table -AutoSize -Wrap | Out-Host
        }
    } catch { Write-Err "Search failed: $($_.Exception.Message)" }
    if (Confirm-Action 'Open Windows Update settings?') { Start-Process 'ms-settings:windowsupdate' }
}

Add-Tool -Id 'MNT-11' -Category 'Maintenance & Repair' -Name 'Rebuild icon & thumbnail cache' -Description 'Fix blank/wrong icons and thumbnails' -Action {
    if (-not (Confirm-Action 'Explorer will restart. Continue?')) { return }
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db", "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
    Write-Ok 'Icon and thumbnail caches cleared.'
}

Add-Tool -Id 'MNT-12' -Category 'Maintenance & Repair' -Name 'Create restore point' -Admin -Description 'Create a System Restore checkpoint' -Action {
    try {
        Checkpoint-Computer -Description "HelpdeskToolkit $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Ok 'Restore point created.'
    } catch {
        Write-Err $_.Exception.Message
        Write-Info 'System Protection may be off for this drive, or a restore point was already made in the last 24 hours.'
    }
}

Add-Tool -Id 'MNT-13' -Category 'Maintenance & Repair' -Name 'Component store cleanup' -Admin -Description 'DISM StartComponentCleanup to shrink WinSxS' -Action {
    $null = Invoke-External 'dism.exe' '/Online /Cleanup-Image /AnalyzeComponentStore'
    if (Confirm-Action 'Run component cleanup now?') { $null = Invoke-External 'dism.exe' '/Online /Cleanup-Image /StartComponentCleanup' }
}

Add-Tool -Id 'MNT-14' -Category 'Maintenance & Repair' -Name 'Disk Cleanup (cleanmgr)' -Description 'Launch the built-in Disk Cleanup tool' -Action {
    Start-Process cleanmgr.exe -ArgumentList "/d $env:SystemDrive"
}

Add-Tool -Id 'MNT-15' -Category 'Maintenance & Repair' -Name 'Sync system time' -Admin -Description 'Show time status and force a resync' -Action {
    if ((Get-Service w32time).Status -ne 'Running') { Start-Service w32time }
    Write-Info "Local time: $(Get-Date)"
    $null = Invoke-External 'w32tm.exe' '/query /status'
    Write-Section 'Offset vs time.windows.com'
    w32tm /stripchart /computer:time.windows.com /samples:1 /dataonly | Out-Host
    if (Confirm-Action 'Force resync now?') { $null = Invoke-External 'w32tm.exe' '/resync /force' }
}

Add-Tool -Id 'MNT-16' -Category 'Maintenance & Repair' -Name 'Restart audio services' -Admin -Description 'Fix "no sound" by restarting audio services' -Action {
    Restart-Service -Name AudioEndpointBuilder -Force
    Start-Service -Name Audiosrv -ErrorAction SilentlyContinue
    Get-Service AudioEndpointBuilder, Audiosrv | Select-Object Name, Status | Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'MNT-17' -Category 'Maintenance & Repair' -Name 'Rebuild Windows Search index' -Admin -Description 'Fix Start menu, Outlook or file search not finding things' -Action {
    if (-not (Confirm-Action 'Rebuild the search index? Search results are incomplete until re-indexing finishes (can take a few hours).')) { return }
    Stop-Service -Name WSearch -Force
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows Search' -Name SetupCompletedSuccessfully -Value 0 -Type DWord
    Start-Service -Name WSearch
    Write-Ok 'Search service restarted - the index is being rebuilt in the background.'
}

Add-Tool -Id 'MNT-18' -Category 'Maintenance & Repair' -Name 'Power plan' -Description 'Show and switch the active power plan' -Action {
    $plans = @(powercfg /list | Select-String 'GUID:\s*([0-9a-fA-F-]{36})\s+\((.+?)\)(\s*\*)?' | ForEach-Object {
        $g = $_.Matches[0].Groups
        [pscustomobject]@{ Guid = $g[1].Value; Name = $g[2].Value; Active = [bool]$g[3].Value.Trim() }
    })
    if (-not $plans.Count) { Write-Err 'Could not read power plans.'; return }
    $p = Select-FromList $plans { if ($_.Active) { "$($_.Name)   (active)" } else { $_.Name } } 'Plan to activate'
    if ($p) { powercfg /setactive $p.Guid; Write-Ok "Active power plan: $($p.Name)" }
}

Add-Tool -Id 'MNT-19' -Category 'Maintenance & Repair' -Name 'Schedule or cancel restart' -Description 'Restart later with a warning message, or cancel a pending one' -Action {
    Write-Host '  [1] Schedule a restart   [2] Cancel a scheduled restart/shutdown'
    $c = Read-Host '  Choice'
    if ($c -eq '1') {
        $min = Read-Host '  Restart in how many minutes? [60]'
        if ($min -notmatch '^\d+$') { $min = 60 }
        $msg = Read-Host '  Message for the user [IT will restart this PC to finish maintenance. Please save your work.]'
        if (-not $msg) { $msg = 'IT will restart this PC to finish maintenance. Please save your work.' }
        $msg = $msg.Replace('"', "'")
        $sec = [math]::Min([int]$min * 60, 315360000)
        if (Confirm-Action "Restart this PC in $min minute(s)?") {
            $code = Invoke-External 'shutdown.exe' "/r /t $sec /c `"$msg`""
            if ($code -eq 0) { Write-Ok "Restart scheduled for $((Get-Date).AddSeconds($sec).ToString('HH:mm')). Use option 2 to cancel." }
        }
    } elseif ($c -eq '2') {
        $code = Invoke-External 'shutdown.exe' '/a'
        if ($code -eq 0) { Write-Ok 'Scheduled restart cancelled.' } else { Write-Info 'Nothing was scheduled.' }
    }
}

Add-Tool -Id 'MNT-20' -Category 'Maintenance & Repair' -Name 'Change time zone' -Description 'Show and set the Windows time zone' -Action {
    Write-Info "Current: $((Get-TimeZone).DisplayName)"
    $q = Read-Host '  Search time zones (e.g. Eastern, Pacific, London, Sydney)'
    if (-not $q) { return }
    $pattern = "*$([WildcardPattern]::Escape($q))*"
    $z = Select-FromList @(Get-TimeZone -ListAvailable | Where-Object { $_.DisplayName -like $pattern -or $_.Id -like $pattern }) { $_.DisplayName } 'Time zone'
    if ($z -and (Confirm-Action "Set the time zone to $($z.DisplayName)?")) {
        Set-TimeZone -Id $z.Id
        Write-Ok "Time zone set. Local time is now $(Get-Date -Format 'HH:mm')."
    }
}

Add-Tool -Id 'MNT-21' -Category 'Maintenance & Repair' -Name 'DISM health scan (read-only)' -Admin -Description 'DISM ScanHealth - check for component store corruption without repairing' -Action {
    Write-Info 'Read-only scan, usually 5-15 minutes. If corruption is found, run MNT-04 (RestoreHealth).'
    $code = Invoke-External 'dism.exe' '/Online /Cleanup-Image /ScanHealth'
    if ($code -eq 0) { Write-Ok 'Scan finished.' } else { Write-Warn "DISM exit code $code" }
}

Add-Tool -Id 'MNT-22' -Category 'Maintenance & Repair' -Name 'Optimize drives' -Admin -Description 'TRIM SSDs or defragment hard disks (Windows picks the right method)' -Action {
    $vols = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter)
    $v = Select-FromList $vols { '{0}:  {1,-14} {2,10} free   {3}' -f $_.DriveLetter, $_.FileSystemLabel, (Format-Bytes $_.SizeRemaining), $_.FileSystem } 'Drive'
    if (-not $v) { return }
    Write-Host '  [1] Analyze only   [2] Optimize now'
    $c = Read-Host '  Choice'
    if ($c -eq '1') {
        Optimize-Volume -DriveLetter $v.DriveLetter -Analyze -Verbose 4>&1 | ForEach-Object { Write-Host "  $_" }
    } elseif ($c -eq '2' -and (Confirm-Action "Optimize drive $($v.DriveLetter):? This can take a while on hard disks.")) {
        Optimize-Volume -DriveLetter $v.DriveLetter -Verbose 4>&1 | ForEach-Object { Write-Host "  $_" }
        Write-Ok 'Optimization complete.'
    }
}

Add-Tool -Id 'MNT-23' -Category 'Maintenance & Repair' -Name 'Clear Windows Update download cache' -Admin -Description 'Delete downloaded update files (does not uninstall any updates)' -Action {
    $path = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
    Write-Info ('Download cache: {0}' -f (Format-Bytes (Get-FolderSize $path)))
    if (-not (Confirm-Action 'Stop Windows Update, delete downloaded update files, then restart it? Installed updates are not affected.')) { return }
    Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
    $freed = Clear-FolderContents $path
    Start-Service -Name bits, wuauserv -ErrorAction SilentlyContinue
    Write-Ok ('Freed {0}. Windows will download what it needs again at the next check.' -f (Format-Bytes $freed))
}

Add-Tool -Id 'MNT-24' -Category 'Maintenance & Repair' -Name 'Clean archived event logs' -Admin -Description 'Delete Archive-*.evtx files (the live event logs are not touched)' -Action {
    $files = @(Get-ChildItem "$env:SystemRoot\System32\winevt\Logs" -Filter 'Archive-*.evtx' -ErrorAction SilentlyContinue)
    if (-not $files.Count) { Write-Ok 'No archived event log files found.'; return }
    $bytes = ($files | Measure-Object Length -Sum).Sum
    Write-Info ('{0} archived log file(s), {1}.' -f $files.Count, (Format-Bytes $bytes))
    if (-not (Confirm-Action 'Delete the archived event log files? Current event logs are kept.')) { return }
    $files | Remove-Item -Force -ErrorAction SilentlyContinue
    $left = @($files | Where-Object { Test-Path -LiteralPath $_.FullName }).Count
    Write-Ok ('Removed {0} file(s).{1}' -f ($files.Count - $left), $(if ($left) { " $left were in use and skipped." }))
}

Add-Tool -Id 'MNT-25' -Category 'Maintenance & Repair' -Name 'One-click safe maintenance' -Admin -Description 'Temp files + DNS flush + drive optimize in one go (no personal files touched)' -Action {
    Write-Host '  This will:'
    Write-Host '    - clear user and Windows temporary files'
    Write-Host '    - flush the DNS cache'
    Write-Host '    - optimize the system drive (TRIM or defrag)'
    Write-Host '  Documents, installed apps and settings are not touched.'
    if (-not (Confirm-Action 'Run safe maintenance now?')) { return }
    $total = 0
    foreach ($p in $env:TEMP, (Join-Path $env:SystemRoot 'Temp')) {
        $f = Clear-FolderContents $p
        $total += $f
        Write-Ok ('{0}: freed {1}' -f $p, (Format-Bytes $f))
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Write-Ok 'DNS cache flushed.'
    Write-Info "Optimizing $env:SystemDrive ..."
    try { Optimize-Volume -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop; Write-Ok 'System drive optimized.' }
    catch { Write-Warn "Drive optimization skipped: $($_.Exception.Message)" }
    Write-Ok ('Maintenance complete - {0} of temporary files removed.' -f (Format-Bytes $total))
}

Add-Tool -Id 'MNT-28' -Category 'Maintenance & Repair' -Name 'Disk usage analyzer' -Description 'Find large folders consuming most disk space' -Action {
    Write-Section 'Disk Usage Analysis'
    $driveLetter = Read-Host "Analyze drive [$env:SystemDrive]"
    if (-not $driveLetter) { $driveLetter = $env:SystemDrive }
    $driveLetter = $driveLetter.TrimEnd(':')

    if (-not (Test-Path "${driveLetter}:" )) {
        Write-Warn "Drive ${driveLetter}: not found"
        return
    }

    Write-Info "Scanning ${driveLetter}:\ - this may take several minutes..."
    $folders = @()

    try {
        Get-ChildItem -Path "${driveLetter}:\" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $folderSize = (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            if ($folderSize -gt 0) {
                $folders += [pscustomobject]@{
                    Name = $_.Name
                    FullPath = $_.FullName
                    SizeBytes = $folderSize
                }
            }
        }

        $folders = $folders | Sort-Object SizeBytes -Descending | Select-Object -First 20

        Write-Section "Top 20 Large Folders on ${driveLetter}:"
        $folders | ForEach-Object {
            Write-Host ("{0,-50} {1,15}" -f $_.Name, (Format-Bytes $_.SizeBytes)) -ForegroundColor Cyan
            Write-Host "  $($_.FullPath)" -ForegroundColor Gray
        }

        $totalScanned = ($folders | Measure-Object SizeBytes -Sum).Sum
        Write-Host ""
        Write-Check 'INFO' 'Total in top 20 folders' (Format-Bytes $totalScanned)

        Write-Host ""
        Write-Info "Recommendation: Delete or move large folders that are no longer needed"
    } catch {
        Write-Err "Error analyzing disk: $($_.Exception.Message)"
    }
}

Add-Tool -Id 'MNT-29' -Category 'Maintenance & Repair' -Name 'System restore point' -Admin -Description 'Create a manual System Restore point for backup' -Action {
    if (-not (Test-IsAdmin)) { Write-Warn 'Administrator privileges required'; return }

    $name = Read-Host "Restore point name (default: $(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
    if (-not $name) { $name = "Helpdesk Toolkit - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }

    Write-Info "Creating System Restore point: $name"
    try {
        Checkpoint-Computer -Description $name -RestorePointType 'Manual' -ErrorAction Stop
        Write-Ok "Restore point created successfully"
    } catch {
        Write-Err "Failed to create restore point: $($_.Exception.Message)"
    }
}

Add-Tool -Id 'MNT-30' -Category 'Maintenance & Repair' -Name 'Disable Windows Update server' -Description 'Disable the use of a WSUS/Windows Update server on this PC' -Admin -Action {
    $regPath = 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU'
    $regKeyName = 'UseWUServer'

    Write-Info "Configuring Windows Update server settings..."
    try {
        if (-not (Test-Path $regPath)) {
            Write-Info 'Creating registry path...'
            New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name $regKeyName -Value 0 -ErrorAction Stop
        Write-Ok 'Windows Update server usage has been disabled.'
        Write-Log 'Windows Update server disabled'
    } catch { Write-Err "Configuration failed: $($_.Exception.Message)" }
}

Add-Tool -Id 'MNT-31' -Category 'Maintenance & Repair' -Name 'Enable Windows Update server' -Description 'Enable the use of a WSUS/Windows Update server on this PC' -Admin -Action {
    $regPath = 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU'
    $regKeyName = 'UseWUServer'

    Write-Info "Configuring Windows Update server settings..."
    try {
        if (-not (Test-Path $regPath)) {
            Write-Info 'Creating registry path...'
            New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name $regKeyName -Value 1 -ErrorAction Stop
        Write-Ok 'Windows Update server usage has been enabled.'
        Write-Log 'Windows Update server enabled'
    } catch { Write-Err "Configuration failed: $($_.Exception.Message)" }
}

Add-Tool -Id 'MNT-32' -Category 'Maintenance & Repair' -Name 'Unblock Windows Store' -Description 'Remove registry-based Windows Store blocking policies' -Admin -Action {
    $regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'
    $regKeys = @('RemoveWindowsStore', 'DisableStoreApps')

    Write-Info "Checking Windows Store configuration..."
    try {
        if (-not (Test-Path $regPath)) {
            Write-Ok 'Windows Store is not blocked by registry policies.'
            return
        }

        foreach ($key in $regKeys) {
            try {
                Set-ItemProperty -Path $regPath -Name $key -Value 0 -ErrorAction SilentlyContinue
            } catch { Write-Warn "Could not modify $key : $($_.Exception.Message)" }
        }
        Write-Ok 'Windows Store has been unblocked.'
        Write-Log 'Windows Store unblocked'
    } catch { Write-Err "Configuration failed: $($_.Exception.Message)" }
}

Add-Tool -Id 'MNT-33' -Category 'Maintenance & Repair' -Name 'Remove Appx packages' -Description 'Interactively remove installed Appx packages (Windows Store apps)' -Action {
    Write-Info 'Retrieving installed Appx packages...'
    try {
        $apps = @(Get-AppxPackage -ErrorAction Stop | Sort-Object Name)
    } catch { Write-Err "Could not retrieve Appx packages: $($_.Exception.Message)"; return }

    if (-not $apps.Count) { Write-Ok 'No Appx packages installed.'; return }

    Write-Info "Found $($apps.Count) Appx package(s)."
    $selection = Select-FromList $apps { '{0,-55} {1}' -f $_.Name, $_.Version } 'Appx package to remove'
    if (-not $selection) { Write-Info 'Cancelled.'; return }

    Write-Warn "Removing: $($selection.Name)"
    if (-not (Confirm-Action "Proceed with removing '$($selection.Name)'?")) { return }

    try {
        Remove-AppxPackage -Package $selection.PackageFullName -ErrorAction Stop
        Write-Ok "Package removed: $($selection.Name)"
        Write-Log "Appx package removed: $($selection.Name)"
    } catch { Write-Err "Removal failed: $($_.Exception.Message)" }
}

Add-Tool -Id 'MNT-34' -Category 'Maintenance & Repair' -Name 'Fix Outlook password prompt' -Description 'Disable credentials caching to resolve Outlook password prompt disappearing issues' -Admin -Action {
    Write-Info 'Configuring Outlook password behavior...'

    $registryPaths = @(
        'HKCU:\Software\Microsoft\Office\*\Outlook\Security',
        'HKLM:\Software\Microsoft\Office\*\Outlook\Security'
    )

    $modified = $false
    foreach ($regPath in $registryPaths) {
        $actualPaths = Get-ChildItem -Path ($regPath -replace '\*', '16.0') -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSPath

        foreach ($path in $actualPaths) {
            try {
                Set-ItemProperty -Path $path -Name 'PromptSimplePassword' -Value 1 -ErrorAction SilentlyContinue
                $modified = $true
            } catch { Write-Warn "Could not modify $path : $($_.Exception.Message)" }
        }
    }

    if ($modified) {
        Write-Ok 'Outlook password prompt settings configured.'
        Write-Info 'You may need to restart Outlook for changes to take effect.'
        Write-Log 'Outlook password prompt settings modified'
    } else {
        Write-Warn 'Could not locate Outlook registry settings. Outlook may not be installed.'
    }
}

Add-Tool -Id 'MNT-26' -Category 'Maintenance & Repair' -Name 'Remove Bloatware' -Admin -Description 'Remove common Windows bloatware and pre-installed apps (interactively)' -Action {
    Write-Section 'Bloatware Removal Tool'
    Write-Host 'This tool helps remove common Windows bloatware apps.'
    Write-Host ''

    # Common bloatware app packages to offer for removal
    $bloatwareApps = @(
        @('Clipchamp.Clipchamp', 'Clipchamp Video Editor'),
        @('Microsoft.BingNews', 'Bing News'),
        @('Microsoft.BingWeather', 'Bing Weather'),
        @('Microsoft.GamingApp', 'Xbox Game Pass'),
        @('Microsoft.MixedReality.Portal', 'Mixed Reality Portal'),
        @('Microsoft.OneDrive', 'OneDrive'),
        @('Microsoft.People', 'People'),
        @('Microsoft.SkypeApp', 'Skype'),
        @('Microsoft.Solitaire', 'Solitaire'),
        @('Microsoft.WindowsCommunicationsApps', 'Mail & Calendar'),
        @('Microsoft.WindowsFeedbackHub', 'Feedback Hub'),
        @('Microsoft.WindowsMaps', 'Maps'),
        @('Microsoft.XboxApp', 'Xbox app'),
        @('Microsoft.ZuneMusic', 'Groove Music'),
        @('Microsoft.ZuneVideo', 'Movies & TV')
    )

    Write-Info 'Scanning installed Appx packages...'
    try {
        $installed = Get-AppxPackage -ErrorAction Stop | Select-Object -ExpandProperty Name
    } catch {
        Write-Err "Failed to retrieve installed apps: $($_.Exception.Message)"
        return
    }

    Write-Host ''
    Write-Host 'Available bloatware for removal:'
    Write-Host ''
    $removable = @()
    foreach ($app in $bloatwareApps) {
        $match = $installed | Where-Object { $_ -like "$($app[0])*" }
        if ($match) {
            $removable += [pscustomobject]@{ PackageName = $match; DisplayName = $app[1] }
            Write-Host "  [$($removable.Count)] $($app[1])"
        }
    }

    if ($removable.Count -eq 0) {
        Write-Ok 'No common bloatware found on this PC.'
        return
    }

    Write-Host ''
    Write-Host 'Enter comma-separated numbers to remove (e.g., 1,3,5 or "all"), or press Enter to skip'
    $choice = Read-Host '  Selection'

    if (-not $choice) { Write-Info 'Cancelled.'; return }

    $toRemove = @()
    if ($choice -eq 'all') {
        $toRemove = $removable
    } else {
        $numbers = $choice -split ',' | ForEach-Object { [int]$_.Trim() - 1 }
        foreach ($n in $numbers) {
            if ($n -ge 0 -and $n -lt $removable.Count) {
                $toRemove += $removable[$n]
            }
        }
    }

    if ($toRemove.Count -eq 0) { Write-Info 'No valid selections.'; return }

    Write-Host ''
    Write-Info "Removing $($toRemove.Count) app(s)..."
    $removed = 0
    $failed = 0

    foreach ($app in $toRemove) {
        try {
            Get-AppxPackage -Name $app.PackageName -ErrorAction Stop | Remove-AppxPackage -ErrorAction Stop
            Write-Ok "Removed: $($app.DisplayName)"
            $removed++
        } catch {
            Write-Warn "Failed to remove $($app.DisplayName): $($_.Exception.Message)"
            $failed++
        }
    }

    Write-Host ''
    Write-Ok "Complete: $removed removed, $failed failed."
}

Add-Tool -Id 'MNT-27' -Category 'Maintenance & Repair' -Name 'Rename PC' -Admin -Description 'Change the computer name and optionally join/leave a domain' -Action {
    Write-Section 'PC Rename'
    Write-Host ''

    $currentName = [System.Net.Dns]::GetHostName()
    Write-Info "Current computer name: $currentName"
    Write-Host ''

    $newName = Read-Host '  New computer name'
    if (-not $newName -or $newName -eq $currentName) {
        Write-Info 'No change requested.'
        return
    }

    # Validate computer name (max 15 chars, no special chars except hyphen)
    if ($newName.Length -gt 15) {
        Write-Err 'Computer name must be 15 characters or fewer.'
        return
    }
    if ($newName -notmatch '^[a-zA-Z0-9-]+$') {
        Write-Err 'Computer name can only contain letters, numbers, and hyphens.'
        return
    }

    Write-Host ''
    Write-Info "This PC will be renamed to: $newName"
    Write-Warn "A restart is required for the change to take effect."
    Write-Host ''

    if (-not (Confirm-Action 'Proceed with rename?')) { return }

    try {
        Rename-Computer -NewName $newName -Force -ErrorAction Stop
        Write-Ok "PC renamed to '$newName'. You must restart for changes to take effect."
        Write-Info "Restart this PC to complete the change."
        if (Confirm-Action 'Restart now?') {
            Write-Info 'Restarting...'
            Start-Sleep -Seconds 2
            Restart-Computer -Force
        }
    } catch {
        Write-Err "Failed to rename computer: $($_.Exception.Message)"
    }
}
