# Modules\11-Remote.ps1
# Category: Remote Computers
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.
# These tools act on another PC using your current Windows login, so you need admin rights on the
# target. They use WinRM when available and fall back to RPC/DCOM (the same as Computer Management).

$Script:LastRemote = ''

# Asks for the target PC, defaulting to the last one used
function Read-RemoteComputer {
    $prompt = if ($Script:LastRemote) { "Computer name or IP [$Script:LastRemote]" } else { 'Computer name or IP' }
    $c = Read-Host "  $prompt"
    if (-not $c) { $c = $Script:LastRemote }
    if (-not $c) { return $null }
    $Script:LastRemote = $c.Trim()
    $Script:LastRemote
}

function New-RemoteCimSession {
    param([string]$Computer)
    try { New-CimSession -ComputerName $Computer -OperationTimeoutSec 20 -ErrorAction Stop }
    catch {
        Write-Info 'WinRM not reachable - trying RPC/DCOM...'
        New-CimSession -ComputerName $Computer -SessionOption (New-CimSessionOption -Protocol Dcom) -OperationTimeoutSec 20 -ErrorAction Stop
    }
}

function Test-TcpPort {
    param([string]$Computer, [int]$Port, [int]$TimeoutMs = 1500)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $client.BeginConnect($Computer, $Port, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne($TimeoutMs) -and $client.Connected) { $client.EndConnect($ar); return $true }
        return $false
    } catch { return $false }
    finally { $client.Close() }
}

Add-Tool -Id 'RMT-01' -Category 'Remote Computers' -Name 'Remote connectivity check' -Description 'Ping, DNS and which remote-management ports are open' -Action {
    $c = Read-RemoteComputer
    if (-not $c) { return }
    try {
        $ips = @([Net.Dns]::GetHostAddresses($c) | Where-Object AddressFamily -eq 'InterNetwork' | ForEach-Object IPAddressToString)
        Write-Ok ('{0,-34} {1}' -f 'DNS', ($ips -join ', '))
    } catch { Write-Err ('{0,-34} {1}' -f 'DNS', 'Name not found'); return }
    if (Test-Connection -ComputerName $c -Count 2 -Quiet -ErrorAction SilentlyContinue) { Write-Ok ('{0,-34} {1}' -f 'Ping', 'Replies') }
    else { Write-Warn ('{0,-34} {1}' -f 'Ping', 'No reply (offline, or ICMP blocked)') }
    $smb = $false
    foreach ($p in @(@(135, 'RPC/DCOM (WMI, services)'), @(445, 'SMB (C$ share)'), @(3389, 'Remote Desktop'), @(5985, 'WinRM (PowerShell)'))) {
        $label = 'Port {0} {1}' -f $p[0], $p[1]
        if (Test-TcpPort $c $p[0]) { Write-Ok ('{0,-34} {1}' -f $label, 'Open'); if ($p[0] -eq 445) { $smb = $true } }
        else { Write-Warn ('{0,-34} {1}' -f $label, 'Closed / filtered') }
    }
    if ($smb) {
        if (Test-Path "\\$c\C$" -ErrorAction SilentlyContinue) { Write-Ok ('{0,-34} {1}' -f 'Admin share C$', 'Accessible - you have admin rights') }
        else { Write-Warn ('{0,-34} {1}' -f 'Admin share C$', 'Access denied - you may not be an admin there') }
    }
}

