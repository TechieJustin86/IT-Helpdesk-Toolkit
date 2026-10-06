# Toolkit Architecture & Structure

## Project Organization

```
Project Root/
├── README.md                    # Main guide
├── Launch-GUI.bat              # Quick launcher
├── LICENSE                     # MIT License
│
├── Toolkit/
│   ├── HelpdeskToolkit.ps1     # Console entry point
│   ├── HelpdeskToolkit-GUI.ps1 # GUI entry point
│   ├── Build-SingleFile.ps1    # Build standalone copies
│   │
│   ├── Core/                   # Foundation modules (loaded first)
│   │   ├── Common.ps1          # Helpers, logging, tool registration
│   │   ├── Config.ps1          # Configuration management
│   │   ├── Dependencies.ps1    # Prerequisite tracking
│   │   ├── Validation.ps1      # Input validation
│   │   ├── Cache.ps1           # Performance caching
│   │   ├── ResourceManagement.ps1  # Memory/disk/job limiting
│   │   ├── ErrorHandling.ps1   # Safe execution & retries
│   │   ├── SecurityManagement.ps1  # Audit & credentials
│   │   └── Menu.ps1            # Console menu system
│   │
│   ├── Modules/                # Feature modules (loaded after Core)
│   │   ├── 01-SystemInfo.ps1       # 14 system diagnostic tools
│   │   ├── 02-Hardware.ps1         # 11 hardware tools
│   │   ├── 03-Network.ps1          # 31 network tools
│   │   ├── 04-Maintenance.ps1      # 34 maintenance tools
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
│   │   ├── 16-Performance.ps1      # 6 performance tools
│   │   ├── 17-BatchOps.ps1         # 6 batch operation tools
│   │   ├── 18-Intune.ps1           # 5 Intune tools
│   │   ├── 19-DailyTools.ps1       # 7 daily tools
│   │   ├── 20-Analytics.ps1        # 3 analytics tools
│   │   ├── 21-Developer.ps1        # 9 developer tools
│   │   ├── 22-Settings.ps1         # 5 settings tools
│   │   ├── 23-Recommendations.ps1  # 5 diagnostic tools
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
5. **Cache.ps1** - Caching system
6. **ResourceManagement.ps1** - Resource monitoring
7. **ErrorHandling.ps1** - Error handling (needs above modules)
8. **SecurityManagement.ps1** - Security & audit (needs Config & Error)
9. **Menu.ps1** - Console menu (needs all Core modules)
10. **01-SystemInfo through 24-Toolkit-Admin** - Feature modules

## Core Module Functions

### Common (Common.ps1)
**Purpose:** Foundation helpers and tool registration  
**Key Functions:** Test-IsAdmin, Write-*, Write-Log, Write-ErrorLog, Add-Tool, Get-SystemSummary, Get-SecurityAudit

### Config (Config.ps1)
**Purpose:** Centralized configuration without code changes  
**Key Functions:** Get-ToolkitConfig, Set-ToolkitConfig, Get-ConfigValue, Test-ConfigExists

### Dependencies (Dependencies.ps1)
**Purpose:** Track and validate prerequisites  
**Key Functions:** Test-ModuleAvailable, Test-DependencyMet, Show-MissingDependencies

### Validation (Validation.ps1)
**Purpose:** Input validation for safety  
**Key Functions:** Test-ValidIPAddress, Test-ValidComputerName, Confirm-DestructiveAction

### Cache (Cache.ps1)
**Purpose:** Performance optimization via intelligent caching  
**Key Functions:** Set-Cache, Get-Cache, Get-CompiledRegex, Clear-ExpiredCacheItems

### ResourceManagement (ResourceManagement.ps1)
**Purpose:** Prevent resource exhaustion  
**Key Functions:** Start-ParallelOperation, Monitor-MemoryUsage, Test-DiskSpaceAvailable

### ErrorHandling (ErrorHandling.ps1)
**Purpose:** Safe execution with retries  
**Key Functions:** Invoke-ToolSafe, Invoke-ToolWithRetry, Rotate-OldLogs

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
- Window size/position

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

## Performance Characteristics

| Operation | Before v1.5 | After v1.5 | Method |
|-----------|------------|-----------|--------|
| SystemInfo queries | 5s | 0.5s | Caching |
| Multi-PC operations | Slow | 5x faster | Parallel jobs |
| Regex matching | Slow | 10x faster | Compiled cache |
| Error detection | Silent | 100% logged | Full logging |
| Memory usage | Unbounded | Limited | Resource monitoring |

## Configuration Examples

See `Toolkit\Core\Config.ps1` for all configurable options:

```powershell
# Timeouts (seconds)
$Script:Config.Timeouts.RemoteOperation = 60  # Increase for slow systems

# Parallel jobs
$Script:Config.Performance.MaxParallelJobs = 10  # For faster bulk ops

# Security
$Script:Config.Security.RequireConfirmDestructive = $false  # Skip confirmation
```

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
**Last Updated:** October 6, 2026
