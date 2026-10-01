# Modules\02-Hardware.ps1
# Category: Hardware & Peripherals
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.
# Converted from modulesV2: PeripheralDiagnostics, BatteryHealth, HardwareInventory.

# Battery capacity data from WMI, falling back to the powercfg battery report
function Get-BatteryHealthData {
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $battery) { return [pscustomobject]@{ Present = $false } }

    $design = $null; $full = $null; $remaining = $null; $cycles = $null
    $static = Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($static.DesignedCapacity -gt 0) { $design = [double]$static.DesignedCapacity }
    $fullData = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($fullData.FullChargedCapacity -gt 0) { $full = [double]$fullData.FullChargedCapacity }
    $status = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $status.RemainingCapacity) { $remaining = [double]$status.RemainingCapacity }
    $cycleData = Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $cycleData.CycleCount) { $cycles = [int]$cycleData.CycleCount }

    if ($null -eq $design -or $null -eq $full -or $null -eq $cycles) {
        # powercfg's HTML report includes design/full capacity and cycle count on most laptops
        $tmp = Join-Path $env:TEMP ("hdt_battery_{0}.html" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
        try {
            powercfg.exe /batteryreport /output "$tmp" | Out-Null
            if (Test-Path $tmp) {
                $html = Get-Content -LiteralPath $tmp -Raw
                $num = { param($pattern) if ($html -match $pattern) { [double]($Matches[1] -replace '[^\d]', '') } }
                if ($null -eq $design) { $design = & $num '(?is)DESIGN\s+CAPACITY.*?([\d,.]+)\s*mWh' }
                if ($null -eq $full)   { $full   = & $num '(?is)FULL\s+CHARGE\s+CAPACITY.*?([\d,.]+)\s*mWh' }
                if ($null -eq $cycles) { $c = & $num '(?is)CYCLE\s+COUNT.*?(\d+)'; if ($null -ne $c) { $cycles = [int]$c } }
            }
        } catch { }
        finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }

    $charge = if ($null -ne $remaining -and $full -gt 0) { [math]::Round($remaining / $full * 100, 1) } else { $battery.EstimatedChargeRemaining }
    $health = $null; $wear = $null
    if ($design -gt 0 -and $null -ne $full) {
        $health = [math]::Round($full / $design * 100, 1)
        $wear = if ($health -gt 100) { 0 } else { [math]::Round(100 - $health, 1) }
    }
    [pscustomobject]@{
        Present                = $true
        Name                   = $battery.Name
        Status                 = $battery.Status
        DesignCapacity_mWh     = $design
        FullChargeCapacity_mWh = $full
        RemainingCapacity_mWh  = $remaining
        ChargePercent          = $charge
        HealthPercent          = $health
        WearPercent            = $wear
        CycleCount             = $cycles
    }
}

function Get-MemoryTestResult {
    $e = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } -MaxEvents 1 -ErrorAction SilentlyContinue
    if (-not $e) { return [pscustomobject]@{ Status = 'NOT TESTED'; Time = $null } }
    $status = if ($e.Message -match 'no errors') { 'PASSED' } elseif ($e.Message -match 'hardware problems|errors') { 'FAILED' } else { 'RESULT AVAILABLE' }
    [pscustomobject]@{ Status = $status; Time = $e.TimeCreated }
}

# Bluetooth radio and paired devices, without the dozens of internal service/profile entries
function Get-BluetoothDevices {
    @(Get-PnpDevice -Class Bluetooth -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -and $_.FriendlyName -notmatch 'Service$|Profile$|Protocol|Enumerator|Transport$|Identification|RFCOMM' })
}

# Windows privacy switch for camera / microphone ("Allow apps to access...")
function Get-PrivacyAccess {
    param([ValidateSet('webcam', 'microphone')][string]$Capability)
    $v = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$Capability" -ErrorAction SilentlyContinue).Value
    $machine = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$Capability" -ErrorAction SilentlyContinue).Value
    if ($machine -eq 'Deny') { return 'Blocked for all users' }
    if ($v -eq 'Deny') { return 'Blocked for this user' }
    'Allowed'
}

