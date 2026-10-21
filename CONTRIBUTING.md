# Contributing to IT Helpdesk Toolkit

Thank you for your interest in contributing to the IT Helpdesk Toolkit! This guide will help you get started.

## Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```powershell
   git clone https://github.com/<your-username>/IT-Helpdesk-Toolkit.git
   cd IT-Helpdesk-Toolkit
   ```
3. **Create a feature branch**:
   ```powershell
   git checkout -b feature/your-feature-name
   ```

## This repository is public

Everything you commit is visible to everyone, and git history is permanent: a secret that reaches a commit cannot be fully removed by deleting it later. Before every commit, check your changes contain none of these:

- Passwords, API keys, tokens, connection strings, or certificate and key files (`.pfx`, `.pem`, `.key`)
- Real domain names, server names, internal hostnames, UNC paths to real servers, or internal IP ranges. Placeholders such as `fileserver`, `domain.local` and `192.168.1.0/24` are fine.
- Real names, usernames, email addresses or machine names
- Anything from an employer: internal tool names, company names, ticket data, logs, exports, inventories
- Generated or machine-specific files: settings JSON, logs, reports, CSV exports. `.gitignore` already excludes the toolkit's own.

## Development Guidelines

### Adding a New Tool

1. **Pick the module** in `Toolkit/Modules/` for its category, or create a new one named `NN-CategoryName.ps1`.

2. **Register it with `Add-Tool`**:
   ```powershell
   Add-Tool -Id 'CUS-01' `
       -Category 'Custom' `
       -Name 'Tool Display Name' `
       -Description 'Brief description of what the tool does' `
       -Tags @('tag1', 'tag2') `
       -Admin `
       -Action {
           Write-Info 'Checking...'
           # Your PowerShell code here
           Write-Ok 'Done'
       }
   ```
   Leave out `-Admin` if the tool works without Administrator rights.

3. **Choose an unused ID** in the form `PREFIX-NN`: letters or digits, a hyphen, then a number, such as `NET-32` or `HW-15`. Use the prefix the category already uses. Never reuse the ID of a retired tool: a merged tool's ID is an alias for the tool that replaced it (see `docs/ARCHITECTURE.md`, "Retiring a tool"), and a removed one (SET-01, AD-33) would make old notes and saved favourites point at a different tool. The registration test rejects duplicates.

4. **Output and prompts** - use the toolkit helpers so the tool works in both the GUI and the console:
   - `Write-Ok`, `Write-Info`, `Write-Warn`, `Write-Err`, `Write-Section`, `Write-Check`
   - `Format-Table | Out-Host` for tables
   - `Read-Host`, `Confirm-Action` and `Select-FromList` for questions; they become dialogs in the GUI
   - `Confirm-DestructiveAction` for anything that cannot be undone, so the user has to type `yes`
   - Treat a blank answer or "no" as "do nothing". In the GUI, Cancel stops the tool.

5. **Errors** - the tool runner already logs every run, records failures with full context, and writes the audit trail. Let failures you want reported reach it, for example with `-ErrorAction Stop`.

### Code Standards

- **PowerShell version**: support Windows PowerShell 5.1 and PowerShell 7.
- **File encoding**: if a script contains any non-ASCII character (`°`, `•`, `✓`, box-drawing lines), save it as **UTF-8 with BOM**. Windows PowerShell 5.1 reads a file without a BOM as Windows-1252 and shows garbled text. CI checks this.
- **Standard users**: don't let `-ErrorAction SilentlyContinue` turn "access denied" into a negative result. Some Windows interfaces answer only administrators, so a hidden failure reads as "not installed" or "not enabled". If a result needs elevation, check `Test-IsAdmin` and say so. `docs/ARCHITECTURE.md` lists known cases.
- **The toolkit's JSON logs**: read them with `Get-JsonLogEntries`, and write them with `Add-JsonLogEntry` or `Set-JsonLogEntries`. Never use `@(Get-Content ... | ConvertFrom-Json)`, which Windows PowerShell 5.1 turns into a nested array.
- **Security**: never log passwords or other secrets. Nothing in the toolkit's logs is masked.
- **Documentation**: add a comment explaining non-obvious logic, especially a workaround.

### Testing Your Changes

1. **Registration test** - loads every module and checks IDs, aliases and the README counts:
   ```powershell
   .\Tests\Test-ToolRegistration.ps1
   ```

2. **Console mode test**:
   ```powershell
   .\Toolkit\HelpdeskToolkit.ps1 -List
   .\Toolkit\HelpdeskToolkit.ps1 -Run YOUR-ID
   ```

3. **GUI mode test**:
   ```powershell
   .\Toolkit\Launch-GUI.bat
   ```

4. **Standard user and Administrator** - if the tool reads system state, try it both elevated and not, and make sure neither gives a wrong answer.

The same checks run in CI on every pull request: syntax, file encoding, the registration test, and PSScriptAnalyzer. They must pass before the pull request can merge.

## Making Changes

### Before You Start
- Check existing issues and pull requests to avoid duplication
- Discuss major changes in an issue first

### Commit Messages

Write clear, descriptive commit messages. This repository uses a type prefix:

```
fix: short summary of the change (50 chars or less)

