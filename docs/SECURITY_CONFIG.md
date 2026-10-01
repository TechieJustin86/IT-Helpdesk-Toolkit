# GitHub Security Configuration Guide

Complete step-by-step setup for GitHub security features on your IT Helpdesk Toolkit repository.

## Quick Summary

This guide covers:
- ✅ Branch protection rules
- ✅ Code security & analysis (Dependabot)
- ✅ Secret scanning
- ✅ Access control
- ✅ Status checks
- ✅ CODEOWNERS file

---

## 1. Branch Protection Rules (CRITICAL)

**What it does:** Prevents accidental/bad code from being merged to main branch.

### Steps:

1. **Go to** your repo → **Settings** → **Branches**

2. **Click** "Add rule" (or "Add branch protection rule")

3. **Configure for `master` branch:**

   **Branch name pattern:** `master`

4. **Check these boxes:**

   ☑️ **Require a pull request before merging**
   - Required number of approvals before merging: `1`
   - ☑️ Require review from code owners
   - ☑️ Dismiss stale pull request approvals when new commits are pushed
   - ☑️ Require approval of the most recent reviewable push

   ☑️ **Require status checks to pass before merging**
   - ☑️ Require branches to be up to date before merging
   - (Add checks if you set up GitHub Actions in future)

   ☑️ **Require conversation resolution before merging**

   ☑️ **Include administrators**
   - This applies the rules to you too (prevents accidents)

   ☑️ **Restrict who can push to matching branches** (optional)
   - Can be configured after creation

5. **Click** "Create" or "Save changes"

---

## 2. Code Security & Analysis

**What it does:** Automatically scans for vulnerabilities and keeps dependencies updated.

### 2.1 Dependabot Alerts & Updates

1. **Go to** repo → **Settings** → **Code security and analysis**

2. **Find "Dependabot":**
   - ☑️ **Enable Dependabot alerts**
   - ☑️ **Enable Dependabot security updates**
   - ☑️ **Enable Dependabot version updates** (optional, for all dependency updates)

3. **Configure Dependabot** (optional):
   - Create `.github/dependabot.yml`:
     ```yaml
     version: 2
     updates:
       - package-ecosystem: "github-actions"
         directory: "/"
         schedule:
           interval: "weekly"
     ```

### 2.2 Secret Scanning (if available in your plan)

1. **In same section**, look for **Secret scanning**:
   - ☑️ **Enable secret scanning**
   - ☑️ **Enable secret scanning push protection** (blocks commits with secrets)

---

## 3. Access Control & CODEOWNERS

### 3.1 Create CODEOWNERS File

1. **Create** `.github/CODEOWNERS` in your repo:

```
# Global code owners - must review all changes
* @TechieJustin86

# Core modules - must be reviewed
Toolkit/Core/ @TechieJustin86

# Documentation
docs/ @TechieJustin86
README.md @TechieJustin86

# Security policy
SECURITY.md @TechieJustin86
```

2. **Commit and push:**
   ```powershell
   git add .github/CODEOWNERS
   git commit -m "Add CODEOWNERS file for code review enforcement"
   git push origin master
   ```

### 3.2 Manage Collaborators

1. **Go to** repo → **Settings** → **Collaborators and teams**

2. **Default permission** for new collaborators:
   - Set to **Triage** (safe default - can manage issues/PRs but not merge)

3. **Add collaborators** when needed:
   - Click "Add people"
   - Search for GitHub username
   - Select appropriate role:
     - **Pull** = Read-only
     - **Triage** = Manage issues/discussions (no merge)
     - **Push** = Can commit to branches
     - **Maintain** = Can manage repo settings
     - **Admin** = Full control

---

## 4. Security Settings

### 4.1 General Security

1. **Go to** repo → **Settings** → **General**

2. **Configure:**
   - ☑️ **Require commit signature** (optional but recommended)
   - ☑️ **Automatically delete head branches** (cleanup after PRs merged)

### 4.2 Threat & Vulnerability Management

1. **Go to** repo → **Security** tab (top of page)

2. **Review these sections:**
   - **Security advisories** - See reported vulnerabilities
   - **Dependabot** - Dependency updates
   - **Secret scanning** - Exposed secrets
   - **Code scanning** - Vulnerability scanning (requires GitHub Actions setup)

---

## 5. GitHub Actions Setup (Optional - CI/CD)

### 5.1 Create PowerShell Syntax Checker

1. **Create folder structure:**
   ```
   .github/workflows/
   ```

2. **Create** `.github/workflows/powershell-check.yml`:

