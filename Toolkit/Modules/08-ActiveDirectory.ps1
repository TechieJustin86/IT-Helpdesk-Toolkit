# Modules\08-ActiveDirectory.ps1
# Category: Active Directory
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.
# Converted from modulesV2: ActiveDirectoryTools. Uses the RSAT ActiveDirectory module.
# Changes need AD permissions (e.g. account operator / helpdesk delegation), not local admin.
# USR-06 in Users & Accounts does a quick lookup/unlock without RSAT.

# Loads the ActiveDirectory module, or explains how to get it
function Import-ADModuleSafe {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Warn 'The ActiveDirectory PowerShell module (RSAT) is not installed. Use AD-02 to install it.'
        return $false
    }
    try { Import-Module ActiveDirectory -ErrorAction Stop -WarningAction SilentlyContinue; return $true }
    catch { Write-Err "Could not load the ActiveDirectory module: $($_.Exception.Message)"; return $false }
}

# Escapes a value for use inside a single-quoted AD -Filter string
function ConvertTo-ADFilterValue { param([string]$Value) $Value.Replace("'", "''") }

# Prompts for a username and returns the AD user (or $null)
function Read-ADUser {
    param([string[]]$Properties = @())
    $name = "$(Read-Host '  Username (sAMAccountName)')".Trim()
    if (-not $name) { return $null }
    try { Get-ADUser -Identity $name -Properties $Properties -ErrorAction Stop }
    catch { Write-Err "User '$name' not found: $($_.Exception.Message)"; $null }
}

Add-Tool -Id 'AD-01' -Category 'Active Directory' -Name 'RSAT / AD module status' -Description 'Is the ActiveDirectory module installed and loadable on this PC' -Action {
    $mod = Get-Module -ListAvailable -Name ActiveDirectory | Select-Object -First 1
    Write-Check $(if ($mod) { 'OK' } else { 'WARN' }) 'ActiveDirectory module' $(if ($mod) { "Installed ($($mod.Version))" } else { 'Not installed' })
    if (Test-IsAdmin) {
        try {
            $cap = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object Name -like 'Rsat.ActiveDirectory.DS-LDS.Tools*' | Select-Object -First 1
            if ($cap) { Write-Check $(if ($cap.State -eq 'Installed') { 'OK' } else { 'WARN' }) 'RSAT capability' "$($cap.State)  ($($cap.Name))" }
            else { Write-Check 'WARN' 'RSAT capability' 'Not offered on this Windows edition (Home editions cannot install RSAT)' }
        } catch { Write-Check 'INFO' 'RSAT capability' "Unable to query: $($_.Exception.Message)" }
    } else { Write-Check 'INFO' 'RSAT capability' 'Run as Administrator to check / install' }
    if ($mod) {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop -WarningAction SilentlyContinue
            Write-Check 'OK' 'Module import' 'Successful'
            Write-Check $(if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) { 'OK' } else { 'WARN' }) 'AD cmdlets' $(if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) { 'Available' } else { 'Missing' })
        } catch { Write-Check 'WARN' 'Module import' $_.Exception.Message }
    }
}

Add-Tool -Id 'AD-02' -Category 'Active Directory' -Name 'Install RSAT AD tools' -Admin -Description 'Install the Active Directory RSAT feature (from Windows Update or your WSUS source)' -Action {
    try { $cap = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object Name -like 'Rsat.ActiveDirectory.DS-LDS.Tools*' | Select-Object -First 1 }
    catch { Write-Err "Could not query Windows capabilities: $($_.Exception.Message)"; return }
    if (-not $cap) { Write-Warn 'RSAT is not available on this Windows edition (it needs Pro, Enterprise or Education).'; return }
    if ($cap.State -eq 'Installed') { Write-Ok 'Active Directory RSAT tools are already installed.'; return }
    Write-Info "Capability: $($cap.Name)"
    Write-Info 'Windows downloads this from Windows Update or your organisation''s configured source. It can take several minutes.'
    if (-not (Confirm-Action 'Install the Active Directory RSAT tools now?')) { return }
    try {
        $r = Add-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop
        Write-Ok "Installed. Restart needed: $(if ($r.RestartNeeded) { 'Yes' } else { 'No' })"
        Write-Log "RSAT AD tools installed ($($cap.Name))"
        try { Import-Module ActiveDirectory -Force -ErrorAction Stop -WarningAction SilentlyContinue; Write-Ok 'ActiveDirectory module loaded.' }
        catch { Write-Info 'Restart the toolkit to load the new module.' }
    } catch {
        Write-Err "Installation failed: $($_.Exception.Message)"
        Write-Info 'On WSUS-managed PCs, Group Policy may need to allow "Download repair content and optional features directly from Windows Update".'
    }
}

