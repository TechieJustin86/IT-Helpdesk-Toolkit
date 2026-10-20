# Toolkit Architecture & Structure

## Project Organization

```
Project Root/
├── README.md                    # Main guide
├── SECURITY.md                  # What the toolkit does and does not protect; reporting
├── CONTRIBUTING.md              # How to add or change tools
├── CODE_OF_CONDUCT.md, LICENSE  # MIT License
│
├── Toolkit/                     # Self-contained: copy this folder to run anywhere
│   ├── Launch-GUI.bat           # Quick launcher (elevates, then opens the GUI)
│   ├── HelpdeskToolkit.ps1      # Console entry point
│   ├── HelpdeskToolkit-GUI.ps1  # GUI entry point
│   ├── Build-SingleFile.ps1     # Builds standalone copies into dist/ (generated, git-ignored)
│   │
│   ├── Core/                    # Foundation modules (loaded first)
│   │   ├── Common.ps1           # Helpers, logging, JSON log files, tool registration and lookup
│   │   ├── Config.ps1           # Configuration defaults (see "Configuration" below)
│   │   ├── Dependencies.ps1     # Optional-module tracking and the dependency gate
│   │   ├── Validation.ps1       # Confirm-DestructiveAction, plus input validators
│   │   ├── SecurityManagement.ps1  # Audit trail
│   │   └── Menu.ps1             # Console menu and the console tool runner
│   │
│   ├── Modules/                 # Feature modules (loaded after Core)
│   │   ├── 01-SystemInfo.ps1       # 13 system diagnostic tools
│   │   ├── 02-Hardware.ps1         # 13 hardware tools
│   │   ├── 03-Network.ps1          # 31 network tools
│   │   ├── 04-Maintenance.ps1      # 33 maintenance tools
│   │   ├── 05-AppsOffice.ps1       # 13 apps/Office tools
│   │   ├── 06-Security.ps1         # 20 security tools
│   │   ├── 07-Users.ps1            # 12 user management tools
│   │   ├── 08-ActiveDirectory.ps1  # 23 AD tools (optional module)
│   │   ├── 09-Microsoft365.ps1     # 15 M365 tools (optional module)
│   │   ├── 10-Troubleshooting.ps1  # 22 troubleshooting tools
│   │   ├── 11-Remote.ps1           # 12 remote operation tools
│   │   ├── 13-Reports.ps1          # 10 reporting tools
│   │   ├── 14-QuickLaunch.ps1      # 24 quick launcher tools
│   │   ├── 15-AutoRepair.ps1       # 5 auto-repair tools
│   │   ├── 16-Performance.ps1      # 5 performance tools
│   │   ├── 17-BatchOps.ps1         # 6 batch operation tools
│   │   ├── 18-Intune.ps1           # 5 Intune tools
│   │   ├── 19-DailyTools.ps1       # 6 daily tools
│   │   ├── 20-Analytics.ps1        # 3 analytics tools
│   │   ├── 21-Developer.ps1        # 7 developer tools
│   │   ├── 22-Settings.ps1         # 4 settings tools
│   │   ├── 23-Recommendations.ps1  # 4 diagnostic tools
│   │   └── 24-Toolkit-Admin.ps1    # 6 admin tools
│   │
│   ├── Gui/
│   │   └── GuiHost.ps1          # Redirects tool I/O to the window; the GUI tool runner
│   │
│   ├── Settings/                # GUI preferences (created on first run, git-ignored)
│   ├── Logs/                    # Action log, error log, audit trail (git-ignored)
│   └── Stand alone scripts/     # Independent tools (Input-and-Hardware-Diagnostics.ps1)
│
├── Tests/
│   └── Test-ToolRegistration.ps1   # Load test: modules, IDs, aliases, README counts
├── .github/                     # CODEOWNERS and the CI workflow (see "Checks")
└── docs/
    ├── ARCHITECTURE.md          # This file
    ├── GUIDE.md                 # Common tasks, storage, troubleshooting
    └── CHANGELOG.md             # Release history
```

The module numbers skip 12; files load in name order, so the gap has no effect.

## Module Loading Order

1. **Common.ps1** - Helpers, logging, tool registration
2. **Config.ps1** - Settings
3. **Dependencies.ps1** - Optional-module tracking
4. **Validation.ps1** - Confirmation and validation helpers
5. **SecurityManagement.ps1** - Audit trail (needs Config and Common)
6. **Menu.ps1** - Console menu (needs all Core modules)
7. **01-SystemInfo through 24-Toolkit-Admin** - Feature modules, in file-name order

A module that throws while loading is skipped and reported; the rest of the toolkit still loads.

## How the GUI works

`HelpdeskToolkit-GUI.ps1` builds a WPF window and loads Core and every module into a **background runspace**, so tools run without freezing the window and a long job can be stopped. It then loads `Gui\GuiHost.ps1` into the same runspace. GuiHost replaces the console-facing functions with versions that talk to the window:

