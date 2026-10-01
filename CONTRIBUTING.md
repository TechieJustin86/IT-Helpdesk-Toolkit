# Contributing to IT Helpdesk Toolkit

Thank you for your interest in contributing to the IT Helpdesk Toolkit! This guide will help you get started.

## Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```powershell
   git clone https://github.com/your-username/Git_PS_IT_Helpdesk_Toolkit.git
   cd Git_PS_IT_Helpdesk_Toolkit
   ```
3. **Create a feature branch**:
   ```powershell
   git checkout -b feature/your-feature-name
   ```

## Development Guidelines

### Adding a New Tool

1. **Identify the right module** in `Toolkit/Modules/` or create a new one following the naming convention (e.g., `NN-CategoryName.ps1`)

2. **Use the `Add-Tool` helper**:
   ```powershell
   Add-Tool -Id 'CAT-##' `
       -Category 'Category Name' `
       -Name 'Tool Display Name' `
       -Description 'Brief description of what the tool does' `
       -Tags @('tag1', 'tag2') `
       -Admin `  # Include if tool requires administrator
       -Action {
           # Your PowerShell code here
           Write-Ok "Tool executed successfully"
       }
   ```

3. **Follow naming conventions**:
   - Tool ID: `CAT-##` (3-letter category abbreviation + 2-digit number)
   - IDs should be sequential within each category
   - See `README.md` for existing categories and numbering

4. **Input validation**:
   - Always validate user input using functions from `Validation.ps1`
   - Example: `Validate-ComputerNameInput -ComputerName $name`

5. **Error handling**:
   - Use `Invoke-ToolSafe` wrapper for safe execution
   - Include `Invoke-ToolWithRetry` for flaky operations
   - Log errors with full context using `Write-ErrorLog`

6. **Output formatting**:
   - Use `Write-Ok`, `Write-Warning`, `Write-Error` for consistent UI
   - Use `Format-Table | Out-Host` for tabular output
   - Output appears in both GUI and console

### Code Standards

- **PowerShell Version**: Support PS 5.1 and PS 7+
- **Admin Checks**: Use `Test-IsAdmin` to conditionally mark tools
- **Logging**: Use `Write-Log` for all operations
- **Error Context**: Include stack traces and context in error logs
- **Performance**: Use caching for expensive operations
- **Security**: Never log passwords or sensitive data
- **Documentation**: Add comment explaining non-obvious logic

### Testing Your Changes

1. **Syntax validation**: PowerShell syntax checker validates all files
   ```powershell
   .\Toolkit\Build-SingleFile.ps1
   ```

2. **Console mode test**:
   ```powershell
   .\Toolkit\HelpdeskToolkit.ps1 -List
   .\Toolkit\HelpdeskToolkit.ps1 -Run YOUR-ID
   ```

3. **GUI mode test**:
   ```powershell
   .\Launch-GUI.bat
   # Double-click Launch-GUI.bat to test in GUI
   ```

4. **Backward compatibility**: Ensure existing tools still work

## Making Changes

### Before You Start
- Check existing issues and pull requests to avoid duplication
- Discuss major changes in an issue first

### Commit Messages

Write clear, descriptive commit messages:
```
Brief summary of changes (50 chars or less)

Detailed explanation of what changed and why. Reference any related
issues using #issue-number format.

- Specific change 1
- Specific change 2
```

### Documentation

Update relevant docs when making changes:
- **New tool?** → Update `README.md` tools table
- **New feature?** → Add to `docs/FEATURES.md`
- **Breaking change?** → Update `CHANGELOG.md`
- **Config change?** → Update `docs/IMPLEMENTATION.md`

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
- ✅ Backward compatibility
- ✅ Performance impact
- ✅ Security implications
- ✅ Documentation completeness
- ✅ Test coverage

## Reporting Issues

Use GitHub Issues to report bugs or suggest features:

1. **Check if issue already exists** (search closed issues too)
2. **Include reproduction steps** if it's a bug
3. **Include your environment**:
   - Windows version (e.g., Windows 11 22H2)
   - PowerShell version (5.1 or 7.x)
   - Toolkit version
   - Any error logs

## Security Issues

⚠️ **Do not create public issues for security vulnerabilities**

Instead, email security concerns to: [maintainer-email]

Include:
- Description of vulnerability
- Impact assessment
- Suggested fix (if any)

## Project Structure

```
Toolkit/
├── Core/              # Foundation modules (always loaded first)
├── Modules/           # Feature modules (one per category)
├── Gui/               # GUI-specific code
├── Assets/            # Icons, resources
├── Settings/          # User preferences (portable)
└── Logs/              # Error logs (local, for testing)

docs/
├── FEATURES.md        # Feature documentation
├── ARCHITECTURE.md    # System design
├── IMPLEMENTATION.md  # Implementation details
└── QUICK_REFERENCE.md # Quick reference guide
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
- 💬 **Discussions**: Open a GitHub discussion for questions

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

---

Thank you for helping make the IT Helpdesk Toolkit better! 🙏
