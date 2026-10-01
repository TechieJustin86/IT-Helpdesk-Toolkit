# Modules\14-QuickLaunch.ps1
# Category: Quick Launch
# Loaded by HelpdeskToolkit.ps1 (dot-sourced). Do not run directly.

$quick = @(
    @('QL-01', 'Device Manager', 'devmgmt.msc', ''),
    @('QL-02', 'Services', 'services.msc', ''),
    @('QL-03', 'Event Viewer', 'eventvwr.msc', ''),
    @('QL-04', 'Computer Management', 'compmgmt.msc', ''),
    @('QL-05', 'Disk Management', 'diskmgmt.msc', ''),
    @('QL-06', 'Task Scheduler', 'taskschd.msc', ''),
    @('QL-07', 'Local Users and Groups', 'lusrmgr.msc', ''),
    @('QL-08', 'Group Policy Editor', 'gpedit.msc', ''),
    @('QL-09', 'Network Connections', 'ncpa.cpl', ''),
    @('QL-10', 'Programs and Features', 'appwiz.cpl', ''),
    @('QL-11', 'Printers', 'control.exe', 'printers'),
    @('QL-12', 'System Properties', 'sysdm.cpl', ''),
    @('QL-13', 'Credential Manager', 'control.exe', '/name Microsoft.CredentialManager'),
    @('QL-14', 'Resource Monitor', 'resmon.exe', ''),
    @('QL-15', 'Performance Monitor', 'perfmon.exe', ''),
    @('QL-16', 'System Information', 'msinfo32.exe', ''),
    @('QL-17', 'Registry Editor', 'regedit.exe', ''),
    @('QL-18', 'Windows Update', 'ms-settings:windowsupdate', ''),
    @('QL-19', 'Power Options', 'powercfg.cpl', ''),
    @('QL-20', 'Sound', 'mmsys.cpl', ''),
    @('QL-21', 'Remote Desktop client', 'mstsc.exe', ''),
    @('QL-22', 'Certificates (user)', 'certmgr.msc', ''),
    @('QL-23', 'Quick Assist', 'ms-quick-assist:', ''),
    @('QL-24', 'Network settings', 'ms-settings:network', '')
)
foreach ($q in $quick) {
    $cmd = if ($q[3]) { "Start-Process -FilePath '$($q[2])' -ArgumentList '$($q[3])'" } else { "Start-Process -FilePath '$($q[2])'" }
    Add-Tool -Id $q[0] -Category 'Quick Launch' -Name $q[1] -Description ("Open $($q[2]) $($q[3])").Trim() -Action ([scriptblock]::Create($cmd))
}
