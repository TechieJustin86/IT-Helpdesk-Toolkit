# Toolkit Guide

Day-to-day tasks, where things are stored, and troubleshooting. For the file layout and how it fits together see [ARCHITECTURE.md](ARCHITECTURE.md); for what has changed see [CHANGELOG.md](CHANGELOG.md).

## Common tasks

Run any tool from the console with `-Run <ID>` (use `-List` to see every ID), or pick it in the GUI.

| I want to... | Tool |
|---|---|
| Check this PC's health and get next steps | `TRB-18` Smart diagnosis |
| A one-page status: CPU, RAM, disk, Defender, firewall | `DAILY-01` |
| Check system and toolkit health together | `REC-05` |
| Get recommendations for this PC | `REC-02` |
| Capture a performance baseline to compare later | `REC-03` |
| See which tools I use most, and their errors | `ANA-01` |
| See this session's runs, failures and memory use | `REC-01` |
| Check the toolkit's files are all there and load | `TKA-02` |
| Get a full toolkit diagnostic report | `TKA-03` |
| Read the error log | `DEV-06` |
| Clean up the error log | `TKA-04` |
| See who ran what, and the outcome (audit trail) | `TKA-05` |

```powershell
.\Toolkit\HelpdeskToolkit.ps1 -Run TRB-18
```

## Where things are stored

| Location | Content | Kept |
|---|---|---|
| `Toolkit\Logs\toolkit.log` | One line per tool run, plus notable changes | Grows until you delete it |
| `Toolkit\Logs\toolkit-errors.json` | Failures with message, stack trace, script line and admin/OS context | Last 200 entries |
| `Toolkit\Logs\toolkit-audit.json` | Every tool run: who, which computer, when, admin or not, and the outcome | Last 500 entries |
| `Toolkit\Settings\gui-settings.json` | GUI theme, favorites, recent tools, collapsed categories | - |
| `Documents\HelpdeskToolkit\` | Reports and CSV exports, and `toolkit-usage.json` (runs per tool per day) | - |

`Toolkit\Logs\` and `Toolkit\Settings\` travel with the folder, so on a flash drive they move from PC to PC. `Documents\HelpdeskToolkit` is on whichever PC, and whichever account, the toolkit is running as. Nothing in these files is masked, so treat them as containing user and computer names.

None of these files are part of the repository; `.gitignore` excludes them.

## Configuration

`Toolkit\Core\Config.ps1` holds the toolkit's one setting, and **TKA-01** shows it:

```powershell
$Script:Config.Logging.MaxErrorsToKeep = 200   # entries kept in toolkit-errors.json
```

There is no settings file; to change the value, edit it in `Config.ps1`. A `Toolkit\Settings\toolkit-settings.json` left by an older version (written by the removed SET-01) was never read and can be deleted.

## Helpers for tool authors

The everyday ones live in `Core\Common.ps1`:

```powershell
Write-Ok / Write-Info / Write-Warn / Write-Err 'text'     # coloured output, works in GUI and console
Write-Section 'Heading'                                   # section heading
Write-Check 'OK' 'Label' $value                           # aligned status row: OK, WARN, FAIL or INFO
Confirm-Action 'Do it?'                                   # yes/no prompt; $true for yes
Confirm-DestructiveAction -Action 'What happens' -Target 'Where'   # user must type yes
Select-FromList $items { $_.Name } 'Prompt'               # list picker; the chosen item
Test-IsAdmin                                              # running elevated?
Get-OutFile 'report.csv'                                  # a path in Documents\HelpdeskToolkit
Invoke-External 'sfc.exe' '/scannow'                      # run a program, output streamed to the GUI
```

Prompts behave slightly differently in the two front ends. In the console, a blank answer gives `$null` from `Select-FromList` and `Read-Host`, and "no" from `Confirm-Action`. In the GUI, **Cancel** on any prompt stops the tool, and the run is recorded as `Cancelled`. Write tools so that both are safe: treat `$null` or "no" as "do nothing".

The tool runners already log every run, record failures with full context and write the audit trail, so a tool does not need to do any of that itself. Let errors you want reported reach the runner, for example with `-ErrorAction Stop`, rather than hiding them with `SilentlyContinue`: a hidden "access denied" can read as "not found". See [CONTRIBUTING.md](../CONTRIBUTING.md) for the full checklist.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "This tool needs the ActiveDirectory module" (or Microsoft.Graph) | Run `AD-02` or `M365-02` to install it; `AD-01` and `M365-01` show what is missing. |
| "This tool requires Administrator rights" | Click **Restart as Administrator** in the GUI, or start the console elevated. |
| A tool or category is missing | Run `TKA-02`. It lists any file that is missing or fails to load. |
| A result looks incomplete | Some tools see less without Administrator rights. Run elevated and try again. |
| Need details on a failure | Run `DEV-06`, or read `Toolkit\Logs\toolkit-errors.json`. |
| Error log too large | Run `TKA-04` to remove entries older than 30 days, or clear it. |
| `winget is not installed` | Install App Installer from the Microsoft Store. If it is installed, run the toolkit unelevated once to confirm, then report it as a bug. |
| Garbled characters such as `Â°` or `â”€` | A script was saved without a UTF-8 byte order mark. Save it as "UTF-8 with BOM"; CI checks for this. |
