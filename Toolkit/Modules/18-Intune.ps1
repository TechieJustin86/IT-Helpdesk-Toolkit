# Modules\18-Intune.ps1
# Category: Intune Management
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

function Get-IntuneEnrollment {
    <#
        Intune enrollment as Windows records it, readable by a standard user.

        These tools used to ask WMI's root\cimv2\mdm\dmmap namespace (the MDM Bridge
        provider), which only answers the SYSTEM account. Anyone else - administrators
        included - gets "Access denied", which -ErrorAction SilentlyContinue turned into
        "not enrolled" on enrolled devices too.

        Windows keeps each enrollment under HKLM\SOFTWARE\Microsoft\Enrollments\<id>.
        Intune's has ProviderID "MS DM Server", and EnrollmentState 1 means enrolled. The
        OMADM account named after the same <id> holds the last successful sync, in UTC.
    #>
    $result = [pscustomobject]@{ Enrolled = $false; UPN = $null; LastSyncUtc = $null }

    $enrollment = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue | Where-Object {
        $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
        $props.ProviderID -eq 'MS DM Server' -and $props.EnrollmentState -eq 1
    } | Select-Object -First 1
    if (-not $enrollment) { return $result }

    $result.Enrolled = $true
    $result.UPN = (Get-ItemProperty -LiteralPath $enrollment.PSPath -ErrorAction SilentlyContinue).UPN

    $connInfo = "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\$($enrollment.PSChildName)\Protected\ConnInfo"
    $stamp = (Get-ItemProperty -LiteralPath $connInfo -ErrorAction SilentlyContinue).ServerLastSuccessTime
    if ($stamp) {
        # Stored as e.g. 20261019T152003Z
        $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
        try { $result.LastSyncUtc = [datetime]::ParseExact($stamp, "yyyyMMdd'T'HHmmss'Z'", [Globalization.CultureInfo]::InvariantCulture, $styles) } catch { }
    }
    $result
}

function Get-EntraJoinState {
    # dsregcmd answers for any account; the dmmap check it replaces only answered SYSTEM
    $state = @{}
    foreach ($line in @(dsregcmd /status 2>$null)) {
        if ($line -match '^\s*(AzureAdJoined|DomainJoined)\s*:\s*(\S+)') { $state[$matches[1]] = ($matches[2] -eq 'YES') }
    }
    [pscustomobject]@{ AzureAdJoined = [bool]$state['AzureAdJoined']; DomainJoined = [bool]$state['DomainJoined'] }
}

