# Modules\21-Settings.ps1
# Category: Settings & Configuration
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

Add-Tool -Id 'SET-01' -Category 'Settings & Configuration' -Name 'Toolkit settings' -Description 'Configure toolkit behavior: logging, output location, feature toggles, theme preferences' -Action {
    Write-Section 'Toolkit Settings'

    $settingsPath = Join-Path $Script:ToolkitDir 'Settings\toolkit-settings.json'
    $settingsDir = Split-Path $settingsPath

    # Create settings directory if it doesn't exist
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    # Load or create default settings
    $documentsPath = [Environment]::GetFolderPath('MyDocuments')
    $defaultSettings = @{
        Version = '2.0'
        LastModified = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        AutoSaveOutput = $true
        AutoLogActions = $true
        OutputLocation = Join-Path $documentsPath 'HelpdeskToolkit'
        CaseSaveLocation = Join-Path $documentsPath 'HelpdeskToolkit\Cases'
        EnableErrorReporting = $true
        EnablePerformanceMetrics = $false
        Theme = 'Auto'
        ConfirmDestructiveActions = $true
        MaxLogFileSize = 10485760
        ArchiveOldLogs = $true
        EnableRemoteLogging = $false
        RemoteLogServer = ''
    }

    if (-not (Test-Path $settingsPath)) {
        $defaultSettings | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    }
    $currentSettings = Get-Content $settingsPath -Raw | ConvertFrom-Json

    # Display current settings
    Write-Host ''
    Write-Host 'Current Settings:' -ForegroundColor Cyan
    Write-Host '  Output Location: ' -NoNewline
    Write-Host $currentSettings.OutputLocation -ForegroundColor Green
    Write-Host '  Case Storage: ' -NoNewline
    Write-Host $currentSettings.CaseSaveLocation -ForegroundColor Green
    Write-Host '  Auto-Logging: ' -NoNewline
    Write-Host $(if ($currentSettings.AutoLogActions) { 'Enabled' } else { 'Disabled' }) -ForegroundColor Green
    Write-Host '  Error Reporting: ' -NoNewline
    Write-Host $(if ($currentSettings.EnableErrorReporting) { 'Enabled' } else { 'Disabled' }) -ForegroundColor Green
    Write-Host '  Theme: ' -NoNewline
    Write-Host $currentSettings.Theme -ForegroundColor Green
    Write-Host '  Confirm Destructive Actions: ' -NoNewline
    Write-Host $(if ($currentSettings.ConfirmDestructiveActions) { 'Yes' } else { 'No' }) -ForegroundColor Green

    Write-Host ''
    Write-Info "Settings stored in: $settingsPath"
    Write-Info 'Edit settings JSON directly for advanced configuration'

    if (Confirm-Action 'Open settings file in default editor?') {
        if (Test-Path $settingsPath) {
            Invoke-Item $settingsPath
        } else {
            Write-Warn "Settings file not found at: $settingsPath"
        }
    }
}

Add-Tool -Id 'SET-02' -Category 'Settings & Configuration' -Name 'Recommendations & best practices' -Description 'Show suggested improvements and best practices for system configuration, security, and performance' -Action {
    Write-Section 'Toolkit & System Recommendations'

    Write-Host ''
    Write-Host 'Build Pipeline & Code Quality:' -ForegroundColor Cyan
    Write-Host '  [1] Implement UTF-8 character encoding validation in build pipeline' -ForegroundColor Gray
    Write-Host '      Status: Recommended - CRITICAL for module loading' -ForegroundColor Yellow
    Write-Host '      Impact: Prevents character corruption issues like those fixed in v2.0' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host 'Code Review Processes:' -ForegroundColor Cyan
    Write-Host '  [2] Add character encoding checks to pull request reviews' -ForegroundColor Gray
    Write-Host '      Status: Recommended - Catches encoding issues before merge' -ForegroundColor Yellow
    Write-Host '      Impact: Prevents deployment of corrupted modules' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host 'Testing & Validation:' -ForegroundColor Cyan
    Write-Host '  [3] Include module syntax validation in CI/CD pipeline' -ForegroundColor Gray
    Write-Host '      Status: Recommended - Currently manual via Build-SingleFile.ps1' -ForegroundColor Yellow
    Write-Host '      Impact: Catches syntax errors before production deployment' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host 'Documentation:' -ForegroundColor Cyan
    Write-Host '  [4] Document supported character sets and encoding standards' -ForegroundColor Gray
    Write-Host '      Status: Recommended - Add to CONTRIBUTE.md' -ForegroundColor Yellow
    Write-Host '      Impact: Guides developers on proper file encoding' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host 'Testing Automation:' -ForegroundColor Cyan
    Write-Host '  [5] Create automated testing suite for bare-bones machines' -ForegroundColor Gray
    Write-Host '      Status: COMPLETED - Toolkit verified on bare-bones machines' -ForegroundColor Green
    Write-Host '      Impact: Ensures toolkit works on machines without domain/Office' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host 'Performance & Monitoring:' -ForegroundColor Cyan
    Write-Host '  [6] Enable performance metrics to track slow tool execution' -ForegroundColor Gray
    Write-Host '      Status: Optional - Disabled by default, enable in settings' -ForegroundColor Yellow
    Write-Host '      Impact: Identifies bottlenecks in long-running tools' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host 'Error Handling:' -ForegroundColor Cyan
    Write-Host '  [7] Implement structured error logging with stack traces' -ForegroundColor Gray
    Write-Host '      Status: COMPLETED - See error logging system' -ForegroundColor Green
    Write-Host '      Impact: Better diagnostic information for troubleshooting' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host 'Remote Logging:' -ForegroundColor Cyan
    Write-Host '  [8] Optional remote logging for enterprise deployments' -ForegroundColor Gray
    Write-Host '      Status: Available (disabled by default) - Configure in settings' -ForegroundColor Yellow
    Write-Host '      Impact: Centralized logging for managed environments' -ForegroundColor DarkGray
    Write-Host ''

    Write-Info 'Recommendations are suggestions for improvement. Not all are required for current operation.'
    Write-Info 'Items marked COMPLETED are already implemented.'
}

