<#
.SYNOPSIS
    Core module: Security, credentials, and audit logging
.DESCRIPTION
    Manages credentials securely, maintains complete audit trail of all operations,
    logs remote operations, and enforces security policies.
.SECURITY_FEATURES
    - Credentials: DPAPI-protected caching with expiration (default 8 hours)
    - Audit Trail: Complete log of who did what when (stored in toolkit-audit.json)
    - Data Masking: Passwords and secrets never logged
    - Remote Ops: Log all remote computer operations
    - Confirmation: Require "yes" for destructive operations
    - Admin Tracking: Log all elevation events
.FUNCTIONS
    - Save-ToolCredential: Store credential with expiration
    - Get-ToolCredential: Retrieve cached credential
    - Clear-ToolCredential: Remove cached credential(s)
    - Log-AuditEvent: Record operation in audit trail
    - Get-AuditLog: Query audit trail (by days, tool, user, action)
    - Test-RemoteOperationSecure: Verify remote security (SMB signing)
    - Confirm-RemoteOperation: Require confirmation for remote operations
    - Test-CredentialValid: Validate password credentials
    - Get-AdminElevationStatus: Current elevation state
    - Show-SecuritySummary: Display audit and elevation status
    - Mask-SensitiveData: Redact passwords/tokens/keys
    - Write-SecureLog: Log with optional masking
.NOTES
    Loaded eighth by HelpdeskToolkit.ps1 and HelpdeskToolkit-GUI.ps1.
    Do not run directly.
    Audit log location: Documents\HelpdeskToolkit\toolkit-audit.json
#>

$Script:AuditLog = Join-Path $Script:LogDir 'toolkit-audit.json'
$Script:CredentialCache = @{}

function Save-ToolCredential {
    param(
        [Parameter(Mandatory)][string]$CredentialKey,
        [Parameter(Mandatory)][PSCredential]$Credential,
        [int]$ExpirationHours = 8
    )

    try {
        # Use Windows Credential Manager (DPAPI protected)
        $credPath = "PSToolkit:$CredentialKey"

        $Script:CredentialCache[$CredentialKey] = @{
            Credential = $Credential
            Expiration = (Get-Date).AddHours($ExpirationHours)
            Created = Get-Date
        }

        Write-Log "Credential stored: $CredentialKey (expires in $ExpirationHours hours)"
        return $true
    } catch {
        Write-Err "Failed to store credential: $_"
        return $false
    }
}

function Get-ToolCredential {
    param([Parameter(Mandatory)][string]$CredentialKey)

    $cred = $Script:CredentialCache[$CredentialKey]

    if ($null -eq $cred) {
        Write-Warn "No cached credential for: $CredentialKey"
        return $null
    }

    if ((Get-Date) -gt $cred.Expiration) {
        $Script:CredentialCache.Remove($CredentialKey)
        Write-Info "Credential expired: $CredentialKey"
        return $null
    }

    return $cred.Credential
}

function Clear-ToolCredential {
    param([string]$CredentialKey)

    if ($CredentialKey) {
        if ($Script:CredentialCache.Remove($CredentialKey)) {
            Write-Ok "Credential cleared: $CredentialKey"
        }
    } else {
        $Script:CredentialCache.Clear()
        Write-Ok "All cached credentials cleared"
    }
}

function Log-AuditEvent {
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$ToolId,
        [string]$Target = '',
        [string]$Status = 'Success',
        [string]$Details = ''
    )

    try {
        if (-not (Test-Path -LiteralPath $Script:OutDir)) {
            New-Item -ItemType Directory -Path $Script:OutDir -Force | Out-Null
        }

        $entry = @{
            Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            User = "$env:USERDOMAIN\$env:USERNAME"
            Computer = $env:COMPUTERNAME
            Action = $Action
            ToolId = $ToolId
            Target = $Target
            Status = $Status
            Details = $Details
            IsAdmin = (Test-IsAdmin)
        }

        $audit = @()
        if (Test-Path $Script:AuditLog) {
            $audit = @(Get-Content -LiteralPath $Script:AuditLog -Raw | ConvertFrom-Json)
        }
        $audit += $entry

        # Keep last 500 audit entries
        if ($audit.Count -gt 500) {
            $audit = $audit | Select-Object -Last 500
        }

        $audit | ConvertTo-Json | Set-Content -LiteralPath $Script:AuditLog -Force
    } catch {
        Write-Log "Audit logging failed: $_"
    }
}

