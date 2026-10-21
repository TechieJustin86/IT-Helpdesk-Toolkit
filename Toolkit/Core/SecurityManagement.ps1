<#
.SYNOPSIS
    Core module: the audit trail
.DESCRIPTION
    Records every tool run - who, which computer, when, elevated or not, and the
    outcome - in Logs\toolkit-audit.json. Both tool runners (Invoke-Tool in Menu.ps1
    and Invoke-GuiTool in Gui\GuiHost.ps1) call Log-AuditEvent; TKA-05 reports it.

    Nothing in the log is masked. This file used to also hold credential caching,
    log masking, remote-operation confirmation and credential validation functions;
    no tool called any of them, so they were removed. The toolkit stores no credentials.
.FUNCTIONS
    - Log-AuditEvent: record one tool run (last 500 kept)
.NOTES
    Loaded fourth by HelpdeskToolkit.ps1 and HelpdeskToolkit-GUI.ps1.
    Do not run directly.
#>

$Script:AuditLog = Join-Path $Script:LogDir 'toolkit-audit.json'

function Log-AuditEvent {
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$ToolId,
        [string]$Target = '',
        [string]$Status = 'Success',
        [string]$Details = ''
    )

    try {
        if (-not (Test-Path -LiteralPath $Script:LogDir)) {
            New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null
        }

        $entry = @{
            Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            User = "$env:USERDOMAIN\$env:USERNAME"
            Computer = $env:COMPUTERNAME
            Action = $Action
            ToolId = $ToolId
            Target = $Target
            Status = $Status
            Details = $Details
            IsAdmin = (Test-IsAdmin)
        }

        Add-JsonLogEntry -Path $Script:AuditLog -Entry $entry -MaxEntries 500 -Depth 4
    } catch {
        Write-Log "Audit logging failed: $_"
    }
}