Add-Tool -Id 'HW-01' -Category 'Hardware & Peripherals' -Name 'Full peripheral check' -Description 'One-pass status of GPU, monitors, USB, audio, camera, Bluetooth, input, battery' -Action {
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    $bad = @($gpus | Where-Object { $_.ConfigManagerErrorCode -ne 0 }).Count
    Write-Check $(if ($gpus.Count -and -not $bad) { 'OK' } else { 'WARN' }) 'Display / GPU' "$($gpus.Count) adapter(s), $bad with problems"

    $mons = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)
    Write-Check $(if ($mons.Count) { 'OK' } else { 'WARN' }) 'Monitors' "$($mons.Count) detected"

    $usb = @(Get-CimInstance Win32_USBController -ErrorAction SilentlyContinue)
    $bad = @($usb | Where-Object { $_.ConfigManagerErrorCode -ne 0 }).Count
    Write-Check $(if ($usb.Count -and -not $bad) { 'OK' } else { 'WARN' }) 'USB controllers' "$($usb.Count) detected, $bad with problems"

    $audio = @(Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue)
    $bad = @($audio | Where-Object { $_.ConfigManagerErrorCode -ne 0 }).Count
    Write-Check $(if ($audio.Count -and -not $bad) { 'OK' } else { 'WARN' }) 'Audio devices' "$($audio.Count) detected, $bad with problems"

    $pnp = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)
    $cams = @($pnp | Where-Object { $_.Class -in 'Camera', 'Image' })
    Write-Check $(if ($cams.Count) { 'OK' } else { 'INFO' }) 'Cameras' "$($cams.Count) detected, privacy: $(Get-PrivacyAccess webcam)"
    $mic = Get-PrivacyAccess microphone
    Write-Check $(if ($mic -eq 'Allowed') { 'OK' } else { 'WARN' }) 'Microphone access' $mic

    $bt = @(Get-BluetoothDevices)
    Write-Check $(if ($bt.Count) { 'OK' } else { 'INFO' }) 'Bluetooth' "$($bt.Count) adapter/device(s)"

    $kb = @(Get-CimInstance Win32_Keyboard -ErrorAction SilentlyContinue)
    $mouse = @(Get-CimInstance Win32_PointingDevice -ErrorAction SilentlyContinue)
    Write-Check $(if ($kb.Count -and $mouse.Count) { 'OK' } else { 'WARN' }) 'Keyboard / pointing' "$($kb.Count) keyboard(s), $($mouse.Count) pointing device(s)"

    $up = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up').Count
    Write-Check $(if ($up) { 'OK' } else { 'WARN' }) 'Network adapters up' "$up"

    $errors = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction SilentlyContinue).Count
    Write-Check $(if ($errors) { 'WARN' } else { 'OK' }) 'Device Manager errors' "$errors (details: SYS-06)"

    $b = Get-BatteryHealthData
    if ($b.Present) {
        $st = if ($null -eq $b.HealthPercent) { 'INFO' } elseif ($b.HealthPercent -ge 80) { 'OK' } elseif ($b.HealthPercent -ge 60) { 'WARN' } else { 'FAIL' }
        Write-Check $st 'Battery health' $(if ($null -ne $b.HealthPercent) { "$($b.HealthPercent)% of design capacity" } else { 'Capacity data unavailable' })
    } else { Write-Check 'INFO' 'Battery' 'None (desktop)' }

    Write-Host ''
    Write-Info 'This checks detection and drivers. Sound, microphone input, webcam picture, USB sockets and individual keys still need a hands-on test.'
}

Add-Tool -Id 'HW-02' -Category 'Hardware & Peripherals' -Name 'Display / GPU check' -Description 'Graphics adapters, driver version and date, resolution, refresh rate' -Action {
    foreach ($g in Get-CimInstance Win32_VideoController) {
        $st = if ($g.ConfigManagerErrorCode -eq 0) { 'OK' } else { 'WARN' }
        Write-Check $st 'GPU' $g.Name
        Write-Check $st 'Device status' (Get-PnpProblemText $g.ConfigManagerErrorCode)
        Write-Check 'INFO' 'Driver version' "$($g.DriverVersion)  ($(if ($g.DriverDate) { $g.DriverDate.ToString('yyyy-MM-dd') }))"
        if ($g.CurrentHorizontalResolution) { Write-Check 'INFO' 'Resolution' ('{0}x{1} @ {2} Hz' -f $g.CurrentHorizontalResolution, $g.CurrentVerticalResolution, $g.CurrentRefreshRate) }
        Write-Host ''
    }
}

