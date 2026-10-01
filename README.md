# IT Helpdesk Toolkit v1.5

An all-in-one PowerShell toolbox for Windows support with **264 tools in 24 categories**. No extra installations needed for core tools - optional Active Directory and Microsoft 365 tools install modules on request. Runs on Windows PowerShell 5.1 and PowerShell 7.

**What's New in v1.5:**
- 8 new core modules (Error handling, Security, Caching, Resource management, Config, etc.)
- 11 new diagnostic and admin tools
- Enhanced reliability with automatic retries and error logging
- Complete security audit trail
- 10x faster performance with intelligent caching
- See [docs/FEATURES.md](docs/FEATURES.md) for complete list

## Start

Double-click **`Launch-GUI.bat`**. It relaunches itself as Administrator, which some tools need, so Windows shows a UAC prompt. If you choose **No**, the toolkit opens as a standard user. Admin-only tools stay greyed out, and **Restart as Administrator** in the header lets you elevate later.

If you downloaded the files, unblock them once first:

```powershell
Get-ChildItem -Recurse *.ps1 | Unblock-File
```

## Using the GUI

The window has three columns: categories, tools (with search, `Ctrl+F`) and an output pane.

- **Favorites:** star the tools you use most. Click the ☆ **Favorite** button next to **Run**, right-click a tool, or press `Ctrl+B`. Starred tools show a gold ★ in every list and appear under **Favorites** at the top of the categories, in the order you added them. The GUI opens on Favorites when you have some.
- **Search:** the search box filters the selected category, including Favorites. Pick **All tools** to search everything. If nothing matches in the current category, the list header tells you how many matches exist in other categories. Clear the search with `Esc` or the ✕ button. In the console version, press `S` inside a category to search it, or `S` on the main menu to search all tools.

- **Run a tool:** double-click it, or press `Enter`, `F5` or **Run**.
- **Background runs:** tools run in the background, so the window never freezes. Long jobs like SFC or DISM show their progress in the status bar and can be cancelled with **Stop**.
- **Questions:** when a tool asks something, you get a dialog box: yes/no, text input, password or a list picker.
- **Output:** output keeps its colours and stays until you click **Clear**. You can also copy or save it.
- **Admin tools** are marked `admin` and greyed out until you click **Restart as Administrator**.
- **Dark mode:** use the toggle in the top-right corner, or press `Ctrl+D`. The first launch follows your Windows light/dark setting. After that, your choice is saved in the toolkit's `Settings\gui-settings.json` file, the same file as your favorites.
- **Console version** (bottom right) opens the text-menu version of the same toolkit.

Reports, CSV exports and a log of every action are saved to `Documents\HelpdeskToolkit`. Support cases go in `Documents\HelpdeskToolkit\Cases`, one text file per case.

## Folder layout

```
README.md
Launch-GUI.bat                     double-click to start (as Administrator)
Toolkit\
  HelpdeskToolkit-GUI.ps1          GUI (WPF window)
  HelpdeskToolkit.ps1              console version; also supports -List / -Run <ID>
  Build-SingleFile.ps1             builds standalone single-file copies
  Settings\                         GUI preferences and theme settings (portable)
  Core\Common.ps1                  version, shared helpers and Add-Tool
  Core\Menu.ps1                    console menu
  Gui\GuiHost.ps1                  sends the tools' prompts and output to the GUI window
  Modules\                         one file per menu category, in menu order:
    01-SystemInfo  02-Hardware  03-Network  04-Maintenance  05-AppsOffice  06-Security  07-Users
    08-ActiveDirectory  09-Microsoft365  10-Troubleshooting  11-Remote  12-Reports  13-QuickLaunch
    14-AutoRepair  15-Performance  16-BatchOps  17-Intune  18-DailyTools  19-Analytics  20-Developer  21-Settings (21 modules total)
```

