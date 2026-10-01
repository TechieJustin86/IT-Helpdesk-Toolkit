# Modules\09-Microsoft365.ps1
# Category: Microsoft 365
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.
# Converted from modulesV2: Microsoft365Tools. Read-only Microsoft Graph queries.
# Needs the Microsoft.Graph PowerShell modules (M365-02 installs them for the current user)
# and an account allowed to read the directory. Connect once with M365-03; the session is
# reused by the other tools until you disconnect or close the toolkit.

$Script:GraphModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Groups', 'Microsoft.Graph.Identity.DirectoryManagement')
$Script:GraphScopes  = @('User.Read.All', 'Group.Read.All', 'Directory.Read.All', 'Organization.Read.All')

# Returns $true when a Graph session is active; otherwise explains what to do
function Test-GraphConnected {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Warn 'The Microsoft Graph modules are not installed. Run M365-02 first.'
        return $false
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
    if (Get-MgContext -ErrorAction SilentlyContinue) { return $true }
    Write-Warn 'Not connected to Microsoft 365. Run M365-03 (Connect) first.'
    $false
}

function Import-GraphModule {
    param([string]$Name)
    try { Import-Module $Name -ErrorAction Stop; $true } catch { Write-Err "Could not load $Name : $($_.Exception.Message)"; $false }
}

function ConvertTo-ODataValue { param([string]$Value) $Value.Replace("'", "''") }

Add-Tool -Id 'M365-01' -Category 'Microsoft 365' -Name 'Graph module status' -Description 'Which Microsoft Graph modules are installed and whether they load' -Action {
    foreach ($m in $Script:GraphModules) {
        $mod = Get-Module -ListAvailable -Name $m | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $mod) { Write-Check 'WARN' $m 'Not installed'; continue }
        try { Import-Module $m -ErrorAction Stop; Write-Check 'OK' $m "$($mod.Version) - loads" }
        catch { Write-Check 'WARN' $m "$($mod.Version) - failed to load: $($_.Exception.Message)" }
    }
    $ctx = $null
    if (Get-Command Get-MgContext -ErrorAction SilentlyContinue) { $ctx = Get-MgContext -ErrorAction SilentlyContinue }
    Write-Check $(if ($ctx) { 'OK' } else { 'INFO' }) 'Graph session' $(if ($ctx) { "Connected as $($ctx.Account)" } else { 'Not connected' })
}

Add-Tool -Id 'M365-02' -Category 'Microsoft 365' -Name 'Install Graph modules' -Description 'Install the Microsoft Graph PowerShell modules for the current user (PSGallery)' -Action {
    $missing = @($Script:GraphModules | Where-Object { -not (Get-Module -ListAvailable -Name $_) })
    if (-not $missing.Count) { Write-Ok 'All required Microsoft Graph modules are already installed.'; return }
    Write-Info 'Missing modules (published by Microsoft on the PowerShell Gallery):'
    $missing | ForEach-Object { Write-Host "      $_" }
    if (-not (Confirm-Action 'Install them for the current user? This downloads from the PowerShell Gallery and can take a few minutes.')) { return }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Write-Info 'Installing the NuGet package provider...'
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
        }
        if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) { Register-PSRepository -Default -ErrorAction Stop }
        foreach ($m in $missing) {
            Write-Info "Installing $m ..."
            Install-Module -Name $m -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
            Write-Ok "$m installed."
        }
        Write-Log 'Microsoft Graph modules installed'
    } catch { Write-Err "Installation failed: $($_.Exception.Message)" }
}