Add-Tool -Id 'HW-03' -Category 'Hardware & Peripherals' -Name 'Monitor detection' -Description 'Connected monitors: make, model, serial, year and connection type' -Action {
    $ids = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)
    if (-not $ids.Count) { Write-Warn 'No monitors reported by Windows.'; return }
    $conn = @{}
    Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction SilentlyContinue | ForEach-Object { $conn[$_.InstanceName] = [uint32]$_.VideoOutputTechnology }
    $types = @{ '0' = 'VGA'; '4' = 'DVI'; '5' = 'HDMI'; '6' = 'LVDS'; '10' = 'DisplayPort'; '11' = 'DisplayPort (internal)'; '15' = 'Miracast'; '16' = 'USB-C / indirect'; '2147483648' = 'Built-in panel' }
    $decode = { param($a) (@($a) | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '' }
    $ids | ForEach-Object {
        $t = $conn[$_.InstanceName]
        [pscustomobject]@{
            Make       = & $decode $_.ManufacturerName
            Model      = & $decode $_.UserFriendlyName
            Serial     = & $decode $_.SerialNumberID
            Year       = $_.YearOfManufacture
            Connection = if ($null -ne $t -and $types.ContainsKey("$t")) { $types["$t"] } elseif ($null -ne $t) { "Type $t" } else { '' }
        }
    } | Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'HW-04' -Category 'Hardware & Peripherals' -Name 'USB controllers and devices' -Description 'USB controller health and currently connected USB devices' -Action {
    Write-Section 'Controllers'
    foreach ($c in Get-CimInstance Win32_USBController -ErrorAction SilentlyContinue) {
        Write-Check $(if ($c.ConfigManagerErrorCode -eq 0) { 'OK' } else { 'WARN' }) (Get-PnpProblemText $c.ConfigManagerErrorCode) $c.Name
    }
    Write-Section 'Connected USB devices'
    $devs = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'USB*' -and $_.Class -notin 'USB', 'HIDClass' -and $_.FriendlyName -notmatch 'Root Hub|Composite Device|Generic USB Hub' })
    if ($devs.Count) { $devs | Sort-Object Class, FriendlyName | Select-Object Class, FriendlyName, Status | Format-Table -AutoSize | Out-Host }
    else { Write-Info 'No USB devices other than hubs and input devices.' }
    Write-Info 'A physical port can only be fully tested by plugging in a known-good device.'
}

Add-Tool -Id 'HW-05' -Category 'Hardware & Peripherals' -Name 'Audio devices and microphone' -Description 'Sound hardware, speakers/mics, audio service and microphone privacy' -Action {
    Write-Section 'Sound hardware'
    foreach ($d in Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue) {
        Write-Check $(if ($d.ConfigManagerErrorCode -eq 0) { 'OK' } else { 'WARN' }) (Get-PnpProblemText $d.ConfigManagerErrorCode) $d.Name
    }
    Write-Section 'Speakers and microphones'
    $ep = @(Get-PnpDevice -Class AudioEndpoint -PresentOnly -ErrorAction SilentlyContinue)
    if ($ep.Count) { $ep | Sort-Object FriendlyName | Select-Object FriendlyName, Status | Format-Table -AutoSize | Out-Host }
    else { Write-Warn 'No speakers or microphones found.' }
    Write-Section 'Services and privacy'
    foreach ($s in 'Audiosrv', 'AudioEndpointBuilder') {
        $svc = Get-Service $s -ErrorAction SilentlyContinue
        if ($svc) { Write-Check $(if ($svc.Status -eq 'Running') { 'OK' } else { 'WARN' }) $svc.DisplayName "$($svc.Status)" }
    }
    $mic = Get-PrivacyAccess microphone
    Write-Check $(if ($mic -eq 'Allowed') { 'OK' } else { 'WARN' }) 'Microphone privacy' $mic
    if ($mic -ne 'Allowed') { Write-Info 'Settings > Privacy & security > Microphone controls this.' }
    Write-Info 'If services are stopped, MNT-16 restarts them.'
}

Add-Tool -Id 'HW-06' -Category 'Hardware & Peripherals' -Name 'Camera check' -Description 'Detected cameras, their status and the camera privacy setting' -Action {
    $cams = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Class -in 'Camera', 'Image' })
    if (-not $cams.Count) { Write-Warn 'No camera detected. Check it is not disabled in the BIOS or by a function key / privacy shutter.' }
    foreach ($c in $cams) { Write-Check $(if ($c.Status -eq 'OK') { 'OK' } else { 'WARN' }) 'Camera' "$($c.FriendlyName) - $($c.Status)" }
    $p = Get-PrivacyAccess webcam
    Write-Check $(if ($p -eq 'Allowed') { 'OK' } else { 'WARN' }) 'Camera privacy' $p
    if ($p -ne 'Allowed') { Write-Info 'Settings > Privacy & security > Camera controls this.' }
}

