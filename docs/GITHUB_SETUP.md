# GitHub Setup Guide - IT Helpdesk Toolkit

Your local repository is ready! Follow these steps to push your code to GitHub with proper security configurations.

## Step 1: Create GitHub Repository

1. **Go to GitHub** → https://github.com/new
2. **Repository name**: `PS_IT_Helpdesk_Toolkit`
3. **Description**: *An all-in-one PowerShell toolbox for Windows IT support with 264 tools in 24 categories*
4. **Visibility**: Select **Public** (recommended for open-source sharing)
5. **Initialize with**:
   - ❌ Do NOT check "Add a README file"
   - ❌ Do NOT check "Add .gitignore"
   - ❌ Do NOT check "Add a license"
   
   *(We already have these locally)*

6. Click **Create repository**

## Step 2: Connect Local Repository to GitHub

After creating the repository, GitHub will show you the commands to run. Run this in PowerShell:

```powershell
cd D:\Projects\Git_PS_IT_Helpdesk_Toolkit
git remote add origin https://github.com/YOUR_USERNAME/PS_IT_Helpdesk_Toolkit.git
git branch -M master
git push -u origin master
```

Replace `YOUR_USERNAME` with your actual GitHub username.

**Note:** If you already have two-factor authentication enabled:
- Use a **Personal Access Token (PAT)** instead of your password
- Generate one at: https://github.com/settings/tokens/new
- Scopes needed: `repo`, `workflow` (if you plan to add GitHub Actions)
- Paste the token when prompted for a password

## Step 3: Configure Repository Security Settings

### 3.1 Branch Protection Rules

1. **Go to** repository → **Settings** → **Branches**
2. **Add a rule** for `master` branch:
   - ✅ **Require pull request reviews before merging**
     - Required approving reviews: `1`
     - Require review from code owners: ✅
   - ✅ **Require status checks to pass before merging** (for future CI/CD)
   - ✅ **Require branches to be up to date before merging**
   - ✅ **Include administrators**: ✅ (apply to admins too)

### 3.2 Code Security & Analysis

1. **Go to** repository → **Settings** → **Code security and analysis**
   - ✅ **Enable Dependabot alerts**
   - ✅ **Enable Dependabot security updates**
   - ✅ **Enable secret scanning** (if available in your plan)

### 3.3 Access Control

1. **Go to** repository → **Settings** → **Access** → **Collaborators and teams**
   - Add collaborators with appropriate permissions:
     - **Maintain**: For trusted contributors
     - **Triage**: For issue/PR reviewers (no merge)
     - **Pull**: For read-only access

2. **Go to** repository → **Settings** → **Access** → **CODEOWNERS**
   - Create a `CODEOWNERS` file in root (optional, enforces review):
     ```
     # Global code owners
     * @YOUR_USERNAME
     
     # Core module owners
     Toolkit/Core/ @YOUR_USERNAME
     
     # Documentation owners
     docs/ @YOUR_USERNAME
     ```

### 3.4 General Security Settings

1. **Go to** repository → **Settings** → **General**
   - ✅ **Template repository**: Uncheck (unless you want others to create repos from this)
   - ✅ **Require commit signature**: ✅ (recommended for production)
   - ✅ **Automatically delete head branches**: ✅ (cleanup after PRs)

### 3.5 Collaborator Settings

1. **Go to** repository → **Settings** → **Collaborators and teams**
   - Set default permission level when adding users: **Triage** (safer default)

## Step 4: Configure GitHub Pages (Documentation)

If you want to publish documentation:

1. **Go to** repository → **Settings** → **Pages**
2. **Source**: Select `master` branch
3. **Folder**: Select `/docs` (your documentation folder)
4. **Custom domain**: (optional) Add your domain
5. **Enforce HTTPS**: ✅ Yes

Your documentation will be available at: `https://YOUR_USERNAME.github.io/PS_IT_Helpdesk_Toolkit/`

## Step 5: Set Up GitHub Actions (Optional CI/CD)

Create `.github/workflows/syntax-check.yml`:

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
      - name: Test PowerShell syntax
        shell: powershell
        run: |
          Get-ChildItem -Recurse -Filter "*.ps1" | ForEach-Object {
            if (!(Test-Path $_.FullName -PathType Leaf)) { exit 1 }
            $content = Get-Content $_.FullName -Raw
            $tokens = $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
            if ($errors.Count -gt 0) {
              Write-Error "Syntax errors in $($_.FullName)"
              $errors | ForEach-Object { Write-Error "  Line $($_.Token.StartLine): $_" }
              exit 1
            }
          }
          Write-Output "✅ All PowerShell files valid"