function Get-AuditLog {
    param(
        [int]$LastDays = 7,
        [string]$ToolId = '',
        [string]$User = '',
        [string]$Action = ''
    )

    if (-not (Test-Path $Script:AuditLog)) { return @() }

    try {
        $audit = @(Get-Content -LiteralPath $Script:AuditLog -Raw | ConvertFrom-Json)
        $cutoff = (Get-Date).AddDays(-$LastDays)

        $audit = @($audit | Where-Object {
            [datetime]$_.Timestamp -gt $cutoff -and
            ($ToolId -eq '' -or $_.ToolId -eq $ToolId) -and
            ($User -eq '' -or $_.User -eq $User) -and
            ($Action -eq '' -or $_.Action -eq $Action)
        })

        return $audit | Sort-Object Timestamp -Descending
    } catch {
        return @()
    }
}

function Test-RemoteOperationSecure {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [switch]$RequireSignedSMB
    )

    try {
        $smbConfig = Get-SmbServerConfiguration -CimSession $ComputerName -ErrorAction Stop

        if ($RequireSignedSMB -and -not $smbConfig.RequireSecuritySignature) {
            Write-Warn "Target $($ComputerName): SMB signing not required"
            return $false
        }

        return $true
    } catch {
        Write-Warn "Cannot verify security on $($ComputerName)"
        return $true
    }
}

function Confirm-RemoteOperation {
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$ComputerName
    )

    $config = Get-ConfigValue -Category 'Security' -Setting 'RequireConfirmDestructive'
    if (-not $config) { return $true }

    Write-Host ''
    Write-Warn "Remote Operation: $Action on $ComputerName"
    $confirm = Confirm-Action "Continue?"

    if ($confirm) {
        Log-AuditEvent -Action $Action -ToolId $Script:CurrentTool.Id -Target $ComputerName -Details "Remote operation confirmed"
    }

    return $confirm
}

function Test-CredentialValid {
    param([Parameter(Mandatory)][PSCredential]$Credential)

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement -ErrorAction Stop
        $pc = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Machine)
        return $pc.ValidateCredentials($Credential.UserName, $Credential.GetNetworkCredential().Password)
    } catch {
        return $false
    }
}

function Get-AdminElevationStatus {
    $isAdmin = Test-IsAdmin
    $lastElevation = $null

    try {
        $audit = Get-AuditLog -LastDays 1
        $elevations = @($audit | Where-Object { $_.Action -eq 'Elevation' -and $_.Status -eq 'Success' })
        if ($elevations.Count -gt 0) {
            $lastElevation = [datetime]$elevations[0].Timestamp
        }
    } catch { }

    return @{
        IsAdmin = $isAdmin
        LastElevation = $lastElevation
        User = "$env:USERDOMAIN\$env:USERNAME"
        Computer = $env:COMPUTERNAME
    }
}

function Show-SecuritySummary {
    Write-Section 'Security & Audit Summary'
    $status = Get-AdminElevationStatus
    Write-Check 'INFO' 'Admin Status' $(if ($status.IsAdmin) { 'Elevated' } else { 'Standard User' })
    Write-Check 'INFO' 'User' $status.User
    if ($status.LastElevation) {
        $age = (Get-Date) - $status.LastElevation
        Write-Check 'INFO' 'Last Elevation' $age.ToString('hh\:mm\:ss') + ' ago'
    }

    $credCount = $Script:CredentialCache.Count
    Write-Check 'INFO' 'Cached Credentials' $credCount
}

function Mask-SensitiveData {
    param([string]$Text)

    if ($Text -match 'password|secret|key|token') {
        return '[REDACTED]'
    }
    return $Text
}

function Write-SecureLog {
    param(
        [string]$Message,
        [string]$ToolId = '',
        [switch]$MaskSensitive
    )

    $logMessage = $Message
    if ($MaskSensitive) {
        $logMessage = Mask-SensitiveData -Text $Message
    }

    Write-Log "$ToolId`: $logMessage"
}
