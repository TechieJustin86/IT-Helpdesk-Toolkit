# Modules\03-Network.ps1
# Category: Network
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'NET-01' -Category 'Network' -Name 'IP configuration' -Description 'Active adapters: IP, gateway, DNS, DHCP, MAC' -Action {
    Get-NetworkSummary | Format-List | Out-Host
}

Add-Tool -Id 'NET-02' -Category 'Network' -Name 'Connectivity test' -Description 'Step-by-step: gateway, internet, DNS, HTTP' -Action {
    $gw = (Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4DefaultGateway.NextHop
    $ok = $true
    if ($gw) {
        if (Test-Connection -ComputerName $gw -Count 2 -Quiet) { Write-Ok "Gateway $gw reachable" } else { Write-Err "Gateway $gw NOT reachable (local network / Wi-Fi / cable problem)"; $ok = $false }
    } else { Write-Err 'No default gateway - adapter is not connected or has no DHCP lease.'; $ok = $false }

    if (Test-Connection -ComputerName 1.1.1.1 -Count 2 -Quiet) { Write-Ok 'Internet reachable by IP (1.1.1.1)' } else { Write-Err 'Cannot reach 1.1.1.1 - no internet or ICMP blocked'; $ok = $false }

    try { $d = Resolve-DnsName www.microsoft.com -ErrorAction Stop | Where-Object IPAddress | Select-Object -First 1; Write-Ok "DNS resolution working (www.microsoft.com -> $($d.IPAddress))" }
    catch { Write-Err 'DNS resolution FAILED - check DNS servers (try NET-03 flush DNS)'; $ok = $false }

    try {
        $r = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 10
        if ($r.Content -like 'Microsoft Connect Test*') { Write-Ok 'HTTP test passed' } else { Write-Warn 'HTTP returned unexpected content - captive portal or proxy?' }
    } catch { Write-Err "HTTP test failed: $($_.Exception.Message)"; $ok = $false }

    if ($ok) { Write-Ok 'All connectivity checks passed.' }
}

Add-Tool -Id 'NET-03' -Category 'Network' -Name 'Flush DNS / renew IP' -Description 'Clear DNS cache and optionally release/renew DHCP' -Action {
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    ipconfig /flushdns | Out-Host
    if (Confirm-Action 'Also release and renew the IP address? (connection drops briefly)') {
        ipconfig /release | Out-Null
        ipconfig /renew | Out-Null
        Write-Ok 'IP renewed.'
        Get-NetworkSummary | Select-Object Adapter, IPv4, Gateway | Format-Table -AutoSize | Out-Host
    }
}

Add-Tool -Id 'NET-04' -Category 'Network' -Name 'Reset network stack' -Admin -Description 'Winsock + TCP/IP reset + DNS and ARP flush (reboot required)' -Action {
    if (-not (Confirm-Action 'Reset Winsock and TCP/IP? A reboot is required afterwards. Saved Wi-Fi networks are kept.')) { return }
    $null = Invoke-External 'netsh.exe' 'winsock reset'
    $null = Invoke-External 'netsh.exe' 'int ip reset'
    $null = Invoke-External 'netsh.exe' 'int ipv6 reset'
    ipconfig /flushdns | Out-Null
    netsh interface ip delete arpcache | Out-Null
    Write-Ok 'Network stack reset.'
    if (Confirm-Action 'Reboot now?') { Restart-Computer -Force }
}

Add-Tool -Id 'NET-05' -Category 'Network' -Name 'Public IP and ISP' -Description 'Show external IP address, ISP and location' -Action {
    try {
        $r = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -TimeoutSec 10
        [pscustomobject]@{ 'Public IP' = $r.ip; ISP = $r.org; City = $r.city; Region = $r.region; Country = $r.country } | Format-List | Out-Host
    } catch { Write-Err "Lookup failed: $($_.Exception.Message)" }
}

Add-Tool -Id 'NET-06' -Category 'Network' -Name 'Test TCP port' -Description 'Check if a host:port is reachable (e.g. 443, 3389)' -Action {
    $h = Read-Host '  Host name or IP'
    if (-not $h) { return }
    $p = Read-Host '  Port [443]'
    if ($p -notmatch '^\d+$') { $p = 443 }
    Test-NetConnection -ComputerName $h -Port ([int]$p) -WarningAction SilentlyContinue |
        Select-Object ComputerName, RemoteAddress, RemotePort, TcpTestSucceeded, @{n = 'Source'; e = { $_.SourceAddress.IPAddress } } | Format-List | Out-Host
}

Add-Tool -Id 'NET-07' -Category 'Network' -Name 'Traceroute' -Description 'Trace the route to a host' -Action {
    $h = Read-Host '  Host [8.8.8.8]'
    if (-not $h) { $h = '8.8.8.8' }
    $null = Invoke-External 'tracert.exe' "-d -w 1000 -h 25 $h"
}

Add-Tool -Id 'NET-08' -Category 'Network' -Name 'Saved Wi-Fi networks and keys' -Description 'List saved Wi-Fi profiles, optionally reveal keys' -Action {
    $profiles = @(netsh wlan show profiles | Select-String -Pattern ':\s*(.+)$' | Where-Object { $_.Line -match 'All User Profile|Profil' } | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() })
    if (-not $profiles.Count) { Write-Warn 'No saved Wi-Fi profiles (or no wireless adapter).'; return }
    $reveal = Confirm-Action 'Reveal saved passwords? (Administrator may be required)'
    $profiles | ForEach-Object {
        $name = $_
        $key = ''
        if ($reveal) {
            $line = netsh wlan show profile name="$name" key=clear | Select-String 'Key Content'
            if ($line) { $key = ($line.Line -split ':', 2)[1].Trim() }
        }
        [pscustomobject]@{ Network = $name; Password = $key }
    } | Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'NET-09' -Category 'Network' -Name 'Wi-Fi status and report' -Description 'Signal, band, speed; generate WLAN report' -Action {
    netsh wlan show interfaces | Out-Host
    if ((Test-IsAdmin) -and (Confirm-Action 'Generate the detailed WLAN report (last 3 days)?')) {
        netsh wlan show wlanreport | Out-Null
        Open-File "$env:ProgramData\Microsoft\Windows\WlanReport\wlan-report-latest.html"
    }
}

# Port helpers (from modulesV2 PortTools): who can reach a port, and what it usually is
function Get-PortBinding {
    param([string]$Address)
    if ($Address -in '127.0.0.1', '::1') { 'Local only' } elseif ($Address -in '0.0.0.0', '::') { 'All interfaces' } else { 'One interface' }
}

function Get-PortCategory {
    param([int]$Port, [string]$Process)
    $known = @{ 21 = 'FTP'; 22 = 'SSH'; 53 = 'DNS'; 80 = 'HTTP'; 135 = 'Windows RPC'; 137 = 'NetBIOS'; 139 = 'NetBIOS session'; 443 = 'HTTPS'
                445 = 'SMB file sharing'; 1433 = 'SQL Server'; 3306 = 'MySQL'; 3389 = 'Remote Desktop'; 5040 = 'Windows (CDP)'; 5357 = 'Network discovery'
                5432 = 'PostgreSQL'; 5985 = 'WinRM HTTP'; 5986 = 'WinRM HTTPS'; 7680 = 'Delivery Optimization'; 8080 = 'HTTP alternate'; 8443 = 'HTTPS alternate' }
    if ($known.ContainsKey($Port)) { return $known[$Port] }
    switch -Regex ($Process) {
        'AnyDesk|TeamViewer|rustdesk|ScreenConnect|vnc' { return 'Remote access' }
        'postgres' { return 'PostgreSQL' }
        'mysqld' { return 'MySQL' }
        '^node$' { return 'Node.js / development' }
        'spoolsv' { return 'Print spooler' }
        'lsass' { return 'Windows security' }
        '^(svchost|services|wininit)$' { return 'Windows service' }
        '^System$' { return 'Windows system' }
    }
    'Application'
}

function Get-PortNote {
    param([string]$Binding, [int]$Port, [string]$Process)
    if ($Binding -eq 'Local only') { return 'Only reachable from this PC' }
    if ($Port -eq 445) { return 'File sharing - reachable on the local network' }
    if ($Port -eq 3389) { return 'Remote Desktop is exposed' }
    if ($Process -match 'AnyDesk|TeamViewer|rustdesk|ScreenConnect|vnc') { return 'Remote access software is listening' }
    if ($Process -match 'postgres|mysqld|sqlservr') { return 'Database listening beyond localhost' }
    if ($Binding -eq 'All interfaces') { return 'Listening on all network interfaces' }
    'Listening on one interface'
}

Add-Tool -Id 'NET-10' -Category 'Network' -Name 'Listening ports' -Description 'Open TCP ports, owning process and how exposed each one is' -Action {
    $procs = @{}
    Get-Process | ForEach-Object { $procs[$_.Id] = $_.ProcessName }
    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Sort-Object LocalPort, LocalAddress | ForEach-Object {
        $name = if ($_.OwningProcess -eq 4) { 'System' } elseif ($procs.ContainsKey([int]$_.OwningProcess)) { $procs[[int]$_.OwningProcess] } else { 'Unknown' }
        $bind = Get-PortBinding $_.LocalAddress
        [pscustomobject]@{
            Port     = $_.LocalPort
            Address  = $_.LocalAddress
            Process  = $name
            PID      = $_.OwningProcess
            Binding  = $bind
            Category = Get-PortCategory $_.LocalPort $name
            Note     = Get-PortNote $bind $_.LocalPort $name
        }
    } | Format-Table -AutoSize -Wrap | Out-Host
    Write-Info 'A listening port is not automatically reachable from the internet - the firewall and router still apply. NET-27 inspects one port.'
    Write-Section 'Established connections by process'
    Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Group-Object OwningProcess | Sort-Object Count -Descending | Select-Object -First 10 |
        Select-Object Count, @{n = 'Process'; e = { $procs[[int]$_.Name] } } | Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'NET-11' -Category 'Network' -Name 'Restart network adapter' -Admin -Description 'Disable/enable a selected adapter' -Action {
    $a = Select-FromList (Get-NetAdapter | Sort-Object Name) { '{0,-25} {1,-12} {2}' -f $_.Name, $_.Status, $_.InterfaceDescription } 'Adapter to restart'
    if ($a) { Restart-NetAdapter -Name $a.Name -Confirm:$false; Write-Ok "Restarted $($a.Name)." }
}

Add-Tool -Id 'NET-12' -Category 'Network' -Name 'Mapped drives and shares' -Description 'Network drive mappings and local SMB shares' -Action {
    Write-Section 'Mapped network drives (current user)'
    $m = @(Get-SmbMapping -ErrorAction SilentlyContinue)
    if ($m.Count) { $m | Select-Object LocalPath, RemotePath, Status | Format-Table -AutoSize | Out-Host } else { net use | Out-Host }
    Write-Section 'Local shares'
    Get-SmbShare -ErrorAction SilentlyContinue | Select-Object Name, Path, Description | Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'NET-13' -Category 'Network' -Name 'Proxy settings' -Description 'User (WinINET) and system (WinHTTP) proxy configuration' -Action {
    $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    [pscustomobject]@{
        'Proxy enabled' = [bool]$ie.ProxyEnable
        'Proxy server'  = $ie.ProxyServer
        'Bypass list'   = $ie.ProxyOverride
        'PAC script'    = $ie.AutoConfigURL
    } | Format-List | Out-Host
    Write-Section 'WinHTTP (system) proxy'
    netsh winhttp show proxy | Out-Host
}

Add-Tool -Id 'NET-14' -Category 'Network' -Name 'View hosts file' -Description 'Show active entries in the hosts file' -Action {
    $hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
    $lines = @(Get-Content -LiteralPath $hosts | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' })
    if ($lines.Count) { Write-Warn "$($lines.Count) active entries:"; $lines | ForEach-Object { Write-Host "    $_" } }
    else { Write-Ok 'Hosts file has no active entries.' }
}

Add-Tool -Id 'NET-15' -Category 'Network' -Name 'Network scan (ping sweep)' -Description 'Find live hosts on the local /24 subnet' -Action {
    $ip = (Get-NetIPConfiguration | Where-Object IPv4DefaultGateway | Select-Object -First 1).IPv4Address.IPAddress
    if (-not $ip) { Write-Err 'No active IPv4 network found.'; return }
    $prefix = ($ip -split '\.')[0..2] -join '.'
    Write-Info "Scanning $prefix.1-254 (takes ~30 seconds)..."
    $pings = 1..254 | ForEach-Object {
        $p = New-Object System.Net.NetworkInformation.Ping
        [pscustomobject]@{ IP = "$prefix.$_"; Task = $p.SendPingAsync("$prefix.$_", 800) }
    }
    [void][Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]$pings.Task)
    $arp = @{}
    Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $arp[$_.IPAddress] = $_.LinkLayerAddress }
    $pings | Where-Object { $_.Task.Result.Status -eq 'Success' } | ForEach-Object {
        $name = try { [Net.Dns]::GetHostEntry($_.IP).HostName } catch { '' }
        [pscustomobject]@{ IP = $_.IP; 'Hostname' = $name; MAC = $arp[$_.IP]; 'ms' = $_.Task.Result.RoundtripTime }
    } | Sort-Object { [version]$_.IP } | Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'NET-16' -Category 'Network' -Name 'DNS lookup (compare servers)' -Description 'Resolve a name with your DNS, Cloudflare and Google side by side' -Action {
    $name = Read-Host '  Name to look up [www.microsoft.com]'
    if (-not $name) { $name = 'www.microsoft.com' }
    $type = Read-Host '  Record type: A, AAAA, MX, TXT, CNAME, NS, PTR [A]'
    if (-not $type) { $type = 'A' }
    $type = $type.ToUpper()
    $servers = [ordered]@{ 'Your DNS' = $null; 'Cloudflare 1.1.1.1' = '1.1.1.1'; 'Google 8.8.8.8' = '8.8.8.8' }
    $rows = foreach ($label in $servers.Keys) {
        $p = @{ Name = $name; Type = $type; DnsOnly = $true; NoHostsFile = $true; ErrorAction = 'Stop' }
        if ($servers[$label]) { $p.Server = $servers[$label] }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            $vals = @(Resolve-DnsName @p | Where-Object Section -eq 'Answer' | ForEach-Object {
                if ($_.IPAddress) { $_.IPAddress }
                elseif ($_.NameExchange) { "$($_.Preference) $($_.NameExchange)" }
                elseif ($_.Strings) { $_.Strings -join '' }
                elseif ($_.NameHost) { $_.NameHost }
                elseif ($_.NameTarget) { $_.NameTarget }
            })
            $result = if ($vals.Count) { ($vals | Select-Object -Unique) -join ', ' } else { '(no records)' }
        } catch { $result = "FAILED: $($_.Exception.Message)" }
        [pscustomobject]@{ Server = $label; ms = $sw.ElapsedMilliseconds; Result = $result }
    }
    $rows | Format-Table -AutoSize -Wrap | Out-Host
    Write-Info 'If only "Your DNS" fails or gives different answers, the problem is your DNS server or DNS filtering.'
}

Add-Tool -Id 'NET-17' -Category 'Network' -Name 'Change DNS servers' -Admin -Description 'Set an adapter to automatic, Cloudflare, Google, Quad9 or custom DNS' -Action {
    $a = Select-FromList @(Get-NetAdapter | Where-Object Status -eq 'Up' | Sort-Object Name) { '{0,-22} {1}' -f $_.Name, $_.InterfaceDescription } 'Adapter'
    if (-not $a) { return }
    $current = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4).ServerAddresses -join ', '
    Write-Info "Current DNS on $($a.Name): $current"
    $choices = @(
        @{ Name = 'Automatic (from DHCP)';                 Servers = @() },
        @{ Name = 'Cloudflare   1.1.1.1, 1.0.0.1';         Servers = @('1.1.1.1', '1.0.0.1') },
        @{ Name = 'Google       8.8.8.8, 8.8.4.4';         Servers = @('8.8.8.8', '8.8.4.4') },
        @{ Name = 'Quad9        9.9.9.9, 149.112.112.112'; Servers = @('9.9.9.9', '149.112.112.112') },
        @{ Name = 'Custom...';                             Servers = $null }
    )
    $c = Select-FromList $choices { $_.Name } 'DNS servers'
    if (-not $c) { return }
    $servers = $c.Servers
    if ($null -eq $servers) {
        $in = Read-Host '  DNS server IPs, comma separated'
        $servers = @($in -split '[,; ]+' | Where-Object { $_ -and ($_ -as [ipaddress]) })
        if (-not $servers.Count) { Write-Err 'No valid IP addresses entered.'; return }
    }
    $desc = if ($servers.Count) { $servers -join ', ' } else { 'automatic (DHCP)' }
    if (-not (Confirm-Action "Set DNS on '$($a.Name)' to $desc?")) { return }
    if ($servers.Count) { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $servers }
    else { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses }
    Clear-DnsClientCache
    Write-Ok ('DNS is now: ' + ((Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4).ServerAddresses -join ', '))
}

Add-Tool -Id 'NET-18' -Category 'Network' -Name 'Map / unmap network drive' -Description 'Map a share to a drive letter, or remove a mapping' -Action {
    Write-Host '  [1] Map a network drive   [2] Remove a mapped drive'
    $c = Read-Host '  Choice'
    if ($c -eq '1') {
        $path = Read-Host '  Share path (e.g. \\server\share)'
        if ($path -notmatch '^\\\\[^\\]+\\.+') { Write-Err 'Enter a UNC path like \\server\share'; return }
        $used = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object Name)
        $free = [char[]](90..68) | Where-Object { $used -notcontains [string]$_ } | Select-Object -First 1
        $letter = Read-Host "  Drive letter [$free]"
        if (-not $letter) { $letter = $free }
        $letter = "$letter".TrimEnd(':').ToUpper()
        $params = @{ Name = $letter; PSProvider = 'FileSystem'; Root = $path; Persist = $true; Scope = 'Global'; ErrorAction = 'Stop' }
        if (Confirm-Action 'Connect with a different username and password?') {
            $user = Read-Host '  Username (DOMAIN\user)'
            $pw = Read-Host '  Password' -AsSecureString
            $params.Credential = New-Object System.Management.Automation.PSCredential($user, $pw)
        }
        if (Test-IsAdmin) { Write-Warn 'Running as Administrator: the drive may not appear in Explorer for the normal (non-elevated) session.' }
        try { New-PSDrive @params | Out-Null; Write-Ok "Mapped $($letter): to $path" }
        catch { Write-Err "Mapping failed: $($_.Exception.Message)" }
    } elseif ($c -eq '2') {
        $maps = @(Get-CimInstance Win32_MappedLogicalDisk -ErrorAction SilentlyContinue)
        $m = Select-FromList $maps { '{0}  {1}' -f $_.Name, $_.ProviderName } 'Drive to remove'
        if ($m -and (Confirm-Action "Remove mapping $($m.Name) ($($m.ProviderName))?")) { net use $m.Name /delete /y 2>&1 | Out-Host }
    }
}

