# Gui\GuiHost.ps1
# Loaded last into the GUI's background runspace (after Core\ and Modules\).
# Replaces the console input/output helpers so the unchanged tools talk to the window instead:
#   Write-Host / Out-Host  -> output pane (colours kept)
#   Read-Host              -> input dialog (password box for -AsSecureString)
#   Confirm-Action         -> Yes/No dialog
#   Select-FromList        -> list picker dialog
#   Invoke-External        -> runs the program hidden and streams its output into the pane
# Messages go through $HdtSync.Queue, which the window drains on a timer. Prompts block this
# thread on an event until the window has shown the dialog and stored the answer.

$Script:GuiRecent = New-Object System.Collections.Generic.List[string]

function Send-GuiMessage {
    param([hashtable]$Message)
    $HdtSync.Queue.Enqueue($Message)
}

function Write-GuiText {
    param([string]$Text, [string]$Color = '', [switch]$NoNewline)
    Send-GuiMessage @{ Kind = 'text'; Text = $Text; Color = $Color; NewLine = (-not $NoNewline) }
}

function Write-Host {
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]$Object,
        [object]$ForegroundColor,
        [object]$BackgroundColor,
        [switch]$NoNewline,
        [object]$Separator = ' '
    )
    $text = (@($Object) | ForEach-Object { "$_" }) -join $Separator
    Write-GuiText -Text $text -Color "$ForegroundColor" -NoNewline:$NoNewline
    # Remember recent lines so an input dialog can show the menu that was just printed
    if ($text.Trim()) {
        $Script:GuiRecent.Add($text.TrimEnd())
        while ($Script:GuiRecent.Count -gt 12) { $Script:GuiRecent.RemoveAt(0) }
    }
}

function Out-Host {
    param([Parameter(ValueFromPipeline = $true)]$InputObject, [switch]$Paging)
    begin   { $buffer = New-Object System.Collections.Generic.List[object] }
    process { if ($null -ne $InputObject) { $buffer.Add($InputObject) } }
    end {
        if ($buffer.Count) {
            $text = ($buffer | Out-String -Width 160).Trim([char[]]"`r`n")
            if ($text) { Write-GuiText $text }
        }
    }
}

function Clear-Host { }
function Wait-Key { }

function Request-GuiInput {
    param([string]$Kind, [string]$Prompt, [string[]]$Items)
    $req = @{
        Kind       = 'prompt'
        PromptKind = $Kind
        Prompt     = "$Prompt".Trim()
        Items      = $Items
        Context    = @($Script:GuiRecent)
        Result     = $null
        Done       = New-Object System.Threading.ManualResetEventSlim($false)
    }
    $Script:GuiRecent.Clear()
    $HdtSync.Queue.Enqueue($req)
    $req.Done.Wait()
    $req.Result
}

function Read-Host {
    param([Parameter(Position = 0)][object]$Prompt, [switch]$AsSecureString, [switch]$MaskInput)
    if ($AsSecureString -or $MaskInput) {
        $r = Request-GuiInput -Kind 'secure' -Prompt "$Prompt"
        if ($null -eq $r) { throw (New-Object System.OperationCanceledException 'Cancelled by user.') }
        return $r
    }
    $r = Request-GuiInput -Kind 'input' -Prompt "$Prompt"
    if ($null -eq $r) { throw (New-Object System.OperationCanceledException 'Cancelled by user.') }
    $r
}

function Confirm-Action {
    param([string]$Message)
    $result = Request-GuiInput -Kind 'confirm' -Prompt $Message
    if ($null -eq $result) { throw (New-Object System.OperationCanceledException 'Cancelled by user.') }
    [bool]$result
}

