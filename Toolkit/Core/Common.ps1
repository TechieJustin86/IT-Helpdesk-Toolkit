<#
.SYNOPSIS
    Core module: Common helpers and tool registration system
.DESCRIPTION
    Shared helpers, logging functions, data queries, and Add-Tool registration.
    Provides the foundation for all other modules and tools.
.FUNCTIONS
    - Test-IsAdmin: Check if running with administrator privileges
    - Write-* (Info, Ok, Warn, Err, Section, Check): Colored console output
    - Write-Log: Log all actions to toolkit.log
    - Write-ErrorLog: Log errors with full context to toolkit-errors.json
    - Write-ToolUsage: Track tool usage statistics
    - Get-ToolUsage: Retrieve usage statistics
    - Get-SystemSummary, Get-DiskSpace, Get-NetworkSummary: System queries
    - Get-InstalledSoftware, Get-PendingReboot: Software/system state
    - Get-SecurityAudit, Show-Audit: Security assessment
    - Add-Tool: Register a new tool
    - Get-ExecutionStats: Get session execution statistics
    - Get-ToolsByTag, Find-Tools: Tool discovery
.NOTES
    Loaded first by HelpdeskToolkit.ps1 and HelpdeskToolkit-GUI.ps1.
    Do not run directly.
#>

$Script:Version      = '1.5.0'
# Determine Toolkit directory - Core is one level up from this script
if ($PSScriptRoot) {
    $Script:ToolkitDir = Split-Path $PSScriptRoot -Parent
} elseif ($HdtRoot) {
    # When loaded in GUI background runspace, use HdtRoot passed from GUI
    $Script:ToolkitDir = $HdtRoot
} else {
    # Fallback if $PSScriptRoot is empty (shouldn't happen, but be safe)
    $Script:ToolkitDir = Get-Location
}
# Local logs directory (in Toolkit\Logs)
$Script:LogDir       = Join-Path $Script:ToolkitDir 'Logs'
$Script:LogFile      = Join-Path $Script:LogDir 'toolkit.log'
$Script:ErrorLogFile = Join-Path $Script:LogDir 'toolkit-errors.json'
# User output directory (for exported reports and results - kept in Documents for accessibility)
$Script:OutDir       = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'HelpdeskToolkit'
$Script:Tools        = New-Object System.Collections.Generic.List[object]
$Script:ModuleErrors = @()
$Script:CurrentTool  = $null
$Script:ToolStartTime = $null
$Script:ExecutionStats = @{ ToolsRun = 0; ToolsFailed = 0; TotalExecutionSeconds = 0 }

#region ---------------------------------------------------------------- Helpers

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Info    { param([string]$Message) Write-Host "  [i] $Message" -ForegroundColor Cyan }
function Write-Ok      { param([string]$Message) Write-Host "  [+] $Message" -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host "  [!] $Message" -ForegroundColor Yellow }
function Write-Err     { param([string]$Message) Write-Host "  [x] $Message" -ForegroundColor Red }
function Write-Section { param([string]$Title)   Write-Host ''; Write-Host "  -- $Title --" -ForegroundColor Magenta }

# One colour-coded check line, e.g. "[OK]   Firewall   Enabled"
function Write-Check {
    param([ValidateSet('OK', 'WARN', 'FAIL', 'INFO')][string]$Status, [string]$Label, [string]$Value)
    $color = switch ($Status) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'FAIL' { 'Red' } default { 'Gray' } }
    Write-Host ('  {0,-6} {1,-30} {2}' -f "[$Status]", $Label, $Value) -ForegroundColor $color
}

# Plain-English meaning of a Device Manager ConfigManagerErrorCode
function Get-PnpProblemText {
    param($Code)
    if ($null -eq $Code) { return 'Unknown' }
    switch ([int]$Code) {
        0  { 'OK' }
        1  { 'Not configured correctly' }
        3  { 'Driver may be corrupted' }
        10 { 'Device cannot start' }
        12 { 'Not enough free resources' }
        14 { 'Restart required' }
        18 { 'Reinstall the driver' }
        19 { 'Registry configuration damaged' }
        21 { 'Windows is removing the device' }
        22 { 'Device is disabled' }
        24 { 'Not present or not working' }
        28 { 'Driver not installed' }
        29 { 'Disabled in firmware' }
        31 { 'Windows cannot load the driver' }
        32 { 'Driver service disabled' }
        39 { 'Driver corrupted or missing' }
        43 { 'Device reported a problem' }
        45 { 'Not currently connected' }
        52 { 'Driver signature cannot be verified' }
        default { "Device Manager code $Code" }
    }
}