Detailed explanation of what changed and why. Reference any related
issues using #issue-number format.
```

Common types: `feat`, `fix`, `docs`, `refactor`, `ci`.

### Documentation

Update the relevant docs when making changes:
- **New, merged or removed tool?** → Update the `README.md` tools table and counts. The registration test fails until the counts match.
- **Any user-visible change?** → Add it under "Unreleased" in `docs/CHANGELOG.md`
- **Storage, logging or troubleshooting change?** → Update `docs/GUIDE.md`
- **New module or core file?** → Update `docs/ARCHITECTURE.md`

## Submitting Changes

1. **Push to your fork**:
   ```powershell
   git push origin feature/your-feature-name
   ```

2. **Create a Pull Request** on GitHub with:
   - Clear title describing the change
   - Description of what changed and why
   - Reference to any related issues
   - Screenshots if UI changes

3. **Respond to feedback** from reviewers

## Code Review Process

All submissions will be reviewed for:
- ✅ Code quality and consistency
- ✅ Correct results both elevated and as a standard user
- ✅ Backward compatibility, including tool IDs
- ✅ Security implications and the public-repository checklist above
- ✅ Documentation completeness

## Reporting Issues

Use GitHub Issues to report bugs or suggest features:

1. **Check if the issue already exists** (search closed issues too)
2. **Include reproduction steps** if it's a bug
3. **Include your environment**:
   - Windows version (e.g., Windows 11 23H2)
   - PowerShell version (5.1 or 7.x)
   - Whether the toolkit was running elevated
   - The relevant entries from `Toolkit\Logs\toolkit-errors.json`, with any personal details removed

## Security Issues

⚠️ **Do not create public issues for security vulnerabilities**

Instead, follow the reporting process in [SECURITY.md](SECURITY.md).

## Project Structure

```
Toolkit/
├── Launch-GUI.bat     # Double-click to start
├── Core/              # Foundation modules (always loaded first)
├── Modules/           # Feature modules (one per category)
├── Gui/               # GUI host: redirects tool input and output to the window
├── Settings/          # User preferences (created on first run)
├── Logs/              # Action log, error log, audit trail
└── Stand alone scripts/

Tests/                 # Test-ToolRegistration.ps1
docs/
├── ARCHITECTURE.md    # How it is built
├── GUIDE.md           # Tasks, storage, troubleshooting
└── CHANGELOG.md       # Release history
```

## Building Standalone Versions

To create standalone single-file versions:

```powershell
.\Toolkit\Build-SingleFile.ps1
```

This validates all syntax and creates `Toolkit/dist/` with:
- `HelpdeskToolkit-GUI.ps1`
- `HelpdeskToolkit.ps1`

## Questions?

- 📖 **Documentation**: Check `README.md` and `docs/`
- 🔍 **Code Examples**: Look at existing tools in `Toolkit/Modules/`
- 💬 **Questions and ideas**: Open a GitHub issue

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

---

Thank you for helping make the IT Helpdesk Toolkit better! 🙏