Add-Tool -Id 'RMT-02' -Category 'Remote Computers' -Name 'Remote PC summary' -Description 'OS, model, serial, uptime, logged-on user and disks' -Action {
    $c = Read-RemoteComputer
    if (-not $c) { return }
    $s = New-RemoteCimSession $c
    try {
        $os   = Get-CimInstance Win32_OperatingSystem -CimSession $s
        $cs   = Get-CimInstance Win32_ComputerSystem -CimSession $s
        $bios = Get-CimInstance Win32_BIOS -CimSession $s
        $cpu  = Get-CimInstance Win32_Processor -CimSession $s | Select-Object -First 1
        $up   = (Get-Date) - $os.LastBootUpTime
        [pscustomobject]@{
            'Computer'       = $cs.Name
            'Logged-on user' = $cs.UserName
            'Domain'         = $cs.Domain
            'Manufacturer'   = $cs.Manufacturer
            'Model'          = $cs.Model
            'Serial number'  = $bios.SerialNumber
            'OS'             = $os.Caption
            'Build'          = $os.BuildNumber
            'Last boot'      = $os.LastBootUpTime
            'Uptime'         = '{0}d {1}h {2}m' -f $up.Days, $up.Hours, $up.Minutes
            'CPU'            = "$($cpu.Name)".Trim()
            'RAM total'      = Format-Bytes $cs.TotalPhysicalMemory
            'RAM free'       = Format-Bytes ($os.FreePhysicalMemory * 1KB)
        } | Format-List | Out-Host
        Write-Section 'Disks'
        Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -CimSession $s |
            Select-Object DeviceID, VolumeName, @{n = 'Size'; e = { Format-Bytes $_.Size } }, @{n = 'Free'; e = { Format-Bytes $_.FreeSpace } },
                @{n = 'Free %'; e = { if ($_.Size) { [math]::Round($_.FreeSpace / $_.Size * 100, 1) } } } |
            Format-Table -AutoSize | Out-Host
    } finally { Remove-CimSession $s }
}

Add-Tool -Id 'RMT-03' -Category 'Remote Computers' -Name 'Who is logged on (remote)' -Description 'Sessions on a remote PC, including disconnected RDP' -Action {
    $c = Read-RemoteComputer
    if (-not $c) { return }
    if (Get-Command quser.exe -ErrorAction SilentlyContinue) {
        Write-Section 'Sessions'
        quser /server:$c 2>&1 | Out-Host
    }
    $s = New-RemoteCimSession $c
    try {
        Write-Section 'Interactive users (desktop running)'
        $rows = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -CimSession $s | ForEach-Object {
            $o = Invoke-CimMethod -InputObject $_ -MethodName GetOwner
            [pscustomobject]@{ User = "$($o.Domain)\$($o.User)"; Session = $_.SessionId; 'Signed in' = $_.CreationDate }
        }
        if ($rows) { $rows | Format-Table -AutoSize | Out-Host } else { Write-Info 'Nobody is signed in to the desktop.' }
    } finally { Remove-CimSession $s }
}