| Function | In the GUI becomes |
|---|---|
| `Write-Host`, `Out-Host` | Text in the output pane, colours kept |
| `Read-Host` | An input dialog (a masked password box with `-AsSecureString`) |
| `Confirm-Action` | A Yes/No dialog |
| `Select-FromList` | A list picker |
| `Invoke-External` | Runs the program hidden and streams its output into the pane |

Because of this, a tool is written once and works unchanged in both front ends. Messages pass to the window through a queue it drains on a timer. When a dialog is open the tool's thread waits until the window has stored the answer.

## Core Module Functions

### Common (Common.ps1)
**Purpose:** Foundation helpers and tool registration
**Key Functions:** Add-Tool, Get-ToolById, Resolve-ToolId, Test-IsAdmin, Write-Ok / Write-Info / Write-Warn / Write-Err / Write-Section / Write-Check, Write-Log, Write-ErrorLog, Get-JsonLogEntries, Add-JsonLogEntry, Set-JsonLogEntries, Get-OutFile, Invoke-External, Get-WingetPath, Get-SystemSummary, Get-MemoryMetrics, Show-ResourceStats, Show-ExecutionStats

### Config (Config.ps1)
**Purpose:** Configuration defaults
**Key Functions:** Get-ToolkitConfig, Get-ConfigValue

### Dependencies (Dependencies.ps1)
**Purpose:** Track optional modules, and gate tools whose module is missing
**Key Functions:** Get-UnmetToolDependency, Test-DependencyMet, Clear-DependencyState, Test-ModuleAvailable, Show-MissingDependencies

### Validation (Validation.ps1)
**Purpose:** Confirmation for irreversible actions
**Key Functions:** Confirm-DestructiveAction. The file also holds input validators (`Test-ValidIPAddress`, `Test-ValidComputerName`, `Validate-ComputerNameInput` and others) that no tool currently calls.

### SecurityManagement (SecurityManagement.ps1)
**Purpose:** The audit trail
**Key Functions:** Log-AuditEvent. The file also holds credential-caching, masking and remote-confirmation functions that no tool currently calls, so the toolkit stores no credentials and masks nothing.

## Data Storage

| File | Location | Content | Kept |
|------|----------|---------|------|
| `toolkit.log` | `Toolkit\Logs\` | One line per tool run, plus notable changes | Grows until deleted |
| `toolkit-errors.json` | `Toolkit\Logs\` | Failures with full context | Last 200 (`Logging.MaxErrorsToKeep`) |
| `toolkit-audit.json` | `Toolkit\Logs\` | Every tool run and its outcome | Last 500 |
| `gui-settings.json` | `Toolkit\Settings\` | Theme, favorites, recent tools, collapsed categories | - |
| `toolkit-usage.json` | `Documents\HelpdeskToolkit\` | Runs per tool per day | - |
| Reports and exports | `Documents\HelpdeskToolkit\` | HTML reports, CSV files | - |

Everything under `Toolkit\` travels with the folder, including on a flash drive. `Documents\HelpdeskToolkit` belongs to whichever account the toolkit is running as. Window size and position are not saved; the window opens at 1340x840 each time.

## Running as a standard user or as Administrator

`Launch-GUI.bat` relaunches elevated through UAC. When the signed-in user is not an administrator, UAC elevates as a **different** admin account, and the toolkit then runs as that account: `$env:TEMP`, `$env:LOCALAPPDATA`, `HKCU:`, the Documents folder, saved credentials and the Recycle Bin all refer to the admin's profile. Tools that work on per-user data act on the admin, not the user at the PC.

Some Windows interfaces answer only administrators, or only SYSTEM. Querying one as a standard user with `-ErrorAction SilentlyContinue` returns nothing, and a tool that reads "nothing" as "not present" reports a false negative. Prefer a source a standard user can read, and when there is none, say the result needs Administrator. Known examples and what the tools use instead:

| Needs elevation | Readable by a standard user |
|---|---|
| `root\cimv2\mdm\dmmap` (SYSTEM only) | Intune enrollment under `HKLM:\SOFTWARE\Microsoft\Enrollments` |
| `Win32_Tpm` | TPM presence and version from Device Manager (`Get-PnpDevice -Class SecurityDevices`) |
| `Get-BitLockerVolume` | none; tools report "Unknown - run as Administrator" |

`Get-Tpm` is not a substitute: for a standard user it returns an object with every field empty.

## Tool Registration System

Tools are registered using `Add-Tool` in feature modules:

```powershell
Add-Tool -Id 'CUS-01' `
    -Category 'Custom' `
    -Name 'My Tool' `
    -Description 'What it does' `
    -Tags @('tag1', 'tag2') `
    -Admin `
    -Action {
        # Your code here
    }