```

This automatically validates PowerShell syntax on every push/PR.

## Step 6: Release Management

### Create a Release

1. **Go to** repository → **Releases** → **Create a new release**
2. **Tag version**: `v1.5.0` (matches CHANGELOG.md)
3. **Release title**: `IT Helpdesk Toolkit v1.5.0 - Security & Performance Release`
4. **Description** (copy from CHANGELOG.md for v1.5.0)
5. **Attach binaries**: (optional) Upload single-file builds from `Toolkit/dist/`

### Future Releases

For v1.5.1+, follow this process:
1. Update CHANGELOG.md with changes
2. Commit with message: `release: v1.5.x - Description`
3. Create git tag: `git tag -a v1.5.x -m "Version 1.5.x release"`
4. Push tags: `git push origin --tags`
5. Create GitHub Release from the tag with changelog

## Step 7: Community Setup

### Create Issue Templates

Create `.github/ISSUE_TEMPLATE/bug_report.md`:

```markdown
---
name: Bug report
about: Report a bug
title: '[BUG] '
labels: 'bug'
---

## Describe the bug
A clear description of the issue.

## Steps to reproduce
1. Run tool...
2. Click...
3. See error...

## Expected vs Actual
**Expected**: ...
**Actual**: ...

## Environment
- Windows version: 
- PowerShell version: 
- Toolkit version: v1.5.0
- Error log: (attach toolkit-errors.json)

## Screenshots
(if applicable)
```

Create `.github/ISSUE_TEMPLATE/feature_request.md`:

```markdown
---
name: Feature request
about: Suggest an enhancement
title: '[FEATURE] '
labels: 'enhancement'
---

## Describe the feature
What would you like to add?

## Use case
Why do you need this?

## Proposed implementation
How should it work?

## Alternatives considered
Other approaches?
```

### Create Pull Request Template

Create `.github/pull_request_template.md`:

```markdown
## Description
Brief summary of changes.

## Related Issues
Closes #(issue number)

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Performance improvement
- [ ] Documentation update
- [ ] Security fix

## Testing
How did you test these changes?

## Checklist
- [ ] Code follows style guidelines
- [ ] Backward compatible
- [ ] Documentation updated
- [ ] No new warnings
- [ ] Tested in both console and GUI
```

## Step 8: Documentation Links

Update these files with your GitHub URL:

**In README.md**, add a "Contributing" section:
```markdown
## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

- 🐛 [Report bugs](https://github.com/YOUR_USERNAME/PS_IT_Helpdesk_Toolkit/issues/new?template=bug_report.md)
- 💡 [Request features](https://github.com/YOUR_USERNAME/PS_IT_Helpdesk_Toolkit/issues/new?template=feature_request.md)
- 🔒 [Security issues](SECURITY.md)
```

## Step 9: Ongoing Maintenance

### Weekly
- ✅ Check GitHub Issues
- ✅ Review security alerts
- ✅ Merge PRs with approvals

### Monthly
- ✅ Review Dependabot alerts
- ✅ Update dependencies
- ✅ Check analytics

### Quarterly
- ✅ Plan next release
- ✅ Review ROADMAP
- ✅ Update documentation

## Step 10: Additional Resources

### GitHub Security Best Practices
- https://github.com/YOUR_USERNAME/PS_IT_Helpdesk_Toolkit/security

### Useful GitHub Features
- **Issues**: Track bugs and features → `/issues`
- **Discussions**: Community Q&A → `/discussions`
- **Projects**: Kanban board for planning → `/projects`
- **Wiki**: Additional documentation → `/wiki`
- **Insights**: Analytics and activity → `/graphs`

### Protecting Against Common Issues
- ✅ Never commit `.env` files (covered by `.gitignore`)
- ✅ Never commit credentials (masked by `SecurityManagement.ps1`)
- ✅ Never commit large binaries (use `Releases`)
- ✅ Never commit compiled files (covered by `.gitignore`)

## Verification Checklist

After pushing to GitHub, verify:

- [ ] Repository is visible at `https://github.com/YOUR_USERNAME/PS_IT_Helpdesk_Toolkit`
- [ ] All files are present (56 files, ~16k lines)
- [ ] README.md displays correctly with formatting
- [ ] LICENSE is visible and correct (MIT)
- [ ] Branch protection is enabled for `master`
- [ ] Dependabot is enabled
- [ ] GitHub Pages is configured (optional)
- [ ] Community files are recognized:
  - ✅ CODE_OF_CONDUCT.md
  - ✅ CONTRIBUTING.md
  - ✅ SECURITY.md
  - ✅ .gitignore
  - ✅ LICENSE

## Quick Reference: Commands

```powershell
# View current remote
git remote -v

# Verify branch
git branch

# View commit history
git log --oneline

# Check status
git status

# Add changes
git add .

# Commit
git commit -m "message"

# Push
git push origin master

# Create new branch for feature
git checkout -b feature/name
git push -u origin feature/name

# Create tag
git tag -a v1.5.0 -m "Version 1.5.0"
git push origin --tags
```

## Support

If you encounter issues:

1. **GitHub Documentation**: https://docs.github.com
2. **GitHub Community**: https://github.community
3. **Git Documentation**: https://git-scm.com/doc

---

**Your repository is ready to go! 🚀**

Questions? Check the GitHub documentation or visit the GitHub Community forum.

**Next Steps:**
1. Run the commands in Step 2 to push to GitHub
2. Configure security settings in Step 3
3. (Optional) Set up GitHub Pages in Step 4
4. Monitor for security alerts and Dependabot recommendations