Add-Tool -Id 'RMT-04' -Category 'Remote Computers' -Name 'Remote services' -Description 'Find, start, stop or restart a service on a remote PC' -Action {
    $c = Read-RemoteComputer
    if (-not $c) { return }
    $q = Read-Host '  Service name or part of display name (blank = stopped automatic services)'
    $s = New-RemoteCimSession $c
    try {
        $all = Get-CimInstance Win32_Service -CimSession $s
        if ($q) {
            $pattern = "*$([WildcardPattern]::Escape($q))*"
            $list = @($all | Where-Object { $_.Name -like $pattern -or $_.DisplayName -like $pattern })
        } else {
            $list = @($all | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' })
        }
        $svc = Select-FromList $list { '{0,-28} {1,-9} {2}' -f $_.Name, $_.State, $_.DisplayName } 'Service'
        if (-not $svc) { return }
        $name = $svc.Name
        Write-Host '  [1] Start   [2] Stop   [3] Restart'
        $a = Read-Host '  Action'
        $waitFor = {
            param($state)
            for ($i = 0; $i -lt 30; $i++) {
                $cur = Get-CimInstance Win32_Service -Filter "Name='$name'" -CimSession $s
                if ($cur.State -eq $state) { break }
                Start-Sleep -Milliseconds 500
            }
            $cur.State
        }
        if ($a -in '2', '3') {
            if (-not (Confirm-Action "Stop $name on $c?")) { return }
            $r = Invoke-CimMethod -InputObject $svc -MethodName StopService
            if ($r.ReturnValue -notin 0, 5, 6) { Write-Err "Stop failed (code $($r.ReturnValue))."; return }
            Write-Info ('State: ' + (& $waitFor 'Stopped'))
        }
        if ($a -in '1', '3') {
            $cur = Get-CimInstance Win32_Service -Filter "Name='$name'" -CimSession $s
            $r = Invoke-CimMethod -InputObject $cur -MethodName StartService
            if ($r.ReturnValue -notin 0, 10) { Write-Err "Start failed (code $($r.ReturnValue))." }
            else { Write-Ok ('State: ' + (& $waitFor 'Running')) }
        }
    } finally { Remove-CimSession $s }
}

Add-Tool -Id 'RMT-05' -Category 'Remote Computers' -Name 'Remote processes' -Description 'Top processes by memory on a remote PC; end one' -Action {
    $c = Read-RemoteComputer
    if (-not $c) { return }
    $s = New-RemoteCimSession $c
    try {
        $procs = @(Get-CimInstance Win32_Process -CimSession $s | Sort-Object WorkingSetSize -Descending | Select-Object -First 20)
        $procs | Select-Object Name, ProcessId, @{n = 'Memory'; e = { Format-Bytes $_.WorkingSetSize } }, SessionId | Format-Table -AutoSize | Out-Host
        if (Confirm-Action 'End one of these processes?') {
            $p = Select-FromList $procs { '{0,-30} PID {1}' -f $_.Name, $_.ProcessId } 'Process to end'
            if ($p -and (Confirm-Action "End $($p.Name) (PID $($p.ProcessId)) on $c? Unsaved work in it will be lost.")) {
                $r = Invoke-CimMethod -InputObject $p -MethodName Terminate
                if ($r.ReturnValue -eq 0) { Write-Ok 'Process ended.' } else { Write-Err "Failed (code $($r.ReturnValue))." }
            }
        }
    } finally { Remove-CimSession $s }
}

Add-Tool -Id 'RMT-06' -Category 'Remote Computers' -Name 'Remote installed software' -Description 'Installed programs on a remote PC (needs WinRM)' -Action {
    $c = Read-RemoteComputer
    if (-not $c) { return }
    try {
        $apps = Invoke-Command -ComputerName $c -ErrorAction Stop -ScriptBlock {
            Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 } |
                Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
        }
    } catch {
        Write-Err "PowerShell remoting failed: $($_.Exception.Message)"
        Write-Info 'Enable it on the target with "Enable-PSRemoting -Force" or through Group Policy.'
        return
    }
    $apps = @($apps | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Sort-Object DisplayName, DisplayVersion -Unique)
    Write-Info "$($apps.Count) applications installed on $c."
    $apps | Format-Table -AutoSize | Out-Host
    if (Confirm-Action 'Export to CSV?') { $apps | Export-Results -Name "software_$c.csv" }
}

Add-Tool -Id 'RMT-07' -Category 'Remote Computers' -Name 'Restart / shut down remote PC' -Description 'With a countdown message for the user, or cancel one' -Action {
    $c = Read-RemoteComputer
    if (-not $c) { return }
    Write-Host '  [1] Restart   [2] Shut down   [3] Cancel a pending restart/shutdown'
    $a = Read-Host '  Action'
    if ($a -eq '3') {
        $code = Invoke-External 'shutdown.exe' "/m \\$c /a"
        if ($code -eq 0) { Write-Ok "Cancelled on $c." } else { Write-Warn "shutdown.exe returned $code (nothing pending, or access denied)." }
        return
    }
    if ($a -notin '1', '2') { return }
    $min = Read-Host '  Delay in minutes (0 = now) [5]'
    if ($min -notmatch '^\d+$') { $min = 5 }
    $msg = Read-Host '  Message for the user [Your PC will restart for IT maintenance. Please save your work.]'
    if (-not $msg) { $msg = 'Your PC will restart for IT maintenance. Please save your work.' }
    $msg = $msg.Replace('"', "'")
    $verb = if ($a -eq '1') { 'Restart' } else { 'Shut down' }
    if (-not (Confirm-Action "$verb $c in $min minute(s)?")) { return }
    $flag = if ($a -eq '1') { '/r' } else { '/s' }
    $code = Invoke-External 'shutdown.exe' "/m \\$c $flag /f /t $([int]$min * 60) /c `"$msg`""
    if ($code -eq 0) { Write-Ok "$verb scheduled on $c. Use option 3 to cancel." } else { Write-Err "shutdown.exe returned $code (access denied or PC unreachable?)." }
}

Add-Tool -Id 'RMT-08' -Category 'Remote Computers' -Name 'Remote gpupdate' -Description 'Force a Group Policy refresh on a remote PC' -Action {
    $c = Read-RemoteComputer
    if (-not $c) { return }
    $s = New-RemoteCimSession $c
    try {
        $r = Invoke-CimMethod -CimSession $s -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = 'gpupdate.exe /force /wait:0' }
        if ($r.ReturnValue -eq 0) { Write-Ok "gpupdate started on $c (PID $($r.ProcessId)). It completes in the background within a minute or two." }
        else { Write-Err "Could not start gpupdate (code $($r.ReturnValue))." }
    } finally { Remove-CimSession $s }
}

Add-Tool -Id 'RMT-09' -Category 'Remote Computers' -Name 'Open remote consoles' -Description 'Computer Management, Event Viewer, Services, C$, RDP, Remote Assistance' -Action {
    $c = Read-RemoteComputer
    if (-not $c) { return }
    $items = @(
        @{ Name = 'Computer Management';     File = 'compmgmt.msc'; Args = "/computer=\\$c" },
        @{ Name = 'Event Viewer';            File = 'eventvwr.msc'; Args = "/computer=$c" },
        @{ Name = 'Services';                File = 'services.msc'; Args = "/computer=$c" },
        @{ Name = 'Browse the C$ drive';     File = 'explorer.exe'; Args = "\\$c\C`$" },
        @{ Name = 'Remote Desktop';          File = 'mstsc.exe';    Args = "/v:$c" },
        @{ Name = 'Offer Remote Assistance'; File = 'msra.exe';     Args = "/offerra $c" }
    )
    $i = Select-FromList $items { $_.Name } "Open on $c"
    if ($i) { Start-Process -FilePath $i.File -ArgumentList $i.Args }
}

