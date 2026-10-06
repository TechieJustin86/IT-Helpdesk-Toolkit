# Modules\13-Reports.ps1
# Category: Reports
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'RPT-01' -Category 'Reports' -Name 'Full HTML system report' -Description 'One-page report: system, disks, network, security, errors, apps' -Action {
    Write-Info 'Collecting data (30-60 seconds)...'
    $sections = [ordered]@{}
    $sections['System'] = Get-SystemSummary | ConvertTo-Html -As List -Fragment
    $sections['Disks'] = Get-DiskSpace | ConvertTo-Html -Fragment
    $sections['Network'] = Get-NetworkSummary | ConvertTo-Html -Fragment
    $sections['Security checks'] = Get-SecurityAudit | ConvertTo-Html -Fragment
    $sections['Errors (last 24h)'] = Get-RecentErrors -Hours 24 | Select-Object -First 25 | ConvertTo-Html -Fragment
    $sections['Stopped automatic services'] = Get-StoppedAutoServices | ConvertTo-Html -Fragment
    $sections['Recent updates'] = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 15 HotFixID, Description, InstalledOn | ConvertTo-Html -Fragment
    $sections['Startup programs'] = Get-StartupItems | ConvertTo-Html -Fragment
    $sections['Installed software'] = Get-InstalledSoftware | ConvertTo-Html -Fragment

    $css = @'
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#222;background:#f6f7f9}
h1{margin:0 0 4px}h2{margin-top:28px;border-bottom:2px solid #2b6cb0;padding-bottom:4px;color:#2b6cb0}
table{border-collapse:collapse;background:#fff;font-size:13px;margin-top:8px;min-width:50%}
th,td{border:1px solid #d8dde3;padding:5px 9px;text-align:left;vertical-align:top}
th{background:#eef2f7}td:has(+td){white-space:nowrap}
.meta{color:#666}
</style>
'@
    $body = foreach ($k in $sections.Keys) {
        $html = ($sections[$k] -join "`n")
        $html = $html -replace '<td>WARN</td>', '<td style="color:#b7791f;font-weight:600">WARN</td>' -replace '<td>OK</td>', '<td style="color:#2f855a">OK</td>' -replace '<td>LOW</td>', '<td style="color:#c53030;font-weight:600">LOW</td>'
        "<h2>$k</h2>`n$html"
    }
    $page = "<!DOCTYPE html><html><head><meta charset='utf-8'><title>$env:COMPUTERNAME report</title>$css</head><body>" +
            "<h1>$env:COMPUTERNAME</h1><div class='meta'>Generated $(Get-Date) by $env:USERDOMAIN\$env:USERNAME - Helpdesk Toolkit v$Script:Version</div>" +
            ($body -join "`n") + '</body></html>'
    $file = Get-OutFile 'system-report.html'
    $page | Out-File -LiteralPath $file -Encoding UTF8
    Open-File $file
}

Add-Tool -Id 'RPT-02' -Category 'Reports' -Name 'MSInfo32 full export' -Description 'Complete System Information export (.nfo)' -Action {
    $file = Get-OutFile 'msinfo.nfo'
    Write-Info 'Exporting (can take a few minutes)...'
    Start-Process msinfo32.exe -ArgumentList "/nfo `"$file`"" -Wait
    if (Test-Path $file) { Write-Ok "Saved: $file" } else { Write-Err 'Export failed.' }
}

Add-Tool -Id 'RPT-03' -Category 'Reports' -Name 'Copy system summary to clipboard' -Description 'Paste-ready summary for a ticket' -Action {
    $s = Get-SystemSummary
    $net = Get-NetworkSummary | Select-Object -First 1
    $disk = Get-DiskSpace | Where-Object Drive -eq $env:SystemDrive
    $text = ($s.PSObject.Properties | ForEach-Object { '{0}: {1}' -f $_.Name, $_.Value }) -join "`r`n"
    $text += "`r`nIP: $($net.IPv4)  Gateway: $($net.Gateway)  DNS: $($net.DNS)"
    $text += "`r`n$env:SystemDrive free: $($disk.Free) ($($disk.'Free %')%)"
    $text | Set-Clipboard
    Write-Host $text
    Write-Ok 'Copied to clipboard.'
}

Add-Tool -Id 'RPT-04' -Category 'Reports' -Name 'Open output folder' -Description 'Where reports and exports are saved' -Action {
    if (-not (Test-Path $Script:OutDir)) { New-Item -ItemType Directory -Path $Script:OutDir -Force | Out-Null }
    Invoke-Item $Script:OutDir
}

Add-Tool -Id 'RPT-05' -Category 'Reports' -Name 'View toolkit log' -Description 'Last 40 toolkit actions' -Action {
    if (Test-Path $Script:LogFile) { Get-Content $Script:LogFile -Tail 40 | Out-Host } else { Write-Info 'No log yet.' }
}

Add-Tool -Id 'RPT-06' -Category 'Reports' -Name 'Add PC to inventory CSV' -Description 'Append this PC (model, serial, specs, IP) to a shared inventory file' -Action {
    $default = Join-Path $Script:OutDir 'inventory.csv'
    $path = Read-Host "  Inventory file, local or \\server\share path [$default]"
    if (-not $path) { $path = $default }
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $nt   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    $net  = Get-NetworkSummary | Select-Object -First 1
    $row = [pscustomobject]@{
        Recorded     = Get-Date -Format 'yyyy-MM-dd HH:mm'
        Computer     = $env:COMPUTERNAME
        User         = $cs.UserName
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        Serial       = $bios.SerialNumber
        OS           = "$($os.Caption) $($nt.DisplayVersion)"
        Build        = "$($os.BuildNumber).$($nt.UBR)"
        CPU          = "$($cpu.Name)".Trim()
        'RAM GB'     = [math]::Round($cs.TotalPhysicalMemory / 1GB)
        'Disk GB'    = [math]::Round($disk.Size / 1GB)
        'Free GB'    = [math]::Round($disk.FreeSpace / 1GB)
        IP           = $net.IPv4
        MAC          = $net.MAC
        Domain       = $cs.Domain
        BIOS         = $bios.SMBIOSBIOSVersion
    }
    $dir = Split-Path $path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    try { $row | Export-Csv -LiteralPath $path -Append -NoTypeInformation -Encoding UTF8 -Force -ErrorAction Stop }
    catch { Write-Err "Could not write to $path : $($_.Exception.Message)"; return }
    $row | Format-List | Out-Host
    Write-Ok "Added $env:COMPUTERNAME to $path"
}

# Point-in-time health data shared by the dashboard and the support report (from modulesV2 Dashboard/ReportGenerator)
function Get-HealthSnapshot {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    $net = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4Address -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
    $dnsOk = $true
    try { Resolve-DnsName www.microsoft.com -ErrorAction Stop | Out-Null } catch { $dnsOk = $false }
    $mp = $null
    try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { }
    $fw = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
    $bl = 'Unavailable'
    if (Test-IsAdmin) { try { $bl = "$((Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop).ProtectionStatus)" } catch { } }
    $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = (Get-Date).AddHours(-24) } -ErrorAction SilentlyContinue)
    $battery = if (Get-Command Get-BatteryHealthData -ErrorAction SilentlyContinue) { Get-BatteryHealthData } else { [pscustomobject]@{ Present = $false } }
    [pscustomobject]@{
        OS = $os; CS = $cs; BIOS = $bios; CPU = $cpu
        Uptime        = (Get-Date) - $os.LastBootUpTime
        MemoryUsed    = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 1)
        DiskFree      = if ($drive.Size) { [math]::Round($drive.FreeSpace / $drive.Size * 100, 1) } else { 0 }
        DiskFreeGB    = [math]::Round($drive.FreeSpace / 1GB, 1)
        DiskTotalGB   = [math]::Round($drive.Size / 1GB, 1)
        PendingReboot = [bool]@(Get-PendingReboot).Count
        Adapter       = if ($net) { $net.InterfaceAlias } else { 'Not detected' }
        IPv4          = if ($net) { ($net.IPv4Address | Select-Object -First 1).IPAddress } else { 'Not detected' }
        Gateway       = if ($net -and $net.IPv4DefaultGateway) { ($net.IPv4DefaultGateway | Select-Object -First 1).NextHop } else { 'Not detected' }
        DNS           = if ($net) { $net.DNSServer.ServerAddresses -join ', ' } else { 'Not detected' }
        InternetOk    = [bool](Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction SilentlyContinue)
        DnsOk         = $dnsOk
        Defender      = $mp
        Firewall      = if ($fw.Count) { '{0} / {1} profiles enabled' -f @($fw | Where-Object { "$($_.Enabled)" -ne 'False' }).Count, $fw.Count } else { 'Unavailable' }
        BitLocker     = $bl
        Events        = $events
        Battery       = $battery
        Services      = @(foreach ($n in 'wuauserv', 'BITS', 'Spooler', 'WinDefend', 'EventLog', 'Dhcp', 'Dnscache') {
                            $s = Get-Service $n -ErrorAction SilentlyContinue
                            if ($s) { [pscustomobject]@{ Service = $s.DisplayName; Status = "$($s.Status)"; StartType = "$($s.StartType)" } }
                        })
        TopMemory     = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 Name, Id, @{ n = 'RAM MB'; e = { [math]::Round($_.WorkingSet64 / 1MB, 1) } }, @{ n = 'CPU s'; e = { [math]::Round($_.CPU, 1) } }
        TopCpu        = Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, Id, @{ n = 'CPU s'; e = { [math]::Round($_.CPU, 1) } }, @{ n = 'RAM MB'; e = { [math]::Round($_.WorkingSet64 / 1MB, 1) } }
        Software      = @(Get-InstalledSoftware)
    }
}

# Shared HTML pieces: card class, info tile, table fragment
function Get-HealthClass {
    param([string]$Type, [double]$Value)
    switch ($Type) {
        'Memory' { if ($Value -lt 80) { 'good' } elseif ($Value -lt 90) { 'warn' } else { 'bad' } }
        'Disk'   { if ($Value -ge 20) { 'good' } elseif ($Value -ge 10) { 'warn' } else { 'bad' } }
        'Events' { if ($Value -lt 10) { 'good' } elseif ($Value -lt 25) { 'warn' } else { 'bad' } }
        default  { 'neutral' }
    }
}
function ConvertTo-HtmlText { param($Value) [Net.WebUtility]::HtmlEncode("$Value") }
function ConvertTo-HtmlTable {
    param($Data, [string]$Empty = 'No data available.')
    if (-not @($Data).Count) { return "<div class='empty'>$Empty</div>" }
    "<div class='table-wrap'>$(($Data | ConvertTo-Html -Fragment) -join "`n")</div>"
}
function New-HealthCardsHtml {
    param($S)
    $mp = $S.Defender
    $protected = $mp -and $mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled
    $bh = $S.Battery.HealthPercent
    $cards = @(
        @((Get-HealthClass Memory $S.MemoryUsed), 'Memory used', "$($S.MemoryUsed)%", ('{0} GB installed' -f [math]::Round($S.CS.TotalPhysicalMemory / 1GB, 1))),
        @((Get-HealthClass Disk $S.DiskFree), "$env:SystemDrive free space", "$($S.DiskFree)%", "$($S.DiskFreeGB) GB free of $($S.DiskTotalGB) GB"),
        @('neutral', 'Uptime', ('{0}d {1}h' -f $S.Uptime.Days, $S.Uptime.Hours), "Last boot $($S.OS.LastBootUpTime)"),
        @((Get-HealthClass Events $S.Events.Count), 'Critical / error events', "$($S.Events.Count)", 'Last 24 hours'),
        @($(if ($S.PendingReboot) { 'warn' } else { 'good' }), 'Pending reboot', $(if ($S.PendingReboot) { 'YES' } else { 'NO' }), 'Windows restart requirement'),
        @($(if ($S.InternetOk -and $S.DnsOk) { 'good' } else { 'bad' }), 'Network', $(if ($S.InternetOk -and $S.DnsOk) { 'ONLINE' } else { 'ISSUE' }), 'Internet + DNS check'),
        @($(if ($protected) { 'good' } else { 'warn' }), 'Endpoint security', $(if (-not $mp) { 'Unavailable' } elseif ($protected) { 'Protected' } else { 'Check' }), 'Microsoft Defender'),
        @('neutral', 'Installed applications', "$($S.Software.Count)", 'From the uninstall registry'),
        @($(if ($null -eq $bh) { 'neutral' } elseif ($bh -ge 80) { 'good' } elseif ($bh -ge 60) { 'warn' } else { 'bad' }), 'Battery health', $(if ($null -ne $bh) { "$bh%" } else { 'N/A' }), 'Full charge vs design capacity')
    )
    ($cards | ForEach-Object { "<div class='card $($_[0])'><div class='k'>$(ConvertTo-HtmlText $_[1])</div><div class='v'>$(ConvertTo-HtmlText $_[2])</div><div class='s'>$(ConvertTo-HtmlText $_[3])</div></div>" }) -join "`n"
}

function New-InfoGridHtml {
    param([System.Collections.Specialized.OrderedDictionary]$Items)
    "<div class='info'>" + (($Items.Keys | ForEach-Object { "<div><div class='label'>$(ConvertTo-HtmlText $_)</div><div class='value'>$(ConvertTo-HtmlText $Items[$_])</div></div>" }) -join '') + '</div>'
}

function New-HealthSectionsHtml {
    param($S, [switch]$IncludeSoftware)
    $mp = $S.Defender
    $b = $S.Battery
    $onOff = { param($v) if ($null -eq $v) { 'Unavailable' } elseif ($v) { 'Enabled' } else { 'Disabled' } }
    $html = @()
    $html += "<div class='section'><h2>Device overview</h2>" + (New-InfoGridHtml ([ordered]@{
        'Computer' = $env:COMPUTERNAME; 'Manufacturer / model' = "$($S.CS.Manufacturer) $($S.CS.Model)"; 'Serial number' = $S.BIOS.SerialNumber
        'Operating system' = "$($S.OS.Caption) $($S.OS.Version)"; 'CPU' = "$($S.CPU.Name)".Trim(); 'Installed RAM' = "$([math]::Round($S.CS.TotalPhysicalMemory / 1GB, 1)) GB"
        'Current user' = "$env:USERDOMAIN\$env:USERNAME" })) + '</div>'
    $html += "<div class='section'><h2>Battery</h2>" + (New-InfoGridHtml ([ordered]@{
        'Battery' = if ($b.Present) { $b.Name } else { 'No battery detected' }
        'Design capacity' = if ($b.DesignCapacity_mWh) { "$($b.DesignCapacity_mWh) mWh" } else { 'Unavailable' }
        'Full charge capacity' = if ($b.FullChargeCapacity_mWh) { "$($b.FullChargeCapacity_mWh) mWh" } else { 'Unavailable' }
        'Current charge' = if ($null -ne $b.ChargePercent) { "$($b.ChargePercent)%" } else { 'Unavailable' }
        'Health / wear' = if ($null -ne $b.HealthPercent) { "$($b.HealthPercent)% / $($b.WearPercent)%" } else { 'Unavailable' }
        'Cycle count' = if ($null -ne $b.CycleCount) { "$($b.CycleCount)" } else { 'Unavailable' } })) + '</div>'
    $html += "<div class='section'><h2>Network</h2>" + (New-InfoGridHtml ([ordered]@{
        'Active adapter' = $S.Adapter; 'IPv4 address' = $S.IPv4; 'Default gateway' = $S.Gateway; 'DNS servers' = $S.DNS
        'Internet test' = $(if ($S.InternetOk) { 'PASS' } else { 'FAIL' }); 'DNS resolution' = $(if ($S.DnsOk) { 'PASS' } else { 'FAIL' }) })) + '</div>'
    $html += "<div class='section'><h2>Security</h2>" + (New-InfoGridHtml ([ordered]@{
        'Defender antivirus' = & $onOff $mp.AntivirusEnabled; 'Real-time protection' = & $onOff $mp.RealTimeProtectionEnabled
        'Signature version' = $(if ($mp) { $mp.AntivirusSignatureVersion } else { 'Unavailable' }); 'Windows Firewall' = $S.Firewall
        'BitLocker' = $S.BitLocker; 'Pending reboot' = $(if ($S.PendingReboot) { 'Yes' } else { 'No' }) })) + '</div>'
    $html += "<div class='two'><div class='section'><h2>Top memory processes</h2>$(ConvertTo-HtmlTable $S.TopMemory)</div><div class='section'><h2>Top CPU processes</h2>$(ConvertTo-HtmlTable $S.TopCpu)</div></div>"
    $html += "<div class='section'><h2>Core Windows services</h2>$(ConvertTo-HtmlTable $S.Services)</div>"
    $providers = $S.Events | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 10 @{ n = 'Source'; e = { $_.Name } }, Count
    $recent = $S.Events | Select-Object -First 15 TimeCreated, LogName, Id, ProviderName, @{ n = 'Message'; e = { $m = "$($_.Message)" -replace '\s+', ' '; if ($m.Length -gt 180) { $m.Substring(0, 180) + '...' } else { $m } } }
    $html += "<div class='two'><div class='section'><h2>Top error sources - last 24 hours</h2>$(ConvertTo-HtmlTable $providers 'No critical/error events.')</div><div class='section'><h2>Recent critical / error events</h2>$(ConvertTo-HtmlTable $recent 'No critical/error events.')</div></div>"
    if ($IncludeSoftware) { $html += "<div class='section'><h2>Installed software ($($S.Software.Count))</h2>$(ConvertTo-HtmlTable $S.Software)</div>" }
    $html -join "`n"
}

Add-Tool -Id 'RPT-07' -Category 'Reports' -Name 'IT health dashboard (HTML)' -Description 'Dark, at-a-glance dashboard: health cards, security, network, processes, errors' -Action {
    Write-Info 'Collecting data (about 20 seconds)...'
    $s = Get-HealthSnapshot
    $css = @'
<style>
:root{--panel:#121c2e;--panel2:#172338;--text:#e8eef7;--muted:#91a0b5;--border:#26364f;--good:#22c55e;--warn:#f59e0b;--bad:#ef4444;--neutral:#3b82f6}
*{box-sizing:border-box}body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:linear-gradient(180deg,#0b1220,#101827);color:var(--text)}
.wrap{max-width:1500px;margin:auto;padding:28px}.head{display:flex;justify-content:space-between;align-items:flex-start;gap:20px;margin-bottom:22px}
h1{font-size:28px;margin:0 0 6px}.sub{color:var(--muted);font-size:14px}.badge{border:1px solid var(--border);background:var(--panel);padding:8px 12px;border-radius:999px;color:var(--muted);font-size:13px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:14px}
.card{background:var(--panel);border:1px solid var(--border);border-radius:14px;padding:18px;box-shadow:0 10px 30px rgba(0,0,0,.18)}
.k{color:var(--muted);font-size:13px;margin-bottom:9px}.v{font-size:28px;font-weight:700;line-height:1.1}.s{margin-top:7px;color:var(--muted);font-size:12px}
.good{border-left:4px solid var(--good)}.warn{border-left:4px solid var(--warn)}.bad{border-left:4px solid var(--bad)}.neutral{border-left:4px solid var(--neutral)}
.section{background:var(--panel);border:1px solid var(--border);border-radius:14px;padding:20px;margin-top:18px;min-width:0;overflow:hidden}.section h2{font-size:18px;margin:0 0 16px}
.two{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}
.info{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:10px 18px}.info>div{background:var(--panel2);border:1px solid var(--border);border-radius:10px;padding:12px}
.label{font-size:12px;color:var(--muted);margin-bottom:4px}.value{font-size:14px;font-weight:600;word-break:break-word}
.table-wrap{overflow-x:auto;border:1px solid var(--border);border-radius:10px}table{border-collapse:collapse;width:100%;font-size:13px}
th,td{padding:9px 11px;border-bottom:1px solid var(--border);text-align:left;vertical-align:top;overflow-wrap:anywhere}th{color:#b8c6da;font-weight:600;background:#111a2a}
.empty{color:var(--muted);padding:10px 0}.foot{margin:24px 0 4px;color:var(--muted);font-size:12px;text-align:center}
@media(max-width:900px){.two{grid-template-columns:1fr}.head{flex-direction:column}}
</style>
'@
    $page = "<!DOCTYPE html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>IT Dashboard - $(ConvertTo-HtmlText $env:COMPUTERNAME)</title>$css</head><body><div class='wrap'>" +
            "<div class='head'><div><h1>IT Health Dashboard</h1><div class='sub'>$(ConvertTo-HtmlText $env:COMPUTERNAME) &bull; Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div></div><div class='badge'>Helpdesk Toolkit v$Script:Version</div></div>" +
            "<div class='grid'>$(New-HealthCardsHtml $s)</div>$(New-HealthSectionsHtml $s)" +
            "<div class='foot'>Point-in-time snapshot - values do not update automatically.</div></div></body></html>"
    $file = Get-OutFile 'dashboard.html'
    [IO.File]::WriteAllText($file, $page, (New-Object System.Text.UTF8Encoding($true)))
    Open-File $file
}

Add-Tool -Id 'RPT-08' -Category 'Reports' -Name 'Printable support report (HTML)' -Description 'Light, print-friendly health report with installed software - good for tickets or customers' -Action {
    Write-Info 'Collecting data (about 20 seconds)...'
    $s = Get-HealthSnapshot
    $css = @'
<style>
:root{--text:#1f2937;--muted:#64748b;--border:#dbe3ee;--good:#16a34a;--warn:#d97706;--bad:#dc2626;--blue:#2563eb}
*{box-sizing:border-box}body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:#f3f6fb;color:var(--text)}.page{max-width:1450px;margin:0 auto;padding:30px}
.hero{background:linear-gradient(135deg,#0f172a,#1e3a8a);color:white;padding:28px;border-radius:16px;margin-bottom:20px}.hero h1{margin:0 0 7px;font-size:28px}.hero p{margin:0;color:#dbeafe}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:14px}
.card{background:white;border:1px solid var(--border);border-radius:13px;padding:17px;box-shadow:0 5px 18px rgba(15,23,42,.06)}
.card.good{border-top:4px solid var(--good)}.card.warn{border-top:4px solid var(--warn)}.card.bad{border-top:4px solid var(--bad)}.card.neutral{border-top:4px solid var(--blue)}
.k{font-size:12px;color:var(--muted);margin-bottom:7px}.v{font-size:27px;font-weight:700}.s{font-size:12px;color:var(--muted);margin-top:6px}
.section{background:white;border:1px solid var(--border);border-radius:13px;padding:20px;margin-top:18px;overflow:hidden;min-width:0}.section h2{margin:0 0 15px;font-size:18px}
.info{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px}.info>div{background:#f8fafc;border:1px solid var(--border);border-radius:9px;padding:11px}
.label{font-size:11px;color:var(--muted);margin-bottom:3px}.value{font-weight:600;overflow-wrap:anywhere}.two{display:grid;grid-template-columns:1fr 1fr;gap:18px}
.table-wrap{overflow-x:auto;border:1px solid var(--border);border-radius:9px}table{border-collapse:collapse;width:100%;font-size:12px}
th,td{padding:9px;border-bottom:1px solid var(--border);text-align:left;vertical-align:top;overflow-wrap:anywhere}th{background:#eef3f9;color:#334155}
.empty{color:var(--muted);padding:12px}.foot{font-size:11px;color:var(--muted);text-align:center;margin:24px}
@media(max-width:900px){.two{grid-template-columns:1fr}.page{padding:14px}}
@media print{body{background:white}.page{max-width:none;padding:0}.hero{border-radius:0}.section,.card{box-shadow:none;break-inside:avoid}.table-wrap{overflow:visible}table{font-size:9px}}
</style>
'@
    $page = "<!DOCTYPE html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>IT Support Report - $(ConvertTo-HtmlText $env:COMPUTERNAME)</title>$css</head><body><div class='page'>" +
            "<div class='hero'><h1>IT Support &amp; Health Report</h1><p>$(ConvertTo-HtmlText $env:COMPUTERNAME) &bull; Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') by $(ConvertTo-HtmlText "$env:USERDOMAIN\$env:USERNAME")</p></div>" +
            "<div class='grid'>$(New-HealthCardsHtml $s)</div>$(New-HealthSectionsHtml $s -IncludeSoftware)" +
            "<div class='foot'>Point-in-time diagnostic snapshot - Helpdesk Toolkit v$Script:Version. Print with Ctrl+P.</div></div></body></html>"
    $file = Get-OutFile 'support-report.html'
    [IO.File]::WriteAllText($file, $page, (New-Object System.Text.UTF8Encoding($true)))
    Open-File $file
}

Add-Tool -Id 'RPT-09' -Category 'Reports' -Name 'Event log health report' -Description 'Export errors/warnings from Application, System, and Security logs' -Action {
    Write-Section 'Event Log Report Generation'
    Write-Info 'Analyzing recent events...'

    $hours = Read-Host "Hours to analyze (default: 24)"
    if (-not $hours) { $hours = 24 }

    $startTime = (Get-Date).AddHours(-[int]$hours)
    $allEvents = @()

    foreach ($logName in @('Application', 'System', 'Security')) {
        try {
            $events = @(Get-WinEvent -FilterHashtable @{
                LogName = $logName
                Level = 2, 3
                StartTime = $startTime
            } -MaxEvents 500 -ErrorAction SilentlyContinue)

            foreach ($event in $events) {
                $allEvents += [pscustomobject]@{
                    LogName = $logName
                    TimeCreated = $event.TimeCreated
                    Level = $event.LevelDisplayName
                    ProviderName = $event.ProviderName
                    EventId = $event.Id
                    Message = "$($event.Message)".Substring(0, [math]::Min(200, "$($event.Message)".Length))
                }
            }
        } catch { }
    }

    if ($allEvents.Count -eq 0) {
        Write-Ok 'No errors or warnings found in logs'
        return
    }

    $report = $allEvents | Sort-Object TimeCreated -Descending
    Write-Check 'INFO' 'Total Events' $report.Count
    Write-Check 'INFO' 'Time Range' "$startTime to now"
    Write-Host ''

    $report | Select-Object TimeCreated, LogName, Level, ProviderName, EventId | Format-Table -AutoSize | Out-Host

    if (Confirm-Action 'Export full report to CSV?') {
        $report | Export-Results -Name "event-log-report-$([DateTime]::Now.ToString('yyyyMMdd-HHmm')).csv"
    }
}

Add-Tool -Id 'RPT-10' -Category 'Reports' -Name 'Storage and disk report' -Description 'Disk space summary and largest folders on each drive' -Action {
    Write-Section 'Disk Space Report'

    Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object FriendlyName, MediaType, @{n='SizeGB';e={[math]::Round($_.Size/1GB,2)}} | Format-Table -AutoSize | Out-Host

    Write-Section 'Volume Usage'
    Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.SizeRemaining } | Select-Object DriveLetter, FileSystemLabel, @{n='Total';e={Format-Bytes $_.Size}}, @{n='Free';e={Format-Bytes $_.SizeRemaining}}, @{n='Used %';e={[math]::Round((1-$_.SizeRemaining/$_.Size)*100,1)}} | Format-Table -AutoSize | Out-Host

    Write-Host ''
    Write-Info 'Largest folders (this may take 30-60 seconds per drive)...'

    foreach ($drive in (Get-Volume | Where-Object { $_.SizeRemaining } | Select-Object -ExpandProperty DriveLetter)) {
        Write-Host "$drive drive:"
        $path = "${drive}:\"
        $folders = @(Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $size = (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            [pscustomobject]@{ Name = $_.Name; Size = $size }
        })

        $folders | Where-Object Size | Sort-Object Size -Descending | Select-Object -First 5 | ForEach-Object {
            Write-Host "  $($_.Name): $(Format-Bytes $_.Size)"
        }
        Write-Host ''
    }
}
