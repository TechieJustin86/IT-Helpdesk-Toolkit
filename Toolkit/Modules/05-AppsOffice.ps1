# Modules\05-AppsOffice.ps1
# Category: Apps & Office
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'APP-01' -Category 'Apps & Office' -Name 'Installed software' -Description 'List all installed programs, export to CSV' -Action {
    $apps = @(Get-InstalledSoftware)
    Write-Info "$($apps.Count) applications installed."
    $apps | Format-Table -AutoSize | Out-Host
    if (Confirm-Action 'Export to CSV?') { $apps | Export-Results -Name 'software.csv' }
}

Add-Tool -Id 'APP-02' -Category 'Apps & Office' -Name 'Update all apps (winget)' -Description 'List and install app upgrades via winget' -Action {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Write-Err 'winget is not installed (App Installer from the Microsoft Store).'; return }
    winget upgrade --accept-source-agreements | Out-Host
    if (Confirm-Action 'Upgrade all listed apps? (accepts package license agreements)') {
        $null = Invoke-External 'winget' 'upgrade --all --silent --accept-source-agreements --accept-package-agreements'
    }
}

Add-Tool -Id 'APP-03' -Category 'Apps & Office' -Name 'Uninstall an application' -Description 'Search installed apps and run the uninstaller' -Action {
    $q = Read-Host '  Part of the application name'
    if (-not $q) { return }
    $pattern = "*$([WildcardPattern]::Escape($q))*"
    $app = Select-FromList @(Get-InstalledSoftware -Raw | Where-Object DisplayName -like $pattern) { "$($_.DisplayName) $($_.DisplayVersion)" } 'Application'
    if (-not $app) { return }
    $cmd = if ($app.QuietUninstallString) { $app.QuietUninstallString } else { $app.UninstallString }
    if ($app.PSChildName -match '^\{[0-9A-F-]+\}$' -and $cmd -match 'msiexec') { $cmd = "msiexec.exe /x $($app.PSChildName) /qb" }
    if (-not $cmd) { Write-Err 'No uninstall command registered for this app.'; return }
    Write-Info "Command: $cmd"
    if (Confirm-Action "Uninstall $($app.DisplayName)?") {
        $null = Invoke-External 'cmd.exe' "/c `"$cmd`""
        Write-Ok 'Uninstaller finished.'
    }
}

Add-Tool -Id 'APP-04' -Category 'Apps & Office' -Name 'Microsoft 365 / Office repair' -Description 'Show Office version/channel, quick/online repair, update' -Action {
    $cfg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if (-not $cfg) { Write-Warn 'Click-to-Run Office not found. Use Programs and Features to repair MSI Office.'; return }
    [pscustomobject]@{
        Products = $cfg.ProductReleaseIds
        Version  = $cfg.VersionToReport
        Platform = $cfg.Platform
        Culture  = $cfg.ClientCulture
        Channel  = $cfg.CDNBaseUrl
    } | Format-List | Out-Host
    $common = if ($env:CommonProgramW6432) { $env:CommonProgramW6432 } else { $env:CommonProgramFiles }
    $c2r    = Join-Path $common 'Microsoft Shared\ClickToRun\OfficeClickToRun.exe'
    $client = Join-Path $common 'Microsoft Shared\ClickToRun\OfficeC2RClient.exe'
    Write-Host '  [1] Quick repair (offline, fast)'
    Write-Host '  [2] Online repair (reinstalls Office)'
    Write-Host '  [3] Update Office now'
    $c = Read-Host '  Choice (blank to cancel)'
    switch ($c) {
        '1' { Start-Process $c2r -ArgumentList "scenario=Repair platform=$($cfg.Platform) culture=$($cfg.ClientCulture) RepairType=QuickRepair DisplayLevel=True" }
        '2' { Start-Process $c2r -ArgumentList "scenario=Repair platform=$($cfg.Platform) culture=$($cfg.ClientCulture) RepairType=FullRepair DisplayLevel=True" }
        '3' { Start-Process $client -ArgumentList '/update user' }
    }
}

Add-Tool -Id 'APP-05' -Category 'Apps & Office' -Name 'Clear Microsoft Teams cache' -Description 'Clears cache for new and classic Teams' -Action {
    $running = Get-Process -Name 'ms-teams', 'Teams' -ErrorAction SilentlyContinue
    if ($running) {
        if (-not (Confirm-Action 'Teams is running. Close it now?')) { return }
        $running | Stop-Process -Force
        Start-Sleep -Seconds 3
    }
    $freed = 0
    $newTeams = "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"
    if (Test-Path $newTeams) { $freed += Clear-FolderContents $newTeams; Write-Ok 'New Teams cache cleared.' }
    $classic = "$env:APPDATA\Microsoft\Teams"
    if (Test-Path $classic) {
        foreach ($sub in 'Cache', 'blob_storage', 'databases', 'GPUCache', 'IndexedDB', 'Local Storage', 'tmp', 'Code Cache', 'Service Worker') {
            $freed += Clear-FolderContents (Join-Path $classic $sub)
        }
        Write-Ok 'Classic Teams cache cleared.'
    }
    Write-Info ('Freed {0}. Start Teams again and sign in.' -f (Format-Bytes $freed))
}

Add-Tool -Id 'APP-06' -Category 'Apps & Office' -Name 'Clear browser caches' -Description 'Chrome, Edge and Firefox cache (keeps passwords/cookies)' -Action {
    $running = Get-Process -Name chrome, msedge, firefox -ErrorAction SilentlyContinue
    if ($running) {
        if (-not (Confirm-Action 'Browsers are open. Close them now?')) { return }
        $running | Stop-Process -Force
        Start-Sleep -Seconds 3
    }
    $total = 0
    foreach ($root in "$env:LOCALAPPDATA\Google\Chrome\User Data", "$env:LOCALAPPDATA\Microsoft\Edge\User Data") {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -Directory | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } | ForEach-Object {
            foreach ($sub in 'Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage') { $total += Clear-FolderContents (Join-Path $_.FullName $sub) }
        }
        Write-Ok "Cleared $root"
    }
    Get-ChildItem "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $total += Clear-FolderContents (Join-Path $_.FullName 'cache2')
        Write-Ok "Cleared Firefox profile $($_.Name)"
    }
    Write-Ok ('Total freed: {0}' -f (Format-Bytes $total))
}

Add-Tool -Id 'APP-07' -Category 'Apps & Office' -Name 'Reset Microsoft Store cache' -Description 'Run wsreset to fix Store download issues' -Action {
    Start-Process wsreset.exe
    Write-Ok 'wsreset started - the Store will open when finished.'
}

Add-Tool -Id 'APP-08' -Category 'Apps & Office' -Name 'Outlook troubleshooting' -Description 'Safe mode, reset nav pane, mail profiles, OST/PST sizes' -Action {
    Write-Section 'Outlook data files'
    $dirs = "$env:LOCALAPPDATA\Microsoft\Outlook", "$env:USERPROFILE\Documents\Outlook Files"
    Get-ChildItem $dirs -Include *.ost, *.pst -Recurse -ErrorAction SilentlyContinue |
        Select-Object Name, @{n = 'Size'; e = { Format-Bytes $_.Length } }, LastWriteTime, DirectoryName | Format-Table -AutoSize | Out-Host
    Write-Host '  [1] Start Outlook in safe mode'
    Write-Host '  [2] Start Outlook and reset navigation pane'
    Write-Host '  [3] Open Mail profiles (control panel)'
    $c = Read-Host '  Choice (blank to cancel)'
    switch ($c) {
        '1' { Start-Process outlook.exe -ArgumentList '/safe' }
        '2' { Start-Process outlook.exe -ArgumentList '/resetnavpane' }
        '3' { Start-Process control.exe -ArgumentList 'mlcfg32.cpl' }
    }
}

Add-Tool -Id 'APP-09' -Category 'Apps & Office' -Name 'Reset OneDrive' -Description 'Reset the OneDrive client to fix sync problems' -Action {
    $exe = "$env:LOCALAPPDATA\Microsoft\OneDrive\onedrive.exe", "$env:ProgramFiles\Microsoft OneDrive\onedrive.exe", "${env:ProgramFiles(x86)}\Microsoft OneDrive\onedrive.exe" |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $exe) { Write-Err 'OneDrive not found.'; return }
    if (-not (Confirm-Action 'Reset OneDrive? It resyncs all files (nothing is deleted).')) { return }
    Start-Process $exe -ArgumentList '/reset'
    Start-Sleep -Seconds 15
    if (-not (Get-Process OneDrive -ErrorAction SilentlyContinue)) { Start-Process $exe }
    Write-Ok 'OneDrive reset and restarted.'
}

Add-Tool -Id 'APP-10' -Category 'Apps & Office' -Name 'Credential Manager cleanup' -Description 'List saved credentials, remove stale Office/Teams ones' -Action {
    $targets = @(cmdkey /list | Select-String -Pattern '^\s*Target:\s*(.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() })
    if (-not $targets.Count) { Write-Info 'No saved credentials.'; return }
    $targets | ForEach-Object { Write-Host "    $_" }
    Write-Host ''
    Write-Host '  [1] Remove Office / Teams / OneDrive credentials (fixes repeated sign-in prompts)'
    Write-Host '  [2] Remove one credential'
    $c = Read-Host '  Choice (blank to cancel)'
    $remove = @()
    if ($c -eq '1') { $remove = @($targets | Where-Object { $_ -match 'MicrosoftOffice|msteams|OneDrive Cached|Microsoft_OC' }) }
    elseif ($c -eq '2') { $t = Select-FromList $targets { $_ } 'Credential'; if ($t) { $remove = @($t) } }
    if (-not $remove.Count) { return }
    $remove | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    if (Confirm-Action "Remove $($remove.Count) credential(s)?") {
        foreach ($t in $remove) { cmdkey "/delete:$t" | Out-Null }
        Write-Ok 'Removed. Restart Office apps and sign in again.'
    }
}

Add-Tool -Id 'APP-11' -Category 'Apps & Office' -Name 'Install common apps (winget)' -Description 'Browsers, 7-Zip, PDF reader, VLC, Zoom, runtimes, or search winget' -Action {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Write-Err 'winget is not installed (App Installer from the Microsoft Store).'; return }
    $apps = @(
        @{ Name = 'Google Chrome';                    Id = 'Google.Chrome' },
        @{ Name = 'Mozilla Firefox';                  Id = 'Mozilla.Firefox' },
        @{ Name = 'Adobe Acrobat Reader';             Id = 'Adobe.Acrobat.Reader.64-bit' },
        @{ Name = '7-Zip';                            Id = '7zip.7zip' },
        @{ Name = 'VLC media player';                 Id = 'VideoLAN.VLC' },
        @{ Name = 'Notepad++';                        Id = 'Notepad++.Notepad++' },
        @{ Name = 'Zoom Workplace';                   Id = 'Zoom.Zoom' },
        @{ Name = 'Microsoft Teams';                  Id = 'Microsoft.Teams' },
        @{ Name = 'Microsoft PowerToys';              Id = 'Microsoft.PowerToys' },
        @{ Name = '.NET Desktop Runtime 8';           Id = 'Microsoft.DotNet.DesktopRuntime.8' },
        @{ Name = 'Visual C++ Redistributable x64';   Id = 'Microsoft.VCRedist.2015+.x64' },
        @{ Name = 'Search winget for another app...'; Id = '' }
    )
    $a = Select-FromList $apps { if ($_.Id) { '{0,-34} {1}' -f $_.Name, $_.Id } else { $_.Name } } 'App to install'
    if (-not $a) { return }
    $id = $a.Id
    if (-not $id) {
        $q = Read-Host '  Search for'
        if (-not $q) { return }
        winget search $q --accept-source-agreements | Out-Host
        $id = Read-Host '  Package Id to install (from the Id column)'
        if (-not $id) { return }
    }
    if (Confirm-Action "Install $id? (accepts the package license agreement)") {
        $code = Invoke-External 'winget' "install --id $id -e --silent --accept-source-agreements --accept-package-agreements"
        if ($code -eq 0) { Write-Ok "$id installed." } else { Write-Warn "winget finished with exit code $code." }
    }
}

Add-Tool -Id 'APP-12' -Category 'Apps & Office' -Name 'Re-register built-in apps' -Description 'Fix broken Start menu, Settings, Calculator, Photos (current user)' -Action {
    if (-not (Confirm-Action 'Re-register all built-in and Store apps for the current user? Takes a few minutes; open apps may close.')) { return }
    if ($PSVersionTable.PSEdition -eq 'Core') { Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue }
    $pkgs = @(Get-AppxPackage | Where-Object { $_.InstallLocation -and (Test-Path (Join-Path $_.InstallLocation 'AppxManifest.xml')) })
    Write-Info "Re-registering $($pkgs.Count) apps..."
    $ok = 0; $fail = 0
    foreach ($p in $pkgs) {
        try { Add-AppxPackage -DisableDevelopmentMode -Register (Join-Path $p.InstallLocation 'AppxManifest.xml') -ErrorAction Stop; $ok++ }
        catch { $fail++ }
    }
    Write-Ok "Re-registered $ok app(s)."
    if ($fail) { Write-Info "$fail app(s) were skipped (usually because they are in use - this is normal)." }
    Write-Info 'Sign out and back in if the Start menu still misbehaves.'
}

Add-Tool -Id 'APP-13' -Category 'Apps & Office' -Name 'Recently installed / removed apps' -Description 'Software changes in the last 30 days' -Action {
    $cutoff = (Get-Date).AddDays(-30)
    Write-Section 'Installed in the last 30 days'
    $recent = @(Get-InstalledSoftware -Raw | ForEach-Object {
        $dt = $null
        try { $dt = [datetime]::ParseExact("$($_.InstallDate)", 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture) } catch { }
        if ($dt -and $dt -ge $cutoff) {
            [pscustomobject]@{ Installed = $dt.ToString('yyyy-MM-dd'); Name = $_.DisplayName; Version = $_.DisplayVersion; Publisher = $_.Publisher }
        }
    } | Sort-Object Installed -Descending)
    if ($recent.Count) { $recent | Format-Table -AutoSize | Out-Host } else { Write-Info 'None found (not every installer records a date).' }
    Write-Section 'Removed in the last 30 days (Windows Installer)'
    $removed = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'MsiInstaller'; Id = 1034; StartTime = $cutoff } -ErrorAction SilentlyContinue)
    if ($removed.Count) {
        $removed | Select-Object @{ n = 'Removed'; e = { $_.TimeCreated } }, @{ n = 'Product'; e = { "$($_.Properties[0].Value)" } } | Format-Table -AutoSize | Out-Host
    } else { Write-Info 'None recorded.' }
}