Add-Tool -Id 'INTUNE-01' -Category 'Intune Management' -Name 'Check Intune enrollment status' -Description 'Verify Intune MDM enrollment, Entra/Azure AD join status, device ID - confirms device is managed' -Action {
    Write-Section 'Intune Enrollment Status'

    $deviceName = $env:COMPUTERNAME
    Write-Info "Device: $deviceName"

    $enrollment = Get-IntuneEnrollment
    if ($enrollment.Enrolled) {
        Write-Ok 'Device is Intune enrolled'
        if ($enrollment.UPN) { Write-Check -Status INFO -Label 'Enrolled by' -Value $enrollment.UPN }
        if ($enrollment.LastSyncUtc) { Write-Check -Status INFO -Label 'Last successful sync' -Value $enrollment.LastSyncUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm') }
    } else {
        Write-Err 'Device is NOT Intune enrolled'
        Write-Info 'To enroll: Settings > Accounts > Access work or school > Connect'
        return
    }

    Write-Section 'Azure AD / Entra ID Status'
    $join = Get-EntraJoinState
    if ($join.AzureAdJoined) {
        Write-Ok 'Device is Entra ID (Azure AD) joined'
        if ($join.DomainJoined) { Write-Info 'Also joined to on-premises Active Directory (hybrid joined)' }
    } elseif ($join.DomainJoined) {
        Write-Info 'Device is joined to on-premises Active Directory, not Entra ID'
    } else {
        Write-Info 'Device is NOT Entra ID joined'
    }

    # Check MDM policies
    Write-Section 'MDM Policies'
    $mdmPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MDM'
    if (Test-Path $mdmPath) {
        $devId = (Get-ItemProperty -Path $mdmPath -ErrorAction SilentlyContinue).DeviceId
        if ($devId) {
            Write-Check -Status INFO -Label 'Device ID' -Value $devId
        }
    }

    Write-Host ''
    Write-Info 'To sync with Intune: Settings > Accounts > Access work or school > Sync'
}

Add-Tool -Id 'INTUNE-02' -Category 'Intune Management' -Name 'Force Intune device sync' -Description 'Trigger immediate MDM policy sync with Intune - forces device to pull latest policies and apply them' -Action {
    Write-Section 'Intune Device Sync'

    Write-Info 'Triggering device sync with Intune...'

    # Trigger MDM sync via Registry
    try {
        reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\MDM' /v EnrollmentStatus /t REG_SZ /d 'Syncing' /f | Out-Null

        # Use the syncmlexec
        $scriptPath = "$env:WINDIR\System32\syncmlexec.exe"
        if (Test-Path $scriptPath) {
            & $scriptPath -start
            Start-Sleep -Seconds 3
            Write-Ok 'Sync initiated'
        } else {
            Write-Info 'Alternatively, sync via Settings > Accounts > Access work or school > Sync'
        }
    } catch {
        Write-Err "Sync failed: $_"
    }
}

Add-Tool -Id 'INTUNE-03' -Category 'Intune Management' -Name 'Check Intune policies' -Description 'View active policies: BitLocker status, firewall state, Windows Defender status, password policy - confirms MDM is working' -Admin -Action {
    Write-Section 'Applied Intune Policies'

    Write-Info 'Checking MDM policies...'

    # Check BitLocker policy
    Write-Info 'BitLocker Status:'
    $bl = Get-BitLockerVolume -ErrorAction SilentlyContinue
    if ($bl -and $bl.ProtectionStatus -eq 'On') {
        Write-Check -Status OK -Label 'BitLocker' -Value 'Enabled'
    } else {
        Write-Check -Status WARN -Label 'BitLocker' -Value 'Disabled'
    }

    # Check Firewall
    Write-Info 'Windows Firewall:'
    $fw = Get-NetFirewallProfile | Where-Object { $_.Enabled -eq $true }
    Write-Check -Status $(if ($fw) { 'OK' } else { 'WARN' }) -Label 'Firewall' -Value $(if ($fw) { 'Enabled' } else { 'Disabled' })

    # Check Defender
    Write-Info 'Windows Defender:'
    $defender = Get-MpPreference -ErrorAction SilentlyContinue
    Write-Check -Status INFO -Label 'Defender' -Value $(if ($defender) { 'Installed' } else { 'Not found' })

    # Check password policy
    Write-Info 'Password Policy:'
    Write-Check -Status INFO -Label 'Policy source' -Value 'Check Local Group Policy Editor (gpedit.msc)'

    Write-Host ''
    Write-Info 'To view detailed policies:'
    Write-Host '  1. Run gpresult /scope:user /h report.html'
    Write-Host '  2. Or check Settings > Update & Security > Device Compliance'
}

Add-Tool -Id 'INTUNE-04' -Category 'Intune Management' -Name 'Troubleshoot Intune issues' -Description 'Auto-diagnose MDM problems: enrollment status, network connectivity, certificates, event log errors - provides remediation steps' -Admin -Action {
    Write-Section 'Intune Troubleshooting'

    $issues = @()

    # Check enrollment
    Write-Info 'Checking Intune enrollment...'
    $enrolled = (Get-IntuneEnrollment).Enrolled
    if (-not $enrolled) {
        $issues += 'Device is not Intune enrolled'
    }

    # Check connectivity
    Write-Info 'Checking Intune connectivity...'
    $intunePing = Test-Connection 'manage.microsoft.com' -Count 1 -Quiet -ErrorAction SilentlyContinue
    if (-not $intunePing) {
        $issues += 'Cannot reach manage.microsoft.com'
    }

    # Check MDM certificate
    Write-Info 'Checking MDM certificate...'
    $certs = Get-ChildItem -Path 'Cert:\LocalMachine\My' -ErrorAction SilentlyContinue | Where-Object { $_.Subject -like '*Device*' }
    if (-not $certs) {
        $issues += 'No MDM device certificate found'
    }

    # Check logs
    Write-Info 'Checking event logs...'
    $mdmEvents = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin'; Level = 2 } -MaxEvents 10 -ErrorAction SilentlyContinue)
    if ($mdmEvents.Count) {
        $issues += "Found $($mdmEvents.Count) error(s) in MDM event log"
    }

    # Display results
    Write-Host ''
    if ($issues.Count -eq 0) {
        Write-Ok 'No Intune issues detected'
    } else {
        Write-Warn "Found $($issues.Count) issue(s):"
        Write-Host ''
        $issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }

        Write-Host ''
        Write-Info 'Suggested fixes:'
        Write-Host '  1. Run: gpupdate /force'
        Write-Host '  2. Restart the device'
        Write-Host '  3. Force sync via Settings > Accounts > Access work or school > Sync'
        Write-Host '  4. Re-enroll device if issue persists'
    }
}