Add-Tool -Id 'M365-03' -Category 'Microsoft 365' -Name 'Connect to Microsoft 365' -Description 'Sign in to Microsoft Graph with read-only permissions' -Action {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) { Write-Warn 'Install the Graph modules first (M365-02).'; return }
    if (-not (Import-GraphModule Microsoft.Graph.Authentication)) { return }
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if ($ctx) {
        Write-Info "Already connected as $($ctx.Account) (tenant $($ctx.TenantId))."
        if (Confirm-Action 'Keep using this connection?') { return }
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Info 'Read-only permissions requested:'
    $Script:GraphScopes | ForEach-Object { Write-Host "      $_" }
    Write-Info 'A Microsoft sign-in window opens. An admin may need to approve these permissions the first time.'
    if (-not (Confirm-Action 'Sign in to Microsoft 365 now?')) { return }
    try {
        Connect-MgGraph -Scopes $Script:GraphScopes -NoWelcome -ErrorAction Stop
        $ctx = Get-MgContext
        Write-Ok "Connected as $($ctx.Account)"
        Write-Check 'INFO' 'Tenant' $ctx.TenantId
        Write-Check 'INFO' 'Granted scopes' ($ctx.Scopes -join ', ')
        Write-Log "Connected to Microsoft Graph as $($ctx.Account)"
    } catch {
        Write-Err "Sign-in failed: $($_.Exception.Message)"
        Write-Info 'If the sign-in window does not appear from the GUI, try the Console version (bottom right).'
    }
}

Add-Tool -Id 'M365-04' -Category 'Microsoft 365' -Name 'Current Graph connection' -Description 'Signed-in account, tenant, auth type and granted permissions' -Action {
    if (-not (Test-GraphConnected)) { return }
    $ctx = Get-MgContext
    Write-Check 'OK' 'Account' $ctx.Account
    Write-Check 'INFO' 'Tenant ID' $ctx.TenantId
    Write-Check 'INFO' 'Auth type' "$($ctx.AuthType)"
    Write-Check 'INFO' 'Scopes' ($ctx.Scopes -join ', ')
}

Add-Tool -Id 'M365-05' -Category 'Microsoft 365' -Name 'Disconnect Microsoft 365' -Description 'Sign out of the Microsoft Graph session' -Action {
    if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue) -or -not (Get-MgContext -ErrorAction SilentlyContinue)) { Write-Info 'No active Microsoft Graph session.'; return }
    if (-not (Confirm-Action "Disconnect $((Get-MgContext).Account)?")) { return }
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Write-Ok 'Disconnected.'
}

Add-Tool -Id 'M365-06' -Category 'Microsoft 365' -Name 'Tenant information' -Description 'Organisation name, tenant ID and verified domains' -Action {
    if (-not (Test-GraphConnected) -or -not (Import-GraphModule Microsoft.Graph.Identity.DirectoryManagement)) { return }
    try {
        $org = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1
        Write-Check 'INFO' 'Organisation' $org.DisplayName
        Write-Check 'INFO' 'Tenant ID' $org.Id
        Write-Check 'INFO' 'Country' $org.CountryLetterCode
        Write-Section 'Verified domains'
        $org.VerifiedDomains | Select-Object Name, IsDefault, IsInitial | Format-Table -AutoSize | Out-Host
    } catch { Write-Err "Unable to read tenant information: $($_.Exception.Message)" }
}

