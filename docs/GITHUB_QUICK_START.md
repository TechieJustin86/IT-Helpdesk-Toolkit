# GitHub Quick Start - 5 Minute Setup

## 1. Create Repository (2 minutes)

```
https://github.com/new
```

Fill in:
- **Repository name:** `PS_IT_Helpdesk_Toolkit`
- **Description:** An all-in-one PowerShell toolbox for Windows IT support with 264 tools in 24 categories
- **Visibility:** Public
- **Initialize:** ❌ None (we already have files)

Click **Create repository**

## 2. Push Code (2 minutes)

GitHub will show you these commands. Copy and paste in PowerShell:

```powershell
cd D:\Projects\Git_PS_IT_Helpdesk_Toolkit
git remote add origin https://github.com/YOUR_USERNAME/PS_IT_Helpdesk_Toolkit.git
git branch -M master
git push -u origin master
```

**Replace `YOUR_USERNAME` with your GitHub username**

If prompted for password and you have 2FA:
1. Go to https://github.com/settings/tokens/new
2. Generate token with `repo` scope
3. Copy token
4. Paste when prompted

## 3. Verify Upload (1 minute)

Check your repository at:
```
https://github.com/YOUR_USERNAME/PS_IT_Helpdesk_Toolkit
```

Should show:
- ✅ 56 files
- ✅ README.md displayed
- ✅ MIT License shown
- ✅ All categories visible

## 4. Security Settings (Optional - follow GITHUB_SETUP.md)

Essential:
- Go to **Settings** → **Branches**
- Add branch protection for `master`
- Enable pull request reviews

Recommended:
- Go to **Settings** → **Code security**
- Enable **Dependabot alerts**
- Enable **Secret scanning**

## Done! 🎉

Your toolkit is now on GitHub!

---

## Useful GitHub URLs

| Feature | URL |
|---------|-----|
| **Code** | https://github.com/YOUR_USERNAME/PS_IT_Helpdesk_Toolkit |
| **Issues** | .../issues |
| **Pull Requests** | .../pulls |
| **Releases** | .../releases |
| **Settings** | .../settings |
| **Security** | .../security |
| **Actions** | .../actions |

## Useful Git Commands

```powershell
# Check status
git status

# View log
git log --oneline -5

# Create new branch
git checkout -b feature/name

# Push branch
git push -u origin feature/name

# Create tag
git tag -a v1.5.0 -m "Version 1.5.0"
git push origin --tags

# Pull updates
git pull origin master
```

## Next Steps (After Upload)

1. **Create releases**: Go to **Releases** → Create release for v1.5.0
2. **Enable discussions**: Settings → Features → Discussions
3. **Add topics**: Settings → Topics (add: powershell, windows, helpdesk, toolkit)
4. **Share**: Tweet, blog, newsletter, etc.

---

**Need more details?** See [GITHUB_SETUP.md](GITHUB_SETUP.md)

**Questions?** Check [README.md](README.md) or [CONTRIBUTING.md](CONTRIBUTING.md)