Add-Tool -Id 'NET-19' -Category 'Network' -Name 'Wake-on-LAN' -Description 'Send a magic packet to wake a PC on this network' -Action {
    $mac = Read-Host '  MAC address of the PC to wake (e.g. 58-11-22-3B-80-DA)'
    $hex = $mac -replace '[^0-9A-Fa-f]', ''
    if ($hex.Length -ne 12) { Write-Err 'That is not a valid MAC address.'; return }
    $macBytes = @(0..5 | ForEach-Object { [Convert]::ToByte($hex.Substring($_ * 2, 2), 16) })
    $packet = [byte[]]((@(0xFF) * 6) + ($macBytes * 16))
    # Send to the global broadcast and each local subnet's broadcast address
    $targets = @('255.255.255.255')
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | ForEach-Object {
        $b = ([ipaddress]$_.IPAddress).GetAddressBytes(); [array]::Reverse($b)
        $n = [int64][BitConverter]::ToUInt32($b, 0)
        $hostBits = [int64][math]::Pow(2, 32 - $_.PrefixLength) - 1
        $bc = [BitConverter]::GetBytes([uint32]($n -bor $hostBits)); [array]::Reverse($bc)
        $targets += ([ipaddress]$bc).ToString()
    }
    $udp = New-Object System.Net.Sockets.UdpClient
    try {
        $udp.EnableBroadcast = $true
        foreach ($t in ($targets | Select-Object -Unique)) { foreach ($port in 7, 9) { [void]$udp.Send($packet, $packet.Length, $t, $port) } }
    } finally { $udp.Close() }
    Write-Ok ("Magic packet sent to {0} via {1}" -f ($hex -replace '(..)(?!$)', '$1-').ToUpper(), (($targets | Select-Object -Unique) -join ', '))
    Write-Info 'The target must have Wake-on-LAN enabled in its BIOS and network adapter settings, and be on this network.'
}

