# IT Helpdesk Toolkit v1.5

An all-in-one PowerShell toolbox for Windows support with **290 tools in 23 categories**. Core tools need nothing installed; the optional Active Directory and Microsoft 365 tools install their modules on request. Runs on Windows PowerShell 5.1 and PowerShell 7.

See [docs/GUIDE.md](docs/GUIDE.md) for everyday tasks, logs and troubleshooting, [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it's built, and [docs/CHANGELOG.md](docs/CHANGELOG.md) for what's changed.

## Start

Double-click **`Toolkit\Launch-GUI.bat`**. It relaunches itself as Administrator, which some tools need, so Windows shows a UAC prompt. If you choose **No**, the toolkit opens as a standard user: admin-only tools stay greyed out, and **Restart as Administrator** in the header lets you elevate later.

**The `Toolkit` folder is all you need.** Copy it to a flash drive and double-click `Launch-GUI.bat` inside it on any Windows 10 or 11 PC; nothing needs installing. See [Running from a flash drive](#running-from-a-flash-drive) for what is saved where.

If you downloaded the files, unblock them once first, from inside the `Toolkit` folder. This also stops Windows SmartScreen from questioning `Launch-GUI.bat`:

```powershell
Get-ChildItem -Recurse | Unblock-File
```

## Using the GUI

The window has three columns: categories, tools (with a search box) and the selected tool with its output.

- **Favorites:** star the tools you use most. Click the ☆ **Favorite** button next to **Run**, right-click a tool, or press `Ctrl+B`. Starred tools show a gold ★ in every list and appear under **Favorites** at the top of the categories, in the order you added them. The GUI opens on Favorites when you have some, and on All tools otherwise.
- **Search:** the search box filters the selected category, including Favorites. Pick **All tools** to search everything. If nothing matches in the current category, the list header says how many matches exist elsewhere. Searching by a tool's former ID finds the tool that replaced it.
- **Run a tool:** double-click it, or press `Enter`, `F5` or **Run**.
- **Background runs:** tools run in the background, so the window never freezes. Long jobs like SFC or DISM show their progress in the status bar and can be cancelled with **Stop**.
- **Questions:** when a tool asks something, you get a dialog box: yes/no, text input, password (masked) or a list picker.
- **Output:** output keeps its colours and stays until you click **Clear**. You can also copy or save it.
- **Admin tools** are marked `admin` and greyed out until you click **Restart as Administrator**.
- **Dark mode:** use the toggle in the top-right corner, or press `Ctrl+D`. The first launch follows your Windows light/dark setting; after that your choice is saved with your favorites.
- **Console version** (bottom right) opens the text-menu version of the same toolkit.

| Key | Does |
|---|---|
| `Ctrl+F` | Search |
| `Ctrl+B` | Add or remove the selected tool from Favorites |
| `Ctrl+D` | Switch light / dark mode |
| `Ctrl+E` | Open the output folder |
| `Ctrl+L` | Clear the output pane |
| `Enter` / `F5` | Run the selected tool |
| `Esc` | Clear the search |
| `F1` | Show the keyboard shortcuts |

Your settings and the toolkit's logs are saved inside the `Toolkit` folder (`Settings\` and `Logs\`). Reports, CSV exports and usage statistics are saved to `Documents\HelpdeskToolkit` on the PC the toolkit is running on.

## Running from a flash drive

Copy the `Toolkit` folder to the drive. On the PC, double-click `Launch-GUI.bat` inside it. Nothing is installed.

- **Travels with the drive:** `Settings\` (favourites, theme, recent tools) and `Logs\` (action log, error log and audit trail).
- **Stays on each PC:** reports, CSV exports and usage statistics, in `Documents\HelpdeskToolkit` of the account the toolkit runs as. If you elevate with a separate admin account, that is the admin's Documents folder, not the user's.
- **The audit trail records the user and computer name for every tool run**, so the drive builds up a list of every PC it has been used on. Bear that in mind if the drive is lost or lent out.
- **Updating the drive:** copy the `Toolkit` folder from an up-to-date copy over the one on the drive. Your settings and logs on the drive are kept, because a fresh copy has none to overwrite them with.
- **Where it will not run:** PCs where Group Policy enforces a PowerShell execution policy (the launcher's `-ExecutionPolicy Bypass` cannot override one set by policy), where policy blocks running programs from removable drives, or where AppLocker or WDAC restricts scripts. Windows Server Core has no WPF, so only the console version (`HelpdeskToolkit.ps1`) works there.

### Standard user vs. Administrator

When a standard user elevates the toolkit with a separate admin account, it runs **as that admin account**. Tools that work on per-user things - temp files, browser and Teams caches, saved credentials, the Recycle Bin, per-user registry settings - then act on the admin's profile, not the signed-in user's. Run those without elevating when you want them to affect the person at the PC.

Some read-only tools see less without Administrator rights, such as BitLocker status, TPM details and some event logs, so run elevated when a result looks incomplete.

## Folder layout

```
README.md, SECURITY.md, CONTRIBUTING.md, LICENSE
Toolkit\                           everything needed to run it - copy this folder to a flash drive
  Launch-GUI.bat                   double-click to start (as Administrator)
  HelpdeskToolkit-GUI.ps1          GUI (WPF window)
  HelpdeskToolkit.ps1              console version; also supports -List / -Run <ID>
  Build-SingleFile.ps1             builds standalone single-file copies into dist\
  Core\                            shared helpers, config, dependency checks, audit log, console menu
  Gui\GuiHost.ps1                  sends the tools' prompts and output to the GUI window
  Modules\                         one file per menu category (01-SystemInfo ... 24-Toolkit-Admin)
  Settings\                        GUI preferences (created on first run; travels with the folder)
  Logs\                            action log, error log and audit trail (travels with the folder)
  Stand alone scripts\             independent tools that don't use the toolkit framework
Tests\Test-ToolRegistration.ps1    checks every module loads and every tool ID is valid and unique
docs\                              GUIDE, ARCHITECTURE, CHANGELOG
.github\                           CI checks and code owners
```

- The GUI and the console version load the same `Modules\` files, so any tool you add shows up in both.
- Modules load in file-name order, which sets the menu order. A new module file with a new `-Category` shows up in the menu automatically.
- A module with an error is skipped with a warning, and the rest of the toolkit still works.

## Adding your own tool

Add this to the matching file in `Toolkit\Modules\`, or create a new file such as `Modules\25-Custom.ps1` for a new category:

```powershell
Add-Tool -Id 'CUS-01' -Category 'Custom' -Name 'My tool' -Description 'What it does' -Action {
    Write-Info 'Doing the thing...'
    if (-not (Confirm-Action 'Go ahead?')) { return }
    # your code here
    Write-Ok 'Done.'
}
```

- **IDs must be unique** and look like `PREFIX-NN`. `Tests\Test-ToolRegistration.ps1` checks this; run it after adding a tool.
- Add `-Admin` if the tool needs Administrator rights; the toolkit then refuses to run it until elevated.
- Output from `Write-Host`, `Write-Ok` and the other helpers, and from `... | Format-Table | Out-Host`, shows up in the GUI output pane. `Read-Host`, `Confirm-Action` and `Select-FromList` become dialogs automatically.
- For anything that cannot be undone, ask with `Confirm-DestructiveAction`, which makes the user type `yes`.

[CONTRIBUTING.md](CONTRIBUTING.md) has the full checklist.

## Single-file copies (remote PCs)

For a flash drive, use the whole `Toolkit` folder (see above): it has a double-click launcher. Single files suit the cases where you can only copy one or two files, such as dropping the toolkit onto a remote PC.

```powershell
.\Toolkit\Build-SingleFile.ps1
```

This creates `Toolkit\dist\` with two standalone files that run anywhere on their own:
- `HelpdeskToolkit-GUI.ps1`
- `HelpdeskToolkit.ps1` (console)

There is no launcher, and double-clicking a `.ps1` in Explorer opens it in Notepad, so start them from PowerShell: `powershell -ExecutionPolicy Bypass -File .\HelpdeskToolkit-GUI.ps1`. The GUI offers to restart itself as Administrator. Keep the two together so the GUI's **Console version** button works. The build syntax-checks every source file first and stops if one has an error. Rebuild after you edit a module. The `dist` folder is generated, so you can delete it at any time.

## Command line (console version)

```powershell
.\Toolkit\HelpdeskToolkit.ps1 -List           # every tool with its ID, category and admin flag
.\Toolkit\HelpdeskToolkit.ps1 -Run NET-02     # run one tool by ID or exact name, then exit
.\Toolkit\HelpdeskToolkit.ps1 -NoElevate      # open the menu without offering to elevate
```

`-Run` also accepts the former ID of a tool that was merged into another, so scripts written against an old ID keep working. [docs/CHANGELOG.md](docs/CHANGELOG.md) lists which IDs moved where.

## Tools

`*` = requires Administrator

| Category | Tools |
|---|---|
| **System Information** (13) | System summary · Hardware inventory · Windows activation status · Battery health report · Drivers and problem devices · Pending reboot check · Installed updates (hotfixes) · Disk space · Environment and PowerShell info · Boot performance history* · Warranty / support lookup · Windows optional features* · Advanced system checks |
| **Hardware & Peripherals** (13) | Full peripheral check · Display / GPU check · Monitor detection · USB controllers and devices · Audio devices and microphone · Camera check · Bluetooth check · Keyboard and mouse check · Storage controllers · Battery health · Memory (RAM) details · Battery reports · RAM slot utilization |
| **Network** (31) | IP configuration · Connectivity test · Flush DNS / renew IP · Reset network stack* · Public IP and ISP · Test TCP port · Traceroute · Saved Wi-Fi networks and keys · Wi-Fi status and report · Listening ports · Restart network adapter* · Mapped drives and shares · Proxy settings · View hosts file · Network scan (ping sweep) · DNS lookup (compare servers) · Change DNS servers* · Map / unmap network drive · Wake-on-LAN · Internet speed test · Ping monitor (packet loss) · Routing table · Network profiles · Restart network services* · Clear ARP cache* · Full IP configuration · Inspect a local port · Advanced ping test · Traceroute analysis · DNS lookup tools · WiFi diagnostics |
| **Maintenance & Repair** (33) | Clean temporary files · Empty Recycle Bin · System File Checker (SFC)* · DISM image repair* · Full repair (DISM + SFC)* · Check disk (CHKDSK)* · Clear print spooler* · Restart Explorer · Reset Windows Update* · Check for Windows updates · Rebuild icon & thumbnail cache · Create restore point* · Component store cleanup* · Disk Cleanup (cleanmgr) · Sync system time* · Restart audio services* · Rebuild Windows Search index* · Power plan · Schedule or cancel restart · Change time zone · DISM health scan (read-only)* · Optimize drives* · Clear Windows Update download cache* · Clean archived event logs* · One-click safe maintenance* · Disk usage analyzer · System restore point* · Disable Windows Update server* · Enable Windows Update server* · Unblock Windows Store* · Fix Outlook password prompt* · Remove bloatware and Store apps* · Rename PC* |
| **Apps & Office** (13) | Installed software · Update all apps (winget) · Uninstall an application · Microsoft 365 / Office repair · Clear Microsoft Teams cache · Clear browser caches · Reset Microsoft Store cache · Outlook troubleshooting · Reset OneDrive · Credential Manager cleanup · Install common apps (winget) · Re-register built-in apps · Recently installed / removed apps |
| **Security** (20) | Security health check · Defender status and threats · Defender update + quick scan* · Firewall status · Local administrators · Failed logon attempts* · Startup programs · Non-Microsoft scheduled tasks · USB storage history · Installed certificates expiring · Browser extensions · Remote access software check · Defender exclusions* · Suspend / resume BitLocker* · Password and lockout policy · Defender and hardening details · Startup program manager · BitLocker status* · TPM status · Product key retrieval |
| **Users & Accounts** (12) | Local user accounts · Logged-on sessions · User profile sizes · Manage a local user* · Create local user* · Active Directory user lookup · Group Policy update · Group Policy results report · Azure AD / Entra join status · Local groups and members · Logon history* · Delete local user* |
| **Active Directory** (22) | RSAT / AD module status · Install RSAT AD tools* · Domain and DC info · Search AD users · AD user group memberships · Search AD computers · Unlock AD user · Enable / disable AD user · Reset AD user password · Find unlinked GPOs · Find disabled GPOs · Search GPOs for text · Find empty groups · Get detailed user info · Check user last logon · User password age report · Export user details and groups · Security groups members report · User security group report · All staff member details · Staff member details (single) · User profile management |
| **Microsoft 365** (15) | Graph module status · Install Graph modules · Connect to Microsoft 365 · Current Graph connection · Disconnect Microsoft 365 · Tenant information · Search Microsoft 365 users · Microsoft 365 user details · Microsoft 365 user licences · Microsoft 365 user groups · Licensed users · Unlicensed users · Licence summary · Search Microsoft 365 groups · List Microsoft 365 groups |
| **Troubleshooting** (22) | Recent errors (event log) · Crash / BSOD history · Shutdown / restart history · Performance snapshot · Kill a process · Stopped automatic services · Restart a service* · Find large files / folders · Disk health (SMART) · Reliability history · Printer tools · Windows troubleshooters · Energy / sleep diagnostics · Windows Update history · Memory (RAM) test · Sleep study (battery drain)* · Hardware errors (WHEA) · Smart diagnosis · Windows Update health · Core services status · BSOD analysis (detailed) · Event log analysis |
| **Remote Computers** (12) | Remote connectivity check · Remote PC summary · Who is logged on (remote) · Remote services · Remote processes · Remote installed software · Restart / shut down remote PC · Remote gpupdate · Open remote consoles · Remote recent errors · Copy files to remote computer · Check registry value on remote computer |
| **Reports** (10) | Full HTML system report · MSInfo32 full export · Copy system summary to clipboard · Open output folder · View toolkit log · Add PC to inventory CSV · IT health dashboard (HTML) · Printable support report (HTML) · Event log health report · Storage and disk report |
| **Quick Launch** (24) | Device Manager · Services · Event Viewer · Computer Management · Disk Management · Task Scheduler · Local Users and Groups · Group Policy Editor · Network Connections · Programs and Features · Printers · System Properties · Credential Manager · Resource Monitor · Performance Monitor · System Information · Registry Editor · Windows Update · Power Options · Sound · Remote Desktop client · Certificates (user) · Quick Assist · Network settings |
| **Auto-Repair** (5) | One-click PC tune-up* · Disable startup bloat* · Fix network issues* · Fix Windows Update* · Diagnose & fix common issues |
| **Performance & Optimization** (5) | Performance snapshot · Optimize power plan* · Find memory leaks · Boot time analyzer* · Network speed test |
| **Batch Operations** (6) | Bulk restart PCs* · Network inventory scan · Get software inventory (multi-PC) · Remote system info · Apply Windows updates (multi-PC)* · Run script on multiple PCs* |
| **Intune Management** (5) | Check Intune enrollment status · Force Intune device sync · Check Intune policies* · Troubleshoot Intune issues* · Export device compliance info |
| **Daily Utilities** (6) | Quick PC health check · Copy system info to clipboard · Open shared drives/resources · Generate device documentation · Remote desktop launcher · Send test email |
| **Analytics** (3) | Tool usage analytics · Keyboard shortcuts · Reset usage analytics |
| **Developer & Debugging** (7) | Tool explorer · Tool statistics · Run tool by ID · Search tools by name · Error log viewer · Error statistics · View tool source (manual) |
| **Settings & Configuration** (3) | Recommendations & best practices · About the toolkit · Performance metrics |
| **Recommendations** (4) | Runtime diagnostics · Recommendations for this PC · Performance baseline · Health check summary |
| **Toolkit Administration** (6) | Toolkit configuration · Toolkit integrity check · Toolkit diagnostics · Clear error log · Security audit report · About this toolkit |

**Total: 290 tools across 23 categories** (run `HelpdeskToolkit.ps1 -List` for the live list)

**Active Directory** tools need the RSAT ActiveDirectory module, which AD-02 installs on Pro, Enterprise or Education editions, plus AD permissions for changes such as unlock or password reset. **Microsoft 365** tools need Microsoft's Graph PowerShell modules, which M365-02 installs for the current user, and a sign-in with M365-03; the session is reused until you disconnect or close the toolkit. Until a module is installed, the tools that need it stop with a note saying which tool installs it.

**Remote Computers** tools use your current Windows login, so you need admin rights on the target PC. They use WinRM when it's available and fall back to RPC/DCOM, the same connection Computer Management uses. **RMT-01** shows which of these the target allows.

## Stand-alone scripts

`Toolkit\Stand alone scripts\Input-and-Hardware-Diagnostics.ps1` is a separate GUI for testing keyboards, mice, touchscreens and game controllers. It doesn't need the toolkit and writes nothing to disk.

## Safety

- **Destructive actions ask first.** Deleting files, resetting the network, uninstalling apps, logging off sessions and removing credentials all ask for confirmation.
- **Irreversible ones need you to type `yes`:** emptying the Recycle Bin, deleting a user profile, removing saved credentials, an immediate restart of this PC, restarting or shutting down a remote PC or several at once, logging off a session, and ending processes with unsaved work. Deleting a local user needs `DELETE`. A scheduled restart (MNT-19) asks yes/no, since it can still be cancelled.
- **Every tool run is recorded** in the audit trail with its outcome (Success, Failed, Cancelled or Blocked). Review it with **TKA-05**.
- Read-only tools change nothing.

See [SECURITY.md](SECURITY.md) for what the toolkit does and does not protect, and how to report a vulnerability.
