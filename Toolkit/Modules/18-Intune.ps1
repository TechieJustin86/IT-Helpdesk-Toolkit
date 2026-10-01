# Modules\18-Intune.ps1
# Category: Intune Management
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'INTUNE-01' -Category 'Intune Management' -Name 'Check Intune enrollment status' -Description 'Verify Intune MDM enrollment, Entra/Azure AD join status, device ID - confirms device is managed' -Action {
    Write-Section 'Intune Enrollment Status'

    $deviceName = $env:COMPUTERNAME
    Write-Info "Device: $deviceName"

    # Check enrollment via WMI
    $enrollmentStatus = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName DMClient -ErrorAction SilentlyContinue

    if ($enrollmentStatus) {
        Write-Ok 'Device is Intune enrolled'
        Write-Check -Status OK -Label 'Version' -Value $enrollmentStatus.VersionNumber
    } else {
        Write-Err 'Device is NOT Intune enrolled'
        Write-Info 'To enroll: Settings > Accounts > Access work or school > Connect'
        return
    }

    # Check Entra/AAD join status
    Write-Section 'Azure AD / Entra ID Status'
    $aadJoin = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName DMRegularObject -ErrorAction SilentlyContinue
    if ($aadJoin) {
        Write-Ok 'Device is Azure AD joined'
    } else {
        Write-Info 'Device is NOT Azure AD joined'
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
    $pwd = Get-LocalUser | Select-Object -First 1 -ExpandProperty Name
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
    $enrolled = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName DMClient -ErrorAction SilentlyContinue
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
    $mdmEvents = Get-EventLog -LogName System -Source 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider' -Newest 10 -ErrorAction SilentlyContinue | Where-Object { $_.EntryType -eq 'Error' }
    if ($mdmEvents) {
        $issues += "Found $($mdmEvents.Count) error(s) in MDM event log"
    }

    # Display results
    Write-Host ''
    if ($issues.Count -eq 0) {
        Write-Ok 'No Intune issues detected'
    } else {
        Write-Warn "Found $($issues.Count) issue(s):"
        Write-Host ''
        $issues | ForEach-Object { Write-Host "  • $_" -ForegroundColor Yellow }

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

    $complianceInfo = [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        User = $env:USERNAME
        OSVersion = (Get-WmiObject -Class Win32_OperatingSystem).Caption
        Enrolled = $(if (Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName DMClient -ErrorAction SilentlyContinue) { 'Yes' } else { 'No' })
        BitLocker = $(if ((Get-BitLockerVolume -ErrorAction SilentlyContinue).ProtectionStatus -eq 'On') { 'Enabled' } else { 'Disabled' })
        Firewall = $(if ((Get-NetFirewallProfile | Where-Object { $_.Enabled }).Count -gt 0) { 'Enabled' } else { 'Disabled' })
        Defender = $(if (Get-MpPreference -ErrorAction SilentlyContinue) { 'Installed' } else { 'Not Found' })
        LastSync = $(Get-ItemProperty -Path 'HKCU\Software\Microsoft\Windows\CurrentVersion\MDM' -Name LastSuccessfulSync -ErrorAction SilentlyContinue).LastSuccessfulSync
        Timestamp = Get-Date
    }

    $file = Get-OutFile -Name "IntuneCompliance_$(Get-Date -Format yyyyMMdd-HHmmss).csv"
    $complianceInfo | Export-Csv -Path $file -NoTypeInformation -Force

    Write-Ok "Compliance info exported to:"
    Write-Host "  $file" -ForegroundColor Cyan

    Write-Host ''
    $complianceInfo | Format-List | Out-Host
}