Add-Tool -Id 'NET-20' -Category 'Network' -Name 'Internet speed test' -Description 'Latency, download and upload speed (Cloudflare)' -Action {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $base = 'https://speed.cloudflare.com'
    $wc = New-Object System.Net.WebClient
    try {
        Write-Info 'Measuring latency...'
        # first request includes the TLS handshake, so it is skipped
        $samples = foreach ($i in 1..6) {
            $wc.Headers['User-Agent'] = 'HelpdeskToolkit'
            $sw = [Diagnostics.Stopwatch]::StartNew(); [void]$wc.DownloadData("$base/__down?bytes=0"); $sw.Elapsed.TotalMilliseconds
        }
        $lat = @($samples | Select-Object -Skip 1 | Sort-Object)
        Write-Ok ('Latency:  {0:N0} ms (HTTPS request round trip - ping is usually lower)' -f $lat[[int]($lat.Count / 2)])
        Write-Info 'Testing download (25 MB)...'
        $wc.Headers['User-Agent'] = 'HelpdeskToolkit'
        $sw = [Diagnostics.Stopwatch]::StartNew(); $data = $wc.DownloadData("$base/__down?bytes=25000000"); $sw.Stop()
        Write-Ok ('Download: {0:N1} Mbps' -f ($data.Length * 8 / $sw.Elapsed.TotalSeconds / 1e6))
        Write-Info 'Testing upload (10 MB)...'
        $payload = New-Object byte[] 10000000
        $wc.Headers['User-Agent'] = 'HelpdeskToolkit'
        $wc.Headers['Content-Type'] = 'application/octet-stream'
        $sw = [Diagnostics.Stopwatch]::StartNew(); [void]$wc.UploadData("$base/__up", 'POST', $payload); $sw.Stop()
        Write-Ok ('Upload:   {0:N1} Mbps' -f ($payload.Length * 8 / $sw.Elapsed.TotalSeconds / 1e6))
    } catch { Write-Err "Speed test failed: $($_.Exception.Message)" }
    finally { $wc.Dispose() }
}

