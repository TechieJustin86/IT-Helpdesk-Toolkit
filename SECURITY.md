# Security Policy

## Supported Versions

Only the latest code on the `master` branch is supported. There are no tagged releases or maintenance branches yet, so security fixes land on `master` and are recorded in [docs/CHANGELOG.md](docs/CHANGELOG.md).

## Reporting Security Vulnerabilities

**Do not create public GitHub issues for security vulnerabilities.**

Instead, please report security issues privately by emailing: **jjeschette@gmail.com**

Include in your report:
- Description of the vulnerability
- Affected component(s)
- Steps to reproduce (if applicable)
- Potential impact
- Suggested fix (if you have one)

**Response timeline:**
- Acknowledgment: Within 48 hours
- Assessment: Within 1 week
- Fix/patch: Varies by severity (see below)

### Severity Levels

| Severity | Description | Timeline |
|----------|-------------|----------|
| **Critical** | Remote code execution, credential exposure, full system compromise | Patch within 24-48 hours |
| **High** | Significant privilege escalation, data disclosure | Patch within 1 week |
| **Medium** | Limited impact, specific conditions required | Patch within 2 weeks |
| **Low** | Minor issues, minimal impact | Include in next release |

## What the Toolkit Does

### 🛡️ Administrator-only tools
- Tools that need Administrator rights are marked `admin`.
- The tool runners refuse them until the toolkit runs elevated.
- Whether a run was elevated is recorded in the audit trail.

### ⚠️ Confirmation before destructive actions
- Destructive actions ask for confirmation first.
- Irreversible ones make the user type `yes`: emptying the Recycle Bin, deleting a user profile, removing saved credentials, an immediate restart of this PC, restarting or shutting down a remote PC or several at once, logging off a session, and ending processes with unsaved work.
- Deleting a local user requires typing `DELETE`, and the built-in and signed-in accounts are protected.
- Answering no, or cancelling a prompt, changes nothing.

### 📋 Audit trail
- Every tool run is recorded: the tool, the account that ran it, the computer, the time, whether it was elevated, and the outcome (Success, Failed, Cancelled or Blocked).
- Stored in `Toolkit\Logs\toolkit-audit.json`, last 500 entries. **TKA-05** reports it.
- It records the computer the toolkit runs on, not the target of a remote tool. When the toolkit is elevated with a separate admin account, it records that admin account.

### 🔍 Error log
- Failures are recorded with the message, exception type, stack trace, script line, and admin, OS and PowerShell context.
- Stored in `Toolkit\Logs\toolkit-errors.json`, last 200 entries by default. **DEV-06** shows it and **TKA-04** cleans it up.

### 🔑 No stored credentials
- The toolkit does not save passwords or other credentials.
- Password prompts use masked input.
- Remote tools use your current Windows login.

## What the Toolkit Does Not Do

Read this before relying on the toolkit in a sensitive environment.

- **It does not mask anything in its logs.** The log, error log and audit trail contain user names, computer names and the details of whatever failed. Treat `Toolkit\Logs\` as sensitive.
- **It does not restrict who can read its logs.** They inherit the permissions of the folder the toolkit is in. On a flash drive formatted FAT32 or exFAT there are no file permissions at all, so anyone with the drive can read them.
- **Some tools show secrets on screen when you ask them to:** saved Wi-Fi keys, BitLocker recovery keys and the Windows product key. They stay in the output pane unless you save or copy it.
- **It is not signed.** `Launch-GUI.bat` runs it with `-ExecutionPolicy Bypass`, which cannot override an execution policy set by Group Policy, so it will not run where policy requires signed scripts.
- **It is not a compliance tool.** The audit trail and security checks can help gather evidence, but no tool maps to CIS, NIST, HIPAA, PCI-DSS or any other framework, and the toolkit has not been assessed against one.

## Security Best Practices for Users

### Installation
1. **Unblock downloaded files**, from inside the `Toolkit` folder:
   ```powershell
   Get-ChildItem -Recurse | Unblock-File
   ```

2. **Review before execution**:
   - Read the tool description
   - Understand what it does
   - Check for required permissions

3. **Keep updated**:
   - Pull or download the latest `master` regularly

### Usage
1. **Run with appropriate permissions**:
   - Standard user for read-only tools
   - Administrator only when needed for changes
   - If you elevate with a separate admin account, tools that work on per-user data act on that admin's profile, not the user's

2. **Monitor the audit trail**:
   - Run `TKA-05` periodically to review actions
   - Watch for unexpected activity

3. **Protect the log files**:
   - `Toolkit\Logs\` and `Documents\HelpdeskToolkit\` contain user and computer names and other details
   - Keep a flash drive carrying the toolkit somewhere safe
   - Delete old logs you no longer need

4. **Secrets on screen**:
   - Don't run tools that reveal keys or passwords while someone else can see the screen
   - Clear the output pane afterwards (`Ctrl+L`)

### Remote Operations
1. **Network security**:
   - Remote tools use your Windows login over WinRM, falling back to RPC/DCOM
   - You need admin rights on the target PC

2. **Target system security**:
   - Ensure target systems are trusted
   - Check SMB signing when available

3. **Audit remote access**:
   - Runs of remote tools are recorded in the audit trail, without the target name
   - Check the target system's own logs for what was done there

## Vulnerability Disclosure

When we receive a security report:

1. **Verification**: We verify the vulnerability
2. **Assessment**: We assess impact and severity
3. **Development**: We develop a fix
4. **Testing**: We test the fix
5. **Release**: We merge the fix to `master`
6. **Disclosure**: We note the fix in the CHANGELOG
7. **Credit**: We credit the reporter (if desired)

## Security Checks

Every pull request that changes a `.ps1` file or `README.md` runs these checks in GitHub Actions:

- Every script must parse
- Scripts containing non-ASCII text must be saved as UTF-8 with BOM
- Every module must load, with valid and unique tool IDs
- PSScriptAnalyzer, failing on Error-severity findings

GitHub secret scanning and push protection are enabled for the repository. Every commit is also checked by hand for credentials, real server names and other private details before it is pushed. There is no penetration testing.

## Dependencies

The toolkit needs only what Windows includes: Windows PowerShell 5.1 and WPF for the GUI. Some tools download software when you ask them to:

- **RSAT Active Directory tools** (AD-02): installed by Windows from Windows Update or your organisation's update source
- **Microsoft Graph PowerShell modules** (M365-02): from the PowerShell Gallery, published by Microsoft. It installs the NuGet package provider first if it is missing.
- **Applications through winget** (APP-02, APP-11): from the winget repository. Most are third-party software, such as browsers, 7-Zip and Zoom.

The toolkit does not check these downloads itself; it relies on Windows, the PowerShell Gallery and winget.

## Security Contact

**Email**: jjeschette@gmail.com
**Response**: Within 48 hours for security reports

## Acknowledgments

We thank the security community for responsible disclosure of vulnerabilities.

---

**Last Updated**: October 19, 2026
