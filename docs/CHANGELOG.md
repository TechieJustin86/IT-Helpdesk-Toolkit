# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Merged 9 duplicate tools into the tool they duplicated (301 -> 292 tools).** Each
  retired ID still works as an alias, so `-Run`, Run by ID, saved favourites and recents,
  search and usage history all reach the replacement:

  | Retired | Now | Notes |
  |---------|-----|-------|
  | SYS-04 BitLocker status | SEC-18 BitLocker status | Gains the manage-bde fallback and optional recovery keys |
  | HW-13 Storage SMART health | TRB-09 Disk health (SMART) | Gains bus type and reallocated sectors; no longer admin-only |
  | REC-04 Tool usage analytics | ANA-01 Tool usage analytics | Gains errors per tool; renamed from "heatmap" |
  | SET-04 Verify toolkit integrity | TKA-02 Toolkit integrity check | One check: files, syntax, loading, tool counts |
  | DEV-02 Module diagnostics | TKA-02 Toolkit integrity check | |
  | DEV-08 Clear error log | TKA-04 Clear error log | "Clear everything" is now option 2 |
  | PERF-04 Disk defragmentation | MNT-22 Optimize drives | "All fixed drives" is now a choice |
  | MNT-33 Remove Appx packages | MNT-26 Remove bloatware and Store apps | "Any installed app" is now mode 2 |
  | DAILY-07 Service quick restart | TRB-07 Restart a service | Common services list, or search |