Add-Tool -Id 'NET-21' -Category 'Network' -Name 'Ping monitor (packet loss)' -Description 'Ping a host once a second to catch drops and lag spikes' -Action {
    $gw = (Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object IPv4DefaultGateway | Select-Object -First 1).IPv4DefaultGateway.NextHop
    $hint = if ($gw) { " - your gateway is $gw" } else { '' }
    $h = Read-Host "  Host to ping [8.8.8.8]$hint"
    if (-not $h) { $h = '8.8.8.8' }
    $n = Read-Host '  Number of pings [60]'
    if ($n -notmatch '^\d+$') { $n = 60 }
    $n = [int]$n
    $ping = New-Object System.Net.NetworkInformation.Ping
    $times = New-Object System.Collections.Generic.List[double]
    $lost = 0
    Write-Info "Pinging $h $n times..."
    for ($i = 1; $i -le $n; $i++) {
        $r = $null
        try { $r = $ping.Send($h, 1000) } catch { }
        $stamp = Get-Date -Format 'HH:mm:ss'
        if ($r -and $r.Status -eq 'Success') {
            $times.Add($r.RoundtripTime)
            $color = if ($r.RoundtripTime -gt 150) { 'Yellow' } else { 'Gray' }
            Write-Host ('  {0}  #{1,-4} {2,5} ms' -f $stamp, $i, $r.RoundtripTime) -ForegroundColor $color
        } else {
            $lost++
            $status = if ($r) { "$($r.Status)" } else { 'Error' }
            Write-Host ('  {0}  #{1,-4} LOST ({2})' -f $stamp, $i, $status) -ForegroundColor Red
        }
        if ($i -lt $n) { Start-Sleep -Milliseconds ([math]::Max(0, 1000 - $(if ($r) { [int]$r.RoundtripTime } else { 1000 }))) }
    }
    Write-Section 'Summary'
    $msg = 'Sent {0}, lost {1} ({2}%)' -f $n, $lost, [math]::Round($lost / $n * 100, 1)
    if ($times.Count) {
        $m = $times | Measure-Object -Minimum -Maximum -Average
        $jitter = 0
        if ($times.Count -gt 1) { $jitter = (@(1..($times.Count - 1) | ForEach-Object { [math]::Abs($times[$_] - $times[$_ - 1]) }) | Measure-Object -Average).Average }
        $msg += '   min {0} / avg {1:N0} / max {2} ms, jitter {3:N0} ms' -f $m.Minimum, $m.Average, $m.Maximum, $jitter
    }
    if ($lost) { Write-Warn $msg } else { Write-Ok $msg }
}

