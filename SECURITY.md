# Security Policy

## Supported Versions

| Version | Supported          | Status |
|---------|-------------------|--------|
| 1.5.x   | ✅ Yes            | Current |
| 1.4.x   | ⚠️ Limited         | Maintenance |
| < 1.4   | ❌ No             | Unsupported |

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

## Security Features

The IT Helpdesk Toolkit includes built-in security features:

### 🔐 Credential Management
- Credentials cached using Windows Credential Manager (DPAPI encrypted)
- Automatic expiration after configured time
- Never logged in plain text
- Credential validation before use

### 📋 Audit Trail
- Complete audit log of all operations
- Tracks: action, user, computer, timestamp, admin status
- Stored in `Documents\HelpdeskToolkit\toolkit-audit.json`
- Last 500 events retained

### ✅ Input Validation
- IP address validation
- Computer name validation
- UNC path validation
- Email format validation
- Port number range checking
- Remote connectivity verification

### ⚠️ Destructive Action Confirmation
- All destructive operations require explicit confirmation
- User must type "DELETE", "YES", or similar acknowledgment
- Operations logged with confirmation evidence

### 🛡️ Privilege Management
- Built-in admin elevation detection
- Admin-only tools clearly marked
- Non-destructive mode for standard users
- Admin status tracked in audit log

### 🔍 Error Logging
- Full error context captured:
  - Stack traces
  - Inner exceptions
  - Execution context (OS, PS version, admin status)
  - Source location (file, line number)
- Sensitive data automatically masked
- Error logs accessible only to local user

## Security Best Practices for Users

### Installation
1. **Unblock downloaded files**:
   ```powershell
   Get-ChildItem -Recurse *.ps1 | Unblock-File
   ```

2. **Review before execution**:
   - Read the tool description
   - Understand what it does
   - Check for required permissions

3. **Keep updated**:
   - Check for newer versions regularly
   - Apply security patches immediately

### Usage
1. **Run with appropriate permissions**:
   - Standard user for read-only tools
   - Administrator only when needed for changes

2. **Monitor audit trail**:
   - Run `TKA-05` periodically to review actions
   - Watch for unauthorized activity

3. **Secure log files**:
   - Logs in `Documents\HelpdeskToolkit\` may contain sensitive info
   - Restrict access to authorized personnel
   - Rotate/archive old logs regularly

4. **Credential security**:
   - Don't write credentials on screen
   - Use tool password dialogs (masked input)
   - Credentials expire after configured time
   - Clear credentials on logout

### Remote Operations
1. **Network security**:
   - Tools work over network with proper credentials
   - WinRM and RPC/DCOM available
   - Consider network encryption for sensitive data

2. **Target system security**:
   - Ensure target systems are trusted
   - Verify credentials for sensitive operations
   - Check SMB signing when available

3. **Audit remote access**:
   - All remote operations logged
   - Review audit trail for unexpected activity
   - Check target system logs for coordination

## Security Configuration

Edit `Toolkit\Core\Config.ps1` to adjust security settings:

```powershell
$Script:Config = @{
    Security = @{
        # Require confirmation for destructive operations
        RequireConfirmDestructive = $true
        
        # Never log passwords, tokens, keys
        MaskCredentialsInLogs = $true
        
        # Log all remote operations
        LogRemoteOperations = $true
        
        # Credential cache expiration (hours)
        CredentialExpirationHours = 8
    }
}
```

## Known Security Considerations

### Windows Credential Manager
- Credentials stored using Windows native DPAPI
- Protected by Windows security
- Lost if user password changes
- Consider credential refresh for long sessions

### Audit Log Retention
- Limited to last 500 entries (configurable)
- Use `TKA-04` to archive old entries
- Consider forwarding to central logging system

### Local File Access
- Tools operate with user's file permissions
- Cannot access files user shouldn't see
- Respect Windows NTFS permissions

### Remote Access
- Requires valid credentials on target system
- Respects target system security policies
- Limited by WinRM/RPC access restrictions

## Vulnerability Disclosure

When we receive a security report:

1. **Verification**: We verify the vulnerability
2. **Assessment**: We assess impact and severity
3. **Development**: We develop a fix
4. **Testing**: We test the fix thoroughly
5. **Release**: We release a patch
6. **Disclosure**: We publish security advisory
7. **Credit**: We credit the reporter (if desired)

### Security Advisories

Security fixes are released as:
- **Hotfix releases** for critical issues (v1.5.1, v1.5.2, etc.)
- **Point releases** for high-priority issues (v1.6)
- **Release notes** include security sections

All releases include information about:
- What vulnerability was fixed
- Who is affected
- Update instructions
- Workarounds (if available)

## Security Testing

We regularly test for:
- ✅ PowerShell injection
- ✅ Privilege escalation
- ✅ Credential exposure
- ✅ Remote code execution
- ✅ Information disclosure
- ✅ Denial of service
- ✅ Configuration mistakes

## Dependencies Security

The toolkit has minimal dependencies:
- **PowerShell 5.1+** (built-in to Windows)
- **Optional**: Active Directory PowerShell module (Microsoft-provided)
- **Optional**: Microsoft Graph PowerShell (Microsoft-provided)

All dependencies are from Microsoft and automatically validated.

## Compliance

The toolkit helps with security compliance:
- **Audit logging** for compliance audits
- **Credential protection** for data security
- **Destructive action confirmation** for change control
- **Security status checks** for compliance scanning

### Supported Compliance Frameworks
- Windows Security Baselines
- CIS Benchmarks
- NIST guidelines
- HIPAA security requirements
- PCI-DSS requirements

## Security Contact

**Email**: jjeschette@gmail.com  
**Response**: Within 48 hours for security reports

## Acknowledgments

We thank the security community for responsible disclosure of vulnerabilities.

---

**Last Updated**: October 2026  
**Version**: 1.5  
**Status**: Current
