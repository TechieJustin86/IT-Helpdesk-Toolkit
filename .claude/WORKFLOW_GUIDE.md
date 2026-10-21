# IT Helpdesk Toolkit - Development Workflow Guide

**Quick reference for working with Claude on toolkit fixes and features.**

## Quick Start (TL;DR)

```powershell
# 1. Create feature branch
git checkout -b feature/your-name

# 2. Make changes & test locally
.\Tests\Test-ToolRegistration.ps1       # every module loads, IDs valid, README counts right
.\Toolkit\HelpdeskToolkit.ps1 -Run TOOL-ID
.\Toolkit\Launch-GUI.bat

# 3. Commit changes
git add .
git commit -m "fix: clear description of what changed"

# 4. Push to remote
git push -u origin feature/your-name

# 5. Open a PR
gh pr create --base master

# 6. Wait for the "Validate PowerShell" check to pass, then merge
gh pr merge <number> --squash --admin --delete-branch
```

---

## When to Ask Claude for Help

### ✅ Tell Claude To:
- 🐛 **Fix bugs** - "TRB-07 gives an error when..."
- ✨ **Add features** - "Add a new tool to the Network category..."
- 📝 **Update docs** - "Update README to mention..."
- 🔍 **Code review** - "Review this before I push"

### ✅ Claude Will:
- Find and fix bugs in the code
- Add new tools/features to appropriate modules
- Update documentation
- Scan every change for credentials, real server names and other private details before committing (see `CLAUDE.md`)
- Commit to a feature branch, push it, and open the PR
- Merge only when you say so

### ✅ You Handle:
- Reviewing the PR
- Final testing before merge
- Saying when to merge

---

## Detailed Workflow

### Step 1: Create Feature Branch

```powershell
cd <your clone of IT-Helpdesk-Toolkit>

# For fixes:
git checkout -b fix/brief-description
# Example: git checkout -b fix/trb-07-restart-error

# For new features:
git checkout -b feature/brief-description
# Example: git checkout -b feature/add-network-diagnostics
```

### Step 2: Work & Test Locally

**Check the registry:**
```powershell
.\Tests\Test-ToolRegistration.ps1
```

**Test the GUI:**
```powershell
.\Toolkit\Launch-GUI.bat
# Find your tool and test it
```

**Test console:**
```powershell
.\Toolkit\HelpdeskToolkit.ps1 -List      # See all tools
.\Toolkit\HelpdeskToolkit.ps1 -Run SYS-01  # Run a specific tool
```

If the tool reads system state, try it both elevated and as a standard user.

### Step 3: Commit Changes

```powershell
# Stage all changes
git add .

# Commit with clear message
git commit -m "fix: TRB-07 reports a failed restart as failed

Detailed explanation here if needed.
Explain what changed and why."
```

**Good commit messages:**
- ✅ `fix: TRB-07 reports a failed restart instead of success`
- ✅ `feat: add NET-32 subnet scanner tool`
- ✅ `docs: update README with new feature explanation`

**Bad commit messages:**
- ❌ `fix stuff`
- ❌ `update`
- ❌ `WIP`

### Step 4: Push to Remote

```powershell
git push -u origin fix/your-branch-name
# or
git push -u origin feature/your-branch-name
```

### Step 5: Create PR on GitHub

```powershell
gh pr create --base master
```

Or on the web: https://github.com/TechieJustin86/IT-Helpdesk-Toolkit/compare

### Step 6: Merge

`master` requires one approving review, and GitHub does not let you approve your own pull request. As the only admin, you merge with the admin override:

```powershell
gh pr checks <number>                                   # wait for "Validate PowerShell: pass"
gh pr merge <number> --squash --admin --delete-branch
```

"Validate PowerShell" is a required check enforced by a repository ruleset with no bypass, so even `--admin` cannot merge until it passes. If the merge is refused, wait for the check to finish.

### Step 7: Clean Up Locally

```powershell
# Switch back to master
git checkout master

# Get latest changes
git pull origin master

# Delete old branch
git branch -d feature/your-branch-name
```

---

## Common Workflows

### Fixing a Bug

```powershell
# 1. Identify the problem
# "TRB-07 says the service restarted when it did not"

# 2. Create fix branch
git checkout -b fix/trb-07-restart-status

# 3. Find and edit the file
# Open Toolkit\Modules\10-Troubleshooting.ps1

# 4. Fix the issue

# 5. Test it
.\Tests\Test-ToolRegistration.ps1
.\Toolkit\Launch-GUI.bat
# Navigate to TRB-07, test the fix

# 6. Commit
git add .
git commit -m "fix: TRB-07 reports a failed restart as failed

Restart-Service errors were hidden by SilentlyContinue, so the tool
always printed success. It now uses -ErrorAction Stop and reports the error."

# 7. Push, open the PR, and merge once the check passes
git push -u origin fix/trb-07-restart-status
```