Add-Tool -Id 'NET-22' -Category 'Network' -Name 'Routing table' -Description 'IPv4 routes, next hops and metrics (spot VPN or duplicate-gateway problems)' -Action {
    try {
        $routes = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop | Sort-Object RouteMetric, DestinationPrefix)
        $routes | Select-Object DestinationPrefix, NextHop, InterfaceAlias, RouteMetric, @{ n = 'Total metric'; e = { $_.RouteMetric + $_.InterfaceMetric } } |
            Format-Table -AutoSize | Out-Host
        $defaults = @($routes | Where-Object DestinationPrefix -eq '0.0.0.0/0')
        if ($defaults.Count -gt 1) { Write-Warn "$($defaults.Count) default routes - traffic uses the lowest total metric. Multiple gateways (e.g. Wi-Fi + Ethernet or a VPN) can cause intermittent problems." }
    } catch { route print -4 | Out-Host }
}

Add-Tool -Id 'NET-23' -Category 'Network' -Name 'Network profiles' -Description 'Public/Private/Domain profile and internet connectivity per connection' -Action {
    Get-NetConnectionProfile -ErrorAction SilentlyContinue |
        Select-Object Name, InterfaceAlias, NetworkCategory, IPv4Connectivity, IPv6Connectivity | Format-Table -AutoSize | Out-Host
    Write-Info 'Public blocks file/printer sharing and discovery. A trusted office or home network is normally Private (or Domain on a company network).'
}