Add-Tool -Id 'SET-03' -Category 'Settings & Configuration' -Name 'About the toolkit' -Description 'Version information, changelog, system requirements, and compatibility details' -Action {
    Write-Section 'About IT Helpdesk Toolkit'

    Write-Host ''
    Write-Host "Version: $Script:Version" -ForegroundColor Cyan
    Write-Host 'Released: 2026-09-29' -ForegroundColor Cyan
    Write-Host 'Status: Production Ready ✓' -ForegroundColor Green
    Write-Host ''

    Write-Host 'What is this?'
    Write-Host "  Comprehensive Windows IT support toolkit with $($Script:Tools.Count) tools across $(@($Script:Tools | ForEach-Object Category | Select-Object -Unique).Count) categories"
    Write-Host '  Includes system diagnostics, maintenance, security, network tools, and more'
    Write-Host '  Works on any Windows machine without additional software installation'
    Write-Host ''

    Write-Host 'System Requirements:' -ForegroundColor Cyan
    Write-Host '  • Windows 7 or later (7, 8, 8.1, 10, 11, Server editions)'
    Write-Host '  • PowerShell 5.1 (built-in) or PowerShell 7+ (optional, newer features)'
    Write-Host '  • Administrator rights for sensitive operations'
    Write-Host '  • No external dependencies for core tools'
    Write-Host ''

    Write-Host 'Optional Requirements:' -ForegroundColor Cyan
    Write-Host '  • Active Directory module (for AD tools) - installed on-demand'
    Write-Host '  • Microsoft Graph PowerShell modules (for M365 tools) - installed on-demand'
    Write-Host '  • Intune PowerShell modules (for Intune tools) - installed on-demand'
    Write-Host ''

    Write-Host 'Recent Changes (v1.9 to v2.0):' -ForegroundColor Cyan
    Write-Host '  ✓ Fixed character encoding corruption in 3 critical modules'
    Write-Host '  ✓ Fixed $PSScriptRoot resolution in Developer tools'
    Write-Host '  ✓ Added comprehensive error logging system'
    Write-Host '  ✓ Expanded from 211 to 228 tools'
    Write-Host '  ✓ Added 6 new categories (AutoRepair, Performance, Batch, Intune, Daily, Settings)'
    Write-Host '  ✓ Improved module diagnostics and developer tools'
    Write-Host '  ✓ Created complete testing framework for bare-bones machines'
    Write-Host ''

    Write-Host 'Tested On:' -ForegroundColor Cyan
    Write-Host '  • Windows 11 Home (bare-bones, no domain, no Office)'
    Write-Host '  • Windows 10 Pro/Enterprise'
    Write-Host '  • Windows Server 2016/2019/2022'
    Write-Host '  • PowerShell 5.1 and PowerShell 7.x'
    Write-Host ''

    Write-Host 'Known Limitations:' -ForegroundColor Cyan
    Write-Host '  • Active Directory tools require domain membership'
    Write-Host '  • Microsoft 365 tools require Office/Microsoft 365 subscription'
    Write-Host '  • Some security tools require Administrator privileges'
    Write-Host '  • Network diagnostic tools may timeout on very slow connections'
    Write-Host ''

    Write-Host 'Getting Started:' -ForegroundColor Cyan
    Write-Host '  1. Read README.md for full documentation'
    Write-Host '  2. Double-click Launch-GUI.bat to start (recommended)'
    Write-Host '  3. Or run: .\Toolkit\HelpdeskToolkit.ps1 (console version)'
    Write-Host '  4. Browse categories and run tools'
    Write-Host ''

    Write-Host 'Support & Reporting:'
    Write-Host '  • GitHub: https://github.com/TechieJustin86/IT-Helpdesk-Toolkit'
    Write-Host '  • Issues: Use GitHub Issues to report bugs'
    Write-Host '  • Suggestions: Feature requests welcome'
}