```

**Parameters:**
- `Id` - Unique tool identifier in the form `PREFIX-NN` (e.g. SYS-01)
- `Category` - Menu category (created automatically if new)
- `Name` - Display name
- `Description` - One-line description
- `Tags` - Optional tags for filtering
- `Admin` - The tool needs Administrator; the runners refuse it until elevated
- `Aliases` - Optional. Former IDs of tools merged into this one
- `Action` - ScriptBlock containing the tool's code

### Retiring a tool

When two tools do the same job, merge the useful parts into one and list the other's ID in `-Aliases` instead of deleting it outright:

```powershell
Add-Tool -Id 'TRB-09' -Category 'Troubleshooting' -Name 'Disk health (SMART)' `
    -Aliases @('HW-13') `
    -Action { ... }
```

An alias keeps every way of reaching the old tool working: `-Run HW-13`, Run by ID in the console menu, saved GUI favourites and recents (rewritten to the current ID on load), search, and the usage history in ANA-01. `Get-ToolById` and `Resolve-ToolId` in `Common.ps1` do the lookup. The registration test fails if an alias is malformed, matches a live ID, or is claimed by two tools.

## Logging and Diagnostics

Every tool run goes through `Invoke-Tool` (console, in `Menu.ps1`) or `Invoke-GuiTool` (GUI, in `GuiHost.ps1`), and both do the same things:

| What | Where | Detail |
|------|-------|--------|
| Admin check | - | Refuses an `-Admin` tool when not elevated |
| Dependency gate | - | Stops a tool whose optional module is missing, with an install hint |
| The run | `toolkit.log` | One line: timestamp, user, tool ID |
| Usage counters | `toolkit-usage.json` | Per tool, per day |
| Failures | `toolkit-errors.json` | Message, type, stack trace, invocation info, admin/OS context |
| Audit trail | `toolkit-audit.json` | Who ran what, when, and the outcome: Success, Failed, Cancelled or Blocked |
| Session statistics | memory | Runs, failures and time, shown by REC-01 |

Cancelling a prompt is recorded as `Cancelled`, not as a failure, so it stays out of the error log. A tool stopped by a missing optional module is recorded as `Blocked`. The audit trail records the computer the toolkit runs on, not the target of a remote tool.

TKA-05 reports the audit trail, DEV-06 and TKA-04 read and clean the error log, and ANA-01 reports usage.

These JSON files are arrays, and they must be read with `Get-JsonLogEntries` and written with `Add-JsonLogEntry` / `Set-JsonLogEntries` from `Common.ps1`. Windows PowerShell 5.1 does not enumerate a top-level JSON array out of `ConvertFrom-Json`, so the obvious `@(Get-Content ... | ConvertFrom-Json)` yields a single-element array wrapping the real one: `.Count` reads 1 and per-entry fields come back as arrays. The helpers handle that, and repair log files written before they existed.

### Dependency gating

`Dependencies.ps1` lists the tools that need an optional module. Both runners call `Get-UnmetToolDependency` before running a tool, so a missing module produces one clear line plus an install hint instead of a "term is not recognized" error from inside the tool. The status and installer tools (AD-01, AD-02, M365-01, M365-02) are deliberately never gated, since they are how the module gets diagnosed and installed. The result is remembered for the session, and AD-02 and M365-02 clear it after installing.

## Configuration

Defaults live in `Toolkit\Core\Config.ps1`, and TKA-01 shows them. One setting is read today:

```powershell
$Script:Config.Logging.MaxErrorsToKeep = 200  # Entries kept in toolkit-errors.json
```

The other sections - `Timeouts`, `Retry`, `Resources`, `Performance` and `Security` - are not read by any code. Most were added for the Cache, ResourceManagement and ErrorHandling modules, which were removed because nothing called them; `Security.RequireConfirmDestructive` is read only by a function that nothing calls. They remain so settings files written by older versions still load. Remote tools that connect through CIM use a fixed 20-second timeout.

## Checks

`.github/workflows/powershell-check.yml` runs on pull requests and pushes to `master` that change a `.ps1` file, `README.md` or the workflow itself. A change to other docs alone does not run it.

1. **Syntax** - every `.ps1` must parse.
2. **File encoding** - any `.ps1` containing non-ASCII text must be saved as UTF-8 with a byte order mark, because Windows PowerShell 5.1 reads a file without one as Windows-1252 and shows garbled text.
3. **Tool registration** - `Tests\Test-ToolRegistration.ps1` loads every module in the real order and checks load errors, duplicate or malformed IDs, aliases, required helpers, and that the counts in `README.md` match the code.
4. **PSScriptAnalyzer** - fails on Error-severity findings and lists warnings.

Run the registration test locally after changing a module:

```powershell
.\Tests\Test-ToolRegistration.ps1
```

## Adding New Tools and Modules

1. Add the tool to the matching file in `Toolkit\Modules\`, or create `Toolkit\Modules\NN-YourCategory.ps1` for a new category.
2. Register it with `Add-Tool`; it appears in both menus automatically, in module load order.
3. Run `Tests\Test-ToolRegistration.ps1`, and update the README counts it reports.

[CONTRIBUTING.md](../CONTRIBUTING.md) has the full checklist.

---

**Version:** 1.5.0 (plus the changes under "Unreleased" in [CHANGELOG.md](CHANGELOG.md))
**Last Updated:** October 19, 2026