Add-Tool -Id 'NET-24' -Category 'Network' -Name 'Restart network services' -Admin -Description 'Restart DNS Client, DHCP Client and Network Location Awareness' -Action {
    if (-not (Confirm-Action 'Restart the DNS Client, DHCP Client and Network Location Awareness services? The connection may drop briefly.')) { return }
    foreach ($name in 'Dnscache', 'Dhcp', 'NlaSvc') {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        try { Restart-Service -Name $name -Force -ErrorAction Stop; Write-Ok "$($svc.DisplayName) restarted." }
        catch { Write-Warn "$($svc.DisplayName): Windows would not restart it ($($_.Exception.Message))." }
    }
}

Add-Tool -Id 'NET-25' -Category 'Network' -Name 'Clear ARP cache' -Admin -Description 'Flush IP-to-MAC mappings (fixes problems after a router or IP change)' -Action {
    $before = @(Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object State -ne 'Permanent').Count
    netsh interface ip delete arpcache | Out-Host
    Write-Ok "ARP cache cleared ($before learned entries removed)."
}

Add-Tool -Id 'NET-26' -Category 'Network' -Name 'Full IP configuration' -Description 'ipconfig /all - every adapter, DHCP lease times, DNS suffixes' -Action {
    ipconfig /all | Out-Host
}

