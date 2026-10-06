# Toolkit Guide

Day-to-day tasks, configuration, logs and troubleshooting. For the file layout and load order see [ARCHITECTURE.md](ARCHITECTURE.md); for release history see [CHANGELOG.md](CHANGELOG.md).

## Common tasks

Run any tool from the console with `-Run <ID>` (use `-List` to see every ID), or pick it in the GUI.

| I want to... | Tool |
|---|---|
| Check system and toolkit health | `REC-05` |
| Get optimization recommendations | `REC-02` |
| Capture a performance baseline to compare later | `REC-03` |
| See which tools I use most and their error rates | `REC-04` |
| See runtime diagnostics for this session | `REC-01` |
| View or change toolkit settings | `TKA-01` |
| Verify toolkit files are present | `TKA-02` |
| Get a full toolkit diagnostic report | `TKA-03` |
| Clean up old error logs | `TKA-04` |
| See who did what (audit trail) | `TKA-05` |

```powershell
.\Toolkit\HelpdeskToolkit.ps1 -Run REC-05
```

## Configuration

Defaults live in `Toolkit\Core\Config.ps1`. TKA-01 shows the current values.

```powershell
$Script:Config.Timeouts.RemoteOperation = 60        # seconds; raise for slow remote systems
$Script:Config.Performance.MaxParallelJobs = 10     # more parallelism for bulk operations
$Script:Config.Performance.EnableCaching = $true    # disable to always refresh data
$Script:Config.Security.RequireConfirmDestructive = $true
$Script:Config.Security.MaskCredentialsInLogs = $true
```

## Where things are stored

| Location | Content |
|---|---|
| `Documents\HelpdeskToolkit\toolkit.log` | Every action performed (rotated) |
| `Documents\HelpdeskToolkit\toolkit-errors.json` | Detailed errors with context (last 200) |
| `Documents\HelpdeskToolkit\toolkit-audit.json` | Audit trail: who/what/when (last 500) |
| `Documents\HelpdeskToolkit\toolkit-usage.json` | Tool usage statistics |
| `Toolkit\Settings\` | GUI preferences and toolkit settings (portable; git-ignored) |
| `Toolkit\Logs\` | Optional local log folder (git-ignored) |

Reports, CSV exports and cases are also saved under `Documents\HelpdeskToolkit`.

## Helpers for tool authors

```powershell
Show-MissingDependencies -ToolId 'AD-01'                 # prerequisite check
Validate-ComputerNameInput -ComputerName $name           # input validation
Invoke-ToolSafe -Tool $tool -TimeoutSeconds 30           # errors, timeouts, prerequisites
Invoke-ToolWithRetry -Tool $tool -MaxAttempts 3          # exponential backoff
Monitor-MemoryUsage -WarningThresholdMB 500              # resource monitoring
Log-AuditEvent -Action 'Reset' -ToolId 'USR-01' -Target 'user'   # masks sensitive data
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Tool timeout after Xs" | Raise the matching value under `Timeouts` in `Config.ps1`. |
| "Missing prerequisites" | Run `AD-02` (RSAT Active Directory) or `M365-02` (Microsoft Graph) as needed. |
| High memory use | Run `REC-01` to monitor; clear the GUI output pane. |
| Need details on a failure | Run `TKA-03`, or read `toolkit-errors.json`. |
| Audit log too large | Run `TKA-04` to clean up old logs. |