function Write-Log {
    param([string]$Message)
    try {
        if (-not (Test-Path -LiteralPath $Script:LogDir)) { New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null }
        $line = '{0}  {1}\{2}  {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $env:USERDOMAIN, $env:USERNAME, $Message
        Add-Content -LiteralPath $Script:LogFile -Value $line -ErrorAction Stop
    } catch { }
}

function Write-ErrorLog {
    param([string]$ToolId, [string]$ToolName, [object]$ErrorRecord)
    try {
        if (-not (Test-Path -LiteralPath $Script:LogDir)) { New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null }

        $errorEntry = @{
            Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            ToolId = $ToolId
            ToolName = $ToolName
            User = "$env:USERDOMAIN\$env:USERNAME"
            Computer = $env:COMPUTERNAME
            ErrorMessage = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $ErrorRecord.Exception.Message } else { "$ErrorRecord" }
            ErrorType = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $ErrorRecord.Exception.GetType().Name } else { 'Unknown' }
            StackTrace = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $ErrorRecord.ScriptStackTrace } else { '' }
            InnerException = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord] -and $ErrorRecord.Exception.InnerException) { $ErrorRecord.Exception.InnerException.Message } else { '' }
            InvocationInfo = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
                @{
                    ScriptName = $ErrorRecord.InvocationInfo.ScriptName
                    LineNumber = $ErrorRecord.InvocationInfo.ScriptLineNumber
                    Line = $ErrorRecord.InvocationInfo.Line
                    CommandName = $ErrorRecord.InvocationInfo.InvocationName
                    OffsetInLine = $ErrorRecord.InvocationInfo.OffsetInLine
                }
            } else { $null }
            ExecutionContext = @{
                IsAdmin = Test-IsAdmin
                PSVersion = $PSVersionTable.PSVersion.ToString()
                OSVersion = [System.Environment]::OSVersion.VersionString
            }
        }

        # Append to JSON error log
        $errors = @()
        if (Test-Path $Script:ErrorLogFile) {
            $errors = @(Get-Content -LiteralPath $Script:ErrorLogFile -Raw | ConvertFrom-Json)
        }
        $errors += $errorEntry

        # Keep only last 200 errors (configurable)
        $maxErrors = Get-ConfigValue -Category 'Logging' -Setting 'MaxErrorsToKeep'
        if ($errors.Count -gt $maxErrors) {
            $errors = $errors | Select-Object -Last $maxErrors
        }

        $errors | ConvertTo-Json | Set-Content -LiteralPath $Script:ErrorLogFile -Force

        # Update stats
        $Script:ExecutionStats.ToolsFailed++
    } catch { }
}

function Write-ToolUsage {
    param([string]$ToolId, [string]$ToolName, [string]$Category)
    try {
        if (-not (Test-Path -LiteralPath $Script:OutDir)) { New-Item -ItemType Directory -Path $Script:OutDir -Force | Out-Null }
        $usageFile = Join-Path $Script:OutDir 'toolkit-usage.json'
        $now = Get-Date

        $usage = @()
        if (Test-Path $usageFile) {
            $usage = @(Get-Content -LiteralPath $usageFile -Raw | ConvertFrom-Json)
        }

        # Check if tool run already exists today
        $today = $now.ToString('yyyy-MM-dd')
        $existing = $usage | Where-Object { $_.ToolId -eq $ToolId -and $_.Date -eq $today }

        if ($existing) {
            $existing.Count += 1
            $existing.LastRun = $now.ToString('yyyy-MM-dd HH:mm:ss')
        } else {
            $usage += @{
                ToolId = $ToolId
                ToolName = $ToolName
                Category = $Category
                Date = $today
                Count = 1
                FirstRun = $now.ToString('yyyy-MM-dd HH:mm:ss')
                LastRun = $now.ToString('yyyy-MM-dd HH:mm:ss')
            }
        }

        $usage | ConvertTo-Json | Set-Content -LiteralPath $usageFile -Force
    } catch { }
}

function Get-ToolUsage {
    $usageFile = Join-Path $Script:OutDir 'toolkit-usage.json'
    $usage = @()
    if (Test-Path $usageFile) {
        try {
            $usage = @(Get-Content -LiteralPath $usageFile -Raw | ConvertFrom-Json -ErrorAction Stop)
        } catch { }
    }
    $usage | Sort-Object -Property @{Expression={$_.Count}; Descending=$true}
}