Add-Tool -Id 'NET-27' -Category 'Network' -Name 'Inspect a local port' -Description 'Which program is listening on a port, its path and exposure' -Action {
    $p = Read-Host '  Local TCP port (e.g. 3389, 8080)'
    if ($p -notmatch '^\d+$' -or [int]$p -lt 1 -or [int]$p -gt 65535) { Write-Err 'Enter a port number between 1 and 65535.'; return }
    $conns = @(Get-NetTCPConnection -LocalPort ([int]$p) -State Listen -ErrorAction SilentlyContinue)
    if (-not $conns.Count) { Write-Info "Nothing is listening on TCP port $p."; return }
    foreach ($c in $conns) {
        $proc = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
        $name = if ($c.OwningProcess -eq 4) { 'System' } elseif ($proc) { $proc.ProcessName } else { 'Unknown' }
        $bind = Get-PortBinding $c.LocalAddress
        $svc = @(Get-CimInstance Win32_Service -Filter "ProcessId=$($c.OwningProcess)" -ErrorAction SilentlyContinue | ForEach-Object Name) -join ', '
        [pscustomobject]@{
            Port     = $c.LocalPort
            Address  = $c.LocalAddress
            Process  = $name
            PID      = $c.OwningProcess
            Path     = if ($proc -and $proc.Path) { $proc.Path } else { 'Unavailable (run as Administrator for system processes)' }
            Services = $svc
            Binding  = $bind
            Category = Get-PortCategory $c.LocalPort $name
            Note     = Get-PortNote $bind $c.LocalPort $name
        } | Format-List | Out-Host
    }
}

Add-Tool -Id 'NET-28' -Category 'Network' -Name 'Advanced ping test' -Description 'Ping a host with multiple attempts and latency statistics' -Action {
    $target = Read-Host "Target host or IP address"
    if (-not $target) { Write-Warn 'No target specified'; return }

    Write-Info "Pinging $target (4 attempts)..."
    Write-Host ''

    $results = @()
    $pinger = New-Object System.Net.NetworkInformation.Ping
    for ($i = 0; $i -lt 4; $i++) {
        $ping = $null
        try { $ping = $pinger.Send($target, 1000) } catch { }
        if ($ping -and $ping.Status -eq 'Success') {
            $results += $ping.RoundtripTime
            Write-Check 'OK' "Reply from $($ping.Address)" "$($ping.RoundtripTime)ms"
        } else {
            Write-Warn "No reply (timeout)"
        }
    }

    if ($results.Count -gt 0) {
        Write-Host ''
        $min = $results | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum
        $max = $results | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
        $avg = $results | Measure-Object -Average | Select-Object -ExpandProperty Average
        Write-Check 'INFO' 'Minimum' "$min ms"
        Write-Check 'INFO' 'Maximum' "$max ms"
        Write-Check 'INFO' 'Average' "$([math]::Round($avg, 2)) ms"
    } else {
        Write-Err "Host $target is unreachable"
    }
}