Add-Tool -Id 'M365-07' -Category 'Microsoft 365' -Name 'Search Microsoft 365 users' -Description 'Find users whose name, UPN or email starts with your text' -Action {
    if (-not (Test-GraphConnected) -or -not (Import-GraphModule Microsoft.Graph.Users)) { return }
    $q = "$(Read-Host '  Start of name, UPN or email')".Trim()
    if (-not $q) { return }
    $e = ConvertTo-ODataValue $q
    try {
        $users = @(Get-MgUser -Filter "startswith(displayName,'$e') or startswith(userPrincipalName,'$e') or startswith(mail,'$e')" `
            -Property Id, DisplayName, UserPrincipalName, Mail, AccountEnabled -ConsistencyLevel eventual -CountVariable n -Top 100 -ErrorAction Stop)
    } catch { Write-Err "Search failed: $($_.Exception.Message)"; return }
    if (-not $users.Count) { Write-Warn 'No matching users.'; return }
    $users | Select-Object DisplayName, UserPrincipalName, Mail, AccountEnabled | Format-Table -AutoSize -Wrap | Out-Host
}

Add-Tool -Id 'M365-08' -Category 'Microsoft 365' -Name 'Microsoft 365 user details' -Description 'Job title, department, phones, created date and licence count' -Action {
    if (-not (Test-GraphConnected) -or -not (Import-GraphModule Microsoft.Graph.Users)) { return }
    $id = "$(Read-Host '  User principal name (email) or object ID')".Trim()
    if (-not $id) { return }
    try {
        $u = Get-MgUser -UserId $id -Property Id, DisplayName, UserPrincipalName, Mail, AccountEnabled, JobTitle, Department, OfficeLocation, BusinessPhones, MobilePhone, CreatedDateTime, AssignedLicenses, OnPremisesSyncEnabled -ErrorAction Stop
        [pscustomobject]@{
            DisplayName       = $u.DisplayName
            UserPrincipalName = $u.UserPrincipalName
            Mail              = $u.Mail
            Enabled           = $u.AccountEnabled
            JobTitle          = $u.JobTitle
            Department        = $u.Department
            Office            = $u.OfficeLocation
            Phones            = (@($u.BusinessPhones) + @($u.MobilePhone) | Where-Object { $_ }) -join ', '
            Created           = $u.CreatedDateTime
            Licences          = @($u.AssignedLicenses).Count
            'Synced from AD'  = [bool]$u.OnPremisesSyncEnabled
            ObjectId          = $u.Id
        } | Format-List | Out-Host
    } catch { Write-Err "User not found or not readable: $($_.Exception.Message)" }
}

Add-Tool -Id 'M365-09' -Category 'Microsoft 365' -Name 'Microsoft 365 user licences' -Description 'Licences (SKUs) assigned to a user' -Action {
    if (-not (Test-GraphConnected) -or -not (Import-GraphModule Microsoft.Graph.Users)) { return }
    $id = "$(Read-Host '  User principal name (email) or object ID')".Trim()
    if (-not $id) { return }
    try {
        $lic = @(Get-MgUserLicenseDetail -UserId $id -ErrorAction Stop)
        if (-not $lic.Count) { Write-Warn 'No licences assigned - the user cannot use Microsoft 365 apps or mailbox.'; return }
        $lic | Select-Object SkuPartNumber, SkuId | Format-Table -AutoSize | Out-Host
    } catch { Write-Err "Unable to read licences: $($_.Exception.Message)" }
}

Add-Tool -Id 'M365-10' -Category 'Microsoft 365' -Name 'Microsoft 365 user groups' -Description 'Groups, teams and directory roles a user belongs to' -Action {
    if (-not (Test-GraphConnected) -or -not (Import-GraphModule Microsoft.Graph.Users)) { return }
    $id = "$(Read-Host '  User principal name (email) or object ID')".Trim()
    if (-not $id) { return }
    try {
        $m = @(Get-MgUserMemberOf -UserId $id -All -ErrorAction Stop)
        if (-not $m.Count) { Write-Info 'No group memberships.'; return }
        $m | ForEach-Object {
            [pscustomobject]@{
                Name = $_.AdditionalProperties['displayName']
                Type = "$($_.AdditionalProperties['@odata.type'])" -replace '^#microsoft\.graph\.', ''
                Mail = $_.AdditionalProperties['mail']
            }
        } | Sort-Object Type, Name | Format-Table -AutoSize | Out-Host
    } catch { Write-Err "Unable to read memberships: $($_.Exception.Message)" }
}

Add-Tool -Id 'M365-11' -Category 'Microsoft 365' -Name 'Licensed users' -Description 'All users with at least one licence' -Action {
    if (-not (Test-GraphConnected) -or -not (Import-GraphModule Microsoft.Graph.Users)) { return }
    Write-Info 'Reading all users (large tenants take a moment)...'
    try {
        $users = @(Get-MgUser -All -Property DisplayName, UserPrincipalName, AccountEnabled, AssignedLicenses -ErrorAction Stop | Where-Object { @($_.AssignedLicenses).Count })
        Write-Check 'INFO' 'Licensed users' "$($users.Count)"
        $users | Sort-Object DisplayName | Select-Object DisplayName, UserPrincipalName, AccountEnabled, @{ n = 'Licences'; e = { @($_.AssignedLicenses).Count } } |
            Format-Table -AutoSize | Out-Host
        $off = @($users | Where-Object { -not $_.AccountEnabled }).Count
        if ($off) { Write-Warn "$off disabled account(s) still hold licences - these may be reclaimable." }
    } catch { Write-Err $_.Exception.Message }
}

Add-Tool -Id 'M365-12' -Category 'Microsoft 365' -Name 'Unlicensed users' -Description 'All users with no licence assigned' -Action {
    if (-not (Test-GraphConnected) -or -not (Import-GraphModule Microsoft.Graph.Users)) { return }
    Write-Info 'Reading all users (large tenants take a moment)...'
    try {
        $users = @(Get-MgUser -All -Property DisplayName, UserPrincipalName, AccountEnabled, AssignedLicenses, UserType -ErrorAction Stop | Where-Object { -not @($_.AssignedLicenses).Count })
        Write-Check 'INFO' 'Unlicensed users' "$($users.Count)"
        $users | Sort-Object DisplayName | Select-Object DisplayName, UserPrincipalName, AccountEnabled, UserType | Format-Table -AutoSize | Out-Host
    } catch { Write-Err $_.Exception.Message }
}

Add-Tool -Id 'M365-13' -Category 'Microsoft 365' -Name 'Licence summary' -Description 'Every subscription: purchased, used and available licences' -Action {
    if (-not (Test-GraphConnected) -or -not (Import-GraphModule Microsoft.Graph.Identity.DirectoryManagement)) { return }
    try {
        Get-MgSubscribedSku -All -ErrorAction Stop | Sort-Object SkuPartNumber | ForEach-Object {
            $total = [int]$_.PrepaidUnits.Enabled
            [pscustomobject]@{ SKU = $_.SkuPartNumber; Purchased = $total; Assigned = [int]$_.ConsumedUnits; Available = $total - [int]$_.ConsumedUnits; Status = $_.CapabilityStatus }
        } | Format-Table -AutoSize | Out-Host
    } catch { Write-Err "Unable to read subscriptions: $($_.Exception.Message)" }
}

Add-Tool -Id 'M365-14' -Category 'Microsoft 365' -Name 'Search Microsoft 365 groups' -Description 'Find groups whose name starts with your text' -Action {
    if (-not (Test-GraphConnected) -or -not (Import-GraphModule Microsoft.Graph.Groups)) { return }
    $q = "$(Read-Host '  Start of group name')".Trim()
    if (-not $q) { return }
    $e = ConvertTo-ODataValue $q
    try {
        $groups = @(Get-MgGroup -Filter "startswith(displayName,'$e')" -Property Id, DisplayName, Mail, MailEnabled, SecurityEnabled, GroupTypes -ConsistencyLevel eventual -CountVariable n -Top 100 -ErrorAction Stop)
        if (-not $groups.Count) { Write-Warn 'No matching groups.'; return }
        $groups | Select-Object DisplayName, Mail, MailEnabled, SecurityEnabled, @{ n = 'Type'; e = { if ($_.GroupTypes -contains 'Unified') { 'Microsoft 365' } elseif ($_.SecurityEnabled) { 'Security' } else { 'Distribution' } } } |
            Format-Table -AutoSize -Wrap | Out-Host
    } catch { Write-Err "Search failed: $($_.Exception.Message)" }
}

Add-Tool -Id 'M365-15' -Category 'Microsoft 365' -Name 'List Microsoft 365 groups' -Description 'Every group in the tenant with its type' -Action {
    if (-not (Test-GraphConnected) -or -not (Import-GraphModule Microsoft.Graph.Groups)) { return }
    try {
        $groups = @(Get-MgGroup -All -Property DisplayName, Mail, MailEnabled, SecurityEnabled, GroupTypes -ErrorAction Stop)
        Write-Check 'INFO' 'Groups' "$($groups.Count)"
        $groups | Sort-Object DisplayName | Select-Object DisplayName, Mail, @{ n = 'Type'; e = { if ($_.GroupTypes -contains 'Unified') { 'Microsoft 365' } elseif ($_.SecurityEnabled) { 'Security' } else { 'Distribution' } } } |
            Format-Table -AutoSize | Out-Host
    } catch { Write-Err $_.Exception.Message }
}
