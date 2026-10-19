# Toolkit Architecture & Structure

## Project Organization

```
Project Root/
├── README.md                    # Main guide
├── LICENSE                     # MIT License
│
├── Toolkit/                    # Self-contained: copy this folder to run anywhere
│   ├── Launch-GUI.bat          # Quick launcher (elevates, then opens the GUI)
│   ├── HelpdeskToolkit.ps1     # Console entry point
│   ├── HelpdeskToolkit-GUI.ps1 # GUI entry point
│   ├── Build-SingleFile.ps1    # Build standalone copies
│   │
│   ├── Core/                   # Foundation modules (loaded first)
│   │   ├── Common.ps1          # Helpers, logging, tool registration
│   │   ├── Config.ps1          # Configuration management
│   │   ├── Dependencies.ps1    # Prerequisite tracking
│   │   ├── Validation.ps1      # Input validation
│   │   ├── SecurityManagement.ps1  # Audit & credentials
│   │   └── Menu.ps1            # Console menu system
│   │
│   ├── Modules/                # Feature modules (loaded after Core)
│   │   ├── 01-SystemInfo.ps1       # 13 system diagnostic tools
│   │   ├── 02-Hardware.ps1         # 13 hardware tools
│   │   ├── 03-Network.ps1          # 31 network tools
│   │   ├── 04-Maintenance.ps1      # 33 maintenance tools
│   │   ├── 05-AppsOffice.ps1       # 13 apps/Office tools
│   │   ├── 06-Security.ps1         # 20 security tools
│   │   ├── 07-Users.ps1            # 12 user management tools
│   │   ├── 08-ActiveDirectory.ps1  # 23 AD tools (optional)
│   │   ├── 09-Microsoft365.ps1     # 15 M365 tools (optional)
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
│   │   └── GuiHost.ps1         # GUI I/O redirection
│   │
│   ├── Settings/               # GUI preferences (portable, git-ignored)
│   ├── Logs/                   # Optional local logs (git-ignored)
│   └── Stand alone scripts/    # Independent tools (Input-and-Hardware-Diagnostics.ps1)
│
├── .github/                    # CODEOWNERS, syntax-check workflow
└── docs/
    ├── ARCHITECTURE.md         # This file
    ├── GUIDE.md                # Common tasks, config, logs, troubleshooting
    └── CHANGELOG.md            # Release history
```

## Module Loading Order

The toolkit loads modules in this specific order to ensure dependencies are met:

1. **Common.ps1** - Helpers, logging, tool registration
2. **Config.ps1** - Settings (needed by other modules)
3. **Dependencies.ps1** - Prerequisite tracking
4. **Validation.ps1** - Input validation
5. **SecurityManagement.ps1** - Security & audit (needs Config and Common)
6. **Menu.ps1** - Console menu (needs all Core modules)
7. **01-SystemInfo through 24-Toolkit-Admin** - Feature modules

## Core Module Functions

### Common (Common.ps1)
**Purpose:** Foundation helpers and tool registration  
**Key Functions:** Test-IsAdmin, Write-*, Write-Log, Write-ErrorLog, Add-Tool, Get-SystemSummary, Get-SecurityAudit, Get-JsonLogEntries, Add-JsonLogEntry, Set-JsonLogEntries, Get-MemoryMetrics, Show-ResourceStats

### Config (Config.ps1)
**Purpose:** Centralized configuration without code changes  
**Key Functions:** Get-ToolkitConfig, Set-ToolkitConfig, Get-ConfigValue, Test-ConfigExists

### Dependencies (Dependencies.ps1)
**Purpose:** Track and validate prerequisites, and gate tools whose module is missing  
**Key Functions:** Test-ModuleAvailable, Test-DependencyMet, Get-UnmetToolDependency, Clear-DependencyState, Show-MissingDependencies

### Validation (Validation.ps1)
**Purpose:** Input validation for safety  
**Key Functions:** Test-ValidIPAddress, Test-ValidComputerName, Confirm-DestructiveAction

### SecurityManagement (SecurityManagement.ps1)
**Purpose:** Security, audit trails, credentials  
**Key Functions:** Save-ToolCredential, Log-AuditEvent, Get-AuditLog, Show-SecuritySummary

## Data Storage

### Logs & Configuration
**Location:** `Documents\HelpdeskToolkit\`

| File | Purpose | Max Size |
|------|---------|----------|
| `toolkit.log` | All actions | ~50MB (rotated) |
| `toolkit-errors.json` | Detailed errors with context | Last 200 entries |
| `toolkit-audit.json` | Audit trail (who/what/when) | Last 500 entries |
| `toolkit-usage.json` | Tool usage statistics | Daily summaries |

### GUI Settings (Portable)
**Location:** `Toolkit\Settings\gui-settings.json`
- Theme preference (light/dark)
- Favorite tools list
- Recently used tools
- Collapsed categories

Window size and position are not saved; the window opens at 1340x840 each time.

### Local logs
**Location:** `Toolkit\Logs\` (optional, for local testing)
- Can be configured to store locally instead of Documents

## Tool Registration System

Tools are registered using `Add-Tool` in feature modules:

```powershell
Add-Tool -Id 'NET-01' `
    -Category 'Network' `
    -Name 'My Tool' `
    -Description 'What it does' `
    -Tags @('tag1', 'tag2') `
    -Admin `
    -Action {
        # Your code here
    }