function Confirm-Action {
    param([string]$Message)
    $answer = Read-Host "  $Message [y/N]"
    return ($answer -match '^(y|yes)$')
}

function Wait-Key { [void](Read-Host '  Press Enter to continue') }

function Get-OutFile {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Test-Path -LiteralPath $Script:OutDir)) { New-Item -ItemType Directory -Path $Script:OutDir -Force | Out-Null }
    Join-Path $Script:OutDir ('{0}_{1}_{2}' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss'), $Name)
}

function Format-Bytes {
    param([double]$Bytes)
    if     ($Bytes -ge 1TB) { '{0:N2} TB' -f ($Bytes / 1TB) }
    elseif ($Bytes -ge 1GB) { '{0:N2} GB' -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { '{0:N1} MB' -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { '{0:N0} KB' -f ($Bytes / 1KB) }
    else                    { '{0:N0} B'  -f $Bytes }
}

function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if ($sum) { [int64]$sum } else { [int64]0 }
}

# Deletes everything inside a folder (not the folder itself). Returns bytes freed.
function Clear-FolderContents {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $before = Get-FolderSize $Path
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    $after = Get-FolderSize $Path
    [int64][math]::Max(0, $before - $after)
}

# Runs an external program attached to this console so its live output shows correctly.
function Invoke-External {
    param([Parameter(Mandatory)][string]$FilePath, [string]$Arguments = '')
    Write-Host "  > $FilePath $Arguments" -ForegroundColor DarkGray
    if ($Arguments) { $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -Wait -PassThru }
    else            { $p = Start-Process -FilePath $FilePath -NoNewWindow -Wait -PassThru }
    $p.ExitCode
}

function Select-FromList {
    param([object[]]$Items, [scriptblock]$Label, [string]$Prompt = 'Select')
    $Items = @($Items)
    if ($Items.Count -eq 0) { Write-Warn 'Nothing to select.'; return $null }
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $text = $Items[$i] | ForEach-Object $Label
        Write-Host ('  [{0,2}] {1}' -f ($i + 1), $text)
    }
    $sel = Read-Host "  $Prompt (number, blank to cancel)"
    if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $Items.Count) { return $Items[[int]$sel - 1] }
    return $null
}

function Open-File {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Write-Ok "Saved: $Path"
        try { Invoke-Item -LiteralPath $Path } catch { }
    } else {
        Write-Err "File was not created: $Path"
    }
}

function Export-Results {
    param([Parameter(ValueFromPipeline)]$InputObject, [string]$Name)
    begin   { $all = New-Object System.Collections.Generic.List[object] }
    process { $all.Add($InputObject) }
    end {
        $file = Get-OutFile $Name
        $all | Export-Csv -LiteralPath $file -NoTypeInformation -Encoding UTF8
        Write-Ok "Exported $($all.Count) rows to $file"
    }
}

#endregion

#region ---------------------------------------------------------------- Shared data functions

function Get-SystemSummary {
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $nt   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $up   = (Get-Date) - $os.LastBootUpTime
    [pscustomobject]@{
        'Computer name'    = $env:COMPUTERNAME
        'Logged-on user'   = $cs.UserName
        'Domain/Workgroup' = if ($cs.PartOfDomain) { "$($cs.Domain) (domain)" } else { "$($cs.Workgroup) (workgroup)" }
        'Manufacturer'     = $cs.Manufacturer
        'Model'            = $cs.Model
        'Serial number'    = $bios.SerialNumber
        'BIOS'             = "$($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate))"
        'OS'               = "$($os.Caption) $($nt.DisplayVersion)"
        'Build'            = "$($os.BuildNumber).$($nt.UBR)"
        'Architecture'     = $os.OSArchitecture
        'Installed'        = $os.InstallDate
        'Last boot'        = $os.LastBootUpTime
        'Uptime'           = '{0}d {1}h {2}m' -f $up.Days, $up.Hours, $up.Minutes
        'CPU'              = $cpu.Name.Trim()
        'Cores / threads'  = "$($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors)"
        'RAM total'        = Format-Bytes $cs.TotalPhysicalMemory
        'RAM free'         = Format-Bytes ($os.FreePhysicalMemory * 1KB)
    }
}