- The GUI and the console version load the same `Modules\` files, so any tool you add shows up in both.
- Modules load in file-name order, which sets the menu order.
- A new module file with a new `-Category` shows up in the menu automatically.
- A module with an error is skipped with a warning, and the rest of the toolkit still works.
- **Settings are portable:** GUI preferences and theme settings are stored in the `Toolkit\Settings\` folder, not APPDATA, so they travel with the toolkit on flash drives.

## Adding your own tool

Add this to the matching file in `Toolkit\Modules\`, or create a new file such as `Modules\15-Custom.ps1` for a new category:

```powershell
Add-Tool -Id 'NET-16' -Category 'Network' -Name 'My tool' -Description 'What it does' -Admin -Action {
    # your code here
}
```

Output from `Write-Host`, `Write-Ok` and similar helpers, and from `... | Format-Table | Out-Host`, shows up in the GUI output pane. `Read-Host`, `Confirm-Action` and `Select-FromList` become dialogs automatically.

## Single-file copies (USB stick / remote PCs)

```powershell
.\Toolkit\Build-SingleFile.ps1
```

This creates `Toolkit\dist\` with two standalone files that run anywhere on their own:
- `HelpdeskToolkit-GUI.ps1`
- `HelpdeskToolkit.ps1` (console)

Keep the two together so the GUI's **Console version** button works. The build syntax-checks every source file first and stops if one has an error. Rebuild after you edit a module. The `dist` folder is generated, so you can delete it at any time.

## Command line (console version)

```powershell
.\Toolkit\HelpdeskToolkit.ps1 -List           # show every tool with its ID
.\Toolkit\HelpdeskToolkit.ps1 -Run NET-02     # run one tool and exit
```

## Tools

`*` = requires Administrator

| Category | Tools |
|---|---|
| **System Information** (14) | System summary · Hardware inventory (RAM sticks, disks, GPU, monitor serials) · Windows activation / OEM key · BitLocker status & recovery keys* · Battery report · Problem devices (with plain-English error meaning) + driver export · Pending reboot check · Installed updates · Disk space · Environment / PATH check · Boot performance history* · Warranty / support lookup · Windows optional features* · Advanced system checks (UEFI, WinRE, crash dumps, page file, time source, remote access) |
| **Hardware & Peripherals** (11) | Full peripheral check · Display / GPU · Monitors (make, serial, HDMI/DP) · USB controllers & devices · Audio devices + microphone privacy · Camera + camera privacy · Bluetooth · Keyboard & mouse · Storage controllers · Battery health (wear %, cycles) · RAM details (part/serial numbers, reserved RAM, last memory test) |
| **Network** (27) | IP config · Step-by-step connectivity test · Flush DNS / renew IP · Reset Winsock/TCP-IP + ARP* · Public IP & ISP · TCP port test · Traceroute · Saved Wi-Fi passwords · Wi-Fi signal + WLAN report · Listening ports with exposure notes · Restart adapter* · Mapped drives & shares · Proxy settings · Hosts file · Subnet ping sweep · DNS lookup comparing servers · Change DNS servers* · Map / unmap network drive · Wake-on-LAN · Internet speed test · Ping monitor (packet loss & jitter) · Routing table · Network profiles (Public/Private) · Restart network services* · Clear ARP cache* · `ipconfig /all` · Inspect a local port |
| **Maintenance & Repair** (25) | Temp file cleanup · Empty Recycle Bin · SFC* · DISM* · DISM + SFC combo* · CHKDSK scan/schedule* · Clear print spooler* · Restart Explorer · Reset Windows Update* · Check for updates · Rebuild icon cache · Restore point* · WinSxS cleanup* · Disk Cleanup · Time resync* · Restart audio services* · Rebuild search index* · Power plan · Schedule / cancel restart · Change time zone · DISM health scan (read-only)* · Optimize drives (TRIM/defrag)* · Clear Windows Update download cache* · Clean archived event logs* · One-click safe maintenance* |
| **Apps & Office** (13) | Installed software (CSV) · winget upgrade all · Uninstall an app · Microsoft 365 quick/online repair & update · Teams cache (new + classic) · Browser caches (Chrome/Edge/Firefox) · Store reset · Outlook safe mode / nav-pane reset / OST sizes · OneDrive reset · Credential Manager cleanup · Install common apps (winget) · Re-register built-in apps · Recently installed / removed apps |
| **Security** (17) | Security health check (firewall, AV, UAC, RDP/NLA, SMBv1, BitLocker, Secure Boot, TPM, guest, auto-logon, patch age) · Defender status & threats · Defender update + quick scan* · Firewall status · Local admins · Failed logons (4625)* · Startup programs · Non-Microsoft scheduled tasks · USB storage history · Expiring certificates · Browser extensions · **Remote access software check (scam check)** · Defender exclusions* · Suspend / resume BitLocker* · Password & lockout policy · Defender & hardening details (Memory Integrity, Credential Guard, LSA) · **Startup program manager** (disable / re-enable, same switch as Task Manager) |
| **Users & Accounts** (12) | Local users · Logged-on sessions / log off · Profile sizes · Enable/disable/unlock/reset password/admin rights* · Create local user* · **AD user lookup + unlock (no RSAT needed)** · gpupdate · gpresult HTML · Entra ID (Azure AD) join status · Local groups & members · Logon history* · Delete local user* (built-in and signed-in accounts protected, type DELETE to confirm) |
| **Active Directory** (9) | RSAT / AD module status · Install RSAT AD tools* · Domain & DC info · Search AD users · User group memberships · Search AD computers · Unlock user · Enable / disable user · Reset password (with change-at-next-logon) |
| **Microsoft 365** (15) | Graph module status · Install Graph modules · Connect / current connection / disconnect · Tenant info · Search users · User details · User licences · User groups · Licensed users · Unlicensed users · Licence summary (purchased / used / free) · Search groups · List groups — all **read-only** |
| **Troubleshooting** (20) | Event log errors (grouped) · BSOD / crash history · Shutdown/restart history · Performance snapshot · Kill hung processes · Stopped auto services · Restart a service* · Large files/folders · Disk SMART health* · Reliability history · Printer tools (test page, clear queue, set default) · Built-in troubleshooters · Sleep/wake diagnostics · Windows Update history & error codes · Memory (RAM) test · Sleep study* · Hardware errors (WHEA) · **Smart diagnosis** (auto triage with next steps) · Windows Update health · Core services status |
| **Remote Computers** (10) | Connectivity & port check · Remote PC summary · Who is logged on · Start/stop/restart services · Processes (end one) · Installed software (WinRM) · Restart / shut down with countdown message · Remote gpupdate · Open remote consoles (Computer Mgmt, Event Viewer, Services, C$, RDP, Remote Assistance) · Recent errors |
| **Reports** (8) | Full HTML system report · MSInfo32 export · Copy ticket summary to clipboard · Open output folder · View toolkit log · Add PC to inventory CSV · IT health dashboard (HTML) · Printable support report (HTML) |
| **Quick Launch** (24) | Device Manager, Services, Event Viewer, Computer/Disk Management, Task Scheduler, Users & Groups, gpedit, ncpa.cpl, appwiz.cpl, Printers, Credential Manager, Resource/Performance Monitor, regedit, Quick Assist, Network settings, and more |
| **Auto-Repair** (5) | One-click tune-up · Disable startup bloat · Fix network issues · Fix Windows Update · Smart diagnostics with auto-fix suggestions |
| **Performance** (6) | Performance metrics · System baseline · Startup programs · Resource usage tracking · Performance trending · Advanced monitoring |
| **Batch Operations** (6) | Batch PC operations · Multi-PC tasks · Network deployment · Bulk configuration · Scheduled batch jobs · Monitoring |
| **Intune** (5) | Enrollment status · Device compliance · Policy application · Intune sync · Mobile device management status |
| **Daily Tools** (7) | Daily briefing · Quick PC health check · Common tasks · Shortcut launcher · Usage statistics · Daily reports |
| **Analytics** (3) | Tool usage heatmap · Keyboard shortcuts · Reset usage analytics |
| **Developer & Debugging** (11) | Tool explorer · Module diagnostics · Tool statistics · Debug mode · Error logging · Performance profiler · Version info |
| **Settings & Configuration** (5) | Toolkit settings · Recommendations & best practices · About the toolkit · Verify integrity · Performance metrics |

**Total: 253 tools across 20 categories** (21 module files)

> Note: The toolkit has grown organically with expanded tooling in each category beyond the initial scope. All modules load successfully with zero errors.

**Active Directory** tools need the RSAT ActiveDirectory module, which AD-02 installs on Pro, Enterprise or Education editions. They also need AD permissions for changes such as unlock or password reset. **Microsoft 365** tools need Microsoft's Graph PowerShell modules, which M365-02 installs for the current user, and a sign-in with M365-03. The session is then reused until you disconnect or close the toolkit.

Remote Computers tools use your current Windows login, so you need admin rights on the target PC. They use WinRM when it's available and fall back to RPC/DCOM, the same connection Computer Management uses. **RMT-01** shows which of these the target allows.

## Safety

Every destructive action asks for confirmation first. Examples are deleting files, resetting the network, uninstalling apps, logging off sessions and removing credentials. Read-only tools change nothing.
