# IT Helpdesk Toolkit - Development Workflow Guide

**Quick reference for working with Claude on toolkit fixes and features.**

## Quick Start (TL;DR)

```powershell
# 1. Create feature branch
git checkout -b feature/your-name

# 2. Make changes & test locally
# Edit files, then test:
.\Launch-GUI.bat
# or
.\Toolkit\HelpdeskToolkit.ps1 -Run TOOL-ID

# 3. Commit changes
git add .
git commit -m "Clear description of what changed"

# 4. Push to remote
git push -u origin feature/your-name

# 5. Create PR on GitHub web interface
# https://github.com/TechieJustin86/IT-Helpdesk-Toolkit/compare

# 6. Approve your own PR (you're the code owner)
# 7. Merge when ready
```

---

## When to Ask Claude for Help

### ✅ Tell Claude To:
- 🐛 **Fix bugs** - "SET-01 gives an error when..."
- ✨ **Add features** - "Add a new tool to the Network category..."
- 📝 **Update docs** - "Update README to mention..."
- 🔍 **Code review** - "Review this before I push"

### ✅ Claude Will:
- Find and fix bugs in the code
- Add new tools/features to appropriate modules
- Update documentation
- Commit changes to feature branch
- Push the branch
- Provide PR URL ready for you to review

### ✅ You Handle:
- Creating/approving the PR on GitHub
- Final testing before merge
- Merging when ready

---

## Detailed Workflow

### Step 1: Create Feature Branch

```powershell
cd D:\Projects\Git_PS_IT_Helpdesk_Toolkit

# For fixes:
git checkout -b fix/brief-description
# Example: git checkout -b fix/set-01-file-open-error

# For new features:
git checkout -b feature/brief-description
# Example: git checkout -b feature/add-network-diagnostics
```

### Step 2: Work & Test Locally

**Test the GUI:**
```powershell
.\Launch-GUI.bat
# Find your tool and test it
```

**Test console:**
```powershell
.\Toolkit\HelpdeskToolkit.ps1 -List      # See all tools
.\Toolkit\HelpdeskToolkit.ps1 -Run SYS-01  # Run a specific tool
```

### Step 3: Commit Changes

```powershell
# Stage all changes
git add .

# Commit with clear message
git commit -m "fix: SET-01 now opens settings file correctly

Detailed explanation here if needed.
Explain what changed and why."
```

**Good commit messages:**
- ✅ `fix: SET-01 opens settings with Invoke-Item instead of &`
- ✅ `feature: add SYS-14 hardware diagnostics tool`
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

1. Go to: https://github.com/TechieJustin86/IT-Helpdesk-Toolkit/compare
2. GitHub will suggest your branch → click "Create pull request"
3. Add title & description
4. Click "Create pull request"

### Step 6: Approve & Merge

Since you're the code owner:
1. GitHub will ask for your approval (CODEOWNERS requirement)
2. Click "Approve"
3. Click "Merge pull request"
4. Delete the branch (GitHub offers this)

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
# "SET-01 gives error when opening settings"

# 2. Create fix branch
git checkout -b fix/set-01-settings-error

# 3. Find and edit the file
# Open Toolkit\Modules\22-Settings.ps1

# 4. Fix the issue

# 5. Test it
.\Launch-GUI.bat
# Navigate to SET-01, test the fix

# 6. Commit
git add .
git commit -m "fix: SET-01 opens settings file with Invoke-Item

Changed from & operator (execute) to Invoke-Item (open in editor).
Added Path validation to prevent empty string error."

# 7. Push
git push -u origin fix/set-01-settings-error

# 8. Create PR on GitHub and merge
```

### Adding a New Tool

```powershell
# 1. Create feature branch
git checkout -b feature/add-network-scanner

# 2. Edit appropriate module
# Open Toolkit\Modules\03-Network.ps1

# 3. Add tool using Add-Tool helper
Add-Tool -Id 'NET-30' -Category 'Network' -Name 'Network Scanner' ...

# 4. Test it
.\Launch-GUI.bat
# Find the new tool in Network category, test it

# 5. Commit
git add .
git commit -m "feature: add NET-30 Network Scanner tool

New network diagnostic tool that scans for active hosts on subnet.
Includes configurable timeout and CIDR range support."

# 6. Push and create PR
```

---

## File Locations to Remember

```
D:\Projects\Git_PS_IT_Helpdesk_Toolkit\
├── Toolkit\
│   ├── HelpdeskToolkit.ps1          # Console entry point
│   ├── HelpdeskToolkit-GUI.ps1      # GUI entry point
│   ├── Launch-GUI.bat               # Double-click to start
│   ├── Core\                        # Core modules
│   │   ├── Common.ps1
│   │   ├── ErrorHandling.ps1
│   │   └── ... (other core modules)
│   └── Modules\                     # Feature modules (by category)
│       ├── 01-SystemInfo.ps1
│       ├── 03-Network.ps1
│       ├── 22-Settings.ps1
│       └── ... (other categories)
├── docs\                            # Public documentation
│   ├── ARCHITECTURE.md
│   ├── FEATURES.md
│   └── ... (other public docs)
└── .claude\
    └── WORKFLOW_GUIDE.md            # This file
```

---

## GitHub Security Setup (What's Already Done)

✅ **Branch Protection** - All PRs need approval  
✅ **CODEOWNERS** - Your approval required  
✅ **PowerShell Syntax Check** - Auto-validates all files  
✅ **Dependabot** - Scans for vulnerable dependencies  
✅ **Secret Scanning** - Detects exposed secrets  

**What this means for you:**
- All changes go through PR review (even yours)
- Syntax is automatically checked
- Security is verified
- Complete audit trail of changes

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
PowerShell syntax error detected.
- Check the error message in GitHub Actions
- Fix the syntax error
- Push the fix to the same branch
- PR updates automatically

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

- **Last Updated:** 2026-10-01
- **Toolkit Version:** 1.5.0
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