function Get-DiskSpace {
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
        $pct = if ($_.Size) { [math]::Round($_.FreeSpace / $_.Size * 100, 1) } else { 0 }
        [pscustomobject]@{
            Drive      = $_.DeviceID
            Label      = $_.VolumeName
            FileSystem = $_.FileSystem
            Size       = Format-Bytes $_.Size
            Free       = Format-Bytes $_.FreeSpace
            'Free %'   = $pct
            Status     = if ($pct -lt 10) { 'LOW' } elseif ($pct -lt 20) { 'Warning' } else { 'OK' }
        }
    }
}

function Get-NetworkSummary {
    Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.NetAdapter.Status -eq 'Up' } | ForEach-Object {
        $ipif = Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Adapter      = $_.InterfaceAlias
            Description  = $_.InterfaceDescription
            IPv4         = ($_.IPv4Address.IPAddress) -join ', '
            Gateway      = ($_.IPv4DefaultGateway.NextHop) -join ', '
            DNS          = (($_.DNSServer | Where-Object AddressFamily -eq 2).ServerAddresses) -join ', '
            DHCP         = if ($ipif) { "$($ipif.Dhcp)" } else { '' }
            MAC          = $_.NetAdapter.MacAddress
            'Link speed' = $_.NetAdapter.LinkSpeed
        }
    }
}

function Get-InstalledSoftware {
    param([switch]$Raw)
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $apps = Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 -and -not $_.ParentKeyName }
    if ($Raw) { return $apps | Sort-Object DisplayName }
    $apps | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Sort-Object DisplayName, DisplayVersion -Unique
}

function Get-PendingReboot {
    $reasons = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $reasons += 'Component Based Servicing' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $reasons += 'Windows Update' }
    $pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($pfro) { $reasons += 'Pending file rename operations' }
    $active  = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction SilentlyContinue).ComputerName
    $pending = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction SilentlyContinue).ComputerName
    if ($active -and $pending -and $active -ne $pending) { $reasons += "Computer rename ($active -> $pending)" }
    $reasons
}

function Get-RecentErrors {
    param([int]$Hours = 24)
    $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = (Get-Date).AddHours(-$Hours) } -ErrorAction SilentlyContinue)
    $events | Group-Object ProviderName, Id | Sort-Object Count -Descending | ForEach-Object {
        $first = $_.Group[0]
        $msg = "$($first.Message)" -replace '\s+', ' '
        if ($msg.Length -gt 90) { $msg = $msg.Substring(0, 90) + '...' }
        [pscustomobject]@{
            Count   = $_.Count
            Log     = $first.LogName
            Source  = $first.ProviderName
            EventId = $first.Id
            Last    = $first.TimeCreated
            Message = $msg
        }
    }
}

function Get-StoppedAutoServices {
    # Services that are set to Automatic but normally stop on their own
    $ignore = 'sppsvc', 'edgeupdate', 'edgeupdatem', 'gupdate', 'gupdatem', 'RemoteRegistry', 'MapsBroker', 'tiledatamodelsvc',
              'WbioSrvc', 'CDPSvc', 'TrustedInstaller', 'wuauserv', 'BITS', 'UsoSvc', 'ShellHWDetection', 'sedsvc', 'GoogleUpdaterService*',
              'GoogleUpdaterInternalService*', 'MicrosoftEdgeElevationService', 'clr_optimization*', 'WMPNetworkSvc', 'OneSyncSvc*',
              'CDPUserSvc*', 'WpnUserService*', 'SysMain', 'DoSvc', 'InstallService', 'IntelAudioService', 'stisvc', 'dbupdate*'
    Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" | Where-Object {
        $name = $_.Name
        -not ($ignore | Where-Object { $name -like $_ })
    } | Select-Object Name, DisplayName, State, ExitCode
}

function Get-StartupItems {
    Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | Select-Object Name, Command, Location, User
}