Add-Tool -Id 'NET-29' -Category 'Network' -Name 'Traceroute analysis' -Description 'Trace network path to destination host' -Action {
    $target = Read-Host "Target host or IP address"
    if (-not $target) { Write-Warn 'No target specified'; return }

    Write-Info "Tracing route to $target..."
    Write-Host ''

    try {
        Test-NetConnection -ComputerName $target -TraceRoute -ErrorAction Stop | Select-Object ComputerName, RemoteAddress, TraceRoute, NetworkIsolationContext | Format-List | Out-Host
    } catch {
        Write-Err "Traceroute failed: $($_.Exception.Message)"
    }
}

Add-Tool -Id 'NET-30' -Category 'Network' -Name 'DNS lookup tools' -Description 'Resolve DNS name to IP, reverse lookup, and query records' -Action {
    Write-Host '  [1] Forward DNS lookup (name to IP)'
    Write-Host '  [2] Reverse DNS lookup (IP to name)'
    Write-Host '  [3] DNS record query (A, MX, NS, SOA)'
    Write-Host '  [0] Cancel'
    Write-Host ''

    $choice = Read-Host 'Select option'

    switch ($choice) {
        '1' {
            $name = Read-Host "Host name to resolve"
            if ($name) {
                Write-Info "Resolving $name..."
                try {
                    $ips = Resolve-DnsName -Name $name -ErrorAction Stop -Type A
                    $ips | ForEach-Object { Write-Check 'OK' 'IP Address' $_.IPAddress }
                } catch {
                    Write-Err "Resolution failed: $($_.Exception.Message)"
                }
            }
        }
        '2' {
            $ip = Read-Host "IP address for reverse lookup"
            if ($ip) {
                Write-Info "Reverse lookup for $ip..."
                try {
                    $result = Resolve-DnsName -Name $ip -Type PTR -ErrorAction Stop
                    Write-Check 'OK' 'Host name' $result.NameHost
                } catch {
                    Write-Warn "Reverse lookup failed: $($_.Exception.Message)"
                }
            }
        }
        '3' {
            $name = Read-Host "Host name"
            if ($name) {
                $type = Read-Host "Record type (A, AAAA, MX, NS, SOA, TXT) [A]"
                if (-not $type) { $type = 'A' }
                Write-Info "Querying $type records for $name..."
                try {
                    $records = Resolve-DnsName -Name $name -Type $type -ErrorAction Stop
                    $records | Format-List | Out-Host
                } catch {
                    Write-Err "Query failed: $($_.Exception.Message)"
                }
            }
        }
        default { Write-Warn 'Cancelled' }
    }
}

Add-Tool -Id 'NET-31' -Category 'Network' -Name 'WiFi diagnostics' -Description 'List WiFi networks, connected network info, and signal strength' -Action {
    Write-Section 'WiFi Adapter Status'
    $wifi = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.MediaType -eq '802.11' -or $_.InterfaceDescription -like '*Wireless*' })

    if ($wifi.Count -eq 0) {
        Write-Info 'No WiFi adapters found'
        return
    }

    $wifi | ForEach-Object {
        $adapter = $_
        Write-Check $(if ($adapter.Status -eq 'Up') { 'OK' } else { 'WARN' }) 'WiFi Adapter' "$($adapter.Name) - $($adapter.Status)"
        if ($adapter.Status -eq 'Up') {
            $connected = Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -eq $adapter.Name }
            if ($connected) {
                Write-Check 'INFO' 'Connected Network' $connected.Name
                Write-Check 'INFO' 'Network Type' $connected.NetworkCategory
            }
        }
    }

    Write-Host ''
    Write-Section 'Available WiFi Networks'

    if (Test-IsAdmin) {
        try {
            $networks = netsh wlan show network | Out-String
            if ($networks -match 'Interface name') {
                Write-Host $networks
            } else {
                Write-Info 'Run WiFi scan with: netsh wlan show network mode=Bssid'
            }
        } catch {
            Write-Warn "WiFi scan requires Administrator: $($_.Exception.Message)"
        }
    } else {
        Write-Info 'Run as Administrator for detailed WiFi network scan'
    }
}