Add-Tool -Id 'RMT-10' -Category 'Remote Computers' -Name 'Remote recent errors' -Description 'Critical/error events from the last 24 hours on a remote PC' -Action {
    $c = Read-RemoteComputer
    if (-not $c) { return }
    try {
        $ev = @(Get-WinEvent -ComputerName $c -FilterHashtable @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = (Get-Date).AddHours(-24) } -MaxEvents 300 -ErrorAction Stop)
    } catch {
        if ($_.Exception.Message -match 'No events') { Write-Ok "No errors on $c in the last 24 hours."; return }
        Write-Err "Could not read the event log: $($_.Exception.Message)"
        Write-Info 'Allow "Remote Event Log Management" in the target PC firewall.'
        return
    }
    $ev | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 20 | ForEach-Object {
        $m = "$($_.Group[0].Message)" -replace '\s+', ' '
        if ($m.Length -gt 90) { $m = $m.Substring(0, 90) + '...' }
        [pscustomobject]@{ Count = $_.Count; Source = $_.Group[0].ProviderName; Id = $_.Group[0].Id; Last = $_.Group[0].TimeCreated; Message = $m }
    } | Format-Table -AutoSize -Wrap | Out-Host
}

Add-Tool -Id 'REM-20' -Category 'Remote Computers' -Name 'Copy files to remote computer' -Description 'Copy files from a server to a remote computer via network share' -Action {
    Write-Info 'File Copy Utility'
    Write-Info 'This will copy one or more files to a remote computer.'

    $computerName = "$(Read-Host '  Remote computer name')".Trim()
    if (-not $computerName) { return }

    $sourcePaths = @()
    while ($true) {
        $source = "$(Read-Host '  Source file path (or press Enter to proceed)')".Trim()
        if (-not $source) { break }
        if (-not (Test-Path -Path $source)) { Write-Warn 'File not found.'; continue }
        $sourcePaths += $source
    }

    if ($sourcePaths.Count -eq 0) { Write-Info 'No files selected.'; return }

    $destFolder = "$(Read-Host '  Destination folder on remote PC (e.g., C:\Temp)')".Trim()
    if (-not $destFolder) { return }

    $remoteDestPath = "\\$computerName\$(($destFolder -split ':')[0])`$\$($destFolder -split '\\', 2 | Select-Object -Last 1)"

    Write-Info "Target: \\$computerName\$destFolder"
    if (-not (Confirm-Action "Copy $($sourcePaths.Count) file(s) to this location?")) { return }

    try {
        if (-not (Test-Path -Path $remoteDestPath)) {
            Write-Info 'Creating destination folder...'
            New-Item -Path $remoteDestPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Ok 'Destination folder created.'
        }
    } catch { Write-Err "Failed to create destination folder: $($_.Exception.Message)"; return }

    $successCount = 0
    foreach ($source in $sourcePaths) {
        try {
            Copy-Item -Path $source -Destination $remoteDestPath -Force -ErrorAction Stop
            $fileName = Split-Path $source -Leaf
            Write-Ok "Copied: $fileName"
            $successCount++
        } catch { Write-Err "Failed to copy $source : $($_.Exception.Message)" }
    }

    Write-Info "Copy operation complete: $successCount of $($sourcePaths.Count) file(s) copied successfully."
    Write-Log "Files copied to remote computer: $computerName ($successCount file(s))"
}