- **`Launch-GUI.bat` moved from the repository root into `Toolkit\`**, so the `Toolkit`
  folder alone runs the toolkit, including from a flash drive.
- **Irreversible actions need `yes` typed to confirm** (`Confirm-DestructiveAction`):
  emptying the Recycle Bin, deleting a user profile, removing saved credentials, an
  immediate restart of this PC, restarting or shutting down remote PCs, logging off a
  session, and ending processes with unsaved work. They used to accept a single `y`.
- AR-01 "One-click PC tune-up" asks separately, with a typed `yes`, before emptying the
  Recycle Bin. It used to empty it without mentioning it.
- `Add-Tool` takes `-Aliases`; `Get-ToolById` and `Resolve-ToolId` resolve former IDs.
- The SET-03 and TKA-06 "About" screens read the version and counts live, and list only
  what the toolkit does.

### Added
- **The audit trail records every tool run** - who, which computer, when, elevated or
  not, and the outcome (Success, Failed, Cancelled or Blocked). It existed before but
  nothing wrote to it, so TKA-05 always said "No audit events logged yet".
- **Dependency gating**: tools that need the ActiveDirectory or Microsoft.Graph module
  stop with one clear line and an install hint, instead of failing deep inside the tool.
  The status and installer tools (AD-01, AD-02, M365-01, M365-02) are never gated.
- **`Tests\Test-ToolRegistration.ps1`**: loads every module and checks load errors,
  duplicate or malformed tool IDs, aliases, required helpers, and the counts in
  `README.md`. CI runs it, together with PSScriptAnalyzer and a file-encoding check.
- `Get-JsonLogEntries`, `Add-JsonLogEntry` and `Set-JsonLogEntries` in `Common.ps1` for the
  toolkit's JSON logs, and `Get-WingetPath` for finding winget.
- README sections on running from a flash drive and on standard-user vs. Administrator
  behaviour.

### Fixed

**Tools that gave wrong answers**
- **INTUNE-01, INTUNE-04 and INTUNE-05 reported "not enrolled" on enrolled devices.**
  They queried WMI's `root\cimv2\mdm\dmmap`, which answers only the SYSTEM account, and
  hid the "Access denied". They now read Windows' enrollment records, which any account
  can read. INTUNE-01's Entra ID check had the same fault.
- **INTUNE-05's compliance export** also reported BitLocker as "Disabled" whenever it
  could not read it, left Last Sync empty (it read a key that is never set), recorded the
  admin account rather than the signed-in user, and called the firewall "Enabled" when
  any one profile was on. Each column now reports what it could determine.
- **SEC-19 "TPM status" reported no TPM to standard users** and advised checking the BIOS,
  because `Win32_Tpm` answers only administrators. It now falls back to Device Manager.
  It also printed a fixed "2.0" as the version of every TPM.
- DAILY-04 "Generate device documentation" had the same BitLocker and firewall faults as
  INTUNE-05.
- **APP-02 and APP-11 reported "winget is not installed"** when the toolkit was elevated
  with a separate admin account, whose profile has no winget alias. They now fall back to
  the machine-wide App Installer.
- **USR-12 "Delete local user" did not protect the signed-in user** after elevation with a
  separate admin account: it protected the account running the toolkit, which is then the
  admin. It now protects both.
- REC-01's session statistics never counted runs, so they showed "Tools Executed: 0" and,
  after a failure, a negative success rate.
- ANA-01's "Today" column was hard-coded to 1, and it listed a tool once for every day it
  was used. Usage is now rolled up per tool.
- PERF-04 chose TRIM vs. defragmentation by asking whether any disk in the PC was an SSD,
  so on an SSD-boot + HDD-data machine it TRIMmed the hard disk and never defragmented
  it. Its replacement lets Windows choose per drive.
- DAILY-07 compared the typed menu number as text, so "10" passed its 1-7 range check; it
  also labelled wmiApSrv (the WMI Performance Adapter) as WMI, and reported a restart as
  successful even when it failed.
- The integrity checks counted tools by counting the text "Add-Tool" in each file, so
  14-QuickLaunch showed 1 tool instead of 24. TKA-02 counts the live registry.
- DAILY-06's prompt named outlook.office365.com as the default server; the default it
  uses is smtp.office365.com.

**Logging**
- **The JSON logs corrupted themselves on every append after the first.** Windows
  PowerShell 5.1 does not enumerate a top-level JSON array out of `ConvertFrom-Json`, so
  `@(Get-Content ... | ConvertFrom-Json)` produced a nested array that serialised as
  `{"value": [...], "Count": n}`. This affected the error log, audit log and usage log, in
  both directions. Existing corrupt files are repaired as they are read.
- Usage counts did not deduplicate per day for the same reason, and the error log lost
  `InvocationInfo` and `ExecutionContext` to the default `ConvertTo-Json` depth.
- TKA-04 rewrote the error log with the same broken pattern.
- Tools run from the console wrote no entry to `toolkit-errors.json`; only the GUI did.

**Display and loading**
- Long tool IDs such as `INTUNE-01` ran into the tool names in the GUI's tool list.
- Three modules showed garbled text under Windows PowerShell 5.1 (`Â°C` for `°C`, and
  `â”€â”€` for every separator line in Analytics), because they were saved without a
  byte-order mark.
- The `WinRM` dependency entry named the Windows feature `WinRM-IIS-Ext`, which is the IIS
  extension and not WinRM. It was removed rather than wired up, since gating on it would
  have blocked all ten remote tools on machines where remoting works.
- The AD dependency list stopped at AD-09 and omitted AD-20 through AD-33.
- `Test-RemoteComputerWinRM` passed `New-PSSession` a parameter it does not have, so it
  returned "unreachable" for every computer. Nothing called it yet.

**CI**
- The "Check file encoding" step read each file's first bytes and then always reported
  success. It now fails on non-ASCII text without a byte-order mark.
- PSScriptAnalyzer no longer fails on the intentional `1.1.1.1` connectivity checks.

**Documentation**
- The docs now describe what the code does. Removed claims of credential caching, log
  masking, log rotation, support cases, Windows 7 support, regular security testing,
  a 1.4.x maintenance line and support for compliance frameworks, none of which exist.
  Corrected the log locations (`Toolkit\Logs`, not Documents), documented which settings
  are read, and generated the README tools table from the code.

### Removed
- **Core modules `Cache.ps1`, `ResourceManagement.ps1` and `ErrorHandling.ps1`** (~550
  lines). Nothing outside those files ever called them. The two functions that were in
  use (`Get-MemoryMetrics`, `Show-ResourceStats`) moved to `Common.ps1`.
- TKA-03's "Cache Status" block, which reported on a cache nothing populated and so always
  showed zeros. It now reports memory instead.
- The "Future Roadmap" section of this changelog. Several items contradicted the current
  design, such as a SQLite cache after the cache was removed as unused, or Linux and
  macOS support for a toolkit built on WMI and the Windows registry.

### Known issues
- Of the settings in `Config.ps1`, only `Logging.MaxErrorsToKeep` is read; the rest are
  kept so older settings files still load. SET-01's settings file is not read at all.
- `Validation.ps1` and `SecurityManagement.ps1` contain functions no tool calls,
  including credential caching and log masking.
- When elevated with a separate admin account, tools that work on per-user data act on
  the admin's profile. See the README.

## [1.5.0] - 2026-09-30

> **Correction (2026-10-19):** several items below never took effect. The Cache,
> ResourceManagement and ErrorHandling modules were added, but nothing called them, so
> the caching and parallel-job speedups, retries and resource limits did not happen; the
> modules have since been removed (see Unreleased). The credential caching and log
> masking in SecurityManagement are not called by any tool, and the audit trail recorded
> nothing until it was connected under Unreleased.

### Added
- **Core Modules (8 new)**:
  - `Config.ps1` - Centralized configuration management
  - `Dependencies.ps1` - Prerequisite tracking and validation
  - `Validation.ps1` - Input validation helpers
  - `Cache.ps1` - Performance optimization via intelligent caching
  - `ResourceManagement.ps1` - Memory/disk/job resource limiting
  - `ErrorHandling.ps1` - Safe execution wrapper with retries
  - `SecurityManagement.ps1` - Audit trails and credential management
  - Enhanced `Common.ps1` with statistics and tagging

- **New Tools (11 total)**:
  - **Recommendations Category** (5 tools):
    - REC-01: Runtime Diagnostics
    - REC-02: Automated Recommendations
    - REC-03: Performance Baseline Capture
    - REC-04: Usage Analytics
    - REC-05: Health Check Summary
  - **Toolkit Administration** (6 tools):
    - TKA-01: Configuration Viewer
    - TKA-02: Integrity Check
    - TKA-03: Toolkit Diagnostics
    - TKA-04: Error Log Cleanup
    - TKA-05: Security Audit
    - TKA-06: About/Version Info

- **Security Features**:
  - Complete audit trail logging (who/what/when)
  - DPAPI-protected credential caching with expiration
  - Sensitive data masking in logs
  - Destructive action confirmation system
  - Remote operation security verification

- **Performance Optimizations**:
  - Intelligent caching reduces SystemInfo queries from 5s to 0.5s (10x faster)
  - Parallel operation management (5x faster for multi-PC jobs)
  - Compiled regex caching (10x faster pattern matching)
  - Output buffer rotation to prevent GUI freezing
  - Resource monitoring and limiting

- **Documentation**: `ARCHITECTURE.md`, `GUIDE.md` (common tasks, configuration, troubleshooting) and this changelog

### Changed
- Restructured module loading order for proper dependency management
- Enhanced error logging with full context (stack traces, source location)
- Improved prerequisite validation with human-friendly messages
- Tool registration now supports tagging for better discovery
- Configuration moved to centralized config file (no code changes needed)

### Improved
- 🛡️ **Security**: Audit logging, credential protection, operation confirmation
- ⚡ **Performance**: 10x faster caching, 5x faster parallel ops
- 🔧 **Reliability**: 90% fewer silent failures, automatic retries, comprehensive logging
- 📊 **Visibility**: Execution stats, error tracking, usage analytics
- 🎯 **Configurability**: All settings in one place

### Fixed
- Module loading sequence errors
- Missing prerequisite detection
- Silent operation failures
- Resource exhaustion on long operations
- Unbounded memory growth in cache

### Backward Compatible
- ✅ All existing tools work unchanged
- ✅ All existing APIs preserved
- ✅ No breaking changes
- ✅ Original menu structure unchanged
- ✅ Existing scripts continue to work

## [1.4.0] - 2026-08-15

### Added
- Initial release of modernized PowerShell toolkit
- GUI with WPF interface
- 253 tools across 21 categories
- MIT License
- Comprehensive README and documentation
- Support for both console and GUI modes

### Features
- **Categories**: System Info, Hardware, Network, Maintenance, Apps, Security, Users, Active Directory, Microsoft 365, Troubleshooting, Remote, Reports, Quick Launch, Auto-Repair, Performance, Batch Ops, Intune, Daily Tools, Analytics, Developer, Settings
- **GUI Features**: Favorites, search, background execution, dark mode
- **Logging**: Tool execution logging, error tracking
- **Portable Settings**: GUI preferences stored with toolkit
- **Stand-alone Support**: Ability to create single-file distributions

---

## Version Numbering

We follow Semantic Versioning:
- **MAJOR** - Breaking changes
- **MINOR** - New features (backward compatible)
- **PATCH** - Bug fixes and security patches

---

## How to Upgrade

### To the current version (Unreleased)
1. Copy the new `Toolkit` folder over the old one. Your `Toolkit\Settings\` and
   `Toolkit\Logs\` are kept, because the new copy contains neither.
2. `Launch-GUI.bat` now lives inside `Toolkit\`. Delete the old copy at the top of the
   folder if you have one, and point any shortcuts at the new location.
3. Scripts and favourites that use a retired tool ID keep working; see the table above.
4. Log files damaged by the old JSON bug are repaired automatically the first time they
   are read.

### From 1.4.x to 1.5.0
1. Backup your current toolkit folder
2. Replace the `Toolkit` folder with the new version
3. Existing settings in `Toolkit/Settings/gui-settings.json` are preserved
4. All existing tools work unchanged
5. New tools (REC-01-REC-05, TKA-01-TKA-06) automatically appear in the menu

---

## Credits

This toolkit was created to provide IT professionals with a comprehensive Windows support solution.

---

## Support

- 📖 **Documentation**: See `README.md` and `docs/` folder
- 🐛 **Bug Reports**: GitHub Issues
- 🔒 **Security Reports**: See `SECURITY.md`
- 📝 **Contributing**: See `CONTRIBUTING.md`

---

**Last Updated**: October 19, 2026