```

**Parameters:**
- `Id` - Unique tool identifier (e.g., SYS-01)
- `Category` - Menu category (auto-creates if new)
- `Name` - Display name
- `Description` - One-line description
- `Tags` - Optional tags for filtering
- `Admin` - Flag if tool requires administrator
- `Action` - ScriptBlock containing tool code
- `Aliases` - Optional. Former IDs of tools merged into this one

### Retiring a tool

When two tools do the same job, merge the useful parts into one and list the other's ID
in `-Aliases` instead of deleting it outright:

```powershell
Add-Tool -Id 'TRB-09' -Category 'Troubleshooting' -Name 'Disk health (SMART)' `
    -Aliases @('HW-13') `
    -Action { ... }
```

An alias keeps every way of reaching the old tool working: `-Run HW-13`, Run by ID in the
console menu, saved GUI favourites and recents (rewritten to the current ID on load), and
search. `Get-ToolById` and `Resolve-ToolId` in `Common.ps1` do the lookup. The
registration test fails if an alias is malformed, matches a live ID, or is claimed by two
tools.

## Logging and Diagnostics

Every tool run goes through `Invoke-Tool` (console) or `Invoke-GuiTool` (GUI), and both
record the same four things:

| What | Where | Detail |
|------|-------|--------|
| The run | `toolkit.log` | One line: timestamp, user, tool ID |
| Usage counters | `toolkit-usage.json` | Per tool, per day, deduplicated |
| Failures | `toolkit-errors.json` | Message, type, stack trace, invocation info, admin/OS context |
| Audit trail | `toolkit-audit.json` | Who ran what, when, and the outcome: Success, Failed, Cancelled or Blocked |

Cancelling a prompt is recorded as `Cancelled`, not as a failure, so it stays out of the
error log. A tool stopped by a missing optional module is recorded as `Blocked`.

TKA-05 reports the audit trail, TKA-04 manages the error log, and ANA-01 reports usage.

These JSON files are arrays, and they must be read with `Get-JsonLogEntries` and written
with `Add-JsonLogEntry` / `Set-JsonLogEntries` from `Common.ps1`. Windows PowerShell 5.1
does not enumerate a top-level JSON array out of `ConvertFrom-Json`, so the obvious
`@(Get-Content ... | ConvertFrom-Json)` yields a single-element array wrapping the real
one - `.Count` reads 1 and per-entry fields come back as arrays. The helpers handle that,
and repair log files written before they existed.

### Dependency gating

`Dependencies.ps1` lists the tools that need an optional module. Both runners call
`Get-UnmetToolDependency` before running a tool, so a missing module produces one clear
line plus an install hint instead of a "term is not recognized" error from inside the
tool. The status and installer tools (AD-01, AD-02, M365-01, M365-02) are deliberately
never gated, since they are how the module gets diagnosed and installed. The result is
remembered for the session, and AD-02 and M365-02 clear it after installing.

## Configuration Examples

See `Toolkit\Core\Config.ps1` for all configurable options:

```powershell
# Timeouts (seconds)
$Script:Config.Timeouts.RemoteOperation = 60  # Increase for slow systems

# Logging
$Script:Config.Logging.MaxErrorsToKeep = 200  # Entries kept in toolkit-errors.json

# Security
$Script:Config.Security.RequireConfirmDestructive = $false  # Skip confirmation
```

Not every section in `Config.ps1` is wired to behaviour. `Retry`, `Resources` and
`Performance` were added for the Cache, ResourceManagement and ErrorHandling modules,
which have since been removed; nothing reads them today. They are left in place rather
than removed, so settings files written by older versions still load.

## Adding New Tools

1. Edit the appropriate module file in `Toolkit\Modules\` (or create new)
2. Use `Add-Tool` to register the tool
3. Tools appear in menu automatically (sorted by module load order)
4. Optional: Add tags for discovery

Example:
```powershell
Add-Tool -Id 'NET-30' -Category 'Network' -Name 'My Tool' -Tags @('diagnostic') -Action {
    Write-Ok "Running my tool"
}
```

## Creating New Modules

1. Create `Toolkit\Modules\NN-YourCategory.ps1` (NN = number sequence)
2. Module loads automatically
3. Add tools using `Add-Tool`
4. New category appears in menu

---

**Version:** 1.5.0  
**Last Updated:** October 19, 2026