Add-Tool -Id 'REM-21' -Category 'Remote Computers' -Name 'Check registry value on remote computer' -Description 'Query a registry value on remote computers in an organizational unit' -Action {
    Write-Info 'Remote Registry Check'
    Write-Info 'This will query a registry value across multiple computers.'

    $regPath = "$(Read-Host '  Registry path (e.g., HKLM:\Software\...)')".Trim()
    if (-not $regPath) { return }

    $valueName = "$(Read-Host '  Value name')".Trim()
    if (-not $valueName) { return }

    Write-Info 'Specify computers to check:'
    Write-Info '1. All computers in an OU'
    Write-Info '2. Specific computer names'
    $method = "$(Read-Host '  Choose method (1-2)')".Trim()

    $computers = @()

    if ($method -eq '1') {
        $ouPath = "$(Read-Host '  OU Distinguished Name')".Trim()
        if (-not $ouPath) { return }

        try {
            if (-not (Get-Module ActiveDirectory -ErrorAction SilentlyContinue)) {
                Import-Module ActiveDirectory -ErrorAction Stop
            }
            $computers = @(Get-ADComputer -Filter * -SearchBase $ouPath -ErrorAction Stop | Select-Object -ExpandProperty Name)
        } catch { Write-Err "Could not retrieve computers from OU: $($_.Exception.Message)"; return }
    } elseif ($method -eq '2') {
        while ($true) {
            $comp = "$(Read-Host '  Computer name (or Enter to proceed)')".Trim()
            if (-not $comp) { break }
            $computers += $comp
        }
    } else { Write-Warn 'Invalid selection.'; return }

    if ($computers.Count -eq 0) { Write-Warn 'No computers specified.'; return }

    Write-Info "Checking $($computers.Count) computer(s) for registry value '$valueName' in '$regPath'..."
    $results = @()

    $scriptBlock = {
        param($regPath, $valueName)
        $regPath = $regPath -replace '^HKLM:\\', 'HKLM:\'
        try {
            $value = Get-ItemProperty -Path $regPath -Name $valueName -ErrorAction Stop
            return @{
                Computer = $env:COMPUTERNAME
                Status = 'Found'
                Value = $value.$valueName
                Error = $null
            }
        } catch {
            return @{
                Computer = $env:COMPUTERNAME
                Status = 'Not Found'
                Value = $null
                Error = $_.Exception.Message
            }
        }
    }

    $jobs = @()
    foreach ($computer in $computers) {
        $job = Invoke-Command -ComputerName $computer -ScriptBlock $scriptBlock -ArgumentList $regPath, $valueName -AsJob -ErrorAction SilentlyContinue
        if ($job) { $jobs += $job }
    }

    if ($jobs.Count -eq 0) { Write-Warn 'No computers could be reached.'; return }

    Write-Info "Waiting for results from $($jobs.Count) computer(s)..."
    $jobs | Wait-Job | Out-Null

    foreach ($job in $jobs) {
        try {
            $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
            if ($result) {
                $results += [PSCustomObject]@{
                    Computer = $result.Computer
                    Status = $result.Status
                    Value = $result.Value
                    Error = $result.Error
                }
            }
        } catch { Write-Warn "Could not retrieve result from job: $($_.Exception.Message)" }
    }

    Remove-Job -Job $jobs -Force

    if ($results.Count -gt 0) {
        Write-Ok "Registry check results:"
        $results | Format-Table -AutoSize | Out-Host
    } else {
        Write-Warn 'No results returned.'
    }
}