Add-Tool -Id 'HW-07' -Category 'Hardware & Peripherals' -Name 'Bluetooth check' -Description 'Bluetooth radio, paired devices and the Bluetooth service' -Action {
    $bt = @(Get-BluetoothDevices)
    if (-not $bt.Count) { Write-Info 'No Bluetooth hardware detected.'; return }
    $bt | Sort-Object FriendlyName -Unique | Select-Object FriendlyName, Status | Format-Table -AutoSize | Out-Host
    $svc = Get-Service bthserv -ErrorAction SilentlyContinue
    if ($svc) { Write-Check $(if ($svc.Status -eq 'Running') { 'OK' } else { 'WARN' }) 'Bluetooth Support Service' "$($svc.Status)" }
}

Add-Tool -Id 'HW-08' -Category 'Hardware & Peripherals' -Name 'Keyboard and mouse check' -Description 'Detected keyboards, mice and touchpads with status' -Action {
    $kb = @(Get-CimInstance Win32_Keyboard -ErrorAction SilentlyContinue)
    $ms = @(Get-CimInstance Win32_PointingDevice -ErrorAction SilentlyContinue)
    Write-Check $(if ($kb.Count) { 'OK' } else { 'WARN' }) 'Keyboards' "$($kb.Count)"
    foreach ($k in $kb) { Write-Check 'INFO' '  Keyboard' "$($k.Description) - $($k.Status)" }
    Write-Check $(if ($ms.Count) { 'OK' } else { 'WARN' }) 'Pointing devices' "$($ms.Count)"
    foreach ($m in $ms) { Write-Check 'INFO' '  Mouse / touchpad' "$($m.Description) - $($m.Status)" }
    Write-Info 'Detection does not test every key, button or touchpad gesture.'
}

Add-Tool -Id 'HW-09' -Category 'Hardware & Peripherals' -Name 'Storage controllers' -Description 'SATA/NVMe/RAID controllers and disk health summary' -Action {
    $ctl = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Class -in 'SCSIAdapter', 'HDC' })
    foreach ($c in $ctl) { Write-Check $(if ($c.Status -eq 'OK') { 'OK' } else { 'WARN' }) 'Controller' "$($c.FriendlyName) - $($c.Status)" }
    if (-not $ctl.Count) { Write-Info 'No storage controllers returned.' }
    Write-Section 'Disks'
    Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object FriendlyName, MediaType, BusType, @{ n = 'Size'; e = { Format-Bytes $_.Size } }, HealthStatus,
        @{ n = 'Status'; e = { $_.OperationalStatus -join ', ' } } | Format-Table -AutoSize | Out-Host
    Write-Info 'Temperature, wear and SMART prediction: TRB-09 (Administrator).'
}

Add-Tool -Id 'HW-10' -Category 'Hardware & Peripherals' -Name 'Battery health' -Description 'Design vs full-charge capacity, wear percentage and cycle count' -Action {
    $b = Get-BatteryHealthData
    if (-not $b.Present) { Write-Info 'No battery detected on this computer.'; return }
    $fmt = { param($v, $unit) if ($null -ne $v) { '{0:N0} {1}' -f $v, $unit } else { 'Unavailable' } }
    Write-Check 'INFO' 'Battery' "$($b.Name) ($($b.Status))"
    Write-Check 'INFO' 'Design capacity' (& $fmt $b.DesignCapacity_mWh 'mWh')
    Write-Check 'INFO' 'Full charge capacity' (& $fmt $b.FullChargeCapacity_mWh 'mWh')
    Write-Check 'INFO' 'Remaining now' (& $fmt $b.RemainingCapacity_mWh 'mWh')
    if ($null -ne $b.ChargePercent) {
        Write-Check $(if ($b.ChargePercent -ge 40) { 'OK' } elseif ($b.ChargePercent -ge 20) { 'WARN' } else { 'FAIL' }) 'Current charge' "$($b.ChargePercent)%"
    }
    if ($null -ne $b.HealthPercent) {
        $st, $word = if ($b.HealthPercent -ge 80) { 'OK', 'GOOD' } elseif ($b.HealthPercent -ge 60) { 'WARN', 'FAIR' } else { 'FAIL', 'POOR' }
        Write-Check $st 'Battery health' "$($b.HealthPercent)% ($word) - wear $($b.WearPercent)%"
    } else { Write-Check 'INFO' 'Battery health' 'Unavailable (firmware does not report capacity)' }
    Write-Check 'INFO' 'Cycle count' $(if ($null -eq $b.CycleCount) { 'Unavailable' } elseif ($b.CycleCount -eq 0) { '0 (many laptops do not report cycles)' } else { "$($b.CycleCount)" })
    Write-Info 'Health = full charge capacity / design capacity. Under 60% usually means the battery should be replaced. SYS-05 generates the full Windows report.'
}