function Get-SecurityAudit {
    $isAdmin = Test-IsAdmin
    $results = New-Object System.Collections.Generic.List[object]
    function Add-Check { param($Check, $Result, $Status) $results.Add([pscustomobject]@{ Check = $Check; Result = $Result; Status = $Status }) }

    # Operating system support
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.Caption -like '*Windows 10*') { Add-Check 'OS support' "$($os.Caption) - reached end of support Oct 14 2025" 'WARN' }
    else { Add-Check 'OS support' $os.Caption 'OK' }

    # Firewall
    try {
        $off = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { "$($_.Enabled)" -eq 'False' })
        if ($off.Count) { Add-Check 'Firewall' ("Disabled on: " + ($off.Name -join ', ')) 'WARN' } else { Add-Check 'Firewall' 'Enabled on all profiles' 'OK' }
    } catch { Add-Check 'Firewall' 'Unable to query' 'INFO' }

    # Antivirus - Defender goes passive when a third-party AV is registered
    $mp = try { Get-MpComputerStatus -ErrorAction Stop } catch { $null }
    $thirdParty = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | Where-Object displayName -notlike '*Defender*')
    if ($mp -and $mp.AMRunningMode -eq 'Normal') {
        if ($mp.RealTimeProtectionEnabled) { Add-Check 'Defender real-time' 'Enabled' 'OK' } else { Add-Check 'Defender real-time' 'Disabled' 'WARN' }
        if ($mp.AntivirusSignatureAge -gt 3) { Add-Check 'Defender signatures' "$($mp.AntivirusSignatureAge) days old" 'WARN' }
        else { Add-Check 'Defender signatures' "$($mp.AntivirusSignatureAge) day(s) old" 'OK' }
    } elseif ($thirdParty.Count) {
        Add-Check 'Antivirus' ('Third-party: ' + (($thirdParty.displayName | Select-Object -Unique) -join ', ')) 'OK'
    } else {
        Add-Check 'Antivirus' 'No active antivirus detected' 'WARN'
    }

    # UAC
    $lua = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue).EnableLUA
    if ($lua -eq 0) { Add-Check 'UAC' 'Disabled' 'WARN' } else { Add-Check 'UAC' 'Enabled' 'OK' }

    # Remote Desktop
    $ts = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue).fDenyTSConnections
    if ($ts -eq 0) {
        $nla = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -ErrorAction SilentlyContinue).UserAuthentication
        if ($nla -eq 1) { Add-Check 'Remote Desktop' 'Enabled (NLA required)' 'INFO' } else { Add-Check 'Remote Desktop' 'Enabled WITHOUT Network Level Authentication' 'WARN' }
    } else { Add-Check 'Remote Desktop' 'Disabled' 'OK' }

    # SMBv1
    try {
        $smb1 = (Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol
        if ($smb1) { Add-Check 'SMBv1 server' 'Enabled' 'WARN' } else { Add-Check 'SMBv1 server' 'Disabled' 'OK' }
    } catch {
        if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10') { Add-Check 'SMBv1 client' 'Installed' 'WARN' } else { Add-Check 'SMBv1' 'Not installed' 'OK' }
    }

    # BitLocker on system drive
    $blStatus = $null
    if ($isAdmin -and (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
        try { $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop; $blStatus = "$($bl.ProtectionStatus)" } catch { }
    }
    if (-not $blStatus) {
        try {
            $v = (New-Object -ComObject Shell.Application).NameSpace("$env:SystemDrive\").Self.ExtendedProperty('System.Volume.BitLockerProtection')
            $map = @{ 0 = 'Not supported'; 1 = 'On'; 2 = 'Off'; 3 = 'Encrypting'; 4 = 'Decrypting'; 5 = 'Suspended'; 6 = 'On (locked)'; 8 = 'Waiting for activation' }
            if ($null -ne $v) { $blStatus = $map[[int]$v] }
        } catch { }
    }
    if ($blStatus -in 'On', 'On (locked)') { Add-Check "BitLocker $env:SystemDrive" 'Protection on' 'OK' }
    elseif ($blStatus -eq 'Not supported') { Add-Check "BitLocker $env:SystemDrive" 'Not supported on this edition/hardware' 'INFO' }
    elseif ($blStatus) { Add-Check "BitLocker $env:SystemDrive" $blStatus 'WARN' }
    else { Add-Check "BitLocker $env:SystemDrive" 'Unknown' 'INFO' }

    # Secure Boot / TPM (need admin)
    if ($isAdmin) {
        try { if (Confirm-SecureBootUEFI -ErrorAction Stop) { Add-Check 'Secure Boot' 'Enabled' 'OK' } else { Add-Check 'Secure Boot' 'Disabled' 'WARN' } }
        catch { Add-Check 'Secure Boot' 'Not supported (legacy BIOS?)' 'WARN' }
        try {
            $tpm = Get-Tpm -ErrorAction Stop
            if ($tpm.TpmPresent -and $tpm.TpmReady) { Add-Check 'TPM' 'Present and ready' 'OK' } elseif ($tpm.TpmPresent) { Add-Check 'TPM' 'Present but not ready' 'WARN' } else { Add-Check 'TPM' 'Not present' 'WARN' }
        } catch { Add-Check 'TPM' 'Unable to query' 'INFO' }
    } else {
        Add-Check 'Secure Boot / TPM' 'Run as Administrator to check' 'INFO'
    }

    # Guest account
    $guest = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -like '*-501' }
    if ($guest -and $guest.Enabled) { Add-Check 'Guest account' 'Enabled' 'WARN' } else { Add-Check 'Guest account' 'Disabled' 'OK' }

    # Auto logon
    $wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
    if ($wl.AutoAdminLogon -eq '1') { Add-Check 'Auto logon' "Enabled for '$($wl.DefaultUserName)'" 'WARN' } else { Add-Check 'Auto logon' 'Disabled' 'OK' }

    # Updates
    $last = Get-HotFix -ErrorAction SilentlyContinue | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1
    if ($last) {
        $age = ((Get-Date) - $last.InstalledOn).Days
        if ($age -gt 35) { Add-Check 'Last update' "$($last.HotFixID) - $age days ago" 'WARN' } else { Add-Check 'Last update' "$($last.HotFixID) - $age days ago" 'OK' }
    } else { Add-Check 'Last update' 'Unknown' 'INFO' }

    # Pending reboot
    $pr = @(Get-PendingReboot)
    if ($pr.Count) { Add-Check 'Pending reboot' ($pr -join '; ') 'WARN' } else { Add-Check 'Pending reboot' 'None' 'OK' }

    # Local admins
    try {
        $admins = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
        Add-Check 'Local administrators' ("$($admins.Count): " + (($admins.Name) -join ', ')) 'INFO'
    } catch { Add-Check 'Local administrators' 'Unable to enumerate' 'INFO' }

    $results
}

function Show-Audit {
    param($Results)
    foreach ($r in $Results) {
        $color = switch ($r.Status) { 'OK' { 'Green' } 'WARN' { 'Yellow' } default { 'Gray' } }
        Write-Host ('  {0,-6} {1,-24} {2}' -f "[$($r.Status)]", $r.Check, $r.Result) -ForegroundColor $color
    }
}

function Get-ErrorLog {
    param([int]$LastHours = 24)
    $errors = @()
    if (Test-Path $Script:ErrorLogFile) {
        try {
            $errors = @(Get-Content -LiteralPath $Script:ErrorLogFile -Raw | ConvertFrom-Json)
            $cutoff = (Get-Date).AddHours(-$LastHours)
            $errors = @($errors | Where-Object { [datetime]$_.Timestamp -gt $cutoff })
        } catch { }
    }
    return $errors | Sort-Object Timestamp -Descending
}

#endregion

#region ---------------------------------------------------------------- Tool registration

function Add-Tool {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Name,
        [string]$Description,
        [switch]$Admin,
        [object[]]$Tags = @(),
        [Parameter(Mandatory)][scriptblock]$Action
    )
    $Script:Tools.Add([pscustomobject]@{
        Id = $Id
        Category = $Category
        Name = $Name
        Description = $Description
        Admin = [bool]$Admin
        Tags = @($Tags)
        Action = $Action
        Created = Get-Date
    })
}

