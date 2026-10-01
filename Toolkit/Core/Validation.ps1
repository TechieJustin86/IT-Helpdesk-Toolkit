<#
.SYNOPSIS
    Core module: Input validation helpers
.DESCRIPTION
    Validates user input before processing to prevent errors and security issues.
    Checks IP addresses, computer names, UNC paths, emails, ports, and connectivity.
.FUNCTIONS
    - Test-ValidIPAddress: Validate IPv4/IPv6 address format
    - Test-ValidComputerName: Validate Windows computer name
    - Test-ValidUNCPath: Validate network path format
    - Test-ValidEmail: Validate email address format
    - Test-ValidPort: Validate port number (0-65535)
    - Test-ValidFilePath: Validate file path format
    - Test-RemoteComputerAccess: Test connectivity (ping)
    - Test-RemoteComputerWinRM: Test WinRM availability
    - Confirm-DestructiveAction: Require confirmation for risky operations
    - Validate-ComputerNameInput: Validate and show user-friendly errors
    - Validate-IPAddressInput: Validate IP with error messages
    - Validate-UNCPathInput: Validate UNC path with error messages
.NOTES
    Loaded fourth by HelpdeskToolkit.ps1 and HelpdeskToolkit-GUI.ps1.
    Do not run directly.
#>

function Test-ValidIPAddress {
    param([Parameter(Mandatory)][string]$IPAddress)
    try {
        [ipaddress]::Parse($IPAddress) | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Test-ValidComputerName {
    param([Parameter(Mandatory)][string]$ComputerName)
    if ([string]::IsNullOrWhiteSpace($ComputerName)) { return $false }
    if ($ComputerName.Length -gt 15) { return $false }
    if ($ComputerName -match '[^a-zA-Z0-9\-]') { return $false }
    if ($ComputerName -match '^-|-$') { return $false }
    return $true
}

function Test-ValidUNCPath {
    param([Parameter(Mandatory)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not $Path.StartsWith('\\')) { return $false }
    return $true
}

function Test-ValidEmail {
    param([Parameter(Mandatory)][string]$Email)
    try {
        $addr = New-Object System.Net.Mail.MailAddress($Email)
        return $addr.Address -eq $Email
    } catch {
        return $false
    }
}

function Test-ValidPort {
    param([Parameter(Mandatory)][int]$Port)
    return ($Port -ge 0 -and $Port -le 65535)
}

function Test-ValidFilePath {
    param([Parameter(Mandatory)][string]$Path)
    try {
        [IO.Path]::GetFullPath($Path) | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Test-RemoteComputerAccess {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [int]$TimeoutSeconds = 5
    )
    try {
        $result = Test-NetConnection -ComputerName $ComputerName -InformationLevel Quiet -WarningAction SilentlyContinue
        return $result
    } catch {
        return $false
    }
}

function Test-RemoteComputerWinRM {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [int]$TimeoutSeconds = 10
    )
    try {
        $session = New-PSSession -ComputerName $ComputerName -ErrorAction Stop -OperationTimeoutSec $TimeoutSeconds
        Remove-PSSession $session -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

function Confirm-DestructiveAction {
    param(
        [Parameter(Mandatory)][string]$Action,
        [string]$Target = 'this system',
        [switch]$Force
    )
    if ($Force) { return $true }

    Write-Host ''
    Write-Warn "DESTRUCTIVE OPERATION: $Action"
    Write-Warn "Target: $Target"
    Write-Host ''
    $confirm = Read-Host "  Type 'yes' to confirm, anything else to cancel"
    return ($confirm -eq 'yes')
}

function Validate-ComputerNameInput {
    param([Parameter(Mandatory)][string]$ComputerName)
    if (-not (Test-ValidComputerName -ComputerName $ComputerName)) {
        Write-Err "Invalid computer name: $ComputerName"
        return $false
    }
    return $true
}

function Validate-IPAddressInput {
    param([Parameter(Mandatory)][string]$IPAddress)
    if (-not (Test-ValidIPAddress -IPAddress $IPAddress)) {
        Write-Err "Invalid IP address: $IPAddress"
        return $false
    }
    return $true
}

function Validate-UNCPathInput {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-ValidUNCPath -Path $Path)) {
        Write-Err "Invalid UNC path: $Path (must start with \\)"
        return $false
    }
    return $true
}