Add-Tool -Id 'HW-11' -Category 'Hardware & Peripherals' -Name 'Memory (RAM) details' -Description 'Modules with part/serial numbers, installed vs usable RAM, last memory test' -Action {
    $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $clean = { param($s) $s = "$s".Trim(); if (-not $s -or $s -match '^(0+|F+|Unknown|N/?A|None|Not Specified|To Be Filled By O\.?E\.?M\.?)$') { 'Unavailable' } else { $s } }
    $mods | ForEach-Object {
        [pscustomobject]@{
            Slot         = "$($_.BankLabel) $($_.DeviceLocator)".Trim()
            Manufacturer = & $clean $_.Manufacturer
            PartNumber   = & $clean $_.PartNumber
            Serial       = & $clean $_.SerialNumber
            Size         = Format-Bytes $_.Capacity
            'MHz'        = $_.Speed
            'Running MHz'= $_.ConfiguredClockSpeed
        }
    } | Format-Table -AutoSize | Out-Host
    $installed = ($mods | Measure-Object Capacity -Sum).Sum
    $usable = (Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize * 1KB
    Write-Check 'INFO' 'Installed RAM' (Format-Bytes $installed)
    Write-Check 'INFO' 'Usable RAM' (Format-Bytes $usable)
    $reserved = [math]::Max(0, $installed - $usable)
    Write-Check $(if ($installed -and $reserved / $installed -gt 0.15) { 'WARN' } else { 'INFO' }) 'Hardware reserved' "$(Format-Bytes $reserved) (integrated graphics and firmware)"
    Write-Check 'INFO' 'Modules' "$($mods.Count)"
    $t = Get-MemoryTestResult
    $st = switch ($t.Status) { 'PASSED' { 'OK' } 'FAILED' { 'FAIL' } default { 'INFO' } }
    Write-Check $st 'Last memory test' "$($t.Status)$(if ($t.Time) { " on $($t.Time)" })"
    Write-Info 'TRB-15 schedules the Windows Memory Diagnostic.'
}

Add-Tool -Id 'HW-12' -Category 'Hardware & Peripherals' -Name 'Battery reports' -Description 'Generate 7/28-day history, energy analysis, or sleep study reports' -Action {
    Write-Section 'Battery Reports'
    Write-Info 'Generate battery reports using Windows PowerCfg:'
    Write-Host ''
    Write-Host '  1. 7-day Quick Report'
    Write-Host '  2. 28-day Detailed Report'
    Write-Host '  3. Sleep Study (Modern Standby)'
    Write-Host '  4. Energy Efficiency Report (requires admin, 60 seconds)'
    Write-Host '  0. Return to menu'
    Write-Host ''

    $choice = Read-Host 'Select option'

    switch ($choice) {
        '1' {
            $outPath = "$env:USERPROFILE\Desktop\BatteryReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
            Write-Info "Generating 7-day battery report..."
            powercfg /batteryreport /output "$outPath" /duration 7 2>&1 | Out-Null
            if (Test-Path $outPath) {
                Write-Check 'OK' 'Report saved' $outPath
                Start-Process $outPath
            }
        }
        '2' {
            $outPath = "$env:USERPROFILE\Desktop\BatteryReport_Detailed_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
            Write-Info "Generating 28-day battery report..."
            powercfg /batteryreport /output "$outPath" /duration 28 2>&1 | Out-Null
            if (Test-Path $outPath) {
                Write-Check 'OK' 'Report saved' $outPath
                Start-Process $outPath
            }
        }
        '3' {
            $outPath = "$env:USERPROFILE\Desktop\SleepStudy_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
            Write-Info "Generating sleep study report..."
            powercfg /sleepstudy /output "$outPath" /duration 7 2>&1 | Out-Null
            if (Test-Path $outPath) {
                Write-Check 'OK' 'Report saved' $outPath
                Start-Process $outPath
            } else {
                Write-Warn 'Sleep Study unavailable - requires Modern Standby support'
            }
        }
        '4' {
            if (-not (Test-IsAdmin)) {
                Write-Warn 'Energy report requires Administrator privileges'
                return
            }
            Write-Info "Running energy analysis (60 seconds) - keep system active..."
            $outPath = "$env:USERPROFILE\Desktop\EnergyReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
            powercfg /energy /output "$outPath" /duration 60 2>&1 | Out-Null
            if (Test-Path $outPath) {
                Write-Check 'OK' 'Report saved' $outPath
                Start-Process $outPath
            }
        }
        default { Write-Warn 'Cancelled' }
    }
}

Add-Tool -Id 'HW-13' -Category 'Hardware & Peripherals' -Name 'Storage SMART health' -Description 'Physical disks: reallocated sectors, read errors, temperature and wear level' -Action {
    Write-Section 'Storage Health Status'
    $disks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    if (-not $disks) { Write-Warn 'No physical disks found'; return }

    $disks | ForEach-Object {
        Write-Host "Disk: $($_.FriendlyName)" -ForegroundColor Cyan
        Write-Check $(if ($_.HealthStatus -eq 'Healthy') { 'OK' } else { 'WARN' }) 'Health' $_.HealthStatus
        Write-Check 'INFO' 'MediaType' $_.MediaType
        Write-Check 'INFO' 'Size' (Format-Bytes $_.Size)
        Write-Check 'INFO' 'Bus Type' $_.BusType

        try {
            $disk = Get-PhysicalDisk -DeviceNumber $_.DeviceId -ErrorAction SilentlyContinue
            $reliability = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction SilentlyContinue
            if ($reliability) {
                $reallocated = if ($reliability.ReallocateCount) { $reliability.ReallocateCount } else { 'N/A' }
                $readErrors = if ($reliability.ReadErrorsTotal) { $reliability.ReadErrorsTotal } else { 'N/A' }
                Write-Check 'INFO' 'Reallocated Sectors' $reallocated
                Write-Check 'INFO' 'Read Errors' $readErrors
                Write-Check 'INFO' 'Temperature' $(if ($reliability.Temperature) { "$($reliability.Temperature)°C" } else { 'N/A' })
                Write-Check 'INFO' 'Wear Level' $(if ($reliability.Wear) { "$($reliability.Wear)%" } else { 'N/A' })
            }
        } catch { }
        Write-Host ''
    }
    if (-not (Test-IsAdmin)) {
        Write-Info 'SMART attributes: Run with administrator privileges for detailed reliability data'
    }
}

Add-Tool -Id 'HW-14' -Category 'Hardware & Peripherals' -Name 'RAM slot utilization' -Description 'Memory modules by slot: speed, type, capacity and identification' -Action {
    Write-Section 'RAM Slot Details'
    $arrays = @(Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue)
    if (-not $arrays) { Write-Warn 'Unable to query memory array'; return }

    $arrays | ForEach-Object {
        $totalSlots = $_.MemoryDevices
        Write-Check 'INFO' 'Total slots' "$totalSlots"
        Write-Check 'INFO' 'Max capacity' (Format-Bytes ($_.MaxCapacity * 1KB))
    }

    $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    Write-Section 'Installed Modules'

    $ddrType = @{ 20='DDR'; 21='DDR2'; 22='DDR2 FB-DIMM'; 24='DDR3'; 26='DDR4'; 30='LPDDR4'; 34='DDR5'; 35='LPDDR5' }
    $mods | ForEach-Object {
        $type = if ($ddrType.ContainsKey($_.MemoryType)) { $ddrType[$_.MemoryType] } else { "Type $($_.MemoryType)" }
        [pscustomobject]@{
            Slot      = "$($_.BankLabel)".Trim()
            Type      = $type
            Speed     = "$($_.Speed) MHz"
            Capacity  = Format-Bytes $_.Capacity
            Manufacturer = "$($_.Manufacturer)".Trim()
        }
    } | Format-Table -AutoSize | Out-Host

    $utilization = "$($mods.Count) / $($totalSlots)"
    Write-Check 'INFO' 'Slot utilization' $utilization
}