### Adding a New Tool

```powershell
# 1. Create feature branch
git checkout -b feature/add-network-scanner

# 2. Edit appropriate module
# Open Toolkit\Modules\03-Network.ps1

# 3. Add tool using Add-Tool, with an ID nothing else uses
Add-Tool -Id 'NET-32' -Category 'Network' -Name 'Network Scanner' ...

# 4. Test it - the registration test also tells you the new README counts
.\Tests\Test-ToolRegistration.ps1
.\Toolkit\Launch-GUI.bat

# 5. Commit, including the README tools table and counts
git add .
git commit -m "feat: add NET-32 Network Scanner tool

New network diagnostic tool that scans for active hosts on subnet."

# 6. Push and create PR
```

---

## File Locations to Remember

```
IT-Helpdesk-Toolkit\
├── Toolkit\                         # Self-contained: copy to a flash drive to run anywhere
│   ├── Launch-GUI.bat               # Double-click to start
│   ├── HelpdeskToolkit.ps1          # Console entry point
│   ├── HelpdeskToolkit-GUI.ps1      # GUI entry point
│   ├── Core\                        # Shared helpers, config, dependencies, audit log
│   ├── Modules\                     # Feature modules (one per category)
│   ├── Logs\                        # Action log, error log, audit trail (git-ignored)
│   └── Stand alone scripts\         # Independent tools
├── Tests\Test-ToolRegistration.ps1  # Load test run by CI
├── docs\                            # ARCHITECTURE, GUIDE, CHANGELOG
├── CLAUDE.md                        # Rules Claude follows in this repo
└── .claude\WORKFLOW_GUIDE.md        # This file
```

---

## GitHub Setup (What's Already Done)

✅ **Branch protection** - `master` needs a PR with one approving review; the admin override bypasses it
✅ **CODEOWNERS** - you own every path
✅ **PowerShell checks** - syntax, file encoding, the registration test and PSScriptAnalyzer run on every PR, and must pass before it merges
✅ **Secret scanning and push protection** - GitHub blocks pushes containing known secret formats
ℹ️ **Dependabot** - security updates are enabled, but the repo has no package manifests, so there is nothing for it to scan

**What this means for you:**
- All changes go through a PR (even yours)
- Scripts are checked automatically, and a PR cannot merge until the check passes
- Known secret formats are caught by GitHub; everything else relies on checking before you commit

---

## Troubleshooting

### "Cannot push to master"
This is working as designed! You must use a feature branch and PR.
```powershell
# Create a feature branch instead
git checkout -b fix/your-issue
git push -u origin fix/your-issue
```

### "PR status check failing"
Open the failed step in GitHub Actions. It will be one of:
- **Validate PowerShell Syntax** - a script doesn't parse
- **Check file encoding** - a script has non-ASCII characters but no BOM; save it as UTF-8 with BOM
- **Tool registration** - a module failed to load, a tool ID is duplicated or malformed, a dependency list is out of date, or the README counts don't match
- **PSScriptAnalyzer** - an Error-severity finding

Fix it and push to the same branch; the PR updates automatically.

### "Forgot which branch I'm on"
```powershell
git branch          # Shows current branch (has *)
git status          # Shows branch and changes
```

### "Need to switch branches"
```powershell
git checkout master              # Switch to master
git checkout feature/other-name  # Switch to another branch
```

---

## Version Info

- **Last Updated:** 2026-10-21
- **Toolkit Version:** 1.5.0 (plus the changes under "Unreleased" in docs\CHANGELOG.md)
- **Repository:** https://github.com/TechieJustin86/IT-Helpdesk-Toolkit

---

## Quick Commands Cheat Sheet

```powershell
# Check status
git status

# See current branch
git branch

# Create & switch to new branch
git checkout -b feature/name

# Switch to existing branch
git checkout master

# Stage changes
git add .
git add filename.ps1        # Stage specific file

# Commit
git commit -m "message"

# Push to remote
git push -u origin feature/name

# Pull latest
git pull origin master

# See recent commits
git log --oneline -5

# Delete local branch
git branch -d feature/name
```

---

**Questions?** Check this guide or ask Claude directly. Good luck! 🚀