function Select-FromList {
    param([object[]]$Items, [scriptblock]$Label, [string]$Prompt = 'Select')
    $Items = @($Items)
    if ($Items.Count -eq 0) { Write-Warn 'Nothing to select.'; return $null }
    $labels = @(foreach ($item in $Items) { "$(@($item | ForEach-Object $Label) -join ' ')" })
    $idx = Request-GuiInput -Kind 'select' -Prompt $Prompt -Items $labels
    if ($null -eq $idx) { throw (New-Object System.OperationCanceledException 'Cancelled by user.') }
    if ([int]$idx -ge 0 -and [int]$idx -lt $Items.Count) { return $Items[[int]$idx] }
    $null
}

function Invoke-External {
    param([Parameter(Mandatory)][string]$FilePath, [string]$Arguments = '')
    Write-GuiText "  > $FilePath $Arguments" 'DarkGray'
    $resolved = Get-Command $FilePath -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = if ($resolved) { $resolved.Source } else { $FilePath }
    $psi.Arguments              = $Arguments
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    # sfc writes UTF-16 when its output is redirected
    if ([IO.Path]::GetFileNameWithoutExtension($FilePath) -eq 'sfc') { $psi.StandardOutputEncoding = [Text.Encoding]::Unicode }

    $p = [System.Diagnostics.Process]::Start($psi)
    $HdtSync.CurrentProcess = $p
    try {
        $errTask = $p.StandardError.ReadToEndAsync()
        $lastBlank = $false
        while ($null -ne ($line = $p.StandardOutput.ReadLine())) {
            $clean = $line.Replace([string][char]0, '').TrimEnd()
            if ($clean -match '^\s*[-\\|/]\s*$') { continue }                                   # spinner characters
            if ($clean -match '^\s*\[?[= ]*\d+(\.\d+)?%' -or ($clean.Length -lt 90 -and $clean -match '\d+(\.\d+)?\s*%\s*(complete)?\.?\s*\]?$')) {
                Send-GuiMessage @{ Kind = 'progress'; Text = $clean.Trim(' ', '[', ']', '=') }  # progress lines go to the status bar
                continue
            }
            if (-not $clean.Trim()) { if ($lastBlank) { continue }; $lastBlank = $true } else { $lastBlank = $false }
            Write-GuiText $clean
        }
        $p.WaitForExit()
        $err = $errTask.Result
        if ($err -and $err.Trim()) { Write-GuiText $err.Trim() 'Red' }
        Send-GuiMessage @{ Kind = 'progress'; Text = '' }
        $p.ExitCode
    } finally {
        
        $HdtSync.CurrentProcess = $null
    }
}

function Invoke-GuiTool {
    param([string]$Id)
    $tool = $Script:Tools | Where-Object Id -eq $Id | Select-Object -First 1
    if (-not $tool) { Write-Err "Unknown tool '$Id'."; return }
    if ($tool.Admin -and -not (Test-IsAdmin)) {
        Write-Warn 'This tool requires Administrator rights. Use "Restart as Administrator" at the top of the window.'
        return
    }
    $Script:GuiRecent.Clear()
    $Script:CurrentTool = $tool
    Write-Log "RUN $($tool.Id) $($tool.Name) (GUI)"
    Write-ToolUsage -ToolId $tool.Id -ToolName $tool.Name -Category $tool.Category
    try {
        & $tool.Action 2>&1 3>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                Write-Err $_.Exception.Message
                Write-ErrorLog -ToolId $tool.Id -ToolName $tool.Name -ErrorRecord $_
            }
            elseif ($_ -is [System.Management.Automation.WarningRecord]) { Write-Warn $_.Message }
            else { $_ }
        } | Out-Host
    } catch [System.OperationCanceledException] {
        # Cancel in an input dialog is not a failure: keep it out of the error log
        Write-Warn 'Cancelled.'
        Write-Log "CANCELLED $($tool.Id)"
    } catch {
        Write-Err $_.Exception.Message
        Write-ErrorLog -ToolId $tool.Id -ToolName $tool.Name -ErrorRecord $_
        Write-Log "ERROR $($tool.Id): $($_.Exception.Message)"
    }
    $Script:CurrentTool = $null
}
