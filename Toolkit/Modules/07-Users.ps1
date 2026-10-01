# Modules\07-Users.ps1
# Category: Users & Accounts
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'USR-01' -Category 'Users & Accounts' -Name 'Local user accounts' -Description 'All local users, status and password dates' -Action {
    Get-LocalUser | Select-Object Name, Enabled, LastLogon, PasswordLastSet, PasswordExpires, Description | Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'USR-02' -Category 'Users & Accounts' -Name 'Logged-on sessions' -Description 'Who is signed in; optionally log a session off' -Action {
    $quser = Get-Command quser.exe -ErrorAction SilentlyContinue
    if ($quser) {
        $out = quser 2>&1
        $out | Out-Host
        if ((Test-IsAdmin) -and (Confirm-Action 'Log off a session?')) {
            $id = Read-Host '  Session ID'
            if ($id -match '^\d+$' -and (Confirm-Action "Log off session $id? Unsaved work will be lost.")) { logoff $id; Write-Ok 'Logged off.' }
        }
    } else {
        Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | ForEach-Object {
            $o = Invoke-CimMethod -InputObject $_ -MethodName GetOwner
            [pscustomobject]@{ User = "$($o.Domain)\$($o.User)"; SessionId = $_.SessionId }
        } | Format-Table -AutoSize | Out-Host
    }
}

Add-Tool -Id 'USR-03' -Category 'Users & Accounts' -Name 'User profile sizes' -Description 'Profiles on this PC, last use and disk usage' -Action {
    $profiles = Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special }
    $measure = Confirm-Action 'Measure folder sizes? (slow; needs admin for other users)'
    $profiles | ForEach-Object {
        $user = try { (New-Object Security.Principal.SecurityIdentifier $_.SID).Translate([Security.Principal.NTAccount]).Value } catch { $_.SID }
        [pscustomobject]@{
            User     = $user
            Path     = $_.LocalPath
            Loaded   = $_.Loaded
            LastUsed = $_.LastUseTime
            Size     = if ($measure) { Format-Bytes (Get-FolderSize $_.LocalPath) } else { '-' }
        }
    } | Sort-Object LastUsed -Descending | Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'USR-04' -Category 'Users & Accounts' -Name 'Manage a local user' -Admin -Description 'Enable, disable, unlock, reset password, admin rights' -Action {
    $u = Select-FromList (Get-LocalUser) { '{0,-22} Enabled={1}' -f $_.Name, $_.Enabled } 'User'
    if (-not $u) { return }
    $adsi = [ADSI]"WinNT://$env:COMPUTERNAME/$($u.Name),user"
    $locked = try { $adsi.InvokeGet('IsAccountLocked') } catch { $false }
    Write-Info "Account '$($u.Name)': Enabled=$($u.Enabled)  Locked=$locked"
    Write-Host '  [1] Enable   [2] Disable   [3] Unlock   [4] Reset password'
    Write-Host '  [5] Add to Administrators   [6] Remove from Administrators'
    switch (Read-Host '  Action') {
        '1' { Enable-LocalUser -Name $u.Name; Write-Ok 'Enabled.' }
        '2' { if (Confirm-Action "Disable $($u.Name)?") { Disable-LocalUser -Name $u.Name; Write-Ok 'Disabled.' } }
        '3' { $adsi.InvokeSet('IsAccountLocked', $false); $adsi.SetInfo(); Write-Ok 'Unlocked.' }
        '4' {
            $p1 = Read-Host '  New password' -AsSecureString
            $p2 = Read-Host '  Confirm password' -AsSecureString
            $a = (New-Object Net.NetworkCredential('', $p1)).Password
            $b = (New-Object Net.NetworkCredential('', $p2)).Password
            if ($a -ne $b) { Write-Err 'Passwords do not match.'; return }
            Set-LocalUser -Name $u.Name -Password $p1
            Write-Ok 'Password reset.'
            if ($u.PrincipalSource -eq 'MicrosoftAccount') { Write-Warn 'This is a Microsoft account - the online password is unchanged.' }
        }
        '5' { Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $u.Name; Write-Ok 'Added to Administrators.' }
        '6' { if (Confirm-Action "Remove admin rights from $($u.Name)?") { Remove-LocalGroupMember -SID 'S-1-5-32-544' -Member $u.Name; Write-Ok 'Removed.' } }
    }
}

Add-Tool -Id 'USR-05' -Category 'Users & Accounts' -Name 'Create local user' -Admin -Description 'New local account as standard user or admin' -Action {
    $name = Read-Host '  Username'
    if (-not $name) { return }
    $full = Read-Host '  Full name (optional)'
    $pw = Read-Host '  Password' -AsSecureString
    $params = @{ Name = $name; Password = $pw; PasswordNeverExpires = $false }
    if ($full) { $params.FullName = $full }
    New-LocalUser @params | Out-Null
    Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $name
    if (Confirm-Action 'Make this user a local administrator?') { Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $name }
    Write-Ok "User $name created."
}

Add-Tool -Id 'USR-06' -Category 'Users & Accounts' -Name 'Active Directory user lookup' -Description 'Lock/disable/password status and groups; unlock (no RSAT)' -Action {
    if (-not (Get-CimInstance Win32_ComputerSystem).PartOfDomain) { Write-Warn 'This computer is not joined to a domain.'; return }
    $name = Read-Host '  Username (sAMAccountName)'
    if (-not $name) { return }
    $safe = $name.Replace('\', '\5c').Replace('*', '\2a').Replace('(', '\28').Replace(')', '\29')
    $s = [adsisearcher]"(&(objectCategory=person)(objectClass=user)(sAMAccountName=$safe))"
    $r = $s.FindOne()
    if (-not $r) { Write-Err "User '$name' not found."; return }
    $de = $r.GetDirectoryEntry()
    $de.RefreshCache(@('msDS-User-Account-Control-Computed'))
    $p = $r.Properties
    $first = { param($k) if ($p[$k].Count) { $p[$k][0] } }
    $ft = { param($v) if ($v -and $v -gt 0 -and $v -lt [DateTime]::MaxValue.ToFileTime()) { [DateTime]::FromFileTime([int64]$v) } else { $null } }
    $uac = [int](& $first 'useraccountcontrol')
    $computed = [int]$de.Properties['msDS-User-Account-Control-Computed'].Value
    $pwdSet = & $first 'pwdlastset'
    [pscustomobject]@{
        Name              = & $first 'displayname'
        Email             = & $first 'mail'
        Title             = & $first 'title'
        Department        = & $first 'department'
        Phone             = & $first 'telephonenumber'
        Enabled           = -not ($uac -band 0x2)
        'Locked out'      = [bool]($computed -band 0x10)
        'Password expired'= [bool]($computed -band 0x800000)
        'Pwd never expires' = [bool]($uac -band 0x10000)
        'Password set'    = if ($pwdSet -eq 0) { 'Must change at next logon' } else { & $ft $pwdSet }
        'Bad pwd count'   = & $first 'badpwdcount'
        'Last logon (approx)' = & $ft (& $first 'lastlogontimestamp')
        'Account expires' = & $ft (& $first 'accountexpires')
        Groups            = ($p['memberof'] | ForEach-Object { ($_ -split ',')[0] -replace '^CN=' }) -join ', '
        DN                = & $first 'distinguishedname'
    } | Format-List | Out-Host
    if (($computed -band 0x10) -and (Confirm-Action 'Account is locked. Unlock it now? (requires AD permissions)')) {
        try { $de.Properties['lockoutTime'].Value = 0; $de.CommitChanges(); Write-Ok 'Account unlocked.' }
        catch { Write-Err "Unlock failed: $($_.Exception.Message)" }
    }
}

Add-Tool -Id 'USR-07' -Category 'Users & Accounts' -Name 'Group Policy update' -Description 'gpupdate /force' -Action {
    $null = Invoke-External 'gpupdate.exe' '/force'
}

Add-Tool -Id 'USR-08' -Category 'Users & Accounts' -Name 'Group Policy results report' -Description 'gpresult HTML report of applied policies' -Action {
    $file = Get-OutFile 'gpresult.html'
    $scope = if (Test-IsAdmin) { '' } else { ' /scope user' }
    $null = Invoke-External 'gpresult.exe' "/h `"$file`" /f$scope"
    Open-File $file
}

Add-Tool -Id 'USR-09' -Category 'Users & Accounts' -Name 'Azure AD / Entra join status' -Description 'dsregcmd summary: join type, tenant, PRT' -Action {
    $out = dsregcmd /status
    $keys = 'AzureAdJoined', 'EnterpriseJoined', 'DomainJoined', 'DomainName', 'TenantName', 'TenantId', 'DeviceId', 'WorkplaceJoined', 'AzureAdPrt', 'AzureAdPrtUpdateTime', 'MdmUrl', 'NgcSet'
    $out | ForEach-Object {
        if ($_ -match '^\s*(\w+)\s*:\s*(.*)$' -and $keys -contains $Matches[1]) { Write-Host ('  {0,-22} {1}' -f $Matches[1], $Matches[2]) }
    }
}

Add-Tool -Id 'USR-10' -Category 'Users & Accounts' -Name 'Local groups and members' -Description 'Every local group that has members' -Action {
    foreach ($g in Get-LocalGroup | Sort-Object Name) {
        $members = @(try { Get-LocalGroupMember -Group $g -ErrorAction Stop } catch { })
        if (-not $members.Count) { continue }
        Write-Host "  $($g.Name)" -ForegroundColor Cyan
        foreach ($m in $members) { Write-Host ('      {0,-44} {1}' -f $m.Name, $m.ObjectClass) }
    }
}

Add-Tool -Id 'USR-11' -Category 'Users & Accounts' -Name 'Logon history' -Admin -Description 'Who signed in, when and how (last 7 days)' -Action {
    $types = @{ 2 = 'Console'; 7 = 'Unlock'; 10 = 'Remote Desktop'; 11 = 'Cached credentials' }
    Write-Info 'Reading the Security log...'
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4624; StartTime = (Get-Date).AddDays(-7) } -MaxEvents 5000 -ErrorAction SilentlyContinue)
    $rows = @(foreach ($e in $ev) {
        $lt = [int]$e.Properties[8].Value
        if (-not $types.ContainsKey($lt)) { continue }
        $user = "$($e.Properties[5].Value)"
        if ($user -match '^(DWM-|UMFD-)' -or $user -like '*$' -or $user -eq 'SYSTEM') { continue }
        $from = "$($e.Properties[18].Value)"
        if ($from -in '-', '::1', '127.0.0.1') { $from = '' }
        [pscustomobject]@{ Time = $e.TimeCreated; User = "$($e.Properties[6].Value)\$user"; Type = $types[$lt]; From = $from }
    })
    if (-not $rows.Count) { Write-Info 'No interactive sign-ins in the last 7 days.'; return }
    Write-Section 'Most recent'
    $rows | Select-Object -First 30 | Format-Table -AutoSize | Out-Host
    Write-Section 'Summary'
    $rows | Group-Object User, Type | Sort-Object Count -Descending |
        Select-Object Count, @{ n = 'User'; e = { $_.Group[0].User } }, @{ n = 'Type'; e = { $_.Group[0].Type } }, @{ n = 'Last'; e = { $_.Group[0].Time } } |
        Format-Table -AutoSize | Out-Host
}

Add-Tool -Id 'USR-12' -Category 'Users & Accounts' -Name 'Delete local user' -Admin -Description 'Permanently remove a local account (built-in and current accounts are protected)' -Action {
    # Built-in accounts by SID suffix: 500 Administrator, 501 Guest, 503 DefaultAccount, 504 WDAGUtilityAccount
    $protected = { param($u) $u.SID.Value -match '-(500|501|503|504)$' -or $u.Name -eq $env:USERNAME -or $u.Name -eq 'defaultuser0' }
    $users = @(Get-LocalUser | Where-Object { -not (& $protected $_) })
    if (-not $users.Count) { Write-Info 'No local accounts can be deleted (built-in and signed-in accounts are protected).'; return }
    $u = Select-FromList $users { '{0,-24} Enabled={1,-5} Last logon: {2}' -f $_.Name, $_.Enabled, $_.LastLogon } 'Account to delete'
    if (-not $u) { return }
    Write-Warn "This permanently removes the account '$($u.Name)' ($($u.SID))."
    Write-Info "Its profile folder (usually C:\Users\$($u.Name)) is NOT deleted - remove it separately once any files are saved."
    $typed = Read-Host '  Type DELETE to confirm'
    if ($typed -cne 'DELETE') { Write-Info 'Cancelled - nothing was changed.'; return }
    Remove-LocalUser -SID $u.SID -ErrorAction Stop
    Write-Ok "Account '$($u.Name)' deleted."
    Write-Log "Local user '$($u.Name)' deleted"
}