Add-Tool -Id 'AD-03' -Category 'Active Directory' -Name 'Domain and DC info' -Description 'Domain membership, domain details and the nearest domain controller' -Action {
    $cs = Get-CimInstance Win32_ComputerSystem
    Write-Check $(if ($cs.PartOfDomain) { 'OK' } else { 'INFO' }) 'Domain joined' $(if ($cs.PartOfDomain) { $cs.Domain } else { "No (workgroup $($cs.Workgroup))" })
    Write-Check 'INFO' 'Logon server' ("$env:LOGONSERVER".TrimStart('\'))
    if (-not $cs.PartOfDomain) { Write-Info 'AD cmdlets still work from a non-joined PC with network access to a DC and suitable credentials.' }
    if (-not (Import-ADModuleSafe)) { return }
    try {
        $d = Get-ADDomain -ErrorAction Stop
        Write-Check 'OK' 'Domain' "$($d.DNSRoot) (NetBIOS: $($d.NetBIOSName))"
        Write-Check 'INFO' 'Domain mode' "$($d.DomainMode)"
        Write-Check 'INFO' 'PDC emulator' "$($d.PDCEmulator)"
    } catch { Write-Check 'WARN' 'Domain' "Unable to contact Active Directory: $($_.Exception.Message)" }
    try {
        $dc = Get-ADDomainController -Discover -ErrorAction Stop
        Write-Check 'OK' 'Domain controller' "$($dc.HostName) ($($dc.IPv4Address))"
        Write-Check 'INFO' 'AD site' "$($dc.Site)"
    } catch { Write-Check 'WARN' 'Domain controller' 'None discovered' }
}

Add-Tool -Id 'AD-04' -Category 'Active Directory' -Name 'Search AD users' -Description 'Find users by username, name or email; see lock and password status' -Action {
    if (-not (Import-ADModuleSafe)) { return }
    $q = "$(Read-Host '  Username, name or email (part is fine)')".Trim()
    if (-not $q) { return }
    $e = ConvertTo-ADFilterValue $q
    try {
        $users = @(Get-ADUser -Filter "SamAccountName -like '*$e*' -or Name -like '*$e*' -or UserPrincipalName -like '*$e*' -or mail -like '*$e*'" `
            -Properties DisplayName, UserPrincipalName, Enabled, LockedOut, PasswordExpired, PasswordLastSet, LastLogonDate -ResultSetSize 100 -ErrorAction Stop)
    } catch { Write-Err "Search failed: $($_.Exception.Message)"; return }
    if (-not $users.Count) { Write-Warn 'No matching users.'; return }
    $users | Sort-Object SamAccountName | Select-Object SamAccountName, DisplayName, UserPrincipalName, Enabled, LockedOut, PasswordExpired, PasswordLastSet, LastLogonDate |
        Format-Table -AutoSize -Wrap | Out-Host
    if ($users.Count -eq 100) { Write-Info 'Showing the first 100 matches - narrow the search to see more.' }
}

Add-Tool -Id 'AD-05' -Category 'Active Directory' -Name 'AD user group memberships' -Description 'All groups a user belongs to, with type and scope' -Action {
    if (-not (Import-ADModuleSafe)) { return }
    $u = Read-ADUser -Properties MemberOf
    if (-not $u) { return }
    try {
        Get-ADPrincipalGroupMembership -Identity $u -ErrorAction Stop | Sort-Object Name |
            Select-Object Name, GroupCategory, GroupScope | Format-Table -AutoSize | Out-Host
    } catch {
        # Get-ADPrincipalGroupMembership fails on some domains; fall back to memberOf (no primary group)
        Write-Warn "Full lookup failed ($($_.Exception.Message)); showing direct memberships instead."
        $u.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace '^CN=' } | Sort-Object | ForEach-Object { Write-Host "    $_" }
    }
}

Add-Tool -Id 'AD-06' -Category 'Active Directory' -Name 'Search AD computers' -Description 'Find computer accounts: OS, IP, enabled, last logon' -Action {
    if (-not (Import-ADModuleSafe)) { return }
    $q = "$(Read-Host '  Computer name (part is fine)')".Trim()
    if (-not $q) { return }
    $e = ConvertTo-ADFilterValue $q
    try {
        $pcs = @(Get-ADComputer -Filter "Name -like '*$e*'" -Properties OperatingSystem, OperatingSystemVersion, IPv4Address, LastLogonDate, Description -ResultSetSize 100 -ErrorAction Stop)
    } catch { Write-Err "Search failed: $($_.Exception.Message)"; return }
    if (-not $pcs.Count) { Write-Warn 'No matching computers.'; return }
    $pcs | Sort-Object Name | Select-Object Name, Enabled, OperatingSystem, OperatingSystemVersion, IPv4Address, LastLogonDate, Description |
        Format-Table -AutoSize -Wrap | Out-Host
    $stale = @($pcs | Where-Object { $_.LastLogonDate -and $_.LastLogonDate -lt (Get-Date).AddDays(-90) }).Count
    if ($stale) { Write-Info "$stale of these have not logged on for 90+ days." }
}

Add-Tool -Id 'AD-07' -Category 'Active Directory' -Name 'Unlock AD user' -Description 'Unlock a locked-out Active Directory account' -Action {
    if (-not (Import-ADModuleSafe)) { return }
    $u = Read-ADUser -Properties LockedOut, BadLogonCount, LastBadPasswordAttempt
    if (-not $u) { return }
    Write-Check $(if ($u.LockedOut) { 'WARN' } else { 'OK' }) $u.SamAccountName $(if ($u.LockedOut) { "Locked out (last bad password $($u.LastBadPasswordAttempt))" } else { 'Not locked' })
    if (-not $u.LockedOut) { return }
    if (-not (Confirm-Action "Unlock $($u.SamAccountName)?")) { return }
    try { Unlock-ADAccount -Identity $u -ErrorAction Stop; Write-Ok 'Account unlocked.'; Write-Log "AD user $($u.SamAccountName) unlocked" }
    catch { Write-Err "Unlock failed: $($_.Exception.Message)" }
}

Add-Tool -Id 'AD-08' -Category 'Active Directory' -Name 'Enable / disable AD user' -Description 'Enable or disable an Active Directory user account' -Action {
    if (-not (Import-ADModuleSafe)) { return }
    $u = Read-ADUser -Properties Enabled
    if (-not $u) { return }
    $action = if ($u.Enabled) { 'Disable' } else { 'Enable' }
    Write-Info "$($u.SamAccountName) ($($u.Name)) is currently $(if ($u.Enabled) { 'ENABLED' } else { 'DISABLED' })."
    if (-not (Confirm-Action "$action this account?")) { return }
    try {
        if ($u.Enabled) { Disable-ADAccount -Identity $u -ErrorAction Stop } else { Enable-ADAccount -Identity $u -ErrorAction Stop }
        Write-Ok "Account $($action.ToLower())d."
        Write-Log "AD user $($u.SamAccountName) $($action.ToLower())d"
    } catch { Write-Err "$action failed: $($_.Exception.Message)" }
}

Add-Tool -Id 'AD-09' -Category 'Active Directory' -Name 'Reset AD user password' -Description 'Set a new password, optionally force change at next logon and unlock' -Action {
    if (-not (Import-ADModuleSafe)) { return }
    $u = Read-ADUser -Properties LockedOut
    if (-not $u) { return }
    Write-Info "Resetting the password for $($u.SamAccountName) ($($u.Name))."
    $p1 = Read-Host '  New password' -AsSecureString
    $p2 = Read-Host '  Confirm new password' -AsSecureString
    $a = (New-Object Net.NetworkCredential('', $p1)).Password
    $b = (New-Object Net.NetworkCredential('', $p2)).Password
    if (-not $a) { Write-Err 'The password cannot be empty.'; return }
    if ($a -cne $b) { Write-Err 'The passwords do not match - nothing was changed.'; return }
    $a = $null; $b = $null
    if (-not (Confirm-Action "Reset the password for $($u.SamAccountName)?")) { return }
    try {
        Set-ADAccountPassword -Identity $u -Reset -NewPassword $p1 -ErrorAction Stop
        Write-Ok 'Password reset.'
        Write-Log "AD password reset for $($u.SamAccountName)"
    } catch { Write-Err "Password reset failed: $($_.Exception.Message) (it may not meet the domain password policy)"; return }
    if (Confirm-Action 'Require the user to change it at next logon?') {
        try { Set-ADUser -Identity $u -ChangePasswordAtLogon $true -ErrorAction Stop; Write-Ok 'User must change the password at next logon.' }
        catch { Write-Err $_.Exception.Message }
    }
    if ($u.LockedOut -and (Confirm-Action 'The account is also locked out. Unlock it?')) {
        try { Unlock-ADAccount -Identity $u -ErrorAction Stop; Write-Ok 'Account unlocked.' } catch { Write-Err $_.Exception.Message }
    }
}

Add-Tool -Id 'AD-20' -Category 'Active Directory' -Name 'Find unlinked GPOs' -Description 'Find Group Policy Objects that are not linked to any containers' -Action {
    if (-not (Import-ADModuleSafe)) { return }
    try { Import-Module GroupPolicy -ErrorAction Stop }
    catch { Write-Err "Could not load the GroupPolicy module: $($_.Exception.Message)"; return }

    Write-Info 'Scanning all GPOs for unlinked policies (this may take a moment)...'
    $gpos = Get-GPO -All -ErrorAction Stop
    $unlinkedGPOs = @()

    foreach ($gpo in $gpos) {
        try {
            $links = Get-GPOReport -Guid $gpo.Id -ReportType XML -ErrorAction Stop | Out-String
            if ($links -notmatch '<LinksTo>') {
                $unlinkedGPOs += $gpo
            }
        } catch {
            Write-Warn "Could not check links for GPO '$($gpo.DisplayName)': $($_.Exception.Message)"
        }
    }

    if ($unlinkedGPOs.Count -gt 0) {
        Write-Ok "Found $($unlinkedGPOs.Count) unlinked GPO(s):"
        $unlinkedGPOs | Select-Object DisplayName, ModificationTime, Owner | Format-Table -AutoSize | Out-Host
    } else {
        Write-Ok 'No unlinked GPOs found in the domain.'
    }
}

Add-Tool -Id 'AD-21' -Category 'Active Directory' -Name 'Find disabled GPOs' -Description 'Find GPOs with user or computer settings disabled' -Action {
    try { Import-Module GroupPolicy -ErrorAction Stop }
    catch { Write-Err "Could not load the GroupPolicy module: $($_.Exception.Message)"; return }

    Write-Info 'Scanning all GPOs for disabled settings...'
    $gpos = Get-GPO -All -ErrorAction Stop

    $computerDisabled = @($gpos | Where-Object { $_.GpoStatus -eq 'ComputerSettingsDisabled' })
    $userDisabled = @($gpos | Where-Object { $_.GpoStatus -eq 'UserSettingsDisabled' })
    $bothDisabled = @($gpos | Where-Object { $_.GpoStatus -eq 'AllSettingsDisabled' })

    Write-Check $(if ($computerDisabled.Count) { 'INFO' } else { 'OK' }) 'Computer settings disabled' "$($computerDisabled.Count) GPO(s)"
    Write-Check $(if ($userDisabled.Count) { 'INFO' } else { 'OK' }) 'User settings disabled' "$($userDisabled.Count) GPO(s)"
    Write-Check $(if ($bothDisabled.Count) { 'INFO' } else { 'OK' }) 'All settings disabled' "$($bothDisabled.Count) GPO(s)"

    if ($computerDisabled.Count -gt 0) { Write-Info 'Computer disabled:'; $computerDisabled | ForEach-Object { Write-Host "    $($_.DisplayName)" } }
    if ($userDisabled.Count -gt 0) { Write-Info 'User disabled:'; $userDisabled | ForEach-Object { Write-Host "    $($_.DisplayName)" } }
    if ($bothDisabled.Count -gt 0) { Write-Info 'All disabled:'; $bothDisabled | ForEach-Object { Write-Host "    $($_.DisplayName)" } }
}

Add-Tool -Id 'AD-22' -Category 'Active Directory' -Name 'Search GPOs for text' -Description 'Search all GPOs in the domain for a specific configuration or setting text' -Action {
    try { Import-Module GroupPolicy -ErrorAction Stop }
    catch { Write-Err "Could not load the GroupPolicy module: $($_.Exception.Message)"; return }

    $searchTerm = "$(Read-Host '  Search term')".Trim()
    if (-not $searchTerm) { Write-Info 'Search cancelled.'; return }

    Write-Info "Searching all GPOs for '$searchTerm' (this may take several minutes)..."
    $allGpos = Get-GPO -All -ErrorAction Stop
    $matched = @()

    foreach ($gpo in $allGpos) {
        try {
            $report = Get-GPOReport -Guid $gpo.Id -ReportType Xml -ErrorAction SilentlyContinue
            if ($report -match [regex]::Escape($searchTerm)) {
                $matched += $gpo
            }
        } catch {
            Write-Warn "Could not search GPO '$($gpo.DisplayName)': $($_.Exception.Message)"
        }
    }

    if ($matched.Count -gt 0) {
        Write-Ok "Found $($matched.Count) GPO(s) containing '$searchTerm':"
        $matched | Select-Object DisplayName, Owner, ModificationTime | Format-Table -AutoSize | Out-Host
    } else {
        Write-Info "No GPOs found containing '$searchTerm'."
    }
}

Add-Tool -Id 'AD-23' -Category 'Active Directory' -Name 'Find empty groups' -Description 'Find security and distribution groups with no members' -Action {
    if (-not (Import-ADModuleSafe)) { return }

    Write-Info 'Scanning for empty groups (this may take a moment)...'
    $groups = Get-ADGroup -Filter * -ErrorAction Stop
    $emptyGroups = @()

    foreach ($group in $groups) {
        try {
            $members = Get-ADGroupMember -Identity $group -ErrorAction SilentlyContinue
            if ($members.Count -eq 0) {
                $emptyGroups += $group
            }
        } catch {
            Write-Warn "Could not check members for group '$($group.Name)': $($_.Exception.Message)"
        }
    }

    if ($emptyGroups.Count -gt 0) {
        Write-Ok "Found $($emptyGroups.Count) empty group(s):"
        $emptyGroups | Select-Object Name, GroupCategory, GroupScope, Description | Format-Table -AutoSize -Wrap | Out-Host
    } else {
        Write-Ok 'No empty groups found in the domain.'
    }
}

Add-Tool -Id 'AD-24' -Category 'Active Directory' -Name 'Get detailed user info' -Description 'Export detailed user information including groups and contact details' -Action {
    if (-not (Import-ADModuleSafe)) { return }

    $query = "$(Read-Host '  Username or name (or part of it)')".Trim()
    if (-not $query) { return }

    $query = ConvertTo-ADFilterValue $query
    try {
        $users = @(Get-ADUser -Filter "SamAccountName -like '*$query*' -or Name -like '*$query*'" -Properties GivenName, Surname, EmailAddress, SamAccountName, MobilePhone, IPPhone, Title, Department, Manager, MemberOf -ResultSetSize 100 -ErrorAction Stop)
    } catch { Write-Err "Search failed: $($_.Exception.Message)"; return }

    if (-not $users.Count) { Write-Warn 'No matching users found.'; return }
    if ($users.Count -gt 1) { Write-Warn "Multiple matches ($($users.Count)). Showing first 10:"; $users = $users | Select-Object -First 10 }

    foreach ($user in $users) {
        Write-Host "`n==================== $($user.Name) ====================" -ForegroundColor Cyan
        Write-Host "  Username:  $($user.SamAccountName)"
        Write-Host "  Email:     $($user.EmailAddress)"
        Write-Host "  Title:     $($user.Title)"
        Write-Host "  Department: $($user.Department)"
        Write-Host "  Phone:     $($user.IPPhone) (Office)  $($user.MobilePhone) (Mobile)"

        $manager = if ($user.Manager) { (Get-ADUser -Identity $user.Manager -ErrorAction SilentlyContinue).Name } else { '[None]' }
        Write-Host "  Manager:   $manager"

        if ($user.MemberOf.Count -gt 0) {
            Write-Host "  Groups ($($user.MemberOf.Count)):"
            $user.MemberOf | ForEach-Object { Write-Host "    - $($_ -replace '^CN=' -replace ',OU=.*' -replace ',DC=.*')" }
        } else {
            Write-Host "  Groups:    [None]"
        }
    }
}

Add-Tool -Id 'AD-25' -Category 'Active Directory' -Name 'Check user last logon' -Description 'Check when a user last logged on across all domain controllers' -Action {
    if (-not (Import-ADModuleSafe)) { return }

    $username = "$(Read-Host '  Username (sAMAccountName)')".Trim()
    if (-not $username) { return }

    Write-Info "Checking last logon for '$username' across all domain controllers..."

    try {
        $dcs = Get-ADDomainController -Filter * -ErrorAction Stop | Select-Object -ExpandProperty HostName
    } catch { Write-Err "Could not query domain controllers: $($_.Exception.Message)"; return }

    $logonInfo = @()

    foreach ($dc in $dcs) {
        try {
            $user = Get-ADUser -Filter { SamAccountName -eq $username } -Server $dc -Properties LastLogonDate -ErrorAction Stop
            if ($user) {
                $logonInfo += [PSCustomObject]@{
                    DomainController = $dc
                    Username = $user.SamAccountName
                    LastLogon = $user.LastLogonDate
                    DaysAgo = if ($user.LastLogonDate) { [math]::Round(((Get-Date) - $user.LastLogonDate).TotalDays) } else { '[Never]' }
                }
            }
        } catch {
            Write-Warn "Could not query $dc : $($_.Exception.Message)"
        }
    }

    if ($logonInfo.Count -gt 0) {
        Write-Ok "Last logon info for '$username':"
        $logonInfo | Sort-Object LastLogon -Descending | Format-Table -AutoSize | Out-Host
        $latest = $logonInfo | Sort-Object LastLogon -Descending | Select-Object -First 1
        Write-Info "Most recent: $($latest.LastLogon) on $($latest.DomainController)"
    } else {
        Write-Warn "User '$username' not found or no logon data available."
    }
}

Add-Tool -Id 'AD-26' -Category 'Active Directory' -Name 'User password age report' -Description 'Report on user password ages in a specified organizational unit' -Action {
    if (-not (Import-ADModuleSafe)) { return }

    $ouFilter = "$(Read-Host '  OU path (leave blank for entire domain)')".Trim()
    Write-Info 'Retrieving users and analyzing password ages...'

    try {
        if ($ouFilter) {
            $users = @(Get-ADUser -Filter * -SearchBase $ouFilter -Properties DisplayName, SamAccountName, pwdLastSet -ErrorAction Stop)
        } else {
            $users = @(Get-ADUser -Filter * -Properties DisplayName, SamAccountName, pwdLastSet -ErrorAction Stop)
        }
    } catch { Write-Err "Could not retrieve users: $($_.Exception.Message)"; return }

    if (-not $users.Count) { Write-Warn 'No users found.'; return }

    $results = @()
    foreach ($user in $users) {
        $pwdLastSet = if ($user.pwdLastSet -gt 0) { [datetime]::FromFileTimeUtc($user.pwdLastSet) } else { $null }
        $passwordAgeDays = if ($pwdLastSet) { [math]::Round(((Get-Date) - $pwdLastSet).TotalDays) } else { -1 }

        $results += [PSCustomObject]@{
            DisplayName = $user.DisplayName
            SamAccountName = $user.SamAccountName
            PasswordLastSet = $pwdLastSet
            DaysOld = $passwordAgeDays
        }
    }

    $results = $results | Sort-Object DaysOld -Descending

    Write-Ok "Password age report ($($results.Count) users):"
    $results | Select-Object DisplayName, SamAccountName, PasswordLastSet, DaysOld | Format-Table -AutoSize | Out-Host

    $over90 = @($results | Where-Object { $_.DaysOld -gt 90 }).Count
    if ($over90) { Write-Check 'INFO' 'Passwords older than 90 days' "$over90 user(s)" }
}

Add-Tool -Id 'AD-27' -Category 'Active Directory' -Name 'Export user details and groups' -Description 'Export user information with group memberships to a CSV file' -Action {
    if (-not (Import-ADModuleSafe)) { return }

    $ouFilter = "$(Read-Host '  OU path (leave blank for entire domain)')".Trim()
    $outFile = Get-OutFile 'user-export.csv'

    Write-Info 'Retrieving user data (this may take a moment)...'

    try {
        if ($ouFilter) {
            $users = @(Get-ADUser -Filter * -SearchBase $ouFilter -Properties DisplayName, EmailAddress, SamAccountName, Title, Department, MemberOf -ErrorAction Stop)
        } else {
            $users = @(Get-ADUser -Filter * -Properties DisplayName, EmailAddress, SamAccountName, Title, Department, MemberOf -ErrorAction Stop)
        }
    } catch { Write-Err "Could not retrieve users: $($_.Exception.Message)"; return }

    if (-not $users.Count) { Write-Warn 'No users found.'; return }

    Write-Info "Processing $($users.Count) user(s)..."
    $export = @()

    foreach ($user in $users) {
        $groups = if ($user.MemberOf.Count -gt 0) { $user.MemberOf -join '; ' } else { '[None]' }
        $export += [PSCustomObject]@{
            DisplayName = $user.DisplayName
            SamAccountName = $user.SamAccountName
            Email = $user.EmailAddress
            Title = $user.Title
            Department = $user.Department
            Groups = $groups
        }
    }

    try {
        $export | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Ok "Exported $($export.Count) user(s) to: $outFile"
    } catch { Write-Err "Export failed: $($_.Exception.Message)" }
}

Add-Tool -Id 'AD-28' -Category 'Active Directory' -Name 'Security groups members report' -Description 'Generate a report of group members for security groups in a specified OU' -Action {
    if (-not (Import-ADModuleSafe)) { return }

    $ouFilter = "$(Read-Host '  OU path (for groups)')".Trim()
    if (-not $ouFilter) { Write-Info 'Cancelled.'; return }

    $outFile = Get-OutFile 'groups-members-report.csv'

    Write-Info "Retrieving groups and members from $ouFilter..."

    try {
        $groups = @(Get-ADGroup -Filter * -SearchBase $ouFilter -ErrorAction Stop)
    } catch { Write-Err "Could not retrieve groups: $($_.Exception.Message)"; return }

    if (-not $groups.Count) { Write-Warn 'No groups found.'; return }

    $report = @()
    foreach ($group in $groups) {
        try {
            $members = @(Get-ADGroupMember -Identity $group -ErrorAction SilentlyContinue | Where-Object { $_.objectClass -eq 'user' })
            foreach ($member in $members) {
                $report += [PSCustomObject]@{
                    GroupName = $group.Name
                    GroupType = $group.GroupCategory
                    MemberName = $member.Name
                    MemberType = $member.objectClass
                }
            }
        } catch {
            Write-Warn "Could not retrieve members for group '$($group.Name)': $($_.Exception.Message)"
        }
    }

    if ($report.Count -eq 0) { Write-Warn 'No members found.'; return }

    try {
        $report | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Ok "Exported $($report.Count) membership record(s) to: $outFile"
    } catch { Write-Err "Export failed: $($_.Exception.Message)" }
}

Add-Tool -Id 'AD-29' -Category 'Active Directory' -Name 'User security group report' -Description 'Report on user membership in security groups' -Action {
    if (-not (Import-ADModuleSafe)) { return }

    $query = "$(Read-Host '  Username (or part of it)')".Trim()
    if (-not $query) { return }

    $query = ConvertTo-ADFilterValue $query
    $outFile = Get-OutFile 'user-groups-report.csv'

    try {
        $users = @(Get-ADUser -Filter "SamAccountName -like '*$query*' -or Name -like '*$query*'" -Properties MemberOf -ResultSetSize 100 -ErrorAction Stop)
    } catch { Write-Err "Search failed: $($_.Exception.Message)"; return }

    if (-not $users.Count) { Write-Warn 'No matching users found.'; return }

    Write-Info "Retrieving group information for $($users.Count) user(s)..."
    $report = @()

    foreach ($user in $users) {
        if ($user.MemberOf.Count -gt 0) {
            foreach ($groupDN in $user.MemberOf) {
                try {
                    $group = Get-ADGroup -Identity $groupDN -ErrorAction SilentlyContinue
                    $report += [PSCustomObject]@{
                        UserName = $user.SamAccountName
                        DisplayName = $user.Name
                        GroupName = $group.Name
                        GroupScope = $group.GroupScope
                    }
                } catch {
                    $report += [PSCustomObject]@{
                        UserName = $user.SamAccountName
                        DisplayName = $user.Name
                        GroupName = $groupDN
                        GroupScope = '[Error]'
                    }
                }
            }
        }
    }

    if ($report.Count -eq 0) { Write-Warn 'No group memberships found.'; return }

    try {
        $report | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Ok "Exported $($report.Count) membership(s) to: $outFile"
    } catch { Write-Err "Export failed: $($_.Exception.Message)" }
}

Add-Tool -Id 'AD-30' -Category 'Active Directory' -Name 'All staff member details' -Description 'Export details for all staff members in the domain' -Action {
    if (-not (Import-ADModuleSafe)) { return }

    $outFile = Get-OutFile 'all-staff-details.csv'
    Write-Info 'Retrieving all staff member details (this may take a moment)...'

    try {
        $users = @(Get-ADUser -Filter * -Properties DisplayName, EmailAddress, Title, Department, MobilePhone, IPPhone, Manager, Enabled -ErrorAction Stop)
    } catch { Write-Err "Could not retrieve users: $($_.Exception.Message)"; return }

    if (-not $users.Count) { Write-Warn 'No users found.'; return }

    Write-Info "Processing $($users.Count) user(s)..."
    $export = @()

    foreach ($user in $users) {
        $manager = if ($user.Manager) { (Get-ADUser -Identity $user.Manager -ErrorAction SilentlyContinue).Name } else { '[None]' }
        $export += [PSCustomObject]@{
            DisplayName = $user.DisplayName
            Email = $user.EmailAddress
            Username = $user.SamAccountName
            Title = $user.Title
            Department = $user.Department
            OfficePhone = $user.IPPhone
            MobilePhone = $user.MobilePhone
            Manager = $manager
            Enabled = $user.Enabled
        }
    }

    try {
        $export | Sort-Object DisplayName | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Ok "Exported $($export.Count) staff member(s) to: $outFile"
    } catch { Write-Err "Export failed: $($_.Exception.Message)" }
}

Add-Tool -Id 'AD-31' -Category 'Active Directory' -Name 'Staff member details (single)' -Description 'Export details for a specific staff member' -Action {
    if (-not (Import-ADModuleSafe)) { return }

    $query = "$(Read-Host '  Username or name')".Trim()
    if (-not $query) { return }

    $query = ConvertTo-ADFilterValue $query

    try {
        $user = Get-ADUser -Filter "SamAccountName -eq '$query' -or Name -like '*$query*'" -Properties DisplayName, EmailAddress, Title, Department, MobilePhone, IPPhone, Manager, EmployeeID, EmployeeNumber, Enabled -ErrorAction Stop | Select-Object -First 1
    } catch { Write-Err "Search failed: $($_.Exception.Message)"; return }

    if (-not $user) { Write-Warn "User '$query' not found."; return }

    $outFile = Get-OutFile "staff-$($user.SamAccountName).csv"
    $manager = if ($user.Manager) { (Get-ADUser -Identity $user.Manager -ErrorAction SilentlyContinue).Name } else { '[None]' }

    $export = [PSCustomObject]@{
        DisplayName = $user.DisplayName
        Username = $user.SamAccountName
        Email = $user.EmailAddress
        EmployeeID = $user.EmployeeID
        Title = $user.Title
        Department = $user.Department
        OfficePhone = $user.IPPhone
        MobilePhone = $user.MobilePhone
        Manager = $manager
        Enabled = $user.Enabled
    }

    try {
        $export | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Ok "Exported staff details to: $outFile"
    } catch { Write-Err "Export failed: $($_.Exception.Message)" }
}

Add-Tool -Id 'AD-32' -Category 'Active Directory' -Name 'User profile management' -Description 'Manage user profile deletion and roaming settings' -Action {
    Write-Info 'User Profile Management Options:'
    Write-Info '1. Delete local user profile'
    Write-Info '2. Enable roaming profile'
    Write-Info '3. Disable roaming profile'
    $choice = "$(Read-Host '  Select option (1-3)')".Trim()

    switch ($choice) {
        '1' {
            $username = "$(Read-Host '  Username to delete profile for')".Trim()
            if (-not $username) { return }
            if (-not (Confirm-Action "Delete profile for $username ?")) { return }
            try {
                # Win32_UserProfile has no Name property; match the profile folder name (strip DOMAIN\ and WQL wildcards)
                $folder = ($username -split '\\')[-1] -replace "['%]", ''
                Get-CimInstance Win32_UserProfile -Filter "LocalPath LIKE '%\\$folder'" -ErrorAction Stop | Remove-CimInstance -ErrorAction Stop
                Write-Ok "Profile deleted for $username"
                Write-Log "User profile deleted: $username"
            } catch { Write-Err "Profile deletion failed: $($_.Exception.Message)" }
        }
        '2' {
            Write-Info 'To enable roaming profiles, set the profilePath in AD for the user.'
            Write-Info 'Example: \\server\profiles\username'
        }
        '3' {
            Write-Info 'To disable roaming profiles, clear the profilePath in AD for the user.'
        }
        default { Write-Warn 'Invalid selection.' }
    }
}

Add-Tool -Id 'AD-33' -Category 'Active Directory' -Name 'AD Self-Service Plus registry config' -Description 'Configure AD Self-Service Plus registry settings' -Admin -Action {
    Write-Info 'Configuring AD Self-Service Plus registry settings...'
    $regPath = 'HKLM:\Software\Policies\Quest Software\ActiveRoles\SelfService'

    try {
        if (-not (Test-Path $regPath)) {
            Write-Info 'Registry path does not exist. Creating...'
            New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name 'Enabled' -Value 1 -ErrorAction Stop
        Write-Ok 'AD Self-Service Plus registry settings configured.'
        Write-Log 'AD Self-Service Plus registry settings modified'
    } catch { Write-Err "Configuration failed: $($_.Exception.Message)" }
}