```yaml
name: PowerShell Syntax Check

on:
  push:
    branches: [ master ]
    paths: [ '**.ps1' ]
  pull_request:
    branches: [ master ]
    paths: [ '**.ps1' ]

jobs:
  check:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Validate PowerShell Syntax
        shell: powershell
        run: |
          $ErrorCount = 0
          Get-ChildItem -Recurse -Filter "*.ps1" | ForEach-Object {
            $content = Get-Content $_.FullName -Raw
            $tokens = $errors = $null
            [void][System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
            if ($errors.Count -gt 0) {
              Write-Error "❌ Syntax errors in $($_.FullName)"
              $errors | ForEach-Object { Write-Error "   Line $($_.Token.StartLine): $_" }
              $ErrorCount++
            }
          }
          if ($ErrorCount -gt 0) {
            exit 1
          }
          Write-Output "✅ All PowerShell files are valid"
```

3. **Commit and push:**
   ```powershell
   git add .github/workflows/
   git commit -m "Add PowerShell syntax check workflow"
   git push origin master
   ```

4. **Monitor at:** repo → **Actions** tab

---

## 6. Security Settings Checklist

Go through **repo → Settings → Security & analysis** and enable:

| Feature | Status | What It Does |
|---------|--------|--------------|
| **Dependabot alerts** | ☑️ | Notifies you of vulnerable dependencies |
| **Dependabot updates** | ☑️ | Auto-creates PRs to fix vulnerabilities |
| **Secret scanning** | ☑️ | Detects exposed API keys, tokens |
| **Push protection** | ☑️ | Blocks commits with secrets |

---

## 7. Additional Security Tips

### 7.1 Two-Factor Authentication (2FA)

**Personal account security:**
1. **Go to** GitHub → Settings → Password and authentication
2. **Enable 2FA** (highly recommended)
3. Save recovery codes in secure location

### 7.2 Personal Access Tokens

Instead of using passwords:

1. **Go to** Settings → Developer settings → Personal access tokens → **Tokens (classic)**
2. **Generate new token** with minimal required scopes:
   - `repo` (full control of repos)
   - `workflow` (for GitHub Actions)
3. **Copy token** and store securely (use 1Password, Windows Credential Manager, etc.)

### 7.3 SSH Keys (Alternative to Tokens)

Better security alternative to tokens:

1. **Generate SSH key:**
   ```powershell
   ssh-keygen -t ed25519 -C "your_email@example.com"
   ```

2. **Add public key to GitHub:**
   - Settings → SSH and GPG keys → New SSH key
   - Paste public key content (from `~/.ssh/id_ed25519.pub`)

3. **Use SSH for git operations:**
   ```powershell
   git clone git@github.com:TechieJustin86/IT-Helpdesk-Toolkit.git
   ```

---

## 8. Monitoring & Maintenance

### Weekly
- [ ] Check **Security** tab for vulnerabilities
- [ ] Review pull requests for security issues

### Monthly
- [ ] Review **Dependabot PRs** and merge approved ones
- [ ] Check **Access log** for unexpected activity
- [ ] Review **Collaborators** list

### Quarterly
- [ ] Update security policies if needed
- [ ] Review and rotate access tokens if necessary
- [ ] Audit branch protection rules

---

## 9. Verify Your Configuration

After setting everything up, check:

**Branch Protection:**
- [ ] Go to master branch
- [ ] Try to push directly (should be blocked if protected)
- [ ] Create PR, it should require review

**Code Security:**
- [ ] Settings → Code security shows "Enabled"
- [ ] No existing vulnerabilities shown in Security tab

**CODEOWNERS:**
- [ ] Create test branch and PR
- [ ] See your username in "Reviewers" section
- [ ] PR requires your approval before merge

**GitHub Actions (if set up):**
- [ ] Go to Actions tab
- [ ] See workflow runs
- [ ] PR shows status checks

---

## 10. Common Issues & Solutions

### Issue: "Require status checks" grayed out
**Solution:** You need to have at least one status check configured:
- Either enable GitHub Actions
- Or enable branch protection first, then add checks

### Issue: Can't push to master
**Solution:** This is working as designed! 
- Create feature branch: `git checkout -b feature/your-name`
- Push to branch: `git push -u origin feature/your-name`
- Create PR on GitHub
- Wait for approval
- Merge via PR

### Issue: Dependabot PRs not appearing
**Solution:** 
- Ensure Dependabot is enabled in Settings
- May take 24-48 hours to scan initially
- Check Actions tab for Dependabot workflow

### Issue: Secret scanning not working
**Solution:**
- Only available in public repos with GitHub Pro/Team/Enterprise
- If public repo, should work automatically
- Check Settings → Code security

---

## 11. Next Steps

1. **Start with Branch Protection** (most important)
2. **Enable Dependabot** (keeps dependencies safe)
3. **Add CODEOWNERS** (enforces code reviews)
4. **Set up GitHub Actions** (automated testing)
5. **Monitor regularly** (weekly checks)

---

## Security Resources

- [GitHub Security Documentation](https://docs.github.com/en/code-security)
- [Dependabot Documentation](https://docs.github.com/en/code-security/dependabot)
- [Branch Protection](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches)
- [CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)

---

**Status:** Ready to configure ✅

Your repository is now secure with proper access control, dependency management, and code review requirements.