function Get-ExecutionStats {
    return $Script:ExecutionStats
}

function Show-ExecutionStats {
    Write-Section 'Execution Statistics (This Session)'
    Write-Info "Tools Executed: $($Script:ExecutionStats.ToolsRun)"
    Write-Info "Tools Failed: $($Script:ExecutionStats.ToolsFailed)"
    Write-Info "Success Rate: $([math]::Round(($Script:ExecutionStats.ToolsRun - $Script:ExecutionStats.ToolsFailed) / [math]::Max(1, $Script:ExecutionStats.ToolsRun) * 100, 1))%"
    if ($Script:ExecutionStats.TotalExecutionSeconds -gt 0) {
        $avgTime = $Script:ExecutionStats.TotalExecutionSeconds / [math]::Max(1, $Script:ExecutionStats.ToolsRun)
        Write-Info "Average Execution Time: $([math]::Round($avgTime, 2))s"
    }
}

function Get-ToolsByTag {
    param([Parameter(Mandatory)][string]$Tag)
    return $Script:Tools | Where-Object { $_.Tags -contains $Tag }
}

function Find-Tools {
    param([string]$Query)
    $q = $Query.ToLower()
    return $Script:Tools | Where-Object {
        $_.Name.ToLower().Contains($q) -or
        $_.Description.ToLower().Contains($q) -or
        $_.Id.ToLower().Contains($q)
    }
}

#endregion