Add-Tool -Id 'INTUNE-05' -Category 'Intune Management' -Name 'Export device compliance info' -Description 'Generate compliance report: enrollment status, BitLocker, firewall, Defender, last sync time - save to CSV for audits' -Action {
    Write-Section 'Device Compliance Export'

    # Each column reports what it could actually determine. Previously four of them were
    # wrong in ways that read as non-compliance: Enrolled was always "No" (see
    # Get-IntuneEnrollment), BitLocker said "Disabled" whenever it could not read the
    # volume (Get-BitLockerVolume needs admin), LastSync read a per-user key that was never
    # set, and User was whoever ran the toolkit - the admin account, when elevated.
    $enrollment = Get-IntuneEnrollment

    $bitLocker = if (Test-IsAdmin) {
        $v = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
        if ($v) { "$($v.ProtectionStatus) ($($v.VolumeStatus))" } else { 'Not available' }
    } else { 'Unknown - run as Administrator' }

    $profiles = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
    $on = @($profiles | Where-Object Enabled | ForEach-Object Name)
    $firewall = if (-not $profiles) { 'Unknown' }
                elseif ($on.Count -eq $profiles.Count) { 'Enabled (all profiles)' }
                elseif ($on.Count) { "Partly enabled ($($on -join ', ') only)" }
                else { 'Disabled' }

    $signedIn = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName

    $complianceInfo = [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        SignedInUser = $(if ($signedIn) { $signedIn } else { 'None at the console' })
        ReportedBy   = "$env:USERDOMAIN\$env:USERNAME"
        OSVersion    = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
        Enrolled     = $(if ($enrollment.Enrolled) { 'Yes' } else { 'No' })
        LastSync     = $(if ($enrollment.LastSyncUtc) { $enrollment.LastSyncUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') } else { '' })
        BitLocker    = $bitLocker
        Firewall     = $firewall
        Defender     = $(if (Get-MpPreference -ErrorAction SilentlyContinue) { 'Installed' } else { 'Not Found' })
        Timestamp    = Get-Date
    }

    $file = Get-OutFile -Name "IntuneCompliance_$(Get-Date -Format yyyyMMdd-HHmmss).csv"
    $complianceInfo | Export-Csv -Path $file -NoTypeInformation -Force

    Write-Ok "Compliance info exported to:"
    Write-Host "  $file" -ForegroundColor Cyan

    Write-Host ''
    $complianceInfo | Format-List | Out-Host
}