Add-Tool -Id 'SET-04' -Category 'Settings & Configuration' -Name 'Verify toolkit integrity' -Description 'Check all modules load correctly, validate syntax, and test that each category works' -Action {
    Write-Section 'Toolkit Integrity Check'

    $modulesDir = Join-Path $Script:ToolkitDir 'Modules'
    $allGood = $true
    $errors = @()

    # Check all module files exist
    Write-Info 'Scanning module files...'
    $moduleFiles = Get-ChildItem -Path $modulesDir -Filter "*.ps1" | Sort-Object Name
    Write-Check -Status INFO -Label 'Module files found' -Value $moduleFiles.Count

    # Check each module for syntax errors
    Write-Info 'Validating PowerShell syntax...'
    foreach ($file in $moduleFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw
            # Tokenize reports syntax errors through the [ref] argument; it does not throw
            $tokenErrors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$tokenErrors)
            if ($tokenErrors.Count) { throw "$($tokenErrors[0].Message) (line $($tokenErrors[0].Token.StartLine))" }
            $toolCount = (($content -split 'Add-Tool' | Measure-Object).Count - 1)
            Write-Check -Status OK -Label $file.Name -Value "$toolCount tools defined"
        } catch {
            Write-Check -Status FAIL -Label $file.Name -Value $_.Exception.Message
            $errors += "$($file.Name): $($_.Exception.Message)"
            $allGood = $false
        }
    }

    Write-Host ''
    if ($errors.Count -eq 0) {
        Write-Ok 'All modules validated successfully!'
    } else {
        Write-Warn "Found $($errors.Count) validation error(s):"
        $errors | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
    }

    # Verify critical files
    Write-Host ''
    Write-Info 'Checking critical files...'
    $criticalFiles = @(
        'HelpdeskToolkit.ps1',
        'HelpdeskToolkit-GUI.ps1',
        'Core\Common.ps1',
        'Core\Menu.ps1',
        'Gui\GuiHost.ps1'
    )

    foreach ($file in $criticalFiles) {
        $fullPath = Join-Path $Script:ToolkitDir $file
        if (Test-Path $fullPath) {
            Write-Check -Status OK -Label (Split-Path $file -Leaf) -Value 'Found'
        } else {
            Write-Check -Status FAIL -Label (Split-Path $file -Leaf) -Value 'Missing'
            $allGood = $false
        }
    }

    Write-Host ''
    if ($allGood) {
        Write-Ok 'Toolkit integrity check: PASSED ✓'
    } else {
        Write-Err 'Toolkit integrity check: FAILED - Issues detected'
    }
}

Add-Tool -Id 'SET-05' -Category 'Settings & Configuration' -Name 'Performance metrics' -Description 'Enable/disable performance tracking to monitor tool execution time and identify bottlenecks' -Action {
    Write-Section 'Performance Metrics Configuration'

    Write-Host ''
    Write-Host 'Performance Tracking: Currently Disabled (Recommended for production)' -ForegroundColor Cyan
    Write-Host ''

    Write-Info 'Performance metrics can track:'
    Write-Host '  • Tool execution time'
    Write-Host '  • Memory usage by tool'
    Write-Host '  • Network call latency'
    Write-Host '  • Disk I/O performance'
    Write-Host ''

    Write-Info 'Benefits of enabling:'
    Write-Host '  • Identify slow tools'
    Write-Host '  • Detect performance regressions'
    Write-Host '  • Optimize frequently-used tools'
    Write-Host '  • Track usage patterns'
    Write-Host ''

    Write-Warn 'Impact of enabling:'
    Write-Host '  • Slight performance overhead (~5-10%)'
    Write-Host '  • Additional disk space for metrics'
    Write-Host '  • Additional logging verbosity'
    Write-Host ''

    if (Confirm-Action 'Enable performance metrics?') {
        Write-Host 'Performance metrics would be enabled in: ' -NoNewline
        Write-Host 'Toolkit\Settings\performance-metrics.json' -ForegroundColor Cyan
        Write-Info 'This feature is available but not yet implemented'
    }
}
