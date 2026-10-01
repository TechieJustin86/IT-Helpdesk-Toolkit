#requires -Version 5.1

<#
Input & Hardware Diagnostics v8.0.0

Portable Windows diagnostic utility for keyboards, mice, trackpads,
touchscreens, XInput game controllers, and practical system information.

Privacy and behavior:
- Does not reconstruct or save typed text.
- Does not write logs to disk.
- Captures only key identity, scan code, modifier state, shortcuts, mouse buttons, and wheel activity.
- Controller state and Windows hardware information are queried only while their tools are open.
- Capture stops automatically if the window is minimized or closed.
- Ctrl+Alt+Delete and other secure-desktop input cannot be captured by normal applications.
#>

try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
    [System.Windows.Forms.Application]::EnableVisualStyles()
} catch {
    Write-Error "Failed to load System.Windows.Forms: $_"
    exit 1
}

# This tool has no need for administrator rights, and a global keyboard hook
# running elevated is a larger blast radius than necessary. Refuse to continue
# if launched from an elevated session.
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
if ($currentPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    [System.Windows.Forms.MessageBox]::Show(
        "This tool must not be run as Administrator.`n`nPlease close this window and relaunch it from a normal (non-elevated) PowerShell session.",
        'Elevated Session Blocked',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    exit 1
}

if (-not ("GlobalInputDiagnostics" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class GlobalInputDiagnostics
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WH_MOUSE_LL = 14;

    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;

    private const int WM_LBUTTONDOWN = 0x0201;
    private const int WM_LBUTTONUP = 0x0202;
    private const int WM_RBUTTONDOWN = 0x0204;
    private const int WM_RBUTTONUP = 0x0205;
    private const int WM_MBUTTONDOWN = 0x0207;
    private const int WM_MBUTTONUP = 0x0208;
    private const int WM_MOUSEMOVE = 0x0200;
    private const int WM_MOUSEWHEEL = 0x020A;
    private const int WM_MOUSEHWHEEL = 0x020E;
    private const int WM_XBUTTONDOWN = 0x020B;
    private const int WM_XBUTTONUP = 0x020C;

    private static IntPtr keyboardHook = IntPtr.Zero;
    private static IntPtr mouseHook = IntPtr.Zero;
    private static readonly LowLevelKeyboardProc keyboardProc = KeyboardCallback;
    private static readonly LowLevelMouseProc mouseProc = MouseCallback;
    private static readonly ConcurrentQueue<string> queue = new ConcurrentQueue<string>();
    private static readonly HashSet<int> keysDown = new HashSet<int>();
    private static readonly object syncRoot = new object();

    public static bool IsRunning { get; private set; }
    public static bool TrackpadTrackingEnabled { get; set; }

    public static bool Start()
    {
        if (IsRunning) return true;

        using (Process process = Process.GetCurrentProcess())
        using (ProcessModule module = process.MainModule)
        {
            IntPtr moduleHandle = GetModuleHandle(module.ModuleName);
            keyboardHook = SetWindowsHookExKeyboard(WH_KEYBOARD_LL, keyboardProc, moduleHandle, 0);
            mouseHook = SetWindowsHookExMouse(WH_MOUSE_LL, mouseProc, moduleHandle, 0);
        }

        IsRunning = keyboardHook != IntPtr.Zero && mouseHook != IntPtr.Zero;

        if (!IsRunning)
        {
            Stop();
            return false;
        }

        Enqueue("SYS|START");
        return true;
    }

    public static void Stop()
    {
        if (keyboardHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(keyboardHook);
            keyboardHook = IntPtr.Zero;
        }

        if (mouseHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(mouseHook);
            mouseHook = IntPtr.Zero;
        }

        lock (syncRoot)
        {
            keysDown.Clear();
        }

        if (IsRunning) Enqueue("SYS|STOP");
        IsRunning = false;
    }

    public static bool TryGetEvent(out string value)
    {
        return queue.TryDequeue(out value);
    }

    public static void ClearQueue()
    {
        string ignored;
        while (queue.TryDequeue(out ignored)) { }
    }

    public static string GetForegroundWindowInfo()
    {
        IntPtr handle = GetForegroundWindow();
        if (handle == IntPtr.Zero) return "Unknown|";

        StringBuilder title = new StringBuilder(512);
        GetWindowText(handle, title, title.Capacity);

        uint processId;
        GetWindowThreadProcessId(handle, out processId);

        string processName = "Unknown";
        try
        {
            processName = Process.GetProcessById((int)processId).ProcessName;
        }
        catch { }

        return processName + "|" + title.ToString().Replace("|", "/");
    }

    private static IntPtr KeyboardCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && IsRunning)
        {
            int message = wParam.ToInt32();
            KBDLLHOOKSTRUCT data = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
            int vk = unchecked((int)data.vkCode);

            if (message == WM_KEYDOWN || message == WM_SYSKEYDOWN)
            {
                bool firstPress;
                lock (syncRoot)
                {
                    firstPress = keysDown.Add(vk);
                }

                if (firstPress)
                {
                    Enqueue(String.Format(
                        "KD|{0}|{1}|{2}|{3}",
                        vk,
                        data.scanCode,
                        data.flags,
                        GetModifiers()
                    ));
                }
            }
            else if (message == WM_KEYUP || message == WM_SYSKEYUP)
            {
                lock (syncRoot)
                {
                    keysDown.Remove(vk);
                }

                Enqueue(String.Format(
                    "KU|{0}|{1}|{2}|{3}",
                    vk,
                    data.scanCode,
                    data.flags,
                    GetModifiers()
                ));
            }
        }

        return CallNextHookEx(keyboardHook, nCode, wParam, lParam);
    }

    private static IntPtr MouseCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && IsRunning)
        {
            int message = wParam.ToInt32();
            MSLLHOOKSTRUCT data = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(lParam);
            string name = null;
            string state = null;
            int detail = 0;

            switch (message)
            {
                case WM_MOUSEMOVE:
                    if (TrackpadTrackingEnabled)
                    {
                        name = "MOVE";
                        state = "MOVE";
                    }
                    break;
                case WM_LBUTTONDOWN: name = "LEFT"; state = "DOWN"; break;
                case WM_LBUTTONUP: name = "LEFT"; state = "UP"; break;
                case WM_RBUTTONDOWN: name = "RIGHT"; state = "DOWN"; break;
                case WM_RBUTTONUP: name = "RIGHT"; state = "UP"; break;
                case WM_MBUTTONDOWN: name = "MIDDLE"; state = "DOWN"; break;
                case WM_MBUTTONUP: name = "MIDDLE"; state = "UP"; break;
                case WM_XBUTTONDOWN:
                    name = (((data.mouseData >> 16) & 0xffff) == 1) ? "X1" : "X2";
                    state = "DOWN";
                    break;
                case WM_XBUTTONUP:
                    name = (((data.mouseData >> 16) & 0xffff) == 1) ? "X1" : "X2";
                    state = "UP";
                    break;
                case WM_MOUSEWHEEL:
                    name = "WHEEL";
                    state = "MOVE";
                    detail = unchecked((short)((data.mouseData >> 16) & 0xffff));
                    break;
                case WM_MOUSEHWHEEL:
                    name = "HWHEEL";
                    state = "MOVE";
                    detail = unchecked((short)((data.mouseData >> 16) & 0xffff));
                    break;
            }

            if (name != null)
            {
                Enqueue(String.Format(
                    "M|{0}|{1}|{2}|{3}|{4}",
                    name,
                    state,
                    detail,
                    data.pt.x,
                    data.pt.y
                ));
            }
        }

        return CallNextHookEx(mouseHook, nCode, wParam, lParam);
    }

    private static string GetModifiers()
    {
        List<string> values = new List<string>();
        if ((GetAsyncKeyState(0x10) & 0x8000) != 0) values.Add("SHIFT");
        if ((GetAsyncKeyState(0x11) & 0x8000) != 0) values.Add("CTRL");
        if ((GetAsyncKeyState(0x12) & 0x8000) != 0) values.Add("ALT");
        if ((GetAsyncKeyState(0x5B) & 0x8000) != 0 || (GetAsyncKeyState(0x5C) & 0x8000) != 0) values.Add("WIN");
        return String.Join("+", values.ToArray());
    }

    private static void Enqueue(string value)
    {
        queue.Enqueue(DateTime.Now.ToString("HH:mm:ss.fff") + "|" + value);
    }

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
    private delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int x; public int y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSLLHOOKSTRUCT
    {
        public POINT pt;
        public uint mouseData;
        public uint flags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true, EntryPoint = "SetWindowsHookEx")]
    private static extern IntPtr SetWindowsHookExKeyboard(int idHook, LowLevelKeyboardProc callback, IntPtr module, uint threadId);

    [DllImport("user32.dll", SetLastError = true, EntryPoint = "SetWindowsHookEx")]
    private static extern IntPtr SetWindowsHookExMouse(int idHook, LowLevelMouseProc callback, IntPtr module, uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string moduleName);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int virtualKeyCode);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr handle, StringBuilder text, int maxCount);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
}
"@
}

# Windows 8+ pointer messages distinguish touchscreen/pen input from mouse input.
# The filter only observes messages delivered to this application; it is enabled
# while the Touchscreen Diagnostics window is open.
if (-not ("PointerDiagnostics" -as [type])) {
    Add-Type -ReferencedAssemblies 'System.Windows.Forms' -TypeDefinition @"
using System;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public sealed class PointerDiagnostics : IMessageFilter
{
    private const int WM_POINTERUPDATE = 0x0245;
    private const int WM_POINTERDOWN   = 0x0246;
    private const int WM_POINTERUP     = 0x0247;

    private static PointerDiagnostics instance;
    private static readonly ConcurrentQueue<string> queue = new ConcurrentQueue<string>();

    public static void Start()
    {
        if (instance != null) return;
        instance = new PointerDiagnostics();
        Application.AddMessageFilter(instance);
    }

    public static void Stop()
    {
        if (instance == null) return;
        Application.RemoveMessageFilter(instance);
        instance = null;
        string ignored;
        while (queue.TryDequeue(out ignored)) { }
    }

    public static bool TryGetEvent(out string value)
    {
        return queue.TryDequeue(out value);
    }

    public bool PreFilterMessage(ref Message m)
    {
        if (m.Msg != WM_POINTERUPDATE && m.Msg != WM_POINTERDOWN && m.Msg != WM_POINTERUP)
            return false;

        uint pointerId = (uint)((long)m.WParam & 0xFFFF);
        POINTER_INPUT_TYPE type;
        if (!GetPointerType(pointerId, out type))
            return false;

        if (type != POINTER_INPUT_TYPE.PT_TOUCH && type != POINTER_INPUT_TYPE.PT_PEN)
            return false;

        POINTER_INFO info;
        if (!GetPointerInfo(pointerId, out info))
            return false;

        string state = m.Msg == WM_POINTERDOWN ? "DOWN" :
                       m.Msg == WM_POINTERUP   ? "UP" : "MOVE";

        queue.Enqueue(String.Format(
            "{0}|{1}|{2}|{3}|{4}|{5}",
            DateTime.Now.ToString("HH:mm:ss.fff"),
            type == POINTER_INPUT_TYPE.PT_TOUCH ? "TOUCH" : "PEN",
            state,
            pointerId,
            info.ptPixelLocation.X,
            info.ptPixelLocation.Y
        ));

        return false;
    }

    private enum POINTER_INPUT_TYPE : uint
    {
        PT_POINTER = 1,
        PT_TOUCH = 2,
        PT_PEN = 3,
        PT_MOUSE = 4,
        PT_TOUCHPAD = 5
    }

    [Flags]
    private enum POINTER_FLAGS : uint
    {
        NONE = 0x00000000
    }

    private enum POINTER_BUTTON_CHANGE_TYPE : uint
    {
        NONE = 0
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINTER_INFO
    {
        public POINTER_INPUT_TYPE pointerType;
        public uint pointerId;
        public uint frameId;
        public POINTER_FLAGS pointerFlags;
        public IntPtr sourceDevice;
        public IntPtr hwndTarget;
        public POINT ptPixelLocation;
        public POINT ptHimetricLocation;
        public POINT ptPixelLocationRaw;
        public POINT ptHimetricLocationRaw;
        public uint dwTime;
        public uint historyCount;
        public int InputData;
        public uint dwKeyStates;
        public ulong PerformanceCount;
        public POINTER_BUTTON_CHANGE_TYPE ButtonChangeType;
    }

    [DllImport("user32.dll")]
    private static extern bool GetPointerType(
        uint pointerId,
        out POINTER_INPUT_TYPE pointerType
    );

    [DllImport("user32.dll")]
    private static extern bool GetPointerInfo(
        uint pointerId,
        out POINTER_INFO pointerInfo
    );
}
"@
}

# XInput provides controller state without requiring administrator rights or
# third-party modules. The wrapper tries the Windows 10/11 DLL first and falls
# back to the compatibility DLL found on older supported Windows versions.
if (-not ('InputDiagnosticsXInput' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class InputDiagnosticsXInput
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Gamepad
    {
        public ushort Buttons;
        public byte LeftTrigger;
        public byte RightTrigger;
        public short ThumbLX;
        public short ThumbLY;
        public short ThumbRX;
        public short ThumbRY;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct State
    {
        public uint PacketNumber;
        public Gamepad Gamepad;
    }

    [DllImport("xinput1_4.dll", EntryPoint = "XInputGetState")]
    private static extern uint GetState14(uint userIndex, out State state);

    [DllImport("xinput9_1_0.dll", EntryPoint = "XInputGetState")]
    private static extern uint GetState910(uint userIndex, out State state);

    public static bool TryGetState(uint userIndex, out State state, out string api)
    {
        state = new State();
        api = "Unavailable";

        try
        {
            uint result = GetState14(userIndex, out state);
            api = "XInput 1.4";
            return result == 0;
        }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }

        try
        {
            uint result = GetState910(userIndex, out state);
            api = "XInput 9.1.0";
            return result == 0;
        }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }

        return false;
    }
}
"@
}

# ---------------------------- Colors ----------------------------
$Colors = @{
    Background = [System.Drawing.Color]::FromArgb(14, 16, 20)
    Surface    = [System.Drawing.Color]::FromArgb(22, 25, 31)
    Panel      = [System.Drawing.Color]::FromArgb(28, 32, 40)
    PanelAlt   = [System.Drawing.Color]::FromArgb(35, 40, 49)
    Key        = [System.Drawing.Color]::FromArgb(39, 45, 55)
    KeyModifier = [System.Drawing.Color]::FromArgb(37, 47, 62)
    KeyFunction = [System.Drawing.Color]::FromArgb(48, 40, 58)
    KeyNav      = [System.Drawing.Color]::FromArgb(53, 45, 35)
    KeyDanger   = [System.Drawing.Color]::FromArgb(57, 39, 42)
    Border     = [System.Drawing.Color]::FromArgb(58, 66, 78)
    Accent     = [System.Drawing.Color]::FromArgb(74, 144, 226)
    Letter     = [System.Drawing.Color]::FromArgb(52, 199, 89)
    Modifier   = [System.Drawing.Color]::FromArgb(74, 144, 226)
    Navigation = [System.Drawing.Color]::FromArgb(255, 159, 10)
    Function   = [System.Drawing.Color]::FromArgb(175, 82, 222)
    Destructive= [System.Drawing.Color]::FromArgb(255, 69, 58)
    Mouse      = [System.Drawing.Color]::FromArgb(48, 209, 188)
    Text       = [System.Drawing.Color]::FromArgb(242, 244, 247)
    Muted      = [System.Drawing.Color]::FromArgb(157, 164, 177)
    Amber      = [System.Drawing.Color]::FromArgb(255, 214, 10)
    HeatLow    = [System.Drawing.Color]::FromArgb(43, 122, 78)
    HeatMid    = [System.Drawing.Color]::FromArgb(179, 130, 32)
    HeatHigh   = [System.Drawing.Color]::FromArgb(220, 92, 39)
    Warning    = [System.Drawing.Color]::FromArgb(255, 184, 77)
}


# ---------------------------- Runtime State ----------------------------
# Session statistics are kept separately from Test Mode diagnostics.
# This prevents normal UI interaction from being reported as hardware-test data.
$script:ButtonMap = @{}
$script:FadeQueue = @{}
$script:KeyDownTimes = @{}
$script:SessionStarted = $null
$script:Stats = @{
    Keys = 0
    Shortcuts = 0
    MouseClicks = 0
    Wheel = 0
}
$script:MaxFeedLines = 50
$script:LastAppInfo = ""
$script:SelectedInspectorVk = $null
$script:KeyStats = @{}
$script:ShortcutCounts = @{}
$script:PrintablePressTimes = New-Object System.Collections.ArrayList
$script:PrintableKeyCount = 0
$script:TestMode = $false
$script:HardwareTestStarted = $false
# Test Mode state. These counters are intentionally separate from normal capture
# so the diagnostic report does not grade ordinary keyboard/mouse activity.
$script:TestKeyCounts = @{}
$script:TestKeyStats = @{}
$script:TestWheelEvents = 0
$script:StuckWarned = @{}
$script:StuckKeyThresholdMs = 5000
# v6 hardware-test state
$script:LastKeyDownAt = @{}
$script:ChatterCounts = @{}
$script:ChatterThresholdMs = 45
$script:MaxSimultaneousKeys = 0
# v7 diagnostics state
$script:KeyboardLayoutMode = 'Full Size'
$script:MouseClickCounts = @{ LEFT=0; RIGHT=0; MIDDLE=0; X1=0; X2=0 }
$script:MouseLastDownAt = @{}
$script:MouseChatterCounts = @{ LEFT=0; RIGHT=0; MIDDLE=0; X1=0; X2=0 }
$script:MouseChatterThresholdMs = 90

# Optional laptop-input diagnostic windows. These are intentionally separate
# from the normal mouse panel and do not write movement paths to disk.
$script:TrackpadDiagnosticsActive = $false
$script:TrackpadCanvas = $null
$script:TrackpadPath = New-Object System.Collections.ArrayList
$script:TrackpadMovementEvents = 0
$script:TrackpadDistance = 0.0
$script:TrackpadLargeJumps = 0
$script:TrackpadLastPoint = $null
$script:TrackpadScrollUp = 0
$script:TrackpadScrollDown = 0
$script:TrackpadScrollLeft = 0
$script:TrackpadScrollRight = 0
$script:TrackpadClicks = @{ LEFT=0; RIGHT=0; MIDDLE=0 }

function Add-MappedButton {
    param([int]$VkCode, [System.Windows.Forms.Button]$Button)
    if (-not $script:ButtonMap.ContainsKey($VkCode)) {
        $script:ButtonMap[$VkCode] = New-Object System.Collections.ArrayList
    }
    [void]$script:ButtonMap[$VkCode].Add($Button)
}

function Set-KeyVisual {
    param([int]$VkCode, [System.Drawing.Color]$Color)
    if ($script:ButtonMap.ContainsKey($VkCode)) {
        foreach ($button in $script:ButtonMap[$VkCode]) {
            $button.BackColor = $Color
        }
    }
}

function Get-KeyCategoryColor {
    param([int]$VkCode)
    if ($VkCode -in 8,46) { return $Colors.Destructive }
    if (($VkCode -ge 112 -and $VkCode -le 123) -or $VkCode -in 27,44,145,19) { return $Colors.Function }
    if ($VkCode -in 9,13,16,17,18,20,91,92,93,160,161,162,163,164,165) { return $Colors.Modifier }
    if ($VkCode -in 33,34,35,36,37,38,39,40,45,144) { return $Colors.Navigation }
    return $Colors.Letter
}

function Get-KeyIdleColor {
    param([int]$VkCode)
    if ($VkCode -in 8,46) { return $Colors.KeyDanger }
    if (($VkCode -ge 112 -and $VkCode -le 123) -or $VkCode -in 27,44,145,19) { return $Colors.KeyFunction }
    if ($VkCode -in 9,13,16,17,18,20,91,92,93,160,161,162,163,164,165) { return $Colors.KeyModifier }
    if ($VkCode -in 33,34,35,36,37,38,39,40,45,144) { return $Colors.KeyNav }
    return $Colors.Key
}

function Get-HeatMapColor {
    param([int]$VkCode)

    if (-not $script:TestMode -or -not $script:TestKeyCounts.ContainsKey($VkCode)) {
        return Get-KeyIdleColor $VkCode
    }

    $count = [int]$script:TestKeyCounts[$VkCode]
    if ($count -le 0) { return Get-KeyIdleColor $VkCode }

    $maxCount = 1
    if ($script:TestKeyCounts.Count -gt 0) {
        $maxCount = [Math]::Max(1, [int](($script:TestKeyCounts.Values | Measure-Object -Maximum).Maximum))
    }
    $ratio = $count / [double]$maxCount

    if ($ratio -le 0.25) { return $Colors.HeatLow }
    if ($ratio -le 0.55) { return $Colors.HeatMid }
    if ($ratio -le 0.80) { return $Colors.HeatHigh }
    return $Colors.Destructive
}

function Reset-KeyVisual {
    param([int]$VkCode)
    if ($script:TestMode) {
        Set-KeyVisual -VkCode $VkCode -Color (Get-HeatMapColor $VkCode)
    } else {
        Set-KeyVisual -VkCode $VkCode -Color (Get-KeyIdleColor $VkCode)
    }
}

function Update-TestHeatMap {
    foreach ($vk in @($script:ButtonMap.Keys)) {
        if (-not $script:KeyDownTimes.ContainsKey([int]$vk)) {
            Reset-KeyVisual ([int]$vk)
        }
    }
}

function Update-TestModeButton {
    if (-not $TestModeButton) { return }
    if ($script:TestMode) {
        $TestModeButton.Text = '⚗  Test mode: ON'
        $TestModeButton.BackColor = $Colors.PanelAlt
        $TestModeButton.ForeColor = $Colors.Letter
        if ($TestModeValue) { $TestModeValue.Text='⚗ ON'; $TestModeValue.ForeColor=$Colors.Letter }
    } else {
        $TestModeButton.Text = '⚗  Test mode: OFF'
        $TestModeButton.BackColor = $Colors.PanelAlt
        $TestModeButton.ForeColor = $Colors.Text
        if ($TestModeValue) { $TestModeValue.Text='⚗ OFF'; $TestModeValue.ForeColor=$Colors.Muted }
    }
}


function Get-TestMappedKeys {
    $keys = @($script:ButtonMap.Keys | ForEach-Object { [int]$_ } | Sort-Object -Unique)
    switch ($script:KeyboardLayoutMode) {
        'TKL' {
            # Exclude numpad-only VKs and Num Lock.
            return @($keys | Where-Object { $_ -notin 96,97,98,99,100,101,102,103,104,105,106,107,109,110,111,144 })
        }
        'Compact / Laptop' {
            # Core typing/navigation set; excludes function row, dedicated nav cluster, numpad, Print/Pause/Scroll Lock.
            return @($keys | Where-Object {
                ($_ -notin 19,33,34,35,36,44,45,46,96,97,98,99,100,101,102,103,104,105,106,107,109,110,111,144,145) -and
                -not ($_ -ge 112 -and $_ -le 123)
            })
        }
        default { return $keys }
    }
}

function Get-TestCompletion {
    $mapped = @(Get-TestMappedKeys)
    $tested = @($mapped | Where-Object {
        $script:TestKeyCounts.ContainsKey($_) -and [int]$script:TestKeyCounts[$_] -gt 0
    })
    $total = $mapped.Count
    $count = $tested.Count
    $percent = if ($total -gt 0) { [Math]::Round(($count / [double]$total) * 100) } else { 0 }
    return @{ Tested=$count; Total=$total; Percent=$percent }
}

function Update-TestProgress {
    $progress = Get-TestCompletion
    if ($TestProgressLabel) {
        $TestProgressLabel.Text = "$($progress.Tested) / $($progress.Total) ($($progress.Percent)%)"
        $TestProgressLabel.ForeColor = if ($progress.Percent -ge 100) { $Colors.Letter } elseif ($progress.Percent -gt 0) { $Colors.Text } else { $Colors.Text }
    }
    if ($TestProgressBar) { $TestProgressBar.Value = [Math]::Max(0,[Math]::Min(100,[int]$progress.Percent)) }
}



function Register-ChatterSample([int]$VkCode) {
    # Normal capture is informational only. Chatter warnings used for PASS /
    # ATTENTION grading are collected only while Test Mode is active.
    if (-not $script:TestMode) { return }

    $now = Get-Date
    if ($script:LastKeyDownAt.ContainsKey($VkCode)) {
        $delta = ($now - $script:LastKeyDownAt[$VkCode]).TotalMilliseconds
        # Only flag a new down that follows another down suspiciously quickly.
        if ($delta -gt 0 -and $delta -le $script:ChatterThresholdMs) {
            if (-not $script:ChatterCounts.ContainsKey($VkCode)) { $script:ChatterCounts[$VkCode] = 0 }
            $script:ChatterCounts[$VkCode] = [int]$script:ChatterCounts[$VkCode] + 1
            Write-Feed 'WARNING' "Possible switch chatter: $(Get-KeyName $VkCode) repeated after $([Math]::Round($delta)) ms."
        }
    }
    $script:LastKeyDownAt[$VkCode] = $now
}

function Get-ChatterSummary {
    $bad = @($script:ChatterCounts.GetEnumerator() | Where-Object { [int]$_.Value -gt 0 } | Sort-Object Value -Descending)
    if ($bad.Count -eq 0) { return 'None detected' }
    return (($bad | ForEach-Object { "$(Get-KeyName ([int]$_.Key))=$($_.Value)" }) -join ', ')
}

function Show-TestChecklist {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Keyboard Test Checklist'
    $dialog.Size = New-Object System.Drawing.Size(760,690)
    $dialog.MinimumSize = New-Object System.Drawing.Size(680,520)
    $dialog.StartPosition = 'CenterParent'
    $dialog.BackColor = $Colors.Background
    $dialog.ForeColor = $Colors.Text
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $dialog.FormBorderStyle = 'Sizable'
    $dialog.MaximizeBox = $true
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false

    $progress = Get-TestCompletion
    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Keyboard test progress: $($progress.Tested) of $($progress.Total) keys ($($progress.Percent)%)"
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold',13,[System.Drawing.FontStyle]::Bold)
    $title.ForeColor = if($progress.Percent -ge 100){$Colors.Letter}else{$Colors.Text}
    $title.Location = New-Object System.Drawing.Point(14,14)
    $title.Size = New-Object System.Drawing.Size(700,30)
    $title.Anchor = 'Top,Left,Right'
    $dialog.Controls.Add($title)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Timing values are press-to-release hold measurements observed by the Windows hook.'
    $hint.ForeColor = $Colors.Muted
    $hint.Location = New-Object System.Drawing.Point(16,46)
    $hint.Size = New-Object System.Drawing.Size(700,22)
    $hint.Anchor = 'Top,Left,Right'
    $dialog.Controls.Add($hint)

    $list = New-Object System.Windows.Forms.ListView
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.GridLines = $false
    $list.BorderStyle = 'FixedSingle'
    $list.BackColor = $Colors.Surface
    $list.ForeColor = $Colors.Text
    $list.Location = New-Object System.Drawing.Point(16,76)
    $list.Size = New-Object System.Drawing.Size(712,520)
    $list.Anchor = 'Top,Bottom,Left,Right'
    [void]$list.Columns.Add('Key',180)
    [void]$list.Columns.Add('Status',100)
    [void]$list.Columns.Add('Presses',75)
    [void]$list.Columns.Add('Avg hold',105)
    [void]$list.Columns.Add('Longest',105)
    [void]$list.Columns.Add('Category',120)
    $dialog.Controls.Add($list)

    foreach ($vk in @(Get-TestMappedKeys | Sort-Object { Get-KeyName $_ })) {
        $name = Get-KeyName $vk
        $tested = $script:TestKeyCounts.ContainsKey($vk) -and [int]$script:TestKeyCounts[$vk] -gt 0
        $presses = if($tested){[int]$script:TestKeyCounts[$vk]}else{0}
        $stat = Get-OrCreateTestKeyStat $vk
        $avg = if($stat.Count -gt 0){[Math]::Round($stat.TotalHoldMs / $stat.Count)}else{0}
        $longest = [Math]::Round($stat.LongestHoldMs)
        $item = New-Object System.Windows.Forms.ListViewItem($name)
        [void]$item.SubItems.Add($(if($tested){'Tested'}else{'Not tested'}))
        [void]$item.SubItems.Add([string]$presses)
        [void]$item.SubItems.Add("${avg} ms")
        [void]$item.SubItems.Add("${longest} ms")
        [void]$item.SubItems.Add((Get-KeyCategoryName $vk))
        if ($tested) { $item.ForeColor = $Colors.Letter } else { $item.ForeColor = $Colors.Muted }
        [void]$list.Items.Add($item)
    }

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'Close'
    $close.Location = New-Object System.Drawing.Point(628,608)
    $close.Size = New-Object System.Drawing.Size(100,32)
    $close.Anchor = 'Bottom,Right'
    $close.FlatStyle = 'Flat'
    $close.FlatAppearance.BorderColor = $Colors.Border
    $close.BackColor = $Colors.PanelAlt
    $close.ForeColor = $Colors.Text
    $close.Add_Click({$dialog.Close()})
    $dialog.Controls.Add($close)

    [void]$dialog.ShowDialog($Form)
}


function Get-KeyboardTestResult {
    $progress = Get-TestCompletion
    $mapped = @(Get-TestMappedKeys)
    $missing = @($mapped | Where-Object { -not $script:TestKeyCounts.ContainsKey($_) -or [int]$script:TestKeyCounts[$_] -le 0 })
    $chatter = @($script:ChatterCounts.GetEnumerator() | Where-Object { [int]$_.Value -gt 0 -and $mapped -contains [int]$_.Key })
    $stuck = @($script:StuckWarned.Keys | Where-Object { $mapped -contains [int]$_ })
    $status = if($progress.Percent -ge 100 -and $missing.Count -eq 0 -and $chatter.Count -eq 0 -and $stuck.Count -eq 0){'PASS'}else{'ATTENTION'}
    return [pscustomobject]@{Status=$status;Progress=$progress;Missing=$missing;Chatter=$chatter;Stuck=$stuck}
}

function Set-TestResultColors {
    if (-not $script:TestMode) { return }

    foreach ($vk in @(Get-TestMappedKeys)) {
        if ($script:StuckWarned.ContainsKey($vk)) {
            Set-KeyVisual $vk $Colors.Destructive
        }
        elseif ($script:ChatterCounts.ContainsKey($vk) -and
                [int]$script:ChatterCounts[$vk] -gt 0) {
            Set-KeyVisual $vk $Colors.Navigation
        }
        elseif ($script:TestKeyCounts.ContainsKey($vk) -and
                [int]$script:TestKeyCounts[$vk] -gt 0) {
            Set-KeyVisual $vk $Colors.HeatLow
        }
        else {
            Set-KeyVisual $vk $Colors.KeyDanger
        }
    }
}

function Register-MouseDownDiagnostic([string]$Name) {
    # Keep mouse-test counts isolated from ordinary clicks used to operate the UI.
    if (-not $script:TestMode) { return }
    if(-not $script:MouseClickCounts.ContainsKey($Name)){return}
    $now=Get-Date
    $script:MouseClickCounts[$Name]=[int]$script:MouseClickCounts[$Name]+1
    if($script:MouseLastDownAt.ContainsKey($Name)){
        $delta=($now-$script:MouseLastDownAt[$Name]).TotalMilliseconds
        if($delta -gt 0 -and $delta -le $script:MouseChatterThresholdMs){
            $script:MouseChatterCounts[$Name]=[int]$script:MouseChatterCounts[$Name]+1
            Write-Feed 'WARNING' "Possible mouse chatter: $Name repeated after $([Math]::Round($delta)) ms."
        }
    }
    $script:MouseLastDownAt[$Name]=$now
}

function Get-MouseTestResult {
    $required=@('LEFT','RIGHT','MIDDLE')
    $missing=@($required | Where-Object {[int]$script:MouseClickCounts[$_] -le 0})
    $chat=@($script:MouseChatterCounts.GetEnumerator() | Where-Object {[int]$_.Value -gt 0})
    $status=if($missing.Count -eq 0 -and $chat.Count -eq 0){'PASS'}else{'ATTENTION'}
    return [pscustomobject]@{Status=$status;Missing=$missing;Chatter=$chat}
}


function Reset-TrackpadDiagnostics {
    $script:TrackpadPath.Clear()
    $script:TrackpadMovementEvents = 0
    $script:TrackpadDistance = 0.0
    $script:TrackpadLargeJumps = 0
    $script:TrackpadLastPoint = $null
    $script:TrackpadScrollUp = 0
    $script:TrackpadScrollDown = 0
    $script:TrackpadScrollLeft = 0
    $script:TrackpadScrollRight = 0
    foreach($name in @('LEFT','RIGHT','MIDDLE')) {
        $script:TrackpadClicks[$name] = 0
    }

    if ($script:TrackpadCanvas) {
        $script:TrackpadCanvas.Invalidate()
    }
}

function Update-TrackpadMovement {
    param(
        [int]$ScreenX,
        [int]$ScreenY
    )

    if (-not $script:TrackpadDiagnosticsActive -or -not $script:TrackpadCanvas) {
        return
    }

    $point = $script:TrackpadCanvas.PointToClient(
        [System.Drawing.Point]::new($ScreenX,$ScreenY)
    )

    # Only draw movement that happens inside the test surface.
    if (-not $script:TrackpadCanvas.ClientRectangle.Contains($point)) {
        $script:TrackpadLastPoint = $null
        return
    }

    if ($null -ne $script:TrackpadLastPoint) {
        $dx = $point.X - $script:TrackpadLastPoint.X
        $dy = $point.Y - $script:TrackpadLastPoint.Y
        $distance = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
        $script:TrackpadDistance += $distance

        # A very large one-event jump can indicate erratic tracking, although
        # fast swipes can also cause it. Treat this as an observation, not FAIL.
        if ($distance -gt 220) {
            $script:TrackpadLargeJumps++
        }
    }

    [void]$script:TrackpadPath.Add($point)
    if ($script:TrackpadPath.Count -gt 1800) {
        $script:TrackpadPath.RemoveAt(0)
    }

    $script:TrackpadLastPoint = $point
    $script:TrackpadMovementEvents++
    $script:TrackpadCanvas.Invalidate()
}

function Show-TrackpadDiagnostics {
    if ($script:TrackpadDiagnosticsActive) {
        return
    }

    # Trackpads normally surface pointer movement/clicks as mouse input. When
    # no external mouse is attached this provides a practical laptop test.
    if (-not [GlobalInputDiagnostics]::IsRunning) {
        $StartButton.PerformClick()
        if (-not [GlobalInputDiagnostics]::IsRunning) {
            return
        }
    }

    Reset-TrackpadDiagnostics
    $script:TrackpadDiagnosticsActive = $true
    [GlobalInputDiagnostics]::TrackpadTrackingEnabled = $true

    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Trackpad Diagnostics'
    $d.Size = [System.Drawing.Size]::new(900,650)
    $d.MinimumSize = [System.Drawing.Size]::new(760,560)
    $d.StartPosition = 'CenterParent'
    $d.BackColor = $Colors.Background
    $d.ForeColor = $Colors.Text
    $d.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $d.ShowInTaskbar = $false

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Trackpad Diagnostics'
    $title.Location = [System.Drawing.Point]::new(18,14)
    $title.Size = [System.Drawing.Size]::new(400,30)
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold',15,[System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $Colors.Text
    $d.Controls.Add($title)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Move one finger across the trackpad while keeping the pointer inside the test area. Then test clicks and scrolling.'
    $hint.Location = [System.Drawing.Point]::new(20,48)
    $hint.Size = [System.Drawing.Size]::new(830,42)
    $hint.ForeColor = $Colors.Muted
    $d.Controls.Add($hint)

    $canvas = New-Object System.Windows.Forms.Panel
    $canvas.Location = [System.Drawing.Point]::new(20,96)
    $canvas.Size = [System.Drawing.Size]::new(570,455)
    $canvas.Anchor = 'Top,Bottom,Left,Right'
    $canvas.BackColor = $Colors.Surface
    $canvas.BorderStyle = 'FixedSingle'
    $script:TrackpadCanvas = $canvas
    $d.Controls.Add($canvas)

    $canvas.Add_Paint({
        param($trackSurface,$paintArgs)

        # Grid makes dead/skipping areas easier to spot visually.
        $gridPen = New-Object System.Drawing.Pen($Colors.PanelAlt,1)
        $pathPen = New-Object System.Drawing.Pen($Colors.Mouse,2)
        try {
            for($x=0;$x -lt $trackSurface.Width;$x+=50) {
                $paintArgs.Graphics.DrawLine($gridPen,$x,0,$x,$trackSurface.Height)
            }
            for($y=0;$y -lt $trackSurface.Height;$y+=50) {
                $paintArgs.Graphics.DrawLine($gridPen,0,$y,$trackSurface.Width,$y)
            }

            if($script:TrackpadPath.Count -gt 1) {
                [System.Drawing.Point[]]$points = @($script:TrackpadPath)
                $paintArgs.Graphics.DrawLines($pathPen,$points)
            }
        }
        finally {
            $gridPen.Dispose()
            $pathPen.Dispose()
        }
    })

    $statsPanel = New-Object System.Windows.Forms.Panel
    $statsPanel.Location = [System.Drawing.Point]::new(610,96)
    $statsPanel.Size = [System.Drawing.Size]::new(250,455)
    $statsPanel.Anchor = 'Top,Bottom,Right'
    $statsPanel.BackColor = $Colors.Surface
    $statsPanel.BorderStyle = 'FixedSingle'
    $d.Controls.Add($statsPanel)

    $statsTitle = New-Object System.Windows.Forms.Label
    $statsTitle.Text = 'LIVE RESULTS'
    $statsTitle.Location = [System.Drawing.Point]::new(15,14)
    $statsTitle.Size = [System.Drawing.Size]::new(180,22)
    $statsTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9,[System.Drawing.FontStyle]::Bold)
    $statsPanel.Controls.Add($statsTitle)

    $statsLabel = New-Object System.Windows.Forms.Label
    $statsLabel.Location = [System.Drawing.Point]::new(15,50)
    $statsLabel.Size = [System.Drawing.Size]::new(220,350)
    $statsLabel.Font = New-Object System.Drawing.Font('Segoe UI',9.5)
    $statsLabel.ForeColor = $Colors.Text
    $statsPanel.Controls.Add($statsLabel)

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 200
    $timer.Add_Tick({
        $statsLabel.Text = @"
Movement events:  $($script:TrackpadMovementEvents)
Path distance:    $([Math]::Round($script:TrackpadDistance)) px
Large jumps:      $($script:TrackpadLargeJumps)

Left click:       $($script:TrackpadClicks.LEFT)
Right click:      $($script:TrackpadClicks.RIGHT)
Middle click:     $($script:TrackpadClicks.MIDDLE)

Scroll up:        $($script:TrackpadScrollUp)
Scroll down:      $($script:TrackpadScrollDown)
Scroll left:      $($script:TrackpadScrollLeft)
Scroll right:     $($script:TrackpadScrollRight)

Tip:
A smooth continuous path is more useful than the raw event count. Large jumps are observations, not an automatic hardware failure.
"@
    })

    $reset = New-Object System.Windows.Forms.Button
    $reset.Text = 'Reset'
    $reset.Location = [System.Drawing.Point]::new(610,565)
    $reset.Size = [System.Drawing.Size]::new(115,34)
    $reset.Anchor = 'Bottom,Right'
    Set-ActionButtonStyle -b $reset
    $reset.Add_Click({ Reset-TrackpadDiagnostics })
    $d.Controls.Add($reset)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'Close'
    $close.Location = [System.Drawing.Point]::new(745,565)
    $close.Size = [System.Drawing.Size]::new(115,34)
    $close.Anchor = 'Bottom,Right'
    Set-ActionButtonStyle -b $close -back $Colors.Accent -fore ([System.Drawing.Color]::White)
    $close.Add_Click({ $d.Close() })
    $d.Controls.Add($close)

    $d.Add_FormClosed({
        $timer.Stop()
        $timer.Dispose()
        [GlobalInputDiagnostics]::TrackpadTrackingEnabled = $false
        $script:TrackpadDiagnosticsActive = $false
        $script:TrackpadCanvas = $null
        $script:TrackpadLastPoint = $null
    })

    $timer.Start()
    [void]$d.ShowDialog($Form)
}

function Show-TouchscreenDiagnostics {
    # WM_POINTER is available on Windows 8 and later. Actual touch input is
    # distinguished from mouse clicks; pen input is shown separately.
    [PointerDiagnostics]::Start()

    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Touchscreen Diagnostics'
    $d.WindowState = 'Maximized'
    $d.StartPosition = 'CenterParent'
    $d.BackColor = $Colors.Background
    $d.ForeColor = $Colors.Text
    $d.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $d.ShowInTaskbar = $false

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = 'Top'
    $header.Height = 74
    $header.BackColor = $Colors.Surface
    $d.Controls.Add($header)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Touchscreen Coverage Test'
    $title.Location = [System.Drawing.Point]::new(18,10)
    $title.Size = [System.Drawing.Size]::new(420,28)
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold',15,[System.Drawing.FontStyle]::Bold)
    $header.Controls.Add($title)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = 'Touch or drag across the grid. Each detected touchscreen cell turns green.'
    $status.Location = [System.Drawing.Point]::new(20,42)
    $status.Size = [System.Drawing.Size]::new(850,22)
    $status.ForeColor = $Colors.Muted
    $header.Controls.Add($status)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'Close'
    $close.Size = [System.Drawing.Size]::new(100,34)
    $close.Location = [System.Drawing.Point]::new(0,18)
    $close.Anchor = 'Top,Right'
    Set-ActionButtonStyle -b $close -back $Colors.Accent -fore ([System.Drawing.Color]::White)
    $header.Controls.Add($close)

    $reset = New-Object System.Windows.Forms.Button
    $reset.Text = 'Reset'
    $reset.Size = [System.Drawing.Size]::new(100,34)
    $reset.Location = [System.Drawing.Point]::new(0,18)
    $reset.Anchor = 'Top,Right'
    Set-ActionButtonStyle -b $reset
    $header.Controls.Add($reset)

    $gridPanel = New-Object System.Windows.Forms.Panel
    $gridPanel.Dock = 'Fill'
    $gridPanel.BackColor = $Colors.Background
    $d.Controls.Add($gridPanel)
    $gridPanel.BringToFront()

    $footer = New-Object System.Windows.Forms.Panel
    $footer.Dock = 'Bottom'
    $footer.Height = 42
    $footer.BackColor = $Colors.Surface
    $d.Controls.Add($footer)
    $footer.BringToFront()

    $coverageLabel = New-Object System.Windows.Forms.Label
    $coverageLabel.Location = [System.Drawing.Point]::new(16,10)
    $coverageLabel.Size = [System.Drawing.Size]::new(900,22)
    $coverageLabel.ForeColor = $Colors.Text
    $footer.Controls.Add($coverageLabel)

    $script:TouchGridColumns = 12
    $script:TouchGridRows = 7
    $script:TouchTouchedCells = @{}
    $script:TouchActivePointers = @{}
    $script:TouchEventCount = 0
    $script:PenEventCount = 0

    $gridPanel.Add_Paint({
        param($touchSurface,$paintArgs)

        $cellW = [Math]::Max(1,[int]($touchSurface.ClientSize.Width / $script:TouchGridColumns))
        $cellH = [Math]::Max(1,[int]($touchSurface.ClientSize.Height / $script:TouchGridRows))
        $borderPen = New-Object System.Drawing.Pen($Colors.Border,1)
        $emptyBrush = New-Object System.Drawing.SolidBrush($Colors.Surface)
        $hitBrush = New-Object System.Drawing.SolidBrush($Colors.HeatLow)
        try {
            for($row=0;$row -lt $script:TouchGridRows;$row++) {
                for($col=0;$col -lt $script:TouchGridColumns;$col++) {
                    $key = "$col,$row"
                    $rect = [System.Drawing.Rectangle]::new(
                        $col*$cellW,
                        $row*$cellH,
                        [Math]::Max(1,$cellW-2),
                        [Math]::Max(1,$cellH-2)
                    )
                    if($script:TouchTouchedCells.ContainsKey($key)) {
                        $paintArgs.Graphics.FillRectangle($hitBrush,$rect)
                    } else {
                        $paintArgs.Graphics.FillRectangle($emptyBrush,$rect)
                    }
                    $paintArgs.Graphics.DrawRectangle($borderPen,$rect)
                }
            }
        }
        finally {
            $borderPen.Dispose()
            $emptyBrush.Dispose()
            $hitBrush.Dispose()
        }
    })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 25
    $timer.Add_Tick({
        $rawPointer = $null
        while([PointerDiagnostics]::TryGetEvent([ref]$rawPointer)) {
            $parts = $rawPointer -split '\|'
            if($parts.Count -lt 6) { continue }

            $pointerType = $parts[1]
            $pointerState = $parts[2]
            $pointerId = [int]$parts[3]
            $screenX = [int]$parts[4]
            $screenY = [int]$parts[5]

            $clientPoint = $gridPanel.PointToClient(
                [System.Drawing.Point]::new($screenX,$screenY)
            )

            if($pointerType -eq 'TOUCH') {
                $script:TouchEventCount++
                if($pointerState -eq 'DOWN') {
                    $script:TouchActivePointers[$pointerId] = $true
                }
                elseif($pointerState -eq 'UP') {
                    $script:TouchActivePointers.Remove($pointerId)
                }
            }
            elseif($pointerType -eq 'PEN') {
                $script:PenEventCount++
            }

            if($pointerType -eq 'TOUCH' -and $gridPanel.ClientRectangle.Contains($clientPoint)) {
                $cellW = [Math]::Max(1,[int]($gridPanel.ClientSize.Width / $script:TouchGridColumns))
                $cellH = [Math]::Max(1,[int]($gridPanel.ClientSize.Height / $script:TouchGridRows))
                $col = [Math]::Min($script:TouchGridColumns-1,[Math]::Max(0,[int]($clientPoint.X / $cellW)))
                $row = [Math]::Min($script:TouchGridRows-1,[Math]::Max(0,[int]($clientPoint.Y / $cellH)))
                $script:TouchTouchedCells["$col,$row"] = $true
            }
        }

        $totalCells = $script:TouchGridColumns * $script:TouchGridRows
        $coverage = if($totalCells -gt 0) {
            [Math]::Round(($script:TouchTouchedCells.Count / [double]$totalCells) * 100)
        } else { 0 }

        $coverageLabel.Text = "Coverage: $($script:TouchTouchedCells.Count)/$totalCells cells ($coverage%)    Touch events: $script:TouchEventCount    Active touches: $($script:TouchActivePointers.Count)    Pen events: $script:PenEventCount"
        $gridPanel.Invalidate()

        # Keep buttons aligned when maximized/resized.
        $close.Left = $header.ClientSize.Width - 118
        $reset.Left = $header.ClientSize.Width - 228
    })

    $reset.Add_Click({
        $script:TouchTouchedCells.Clear()
        $script:TouchActivePointers.Clear()
        $script:TouchEventCount = 0
        $script:PenEventCount = 0
        $gridPanel.Invalidate()
    })

    $close.Add_Click({ $d.Close() })

    $d.Add_FormClosed({
        $timer.Stop()
        $timer.Dispose()
        [PointerDiagnostics]::Stop()
        $script:TouchTouchedCells = @{}
        $script:TouchActivePointers = @{}
        $script:TouchEventCount = 0
        $script:PenEventCount = 0
    })

    $timer.Start()
    [void]$d.ShowDialog($Form)
}

function ConvertTo-AxisPercent {
    param([int]$Value)

    if ($Value -ge 0) {
        return [Math]::Min(100,[Math]::Round(($Value / 32767.0) * 100))
    }

    return [Math]::Max(-100,[Math]::Round(($Value / 32768.0) * 100))
}

function Get-ControllerButtonNames {
    param([int]$Mask)

    $buttonMap = [ordered]@{
        0x0001 = 'D-pad Up'
        0x0002 = 'D-pad Down'
        0x0004 = 'D-pad Left'
        0x0008 = 'D-pad Right'
        0x0010 = 'Start / Menu'
        0x0020 = 'Back / View'
        0x0040 = 'Left Stick'
        0x0080 = 'Right Stick'
        0x0100 = 'Left Shoulder'
        0x0200 = 'Right Shoulder'
        0x1000 = 'A'
        0x2000 = 'B'
        0x4000 = 'X'
        0x8000 = 'Y'
    }

    $pressed = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $buttonMap.GetEnumerator()) {
        if (($Mask -band [int]$entry.Key) -ne 0) {
            $pressed.Add([string]$entry.Value)
        }
    }

    if ($pressed.Count -eq 0) {
        return 'None'
    }

    return ($pressed -join ', ')
}

function Show-ControllerDiagnostics {
    param([System.Windows.Forms.IWin32Window]$Owner = $Form)

    # XInput supports up to four connected controller slots. It is the most
    # dependable built-in Windows API for Xbox-compatible USB/Bluetooth pads.
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Game Controller Diagnostics'
    $dialog.Size = [System.Drawing.Size]::new(840,660)
    $dialog.MinimumSize = [System.Drawing.Size]::new(760,580)
    $dialog.StartPosition = 'CenterParent'
    $dialog.BackColor = $Colors.Background
    $dialog.ForeColor = $Colors.Text
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $dialog.FormBorderStyle = 'Sizable'
    $dialog.MaximizeBox = $true
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = 'Top'
    $header.Height = 88
    $header.BackColor = $Colors.Surface
    $dialog.Controls.Add($header)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Game Controller Diagnostics'
    $title.Location = [System.Drawing.Point]::new(22,14)
    $title.Size = [System.Drawing.Size]::new(500,30)
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold',16,[System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $Colors.Text
    $header.Controls.Add($title)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Connect an XInput-compatible controller, then test buttons, triggers, D-pad, and both analog sticks.'
    $hint.Location = [System.Drawing.Point]::new(24,50)
    $hint.Size = [System.Drawing.Size]::new(760,24)
    $hint.ForeColor = $Colors.Muted
    $header.Controls.Add($hint)

    $slotLabel = New-Object System.Windows.Forms.Label
    $slotLabel.Text = 'Controller slot'
    $slotLabel.Location = [System.Drawing.Point]::new(22,108)
    $slotLabel.Size = [System.Drawing.Size]::new(110,22)
    $dialog.Controls.Add($slotLabel)

    $slotCombo = New-Object System.Windows.Forms.ComboBox
    $slotCombo.DropDownStyle = 'DropDownList'
    $slotCombo.Location = [System.Drawing.Point]::new(136,105)
    $slotCombo.Size = [System.Drawing.Size]::new(180,28)
    [void]$slotCombo.Items.AddRange(@('Controller 1','Controller 2','Controller 3','Controller 4'))
    $slotCombo.SelectedIndex = 0
    $dialog.Controls.Add($slotCombo)

    $connection = New-Object System.Windows.Forms.Label
    $connection.Text = '● Searching...'
    $connection.Location = [System.Drawing.Point]::new(340,106)
    $connection.Size = [System.Drawing.Size]::new(430,26)
    $connection.Font = New-Object System.Drawing.Font('Segoe UI Semibold',10,[System.Drawing.FontStyle]::Bold)
    $connection.ForeColor = $Colors.Warning
    $dialog.Controls.Add($connection)

    $stateBox = New-Object System.Windows.Forms.RichTextBox
    $stateBox.Location = [System.Drawing.Point]::new(22,150)
    $stateBox.Size = [System.Drawing.Size]::new(780,385)
    $stateBox.Anchor = 'Top,Bottom,Left,Right'
    $stateBox.ReadOnly = $true
    $stateBox.BorderStyle = 'FixedSingle'
    $stateBox.BackColor = $Colors.Surface
    $stateBox.ForeColor = $Colors.Text
    $stateBox.Font = New-Object System.Drawing.Font('Consolas',11)
    $stateBox.DetectUrls = $false
    $dialog.Controls.Add($stateBox)

    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'Tip: centered sticks should remain close to 0%. Small resting values are normal; large values may indicate stick drift.'
    $note.Location = [System.Drawing.Point]::new(22,545)
    $note.Size = [System.Drawing.Size]::new(650,40)
    $note.Anchor = 'Bottom,Left,Right'
    $note.ForeColor = $Colors.Muted
    $dialog.Controls.Add($note)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'Close'
    $close.Location = [System.Drawing.Point]::new(692,555)
    $close.Size = [System.Drawing.Size]::new(110,34)
    $close.Anchor = 'Bottom,Right'
    Set-ActionButtonStyle -b $close -back $Colors.Accent -fore ([System.Drawing.Color]::White)
    $close.Add_Click({ $dialog.Close() })
    $dialog.Controls.Add($close)

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 50
    $timer.Add_Tick({
        $state = New-Object InputDiagnosticsXInput+State
        $api = ''
        $connected = [InputDiagnosticsXInput]::TryGetState(
            [uint32]$slotCombo.SelectedIndex,
            [ref]$state,
            [ref]$api
        )

        if (-not $connected) {
            $connection.Text = "● Not connected  ($api)"
            $connection.ForeColor = $Colors.Destructive
            $stateBox.Text = @"
No XInput-compatible controller was detected in this slot.

Try:
  • Connect the controller by USB or Bluetooth.
  • Press a controller button to wake it.
  • Select another controller slot.
  • Confirm the device appears in Windows game-controller settings.

Some older DirectInput-only controllers are visible to Windows but do not
provide live state through XInput.
"@
            return
        }

        $connection.Text = "● Connected  ($api)    Packet: $($state.PacketNumber)"
        $connection.ForeColor = $Colors.Letter

        $buttons = Get-ControllerButtonNames -Mask ([int]$state.Gamepad.Buttons)
        $leftX = ConvertTo-AxisPercent $state.Gamepad.ThumbLX
        $leftY = ConvertTo-AxisPercent $state.Gamepad.ThumbLY
        $rightX = ConvertTo-AxisPercent $state.Gamepad.ThumbRX
        $rightY = ConvertTo-AxisPercent $state.Gamepad.ThumbRY
        $leftTrigger = [Math]::Round(($state.Gamepad.LeftTrigger / 255.0) * 100)
        $rightTrigger = [Math]::Round(($state.Gamepad.RightTrigger / 255.0) * 100)
        $leftDrift = [Math]::Round([Math]::Sqrt(($leftX * $leftX) + ($leftY * $leftY)))
        $rightDrift = [Math]::Round([Math]::Sqrt(($rightX * $rightX) + ($rightY * $rightY)))

        $stateBox.Text = @"
BUTTONS PRESSED
$buttons

D-PAD / FACE / SHOULDER BUTTONS
Press each button and confirm its name appears above.

TRIGGERS
Left trigger:   $leftTrigger%
Right trigger:  $rightTrigger%

LEFT ANALOG STICK
X axis:         $leftX%
Y axis:         $leftY%
Rest magnitude: $leftDrift%

RIGHT ANALOG STICK
X axis:         $rightX%
Y axis:         $rightY%
Rest magnitude: $rightDrift%

RAW VALUES
Left:  X=$($state.Gamepad.ThumbLX)  Y=$($state.Gamepad.ThumbLY)
Right: X=$($state.Gamepad.ThumbRX)  Y=$($state.Gamepad.ThumbRY)
Triggers: L=$($state.Gamepad.LeftTrigger)  R=$($state.Gamepad.RightTrigger)
Button mask: 0x$('{0:X4}' -f [int]$state.Gamepad.Buttons)
"@
    })

    $dialog.Add_Shown({ $timer.Start() })
    $dialog.Add_FormClosed({
        $timer.Stop()
        $timer.Dispose()
    })

    [void]$dialog.ShowDialog($Owner)
}

function Get-SystemInformationRows {
    $rows = New-Object System.Collections.Generic.List[object]

    try {
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $systemProduct = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
        $operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
        $processors = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
        $memoryModules = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)

        $rows.Add([pscustomobject]@{Section='Computer';Item='Manufacturer';Value=[string]$computer.Manufacturer})
        $rows.Add([pscustomobject]@{Section='Computer';Item='Model';Value=[string]$computer.Model})
        $rows.Add([pscustomobject]@{Section='Computer';Item='Computer name';Value=[string]$env:COMPUTERNAME})
        $rows.Add([pscustomobject]@{Section='Computer';Item='Serial / service tag';Value=[string]$bios.SerialNumber})
        if ($systemProduct -and $systemProduct.UUID) {
            $rows.Add([pscustomobject]@{Section='Computer';Item='System UUID';Value=[string]$systemProduct.UUID})
        }

        $windowsValue = "$($operatingSystem.Caption) — Version $($operatingSystem.Version), Build $($operatingSystem.BuildNumber)"
        $rows.Add([pscustomobject]@{Section='Windows';Item='Edition and build';Value=$windowsValue})
        $rows.Add([pscustomobject]@{Section='Windows';Item='Architecture';Value=[string]$operatingSystem.OSArchitecture})
        $installDate = if ($operatingSystem.InstallDate) {
            ([datetime]$operatingSystem.InstallDate).ToString('yyyy-MM-dd')
        } else {
            'Not reported'
        }
        $rows.Add([pscustomobject]@{Section='Windows';Item='Install date';Value=$installDate})

        $biosDate = if ($bios.ReleaseDate) {
            ([datetime]$bios.ReleaseDate).ToString('yyyy-MM-dd')
        } else {
            'Not reported'
        }
        $rows.Add([pscustomobject]@{Section='BIOS';Item='Version';Value=(@($bios.SMBIOSBIOSVersion,$bios.Version) | Where-Object { $_ } | Select-Object -Unique) -join ' / '})
        $rows.Add([pscustomobject]@{Section='BIOS';Item='Release date';Value=$biosDate})

        $cpuNames = @($processors | ForEach-Object { $_.Name.Trim() } | Select-Object -Unique)
        $rows.Add([pscustomobject]@{Section='Hardware';Item='Processor';Value=$cpuNames -join '; '})
        $rows.Add([pscustomobject]@{Section='Hardware';Item='Logical processors';Value=[string]$computer.NumberOfLogicalProcessors})
        $installedRam = [Math]::Round(([double]$computer.TotalPhysicalMemory / 1GB),2)
        $rows.Add([pscustomobject]@{Section='Hardware';Item='Installed RAM';Value="$installedRam GB"})

        if ($memoryModules.Count -gt 0) {
            $moduleSummary = @(
                $memoryModules | ForEach-Object {
                    $capacity = [Math]::Round(([double]$_.Capacity / 1GB),2)
                    $speed = if ($_.ConfiguredClockSpeed) { $_.ConfiguredClockSpeed } else { $_.Speed }
                    "$capacity GB $speed MHz $($_.Manufacturer)".Trim()
                }
            ) -join '; '
            $rows.Add([pscustomobject]@{Section='Hardware';Item='Memory modules';Value=$moduleSummary})
        }

        $batteries = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
        if ($batteries.Count -eq 0) {
            $rows.Add([pscustomobject]@{Section='Battery';Item='Battery';Value='No Windows battery device reported'})
        } else {
            $batteryIndex = 0
            foreach ($battery in $batteries) {
                $batteryIndex++
                $statusNames = @{
                    1='Discharging'; 2='AC / not discharging'; 3='Fully charged'
                    4='Low'; 5='Critical'; 6='Charging'; 7='Charging (high)'
                    8='Charging (low)'; 9='Charging (critical)'; 10='Undefined'
                    11='Partially charged'
                }
                $status = if ($statusNames.ContainsKey([int]$battery.BatteryStatus)) {
                    $statusNames[[int]$battery.BatteryStatus]
                } else {
                    "Status code $($battery.BatteryStatus)"
                }
                $prefix = if ($batteries.Count -gt 1) { "Battery $batteryIndex" } else { 'Battery' }
                $rows.Add([pscustomobject]@{Section='Battery';Item="$prefix name";Value=[string]$battery.Name})
                $rows.Add([pscustomobject]@{Section='Battery';Item="$prefix charge";Value="$($battery.EstimatedChargeRemaining)%"})
                $rows.Add([pscustomobject]@{Section='Battery';Item="$prefix status";Value=$status})
                if ($battery.EstimatedRunTime -and [int]$battery.EstimatedRunTime -lt 71582788) {
                    $rows.Add([pscustomobject]@{Section='Battery';Item="$prefix estimated runtime";Value="$($battery.EstimatedRunTime) minutes"})
                }
            }
        }
    }
    catch {
        $rows.Add([pscustomobject]@{Section='Error';Item='System information';Value=$_.Exception.Message})
    }

    return @($rows)
}

function Show-SystemInformation {
    param([System.Windows.Forms.IWin32Window]$Owner = $Form)

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Laptop & System Information'
    $dialog.Size = [System.Drawing.Size]::new(960,680)
    $dialog.MinimumSize = [System.Drawing.Size]::new(780,560)
    $dialog.StartPosition = 'CenterParent'
    $dialog.BackColor = $Colors.Background
    $dialog.ForeColor = $Colors.Text
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $dialog.FormBorderStyle = 'Sizable'
    $dialog.MaximizeBox = $true
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Laptop & System Information'
    $title.Location = [System.Drawing.Point]::new(20,14)
    $title.Size = [System.Drawing.Size]::new(620,32)
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold',16,[System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $Colors.Text
    $dialog.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = 'Windows-reported details useful for inventory and help-desk troubleshooting.'
    $subtitle.Location = [System.Drawing.Point]::new(22,50)
    $subtitle.Size = [System.Drawing.Size]::new(760,24)
    $subtitle.ForeColor = $Colors.Muted
    $dialog.Controls.Add($subtitle)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = [System.Drawing.Point]::new(20,86)
    $grid.Size = [System.Drawing.Size]::new(900,500)
    $grid.Anchor = 'Top,Bottom,Left,Right'
    $grid.BackgroundColor = $Colors.Surface
    $grid.BorderStyle = 'FixedSingle'
    $grid.GridColor = $Colors.Border
    $grid.ForeColor = $Colors.Text
    $grid.DefaultCellStyle.BackColor = $Colors.Surface
    $grid.DefaultCellStyle.ForeColor = $Colors.Text
    $grid.DefaultCellStyle.SelectionBackColor = $Colors.PanelAlt
    $grid.DefaultCellStyle.SelectionForeColor = $Colors.Text
    $grid.AlternatingRowsDefaultCellStyle.BackColor = $Colors.Panel
    $grid.ColumnHeadersDefaultCellStyle.BackColor = $Colors.PanelAlt
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = $Colors.Text
    $grid.EnableHeadersVisualStyles = $false
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.RowHeadersVisible = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.AutoSizeRowsMode = 'AllCells'
    [void]$grid.Columns.Add('Section','Section')
    [void]$grid.Columns.Add('Item','Item')
    [void]$grid.Columns.Add('Value','Value')
    $grid.Columns['Section'].Width = 110
    $grid.Columns['Item'].Width = 180
    $grid.Columns['Value'].AutoSizeMode = 'Fill'
    $grid.Columns['Value'].DefaultCellStyle.WrapMode = 'True'
    $dialog.Controls.Add($grid)

    $refresh = New-Object System.Windows.Forms.Button
    $refresh.Text = 'Refresh'
    $refresh.Location = [System.Drawing.Point]::new(690,596)
    $refresh.Size = [System.Drawing.Size]::new(110,34)
    $refresh.Anchor = 'Bottom,Right'
    Set-ActionButtonStyle -b $refresh
    $dialog.Controls.Add($refresh)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'Close'
    $close.Location = [System.Drawing.Point]::new(810,596)
    $close.Size = [System.Drawing.Size]::new(110,34)
    $close.Anchor = 'Bottom,Right'
    Set-ActionButtonStyle -b $close -back $Colors.Accent -fore ([System.Drawing.Color]::White)
    $close.Add_Click({ $dialog.Close() })
    $dialog.Controls.Add($close)

    $loadRows = {
        $grid.Rows.Clear()
        foreach ($row in @(Get-SystemInformationRows)) {
            [void]$grid.Rows.Add($row.Section,$row.Item,$row.Value)
        }
        $grid.ClearSelection()
    }

    $refresh.Add_Click($loadRows)
    $dialog.Add_Shown($loadRows)
    [void]$dialog.ShowDialog($Owner)
}

function Show-DeviceInformation {
    $d=New-Object System.Windows.Forms.Form
    $d.Text='Hardware & Input Device Information'
    $d.Size=[System.Drawing.Size]::new(920,570);$d.StartPosition='CenterParent';$d.BackColor=$Colors.Background;$d.ForeColor=$Colors.Text
    $grid=New-Object System.Windows.Forms.DataGridView
    $grid.Location=[System.Drawing.Point]::new(14,14)
    $grid.Size=[System.Drawing.Size]::new(876,465)
    $grid.Anchor='Top,Bottom,Left,Right'
    $grid.ReadOnly=$true
    $grid.AllowUserToAddRows=$false
    $grid.AllowUserToDeleteRows=$false
    $grid.AllowUserToResizeRows=$false
    $grid.RowHeadersVisible=$false
    $grid.BackgroundColor=$Colors.Surface
    $grid.ForeColor=$Colors.Text
    $grid.DefaultCellStyle.BackColor=$Colors.Surface
    $grid.DefaultCellStyle.ForeColor=$Colors.Text
    $grid.ColumnHeadersDefaultCellStyle.BackColor=$Colors.PanelAlt
    $grid.ColumnHeadersDefaultCellStyle.ForeColor=$Colors.Text
    $grid.EnableHeadersVisualStyles=$false
    $grid.AutoSizeRowsMode='AllCells'
    $grid.DefaultCellStyle.WrapMode='False'

    # Keep short fields compact and let the long PNP Device ID column use
    # whatever horizontal space remains in the window.
    [void]$grid.Columns.Add('Type','Type')
    [void]$grid.Columns.Add('Name','Name')
    [void]$grid.Columns.Add('Manufacturer','Manufacturer')
    [void]$grid.Columns.Add('Status','Status')
    [void]$grid.Columns.Add('PNP','Connection / PNP Device ID')

    $grid.Columns['Type'].AutoSizeMode='AllCells'
    $grid.Columns['Type'].MinimumWidth=65

    $grid.Columns['Name'].AutoSizeMode='DisplayedCells'
    $grid.Columns['Name'].MinimumWidth=150

    $grid.Columns['Manufacturer'].AutoSizeMode='DisplayedCells'
    $grid.Columns['Manufacturer'].MinimumWidth=100

    $grid.Columns['Status'].AutoSizeMode='AllCells'
    $grid.Columns['Status'].MinimumWidth=70

    $grid.Columns['PNP'].AutoSizeMode='Fill'
    $grid.Columns['PNP'].FillWeight=100
    $grid.Columns['PNP'].MinimumWidth=260

    $d.Controls.Add($grid)
    try {
        $devices=@(Get-CimInstance Win32_Keyboard -ErrorAction Stop | ForEach-Object {[pscustomobject]@{Type='Keyboard';Name=$_.Name;Manufacturer=$_.Manufacturer;Status=$_.Status;PNP=$_.PNPDeviceID}})
        $devices+=@(Get-CimInstance Win32_PointingDevice -ErrorAction Stop | ForEach-Object {[pscustomobject]@{Type='Mouse / Pointing';Name=$_.Name;Manufacturer=$_.Manufacturer;Status=$_.Status;PNP=$_.PNPDeviceID}})

        # Win32_PointingDevice often reports a touchpad generically. Add matching
        # PnP entities so Windows' friendlier touchpad/touchscreen names are shown.
        $touchDevices = @(
            Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '(?i)touch.?pad|trackpad|precision touch|touch.?screen|touchscreen'
            } |
            ForEach-Object {
                $type = if($_.Name -match '(?i)screen'){'Touchscreen'}else{'Trackpad'}
                [pscustomobject]@{
                    Type=$type
                    Name=$_.Name
                    Manufacturer=$_.Manufacturer
                    Status=$_.Status
                    PNP=$_.PNPDeviceID
                }
            }
        )
        $devices += $touchDevices

        foreach($dev in $devices){
            [void]$grid.Rows.Add($dev.Type,$dev.Name,$dev.Manufacturer,$dev.Status,$dev.PNP)
        }
    } catch {
        [void]$grid.Rows.Add('Info','Unable to query CIM device information',$_.Exception.Message,'','')
    }
    $controller=New-Object System.Windows.Forms.Button;$controller.Text='Controller test';$controller.Location=[System.Drawing.Point]::new(518,490);$controller.Size=[System.Drawing.Size]::new(126,32);$controller.Anchor='Bottom,Right';Set-ActionButtonStyle -b $controller;$controller.Add_Click({Show-ControllerDiagnostics -Owner $d});$d.Controls.Add($controller)
    $system=New-Object System.Windows.Forms.Button;$system.Text='System info';$system.Location=[System.Drawing.Point]::new(654,490);$system.Size=[System.Drawing.Size]::new(126,32);$system.Anchor='Bottom,Right';Set-ActionButtonStyle -b $system;$system.Add_Click({Show-SystemInformation -Owner $d});$d.Controls.Add($system)
    $close=New-Object System.Windows.Forms.Button;$close.Text='Close';$close.Location=[System.Drawing.Point]::new(790,490);$close.Size=[System.Drawing.Size]::new(100,32);$close.Anchor='Bottom,Right';Set-ActionButtonStyle -b $close -back $Colors.Accent -fore ([System.Drawing.Color]::White);$close.Add_Click({$d.Close()});$d.Controls.Add($close)
    [void]$d.ShowDialog($Form)
}

function Get-DiagnosticReport {
    $elapsed = if($script:SessionStarted){(Get-Date)-$script:SessionStarted}else{[TimeSpan]::Zero}
    $topShortcuts = @($script:ShortcutCounts.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending | Select-Object -First 10)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('INPUT & HARDWARE DIAGNOSTICS REPORT')
    $lines.Add(('Generated: {0}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))
    $lines.Add('Privacy: memory-only diagnostics; typed text is not reconstructed or saved.')
    $lines.Add('')

    $lines.Add('SESSION')
    $lines.Add(('Duration: {0:hh\:mm\:ss}' -f $elapsed))
    $lines.Add("Key presses: $($script:Stats.Keys)")
    $lines.Add("Shortcuts: $($script:Stats.Shortcuts)")
    $lines.Add("Mouse clicks: $($script:Stats.MouseClicks)")
    $lines.Add("Wheel events: $($script:Stats.Wheel)")
    $lines.Add('')

    if (-not $script:HardwareTestStarted) {
        $lines.Add('HARDWARE TEST')
        $lines.Add('Status: NOT RUN')
        $lines.Add('')
        $lines.Add('Test Mode has not been started in this session.')
        $lines.Add('Enable Test Mode before testing the keyboard or mouse to generate PASS / ATTENTION results.')
        $lines.Add('')
    }
    else {
        $progress = Get-TestCompletion
        $mapped = @(Get-TestMappedKeys)
        $missing = @($mapped | Where-Object {
            -not $script:TestKeyCounts.ContainsKey($_) -or [int]$script:TestKeyCounts[$_] -le 0
        } | ForEach-Object { Get-KeyName $_ } | Sort-Object)

        $kResult = Get-KeyboardTestResult
        $mResult = Get-MouseTestResult

        $lines.Add('OVERALL TEST RESULTS')
        $lines.Add("Keyboard: $($kResult.Status)")
        $lines.Add("Mouse: $($mResult.Status)")
        $lines.Add("Keyboard layout profile: $($script:KeyboardLayoutMode)")
        $lines.Add('')

        $lines.Add('KEYBOARD TEST')
        $lines.Add("Completion: $($progress.Tested)/$($progress.Total) keys ($($progress.Percent)%)")
        $lines.Add("Potential stuck-key threshold: $($script:StuckKeyThresholdMs) ms")
        $lines.Add($(if($missing.Count -gt 0){'Not tested: ' + ($missing -join ', ')}else{'Not tested: none'}))
        $lines.Add("Maximum simultaneous keys observed: $($script:MaxSimultaneousKeys)")
        $lines.Add("Possible switch chatter: $(Get-ChatterSummary)")
        $lines.Add("Chatter threshold: $($script:ChatterThresholdMs) ms")
        $lines.Add('')

        # Only include detailed per-key rows for keys that were actually pressed.
        $testedKeys = @($mapped | Where-Object {
            $script:TestKeyCounts.ContainsKey($_) -and [int]$script:TestKeyCounts[$_] -gt 0
        } | Sort-Object { Get-KeyName $_ })

        $lines.Add('TESTED KEY TIMING')
        if($testedKeys.Count -eq 0) {
            $lines.Add('No keyboard keys were tested.')
        } else {
            $lines.Add('Key | Test presses | Avg hold | Longest hold')
            foreach($vk in $testedKeys) {
                $stat = Get-OrCreateTestKeyStat $vk
                $testPresses = [int]$script:TestKeyCounts[$vk]
                $avg = if($stat.Count -gt 0){[Math]::Round($stat.TotalHoldMs / $stat.Count)}else{0}
                $longest = [Math]::Round($stat.LongestHoldMs)
                $lines.Add("$(Get-KeyName $vk) | $testPresses | ${avg} ms | ${longest} ms")
            }
        }
        $lines.Add('')

        $lines.Add('MOUSE TEST')
        $lines.Add("Button counts: LEFT=$($script:MouseClickCounts.LEFT), RIGHT=$($script:MouseClickCounts.RIGHT), MIDDLE=$($script:MouseClickCounts.MIDDLE), X1=$($script:MouseClickCounts.X1), X2=$($script:MouseClickCounts.X2)")
        $lines.Add("Wheel events: $($script:TestWheelEvents)")
        $lines.Add("Possible mouse chatter: " + $(if($mResult.Chatter.Count){($mResult.Chatter | ForEach-Object {"$($_.Key)=$($_.Value)"}) -join ', '}else{'None detected'}))
        $lines.Add('')
    }

    $lines.Add('TOP SHORTCUTS')
    if($topShortcuts.Count -eq 0){
        $lines.Add('None observed.')
    } else {
        foreach($entry in $topShortcuts){$lines.Add("$($entry.Key) | $($entry.Value.Count)")}
    }

    $lines.Add('')
    $lines.Add('NOTE')
    $lines.Add('Normal capture activity is not automatically treated as a completed hardware test.')
    $lines.Add('Hold timing is measured from key-down to key-up. True hardware switch latency requires an external reference/stimulus and cannot be measured by this Windows hook alone.')

    return ($lines -join [Environment]::NewLine)
}

function Show-DiagnosticReport {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Diagnostic Report'
    $dialog.Size = New-Object System.Drawing.Size(820,720)
    $dialog.MinimumSize = New-Object System.Drawing.Size(680,520)
    $dialog.StartPosition = 'CenterParent'
    $dialog.BackColor = $Colors.Background
    $dialog.ForeColor = $Colors.Text
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $dialog.FormBorderStyle = 'Sizable'
    $dialog.MaximizeBox = $true
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false

    $reportBox = New-Object System.Windows.Forms.TextBox
    $reportBox.Multiline = $true
    $reportBox.ReadOnly = $true
    $reportBox.ScrollBars = 'Both'
    $reportBox.WordWrap = $false
    $reportBox.BackColor = $Colors.Surface
    $reportBox.ForeColor = $Colors.Text
    $reportBox.Font = New-Object System.Drawing.Font('Cascadia Mono',9)
    $reportBox.Location = New-Object System.Drawing.Point(14,14)
    $reportBox.Size = New-Object System.Drawing.Size(774,610)
    $reportBox.Anchor = 'Top,Bottom,Left,Right'
    $reportBox.Text = Get-DiagnosticReport
    $dialog.Controls.Add($reportBox)

    $copy = New-Object System.Windows.Forms.Button
    $copy.Text = 'Copy report'
    $copy.Location = New-Object System.Drawing.Point(570,635)
    $copy.Size = New-Object System.Drawing.Size(105,32)
    $copy.Anchor = 'Bottom,Right'
    $copy.FlatStyle = 'Flat'
    $copy.FlatAppearance.BorderColor = $Colors.Border
    $copy.BackColor = $Colors.Accent
    $copy.ForeColor = [System.Drawing.Color]::White
    $copy.Add_Click({
        [System.Windows.Forms.Clipboard]::SetText($reportBox.Text)
        $copy.Text = 'Copied'
    })
    $dialog.Controls.Add($copy)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'Close'
    $close.Location = New-Object System.Drawing.Point(683,635)
    $close.Size = New-Object System.Drawing.Size(105,32)
    $close.Anchor = 'Bottom,Right'
    $close.FlatStyle = 'Flat'
    $close.FlatAppearance.BorderColor = $Colors.Border
    $close.BackColor = $Colors.PanelAlt
    $close.ForeColor = $Colors.Text
    $close.Add_Click({$dialog.Close()})
    $dialog.Controls.Add($close)

    [void]$dialog.ShowDialog($Form)
}

function Get-KeyName {
    param([int]$VkCode)
    $map = @{
        8='BACKSPACE';9='TAB';13='ENTER';16='SHIFT';17='CTRL';18='ALT';19='PAUSE';20='CAPS LOCK';27='ESC'
        32='SPACE';33='PAGE UP';34='PAGE DOWN';35='END';36='HOME';37='LEFT';38='UP';39='RIGHT';40='DOWN'
        44='PRINT SCREEN';45='INSERT';46='DELETE';91='LEFT WIN';92='RIGHT WIN';93='MENU';144='NUM LOCK';145='SCROLL LOCK'
        160='LEFT SHIFT';161='RIGHT SHIFT';162='LEFT CTRL';163='RIGHT CTRL';164='LEFT ALT';165='RIGHT ALT'
        186=';';187='=';188=',';189='-';190='.';191='/';192='`';219='[';220='\';221=']';222="'"
        96='NUM 0';97='NUM 1';98='NUM 2';99='NUM 3';100='NUM 4';101='NUM 5';102='NUM 6';103='NUM 7';104='NUM 8';105='NUM 9'
        106='NUM *';107='NUM +';109='NUM -';110='NUM .';111='NUM /'
    }
    if ($map.ContainsKey($VkCode)) { return $map[$VkCode] }
    if ($VkCode -ge 112 -and $VkCode -le 123) { return 'F' + ($VkCode - 111) }
    if (($VkCode -ge 48 -and $VkCode -le 57) -or ($VkCode -ge 65 -and $VkCode -le 90)) { return [char]$VkCode }
    return "VK $VkCode"
}


function Get-KeyCategoryName {
    param([int]$VkCode)
    if ($VkCode -in 8,46) { return 'Destructive' }
    if (($VkCode -ge 112 -and $VkCode -le 123) -or $VkCode -in 27,44,145,19) { return 'Function' }
    if ($VkCode -in 9,13,16,17,18,20,91,92,93,160,161,162,163,164,165) { return 'Modifier' }
    if ($VkCode -in 33,34,35,36,37,38,39,40,45,144) { return 'Navigation' }
    if ($VkCode -ge 96 -and $VkCode -le 111) { return 'Number Pad' }
    return 'Typing'
}

function Test-PrintableKey {
    param([int]$VkCode)
    return (
        ($VkCode -ge 48 -and $VkCode -le 90) -or
        ($VkCode -ge 96 -and $VkCode -le 111) -or
        $VkCode -in 32,186,187,188,189,190,191,192,219,220,221,222
    )
}

function Format-Shortcut {
    param([string]$Modifiers,[string]$KeyName)
    $items = @()
    foreach ($name in @('CTRL','ALT','SHIFT','WIN')) {
        if (($Modifiers -split '\+') -contains $name) { $items += $name }
    }
    $items += $KeyName
    return ($items -join '+')
}

function Get-ShortcutDescription {
    param([string]$Shortcut)
    $known = @{
        'CTRL+C'='Copy'; 'CTRL+V'='Paste'; 'CTRL+X'='Cut'; 'CTRL+Z'='Undo'; 'CTRL+Y'='Redo'
        'CTRL+A'='Select all'; 'CTRL+S'='Save'; 'CTRL+P'='Print'; 'CTRL+F'='Find'; 'CTRL+N'='New'
        'CTRL+SHIFT+ESC'='Task Manager'; 'ALT+TAB'='Switch applications'; 'ALT+F4'='Close window'
        'WIN+R'='Run'; 'WIN+E'='File Explorer'; 'WIN+D'='Show desktop'; 'WIN+L'='Lock computer'
        'CTRL+SHIFT+T'='Reopen closed tab'; 'CTRL+T'='New tab'; 'CTRL+W'='Close tab'
    }
    if ($known.ContainsKey($Shortcut)) { return $known[$Shortcut] }
    return ''
}

function Get-GhostColor {
    param([System.Drawing.Color]$Source,[double]$Strength)
    $r = [int]($Colors.Key.R + (($Source.R - $Colors.Key.R) * $Strength))
    $g = [int]($Colors.Key.G + (($Source.G - $Colors.Key.G) * $Strength))
    $b = [int]($Colors.Key.B + (($Source.B - $Colors.Key.B) * $Strength))
    return [System.Drawing.Color]::FromArgb($r,$g,$b)
}

function Get-OrCreateKeyStat {
    param([int]$VkCode)
    if (-not $script:KeyStats.ContainsKey($VkCode)) {
        $script:KeyStats[$VkCode] = @{
            Count = 0
            TotalHoldMs = 0.0
            LongestHoldMs = 0.0
            LastUsed = $null
            LastScan = 0
            LastFlags = 0
            IsDown = $false
        }
    }
    return $script:KeyStats[$VkCode]
}

function Get-OrCreateTestKeyStat {
    param([int]$VkCode)

    if (-not $script:TestKeyStats.ContainsKey($VkCode)) {
        $script:TestKeyStats[$VkCode] = @{
            Count = 0
            TotalHoldMs = 0.0
            LongestHoldMs = 0.0
        }
    }

    return $script:TestKeyStats[$VkCode]
}

function Update-KeyInspector {
    param([int]$VkCode)
    $script:SelectedInspectorVk = $VkCode
    $stat = Get-OrCreateKeyStat $VkCode
    $count = [int]$stat.Count
    $average = if ($count -gt 0) { [Math]::Round($stat.TotalHoldMs / $count) } else { 0 }
    $last = if ($stat.LastUsed) { $stat.LastUsed.ToString('HH:mm:ss.fff') } else { 'Never' }
    $InspectorName.Text = Get-KeyName $VkCode
    $InspectorVk.Text = ('{0}  (0x{0:X2})' -f $VkCode)
    $InspectorScan.Text = ('{0}  (0x{0:X2})' -f [int]$stat.LastScan)
    $InspectorCategory.Text = Get-KeyCategoryName $VkCode
    $InspectorState.Text = if ($stat.IsDown) { 'PRESSED' } else { 'Released' }
    $InspectorCount.Text = [string]$count
    $InspectorAverage.Text = "${average} ms"
    $InspectorLongest.Text = "$([Math]::Round($stat.LongestHoldMs)) ms"
    $InspectorLast.Text = $last
}

function Update-ShortcutAnalyzer {
    $ShortcutList.BeginUpdate()
    $ShortcutList.Items.Clear()
    foreach ($entry in $script:ShortcutCounts.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending | Select-Object -First 12) {
        $item = New-Object System.Windows.Forms.ListViewItem($entry.Key)
        [void]$item.SubItems.Add([string]$entry.Value.Count)
        [void]$item.SubItems.Add($entry.Value.Last.ToString('HH:mm:ss'))
        [void]$ShortcutList.Items.Add($item)
    }
    $ShortcutList.EndUpdate()
}

function Write-Feed {
    param(
        [string]$Category,
        [string]$Message,
        [string]$Timestamp = $null
    )

    if (-not $Timestamp) {
        $Timestamp = Get-Date -Format 'HH:mm:ss.fff'
    }

    if (-not $FeedGrid) {
        return
    }

    $device = if ($Category -eq 'MOUSE') {
        'Mouse'
    }
    elseif ($Category -in 'SYSTEM','TEST','WARNING','SHORTCUT') {
        'System'
    }
    else {
        'Keyboard'
    }

    $eventType = $Category
    $key   = ''
    $scan  = ''
    $vkey  = ''
    $mods  = ''

    if ($Category -in 'KEY DOWN','KEY UP') {
        if ($Message -match '^(.+?)\s+VK=(\d+)\s+SCAN=(\d+)') {
            $key  = $matches[1].Trim()
            $vkey = '0x{0:X2}' -f [int]$matches[2]
            $scan = '0x{0:X2}' -f [int]$matches[3]
        }
        elseif ($Message -match '^(.+?)\s+HELD=') {
            $key = $matches[1].Trim()
        }
    }
    elseif ($Category -eq 'SHORTCUT') {
        $key = $Message
    }
    elseif ($Category -eq 'MOUSE') {
        $key = $Message
    }
    else {
        $key = $Message
    }

    [void]$FeedGrid.Rows.Add(
        $Timestamp,
        $device,
        $eventType,
        $key,
        $scan,
        $vkey,
        $mods
    )

    while ($FeedGrid.Rows.Count -gt $script:MaxFeedLines) {
        $FeedGrid.Rows.RemoveAt(0)
    }

    if ($FeedCountLabel) {
        $FeedCountLabel.Text = "$($FeedGrid.Rows.Count) / $script:MaxFeedLines"
        $FeedCountLabel.ForeColor = if ($FeedGrid.Rows.Count -ge $script:MaxFeedLines) { $Colors.Warning } else { $Colors.Muted }
    }

    if ($FeedGrid.Rows.Count -gt 0) {
        $FeedGrid.FirstDisplayedScrollingRowIndex = $FeedGrid.Rows.Count - 1
    }
}

function Update-Stats {
    if ($TotalKeysValue) { $TotalKeysValue.Text = ('{0:N0}' -f $script:Stats.Keys) }
    if ($KeysValue) { $KeysValue.Text = ('{0:N0}' -f $script:Stats.Keys) }
    if ($ShortcutValue) { $ShortcutValue.Text = [string]$script:Stats.Shortcuts }
    if ($MouseValue) { $MouseValue.Text = [string]$script:Stats.MouseClicks }
    if ($WheelValue) { $WheelValue.Text = [string]$script:Stats.Wheel }

    $kpm=0; $avgWpm=0
    if ($script:SessionStarted) {
        $elapsed=(Get-Date)-$script:SessionStarted
        $minutes=[Math]::Max($elapsed.TotalMinutes,1.0/60.0)
        $kpm=[Math]::Round($script:Stats.Keys/$minutes)
        $avgWpm=[Math]::Round(($script:PrintableKeyCount/5.0)/$minutes)
        if ($CaptureElapsedValue) { $CaptureElapsedValue.Text = $elapsed.ToString('hh\:mm\:ss') }
    }
    if ($KpmValue) { $KpmValue.Text=[string]$kpm }
    if ($KeysPerMinuteValue) { $KeysPerMinuteValue.Text=[string]$kpm }
    if ($AverageWpmValue) { $AverageWpmValue.Text=[string]$avgWpm }

    $cutoff=(Get-Date).AddSeconds(-60)
    for($i=$script:PrintablePressTimes.Count-1;$i -ge 0;$i--){ if($script:PrintablePressTimes[$i] -lt $cutoff){$script:PrintablePressTimes.RemoveAt($i)} }
    $currentWpm=0
    if($script:PrintablePressTimes.Count -gt 0){
        $windowMinutes=[Math]::Min(1.0,[Math]::Max(((Get-Date)-$script:PrintablePressTimes[0]).TotalMinutes,1.0/60.0))
        $currentWpm=[Math]::Round(($script:PrintablePressTimes.Count/5.0)/$windowMinutes)
    }
    if ($CurrentWpmValue) { $CurrentWpmValue.Text=[string]$currentWpm }

    if ($UniqueKeysValue) { $UniqueKeysValue.Text=[string]$script:KeyStats.Count }
    $allStats=@($script:KeyStats.Values)
    $totalCount=0; $totalHold=0.0; $longest=0.0
    foreach($st in $allStats){ $totalCount += [int]$st.Count; $totalHold += [double]$st.TotalHoldMs; if([double]$st.LongestHoldMs -gt $longest){$longest=[double]$st.LongestHoldMs} }
    if ($AverageHoldValue) { $AverageHoldValue.Text = if($totalCount -gt 0){"$([Math]::Round($totalHold/$totalCount)) ms"}else{'0 ms'} }
    if ($LongestHoldValue) { $LongestHoldValue.Text = "$([Math]::Round($longest)) ms" }
    if ($EstimatedWpmValue) { $EstimatedWpmValue.Text=[string]$currentWpm }
}


function Update-LockIndicators {
    $CapsOn=[System.Windows.Forms.Control]::IsKeyLocked([System.Windows.Forms.Keys]::CapsLock)
    $NumOn=[System.Windows.Forms.Control]::IsKeyLocked([System.Windows.Forms.Keys]::NumLock)
    $ScrollOn=[System.Windows.Forms.Control]::IsKeyLocked([System.Windows.Forms.Keys]::Scroll)
    foreach($pair in @(@($CapsLed,$CapsOn,'CAPS LOCK'),@($NumLed,$NumOn,'NUM LOCK'),@($ScrollLed,$ScrollOn,'SCROLL LOCK'))){
        $led=$pair[0]; $on=[bool]$pair[1]; $name=$pair[2]
        if($led){
            $led.Text = if($on){"●  $name`r`n     ●  ON"}else{"●  $name`r`n     ●  OFF"}
            $led.ForeColor=if($on){$Colors.Letter}else{$Colors.Muted}
            $led.BackColor=$Colors.PanelAlt
        }
    }
}


# New-KeyButton is defined after the keyboard panel is created so every
# visual key is added to the correct parent container.

# ---------------------------- Form ----------------------------
$script:BaseTitle='Input & Hardware Diagnostics v8.0.0'
$Form=New-Object System.Windows.Forms.Form
$Form.Text=$script:BaseTitle
$Form.ClientSize=New-Object System.Drawing.Size(1536,1038)
$Form.MinimumSize=New-Object System.Drawing.Size(1280,820)
$Form.StartPosition='CenterScreen'
$Form.BackColor=$Colors.Background
$Form.ForeColor=$Colors.Text
$Form.Font=New-Object System.Drawing.Font('Segoe UI',9.25)
$Form.FormBorderStyle='Sizable'
$Form.MaximizeBox=$true
$Form.TopMost=$false
$Form.AutoScaleMode=[System.Windows.Forms.AutoScaleMode]::Dpi
$Form.KeyPreview=$true

function New-Panel([int]$x,[int]$y,[int]$w,[int]$h) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = [System.Drawing.Point]::new($x,$y)
    $p.Size = [System.Drawing.Size]::new($w,$h)
    $p.BackColor = $Colors.Surface
    $p.BorderStyle = 'None'

    $p.Add_Paint({
        param($panelControl, $paintArgs)

        $pen = New-Object System.Drawing.Pen($Colors.Border,1)

        try {
            $borderWidth = [Math]::Max(
                0,
                ([int]$panelControl.ClientSize.Width - 1)
            )

            $borderHeight = [Math]::Max(
                0,
                ([int]$panelControl.ClientSize.Height - 1)
            )

            $rectangle = [System.Drawing.Rectangle]::new(
                0,
                0,
                $borderWidth,
                $borderHeight
            )

            $paintArgs.Graphics.DrawRectangle(
                $pen,
                $rectangle
            )
        }
        finally {
            $pen.Dispose()
        }
    })

    $Form.Controls.Add($p)

    return $p
}
function New-TextLabel($parent,[string]$text,[int]$x,[int]$y,[int]$w,[int]$h,[float]$size=9,[System.Drawing.Color]$color=$Colors.Text,[bool]$bold=$false){
    $l=New-Object System.Windows.Forms.Label;$l.Text=$text;$l.Location=[System.Drawing.Point]::new($x,$y);$l.Size=[System.Drawing.Size]::new($w,$h);$l.ForeColor=$color;$l.BackColor=[System.Drawing.Color]::Transparent
    $style=if($bold){[System.Drawing.FontStyle]::Bold}else{[System.Drawing.FontStyle]::Regular};$l.Font=New-Object System.Drawing.Font('Segoe UI',$size,$style);$parent.Controls.Add($l);return $l
}
function Set-ActionButtonStyle(
    $b,
    [System.Drawing.Color]$back = $Colors.PanelAlt,
    [System.Drawing.Color]$fore = $Colors.Text
) {
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $Colors.Border
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(48,55,66)
    $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(58,67,81)
    $b.BackColor = $back
    $b.ForeColor = $fore
    $b.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.TabStop = $false
    $b.TextAlign = 'MiddleCenter'
    $b.Padding = New-Object System.Windows.Forms.Padding(5,0,5,0)
}
function Add-SectionAccent($parent,[int]$x=14,[int]$y=35,[int]$width=42) {
    $line=New-Object System.Windows.Forms.Panel
    $line.Location=[System.Drawing.Point]::new($x,$y)
    $line.Size=[System.Drawing.Size]::new($width,2)
    $line.BackColor=$Colors.Accent
    $parent.Controls.Add($line)
    return $line
}

$ToolTip=New-Object System.Windows.Forms.ToolTip
$ToolTip.AutoPopDelay=6500
$ToolTip.InitialDelay=450
$ToolTip.ReshowDelay=100
$ToolTip.ShowAlways=$true

# Title bar
$TitleLabel=New-Object System.Windows.Forms.Label;$TitleLabel.Text='Input & Hardware Diagnostics  •  v8.0.0';$TitleLabel.Location=[System.Drawing.Point]::new(18,7);$TitleLabel.Size=[System.Drawing.Size]::new(760,30);$TitleLabel.Font=New-Object System.Drawing.Font('Segoe UI Semibold',12,[System.Drawing.FontStyle]::Bold);$TitleLabel.ForeColor=$Colors.Text;$Form.Controls.Add($TitleLabel)

# Dashboard cards
$Dash=New-Panel 14 42 1508 94
$Dash.BackColor=$Colors.Surface
[void](New-TextLabel $Dash 'Capture status' 24 12 150 18 8.25 $Colors.Muted)
$CaptureStatusValue=New-TextLabel $Dash '● STOPPED' 24 34 150 22 10 $Colors.Destructive $true
$CaptureElapsedValue=New-TextLabel $Dash '● 00:00:00' 24 58 150 22 10 $Colors.Muted

[void](New-TextLabel $Dash 'Events' 205 12 110 18 8.25 $Colors.Muted)
$TotalKeysValue=New-TextLabel $Dash '0' 205 36 110 35 18 $Colors.Text $true
[void](New-TextLabel $Dash 'Keys / Min' 350 12 120 18 8.25 $Colors.Muted)
$KeysPerMinuteValue=New-TextLabel $Dash '0' 350 36 120 35 18 $Colors.Text $true
[void](New-TextLabel $Dash 'Test mode' 500 12 120 18 8.25 $Colors.Muted)
$TestModeValue=New-TextLabel $Dash '⚗ OFF' 500 37 120 32 17 $Colors.Muted $true
[void](New-TextLabel $Dash 'Keys tested' 640 12 170 18 8.25 $Colors.Muted)
$TestProgressLabel=New-TextLabel $Dash '0 / 103 (0%)' 640 34 220 28 14 $Colors.Text $true
$TestProgressBar=New-Object System.Windows.Forms.ProgressBar;$TestProgressBar.Location=[System.Drawing.Point]::new(640,66);$TestProgressBar.Size=[System.Drawing.Size]::new(400,9);$TestProgressBar.Style='Continuous';$Dash.Controls.Add($TestProgressBar)
[void](New-TextLabel $Dash 'Stuck keys' 1075 12 75 18 8.25 $Colors.Muted)
$StuckKeysValue=New-TextLabel $Dash '0  ✓' 1075 38 75 30 17 $Colors.Text $true

$SettingsButton=New-Object System.Windows.Forms.Button
$SettingsButton.Text='Settings'
$SettingsButton.Location=[System.Drawing.Point]::new(1170,25)
$SettingsButton.Size=[System.Drawing.Size]::new(90,44)
Set-ActionButtonStyle -b $SettingsButton
$Dash.Controls.Add($SettingsButton)

$DeviceButton=New-Object System.Windows.Forms.Button
$DeviceButton.Text='Hardware'
$DeviceButton.Location=[System.Drawing.Point]::new(1270,25)
$DeviceButton.Size=[System.Drawing.Size]::new(90,44)
Set-ActionButtonStyle -b $DeviceButton
$Dash.Controls.Add($DeviceButton)

$AboutButton=New-Object System.Windows.Forms.Button
$AboutButton.Text='About'
$AboutButton.Location=[System.Drawing.Point]::new(1370,25)
$AboutButton.Size=[System.Drawing.Size]::new(90,44)
Set-ActionButtonStyle -b $AboutButton
$Dash.Controls.Add($AboutButton)

$SettingsButton.BringToFront()
$DeviceButton.BringToFront()
$AboutButton.BringToFront()

# Toolbar
$Toolbar=New-Panel 14 144 1508 62
$PauseButton=New-Object System.Windows.Forms.Button;$PauseButton.Text='Ⅱ  Pause capture';$PauseButton.Location=[System.Drawing.Point]::new(55,8);$PauseButton.Size=[System.Drawing.Size]::new(195,44);Set-ActionButtonStyle -b $PauseButton -back ([System.Drawing.Color]::FromArgb(23,94,190)) -fore ([System.Drawing.Color]::White);$Toolbar.Controls.Add($PauseButton)
$StartButton=New-Object System.Windows.Forms.Button;$StartButton.Text='▶  Start capture';$StartButton.Location=[System.Drawing.Point]::new(55,8);$StartButton.Size=[System.Drawing.Size]::new(195,44);Set-ActionButtonStyle -b $StartButton -back ([System.Drawing.Color]::FromArgb(23,94,190)) -fore ([System.Drawing.Color]::White);$Toolbar.Controls.Add($StartButton)
$StopButton=New-Object System.Windows.Forms.Button;$StopButton.Text='□  Stop capture';$StopButton.Location=[System.Drawing.Point]::new(275,8);$StopButton.Size=[System.Drawing.Size]::new(200,44);Set-ActionButtonStyle -b $StopButton -back $Colors.PanelAlt -fore $Colors.Destructive;$Toolbar.Controls.Add($StopButton)
$ClearButton=New-Object System.Windows.Forms.Button;$ClearButton.Text='♜  Clear feed';$ClearButton.Location=[System.Drawing.Point]::new(500,8);$ClearButton.Size=[System.Drawing.Size]::new(195,44);Set-ActionButtonStyle -b $ClearButton;$Toolbar.Controls.Add($ClearButton)
$ResetTestButton=New-Object System.Windows.Forms.Button;$ResetTestButton.Text='↻  Reset test';$ResetTestButton.Location=[System.Drawing.Point]::new(720,8);$ResetTestButton.Size=[System.Drawing.Size]::new(195,44);Set-ActionButtonStyle -b $ResetTestButton;$Toolbar.Controls.Add($ResetTestButton)
$ChecklistButton=New-Object System.Windows.Forms.Button;$ChecklistButton.Text='☷  Checklist';$ChecklistButton.Location=[System.Drawing.Point]::new(940,8);$ChecklistButton.Size=[System.Drawing.Size]::new(180,44);Set-ActionButtonStyle -b $ChecklistButton;$Toolbar.Controls.Add($ChecklistButton)
$TestModeButton=New-Object System.Windows.Forms.Button;$TestModeButton.Text='⚗  Test mode: OFF';$TestModeButton.Location=[System.Drawing.Point]::new(1140,8);$TestModeButton.Size=[System.Drawing.Size]::new(150,44);Set-ActionButtonStyle -b $TestModeButton;$Toolbar.Controls.Add($TestModeButton)
$ReportButton=New-Object System.Windows.Forms.Button
$ReportButton.Text='Diagnostic report'
$ReportButton.Location=[System.Drawing.Point]::new(1310,8)
$ReportButton.Size=[System.Drawing.Size]::new(185,44)
Set-ActionButtonStyle -b $ReportButton -back ([System.Drawing.Color]::FromArgb(23,94,190)) -fore ([System.Drawing.Color]::White)
$Toolbar.Controls.Add($ReportButton)
$PauseButton.Visible=$false
$ToolTip.SetToolTip($StartButton,'Begin global keyboard and mouse diagnostic capture.')
$ToolTip.SetToolTip($PauseButton,'Pause capture without resetting the current session statistics.')
$ToolTip.SetToolTip($StopButton,'Stop capture and release the Windows input hooks.')
$ToolTip.SetToolTip($ClearButton,'Clear only the live diagnostic feed. Statistics stay in memory.')
$ToolTip.SetToolTip($ResetTestButton,'Reset keyboard test completion, heat map, and chatter counters.')
$ToolTip.SetToolTip($ChecklistButton,'Open the full mapped-key test checklist and per-key timing results.')
$ToolTip.SetToolTip($TestModeButton,'Toggle keyboard test mode and heat-map tracking.')
$ToolTip.SetToolTip($ReportButton,'Open the in-memory diagnostic report.')
$ToolTip.SetToolTip($SettingsButton,'Change always-on-top and stuck-key warning threshold.')
$ToolTip.SetToolTip($AboutButton,'About this diagnostic utility and its privacy behavior.')
if ($null -ne $DeviceButton) { $ToolTip.SetToolTip($DeviceButton,'Open input devices, game controller diagnostics, and laptop/system information.') }

# ---------------------------- Keyboard Surface ----------------------------
# The visual keyboard uses virtual-key codes as Tags. ButtonMap may contain more
# than one visual button for a VK (for example, main Enter and numpad Enter).
$KeyboardPanel=New-Panel 14 214 1508 462
$KeyboardPanel.BackColor=$Colors.Background

# Lock cards - extra breathing room above keyboard
function New-LockCard([string]$name,[int]$x){
    $l=New-Object System.Windows.Forms.Label;$l.Text="●  $name`r`n     ●  OFF";$l.Location=[System.Drawing.Point]::new($x,12);$l.Size=[System.Drawing.Size]::new(190,58);$l.TextAlign='MiddleCenter';$l.ForeColor=$Colors.Muted;$l.BackColor=$Colors.PanelAlt;$l.Font=New-Object System.Drawing.Font('Segoe UI',9);$KeyboardPanel.Controls.Add($l);return $l
}
$CapsLed=New-LockCard 'CAPS LOCK' 420;$NumLed=New-LockCard 'NUM LOCK' 645;$ScrollLed=New-LockCard 'SCROLL LOCK' 870
$LayoutLabel=New-TextLabel $KeyboardPanel 'Layout profile:' 1190 20 90 20 8 $Colors.Muted
$LayoutCombo=New-Object System.Windows.Forms.ComboBox;$LayoutCombo.DropDownStyle='DropDownList';$LayoutCombo.Location=[System.Drawing.Point]::new(1280,18);$LayoutCombo.Size=[System.Drawing.Size]::new(170,26);$LayoutCombo.BackColor=$Colors.PanelAlt;$LayoutCombo.ForeColor=$Colors.Text;$LayoutCombo.FlatStyle='Flat';[void]$LayoutCombo.Items.AddRange(@('Full Size','TKL','Compact / Laptop'));$LayoutCombo.SelectedItem=$script:KeyboardLayoutMode;$KeyboardPanel.Controls.Add($LayoutCombo)
if ($null -ne $LayoutCombo) {
    $ToolTip.SetToolTip($LayoutCombo,'Choose which mapped keys count toward keyboard test completion.')
}

# Key creator now targets KeyboardPanel
function New-KeyButton {
    param([string]$Text,[int]$VkCode,[int]$X,[int]$Y,[int]$Width=42,[int]$Height=42,[float]$FontSize=7.5)
    $button=New-Object System.Windows.Forms.Button;$button.Text=$Text;$button.UseMnemonic=$false;$button.FlatStyle='Flat';$button.FlatAppearance.BorderSize=1;$button.FlatAppearance.BorderColor=$Colors.Border;$button.FlatAppearance.MouseOverBackColor=$Colors.PanelAlt;$button.FlatAppearance.MouseDownBackColor=$Colors.Accent;$button.BackColor=Get-KeyIdleColor $VkCode;$button.ForeColor=$Colors.Text;$button.Font=New-Object System.Drawing.Font('Segoe UI Semibold',$FontSize);$button.TextAlign='MiddleCenter';$button.Padding=New-Object System.Windows.Forms.Padding(2,1,2,1);$button.Cursor=[System.Windows.Forms.Cursors]::Hand;$button.Size=[System.Drawing.Size]::new($Width,$Height);$button.Location=[System.Drawing.Point]::new($X,$Y);$button.TabStop=$false;$button.Tag=$VkCode;$button.Add_Click({Update-KeyInspector -VkCode ([int]$this.Tag)});$KeyboardPanel.Controls.Add($button);Add-MappedButton -VkCode $VkCode -Button $button
}

$kh=43;$gap=5;$baseY=112
$FunctionRowLabel=New-TextLabel $KeyboardPanel 'FUNCTION ROW' 250 88 130 18 7 $Colors.Accent
$MainSectionLabel=New-TextLabel $KeyboardPanel 'MAIN SECTION' 668 88 130 18 7 $Colors.Accent
$NavigationLabel=New-TextLabel $KeyboardPanel 'NAVIGATION' 1050 88 110 18 7 $Colors.Accent
$NumpadLabel=New-TextLabel $KeyboardPanel 'NUMPAD' 1290 88 90 18 7 $Colors.Accent

New-KeyButton 'Esc' 27 48 $baseY 62 45 8
$fx=166
1..12|ForEach-Object{if($_ -in 5,9){$fx+=22};New-KeyButton "F$_" (111+$_) $fx $baseY 55 45 8;$fx+=60}
New-KeyButton 'PrtSc' 44 994 $baseY 58 45 7;New-KeyButton 'ScrLk' 145 1057 $baseY 58 45 7;New-KeyButton 'Pause' 19 1120 $baseY 58 45 7

$rows=@(
 @(@("~`n``",192,50),@("!`n1",49,50),@("@`n2",50,50),@("#`n3",51,50),@("`$`n4",52,50),@("%`n5",53,50),@("^`n6",54,50),@("&`n7",55,50),@("*`n8",56,50),@("(`n9",57,50),@(")`n0",48,50),@("_`n-",189,50),@("+`n=",187,50),@('Backspace',8,92)),
 @(@('Tab',9,72),@('Q',81,50),@('W',87,50),@('E',69,50),@('R',82,50),@('T',84,50),@('Y',89,50),@('U',85,50),@('I',73,50),@('O',79,50),@('P',80,50),@("{`n[",219,50),@("}`n]",221,50),@("|`n\",220,72)),
 @(@('Caps Lock',20,86),@('A',65,50),@('S',83,50),@('D',68,50),@('F',70,50),@('G',71,50),@('H',72,50),@('J',74,50),@('K',75,50),@('L',76,50),@(";`n:",186,50),@(('"' + "`n" + "'"),222,50),@('Enter',13,112)),
 @(@('Shift',160,125),@('Z',90,50),@('X',88,50),@('C',67,50),@('V',86,50),@('B',66,50),@('N',78,50),@('M',77,50),@(",`n<",188,50),@(".`n>",190,50),@("/`n?",191,50),@('Shift',161,125)),
 @(@('Ctrl',162,82),@('⊞',91,72),@('Alt',164,76),@('SPACE',32,354),@('Alt',165,76),@('⊞',92,72),@('▤',93,72),@('Ctrl',163,82))
)
$y=174
foreach($row in $rows){$x=48;foreach($item in $row){New-KeyButton $item[0] $item[1] $x $y $item[2] $kh 8;$x+=$item[2]+$gap};$y+=$kh+$gap}

$nx=994;$ny=174;$nw=58
$nav=@(@('Ins',45,0,0),@('Home',36,1,0),@('PgUp',33,2,0),@('Del',46,0,1),@('End',35,1,1),@('PgDn',34,2,1))
foreach($n in $nav){New-KeyButton $n[0] $n[1] ($nx+$n[2]*($nw+$gap)) ($ny+$n[3]*($kh+$gap)) $nw $kh 7.5}
New-KeyButton '↑' 38 ($nx+$nw+$gap) ($ny+3*($kh+$gap)) $nw $kh 11;New-KeyButton '←' 37 $nx ($ny+4*($kh+$gap)) $nw $kh 11;New-KeyButton '↓' 40 ($nx+$nw+$gap) ($ny+4*($kh+$gap)) $nw $kh 11;New-KeyButton '→' 39 ($nx+2*($nw+$gap)) ($ny+4*($kh+$gap)) $nw $kh 11

$px=1210;$py=112;$pw=52
function New-NumKey([string]$t,[int]$v,[int]$c,[int]$r,[int]$cs=1,[int]$rs=1){$w=$pw*$cs+$gap*($cs-1);$h=$kh*$rs+$gap*($rs-1);New-KeyButton $t $v ($px+$c*($pw+$gap)) ($py+$r*($kh+$gap)) $w $h 7.5}
New-NumKey "Num`nLock" 144 0 0;New-NumKey '/' 111 1 0;New-NumKey '*' 106 2 0;New-NumKey '-' 109 3 0
New-NumKey "7`nHome" 103 0 1;New-NumKey "8`n↑" 104 1 1;New-NumKey "9`nPgUp" 105 2 1;New-NumKey '+' 107 3 1 1 2
New-NumKey "4`n←" 100 0 2;New-NumKey '5' 101 1 2;New-NumKey "6`n→" 102 2 2
New-NumKey "1`nEnd" 97 0 3;New-NumKey "2`n↓" 98 1 3;New-NumKey "3`nPgDn" 99 2 3;New-NumKey 'Enter' 13 3 3 1 2
New-NumKey "0`nIns" 96 0 4 2 1;New-NumKey ".`nDel" 110 2 4

function Update-KeyboardLayoutVisuals {
    $mode = [string]$script:KeyboardLayoutMode

    # Work with each actual visual button rather than VK codes, because
    # keys such as Enter are represented in more than one keyboard section.
    $allKeyButtons = @(
        $KeyboardPanel.Controls |
        Where-Object { $_ -is [System.Windows.Forms.Button] -and $null -ne $_.Tag }
    )

    foreach ($button in $allKeyButtons) {
        $x = [int]$button.Left
        $y = [int]$button.Top
        $vk = [int]$button.Tag
        $visible = $true

        switch ($mode) {
            'TKL' {
                # Numpad starts at X 1210. Everything else remains visible.
                if ($x -ge 1200) { $visible = $false }
            }

            'Compact / Laptop' {
                # Hide numpad.
                if ($x -ge 1200) { $visible = $false }

                # Hide F1-F12 but retain Esc.
                if ($y -eq $baseY -and $vk -ge 112 -and $vk -le 123) {
                    $visible = $false
                }

                # Hide Print Screen / Scroll Lock / Pause.
                if ($y -eq $baseY -and $vk -in 44,145,19) {
                    $visible = $false
                }

                # Hide the dedicated navigation and arrow clusters.
                if ($x -ge 990 -and $x -lt 1200 -and $y -ge 174) {
                    $visible = $false
                }
            }

            default {
                $visible = $true
            }
        }

        $button.Visible = $visible
    }

    # Section headings and lock cards follow the selected profile.
    $FunctionRowLabel.Visible = ($mode -ne 'Compact / Laptop')
    $NavigationLabel.Visible = ($mode -ne 'Compact / Laptop')
    $NumpadLabel.Visible = ($mode -eq 'Full Size')

    $NumLed.Visible = ($mode -eq 'Full Size')
    $ScrollLed.Visible = ($mode -ne 'Compact / Laptop')

    # Keep these controls available in every profile.
    $CapsLed.Visible = $true
    $MainSectionLabel.Visible = $true
    $LayoutLabel.Visible = $true
    $LayoutCombo.Visible = $true

    Update-TestProgress

    if ($script:TestMode) {
        Set-TestResultColors
    }

    $KeyboardPanel.Invalidate()
}

# Bottom panels
$StatsPanel=New-Panel 14 686 275 260
[void](New-TextLabel $StatsPanel 'KEYBOARD STATISTICS' 18 12 220 22 8.5 $Colors.Muted $true);[void](Add-SectionAccent $StatsPanel 18 36 46)
function Add-StatRow([string]$label,[int]$y){[void](New-TextLabel $StatsPanel $label 18 $y 165 22 8.5 $Colors.Muted);return New-TextLabel $StatsPanel '0' 195 $y 60 22 9 $Colors.Text $true}
$KeysValue=Add-StatRow '⌨  Total keystrokes' 48;$UniqueKeysValue=Add-StatRow '▧  Unique keys pressed' 80;$AverageHoldValue=Add-StatRow '◷  Average hold time' 112;$LongestHoldValue=Add-StatRow '◉  Longest hold time' 144;$EstimatedWpmValue=Add-StatRow '◉  WPM (estimated)' 176;$KpmValue=Add-StatRow '⊕  Keys per minute' 208
$ShortcutValue=New-Object System.Windows.Forms.Label;$MouseValue=New-Object System.Windows.Forms.Label;$WheelValue=New-Object System.Windows.Forms.Label;$CurrentWpmValue=$EstimatedWpmValue;$AverageWpmValue=New-Object System.Windows.Forms.Label

$ShortcutPanel=New-Panel 300 686 230 260
[void](New-TextLabel $ShortcutPanel 'TOP SHORTCUTS' 18 12 180 22 8.5 $Colors.Muted $true);[void](Add-SectionAccent $ShortcutPanel 18 36 46)
$ShortcutList=New-Object System.Windows.Forms.ListView;$ShortcutList.View='Details';$ShortcutList.HeaderStyle='None';$ShortcutList.FullRowSelect=$true;$ShortcutList.BorderStyle='None';$ShortcutList.BackColor=$Colors.Surface;$ShortcutList.ForeColor=$Colors.Text;$ShortcutList.Font=New-Object System.Drawing.Font('Segoe UI',8.75);$ShortcutList.Location=[System.Drawing.Point]::new(12,42);$ShortcutList.Size=[System.Drawing.Size]::new(205,185);[void]$ShortcutList.Columns.Add('Shortcut',145);[void]$ShortcutList.Columns.Add('Count',50);[void]$ShortcutList.Columns.Add('Last',0);$ShortcutPanel.Controls.Add($ShortcutList)
[void](New-TextLabel $ShortcutPanel 'View all shortcuts  →' 82 228 135 20 8 $Colors.Accent)

$FeedPanel=New-Panel 542 686 615 260
[void](New-TextLabel $FeedPanel 'LIVE DIAGNOSTIC FEED' 14 10 260 22 8.5 $Colors.Muted $true);[void](Add-SectionAccent $FeedPanel 14 34 46)
$FeedCountLabel=New-TextLabel $FeedPanel "0 / $($script:MaxFeedLines)" 500 10 100 22 8.5 $Colors.Muted $false
$FeedCountLabel.TextAlign='MiddleRight'
$FeedGrid=New-Object System.Windows.Forms.DataGridView;$FeedGrid.Location=[System.Drawing.Point]::new(12,38);$FeedGrid.Size=[System.Drawing.Size]::new(590,208);$FeedGrid.BackgroundColor=$Colors.Surface;$FeedGrid.BorderStyle='None';$FeedGrid.ReadOnly=$true;$FeedGrid.AllowUserToAddRows=$false;$FeedGrid.AllowUserToDeleteRows=$false;$FeedGrid.AllowUserToResizeRows=$false;$FeedGrid.RowHeadersVisible=$false;$FeedGrid.SelectionMode='FullRowSelect';$FeedGrid.MultiSelect=$false;$FeedGrid.EnableHeadersVisualStyles=$false;$FeedGrid.ColumnHeadersDefaultCellStyle.BackColor=$Colors.PanelAlt;$FeedGrid.ColumnHeadersDefaultCellStyle.ForeColor=$Colors.Text;$FeedGrid.DefaultCellStyle.BackColor=$Colors.Surface;$FeedGrid.DefaultCellStyle.ForeColor=$Colors.Text;$FeedGrid.DefaultCellStyle.SelectionBackColor=$Colors.PanelAlt;$FeedGrid.DefaultCellStyle.SelectionForeColor=$Colors.Text;$FeedGrid.GridColor=$Colors.PanelAlt;$FeedGrid.AutoSizeColumnsMode='None';$FeedGrid.Font=New-Object System.Drawing.Font('Segoe UI',8.5)
$FeedGrid.AlternatingRowsDefaultCellStyle.BackColor=[System.Drawing.Color]::FromArgb(25,29,36)
$FeedGrid.ColumnHeadersHeight=28
$FeedGrid.RowTemplate.Height=25
$FeedGrid.CellBorderStyle='SingleHorizontal'
$FeedGrid.ColumnHeadersBorderStyle='None'
foreach($c in @(@('Time',86),@('Device',80),@('Event',82),@('Key',150),@('Scan Code',76),@('VKey',68),@('Modifiers',80))){[void]$FeedGrid.Columns.Add($c[0],$c[0]);$FeedGrid.Columns[$FeedGrid.Columns.Count-1].Width=$c[1]}
$FeedPanel.Controls.Add($FeedGrid)

$MousePanel=New-Panel 1168 686 354 260
[void](New-TextLabel $MousePanel 'MOUSE STATUS' 18 12 180 22 8.5 $Colors.Muted $true);[void](Add-SectionAccent $MousePanel 18 36 46)

$TrackpadButton=New-Object System.Windows.Forms.Button
$TrackpadButton.Text='Trackpad'
$TrackpadButton.Location=[System.Drawing.Point]::new(190,8)
$TrackpadButton.Size=[System.Drawing.Size]::new(72,28)
Set-ActionButtonStyle -b $TrackpadButton
$MousePanel.Controls.Add($TrackpadButton)

$TouchButton=New-Object System.Windows.Forms.Button
$TouchButton.Text='Touch'
$TouchButton.Location=[System.Drawing.Point]::new(270,8)
$TouchButton.Size=[System.Drawing.Size]::new(66,28)
Set-ActionButtonStyle -b $TouchButton
$MousePanel.Controls.Add($TouchButton)

$ToolTip.SetToolTip($TrackpadButton,'Open movement, click, and scroll diagnostics for a laptop trackpad.')
$ToolTip.SetToolTip($TouchButton,'Open a touchscreen coverage and multi-touch test.')
# Simple visual mouse body
$MouseBody=New-Object System.Windows.Forms.Panel;$MouseBody.Location=[System.Drawing.Point]::new(28,56);$MouseBody.Size=[System.Drawing.Size]::new(92,155);$MouseBody.BackColor=$Colors.PanelAlt;$MouseBody.BorderStyle='FixedSingle';$MousePanel.Controls.Add($MouseBody)
function New-MouseIndicator([string]$text,[int]$x,[int]$y,[int]$w=40,[int]$h=52){$b=New-Object System.Windows.Forms.Button;$b.Text=$text;$b.Enabled=$false;$b.FlatStyle='Flat';$b.FlatAppearance.BorderSize=0;$b.BackColor=$Colors.Key;$b.ForeColor=$Colors.Text;$b.Location=[System.Drawing.Point]::new($x,$y);$b.Size=[System.Drawing.Size]::new($w,$h);$MouseBody.Controls.Add($b);return $b}
$MouseLeft=New-MouseIndicator '' 4 4 40 52;$MouseRight=New-MouseIndicator '' 47 4 40 52;$MouseMiddle=New-MouseIndicator '│' 34 60 24 45;$MouseWheelUp=New-MouseIndicator '' 0 0 1 1;$MouseWheelDown=New-MouseIndicator '' 0 0 1 1;$MouseX1=New-MouseIndicator '' 3 112 10 15;$MouseX2=New-MouseIndicator '' 3 130 10 15
function Add-MouseStatus([string]$name,[int]$y){[void](New-TextLabel $MousePanel $name 155 $y 125 20 8.5 $Colors.Muted);return New-TextLabel $MousePanel 'UP' 292 $y 45 20 8.5 $Colors.Text $true}
$MouseLeftState=Add-MouseStatus 'Left Button' 52;$MouseRightState=Add-MouseStatus 'Right Button' 84;$MouseMiddleState=Add-MouseStatus 'Middle Button' 116;$MouseX1State=Add-MouseStatus 'X1 Button' 148;$MouseX2State=Add-MouseStatus 'X2 Button' 180;$MouseWheelState=Add-MouseStatus 'Wheel Delta' 212
$MousePosition=New-Object System.Windows.Forms.Label;$MousePosition.Visible=$false;$MousePanel.Controls.Add($MousePosition)

# Bottom status bar
$StatusBar=New-Panel 14 956 1508 74
$AppLabel=New-TextLabel $StatusBar 'Active app:  Unknown' 16 12 350 50 8.5 $Colors.Text
[void](New-TextLabel $StatusBar 'Keyboard Layout:   US' 375 12 260 20 8.5 $Colors.Text)
$ThresholdLabel=New-TextLabel $StatusBar 'Stuck key threshold:   5.0 sec' 650 12 350 20 8.5 $Colors.Text
$DpiLabel=New-TextLabel $StatusBar 'DPI Scaling:  Auto' 1305 12 180 20 8.5 $Colors.Muted

# Hidden inspector controls retained for key-click/stat compatibility
$InspectorName=New-Object System.Windows.Forms.Label;$InspectorVk=New-Object System.Windows.Forms.Label;$InspectorScan=New-Object System.Windows.Forms.Label;$InspectorCategory=New-Object System.Windows.Forms.Label;$InspectorState=New-Object System.Windows.Forms.Label;$InspectorCount=New-Object System.Windows.Forms.Label;$InspectorAverage=New-Object System.Windows.Forms.Label;$InspectorLongest=New-Object System.Windows.Forms.Label;$InspectorLast=New-Object System.Windows.Forms.Label

# Legacy label kept for compatibility
$StatusLabel=$CaptureStatusValue

# ---------------------------- UI Timers ----------------------------
# PollTimer drains the thread-safe hook queue.
# UiTimer handles fades, stuck-key checks, lock LEDs, and active-app status.
$PollTimer=New-Object System.Windows.Forms.Timer;$PollTimer.Interval=25
$UiTimer=New-Object System.Windows.Forms.Timer;$UiTimer.Interval=250

# Safety net: capture stops itself after this many minutes even if the user
# forgets it's running. Applies to elapsed time since (re)start, not idle time.
$script:CaptureAutoStopMinutes = 2
$script:CaptureRunSince = $null
$script:StartWarningShown = $false

function Set-CapturingTitle([bool]$Capturing) {
    $Form.Text = if ($Capturing) { "[CAPTURING] $script:BaseTitle" } else { $script:BaseTitle }
}

function Stop-Capture([string]$Reason='Stopped by user') {
    [GlobalInputDiagnostics]::Stop()
    $script:CaptureRunSince = $null

    # A stopped capture cannot continue a hardware test. Preserve collected test
    # results, but return the Test Mode UI to OFF.
    if ($script:TestMode) {
        $script:TestMode = $false
        $script:StuckWarned.Clear()
        Update-TestModeButton
        Update-TestProgress
    }

    $StatusLabel.Text='● STOPPED'
    $StatusLabel.ForeColor=$Colors.Destructive
    $StatusLabel.BackColor=[System.Drawing.Color]::Transparent
    $StartButton.Visible=$true
    $PauseButton.Visible=$false
    Set-CapturingTitle $false

    Write-Feed 'SYSTEM' $Reason

    foreach($vk in @($script:ButtonMap.Keys)){
        Reset-KeyVisual $vk
    }

    $script:KeyDownTimes.Clear()
    $script:FadeQueue.Clear()
}

$StartButton.Add_Click({
    if (-not $script:StartWarningShown) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Capture uses a system-wide keyboard/mouse hook: once started, it keeps receiving input even if this window is not focused or is behind other windows (it only stops if you Pause/Stop it or minimize this window).`n`nNo text is ever reconstructed or saved to disk.`n`nCapture will automatically stop after $script:CaptureAutoStopMinutes minutes as a safety timeout.`n`nStart capture?",
            'Start Capture',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $script:StartWarningShown = $true
    }
    if ([GlobalInputDiagnostics]::Start()) {
        if (-not $script:SessionStarted) {$script:SessionStarted=Get-Date}
        $script:CaptureRunSince = Get-Date
        $StatusLabel.Text='● CAPTURING';$StatusLabel.ForeColor=$Colors.Letter;$StatusLabel.BackColor=[System.Drawing.Color]::Transparent;$StartButton.Visible=$false;$PauseButton.Visible=$true
        Set-CapturingTitle $true
        Write-Feed 'SYSTEM' 'Capture started. No text is reconstructed or saved.'
    } else {[System.Windows.Forms.MessageBox]::Show('Unable to install Windows input hooks. Try running in a normal Windows PowerShell session.','Hook Error','OK','Error')}
})
$PauseButton.Add_Click({ if([GlobalInputDiagnostics]::IsRunning){Stop-Capture 'Capture paused'} else { if([GlobalInputDiagnostics]::Start()){$script:CaptureRunSince=Get-Date;$StatusLabel.Text='● CAPTURING';$StatusLabel.ForeColor=$Colors.Letter;$StatusLabel.BackColor=[System.Drawing.Color]::Transparent;$StartButton.Visible=$false;$PauseButton.Visible=$true;Set-CapturingTitle $true;Write-Feed 'SYSTEM' 'Capture resumed'} } })
$StopButton.Add_Click({Stop-Capture 'Capture stopped'})
$ClearButton.Add_Click({$FeedGrid.Rows.Clear();[GlobalInputDiagnostics]::ClearQueue();Write-Feed 'SYSTEM' 'Feed cleared. Statistics remain in memory.'})

$TestModeButton.Add_Click({
    # Starting Test Mode should also start capture if capture is currently stopped.
    # Use the existing Start button so the normal capture-start logic stays in one place.
    if (-not $script:TestMode -and -not [GlobalInputDiagnostics]::IsRunning) {
        $StartButton.PerformClick()

        # If capture could not be started, do not enable Test Mode.
        if (-not [GlobalInputDiagnostics]::IsRunning) {
            return
        }
    }

    $script:TestMode = -not $script:TestMode
    $script:StuckWarned.Clear()
    Update-TestModeButton
    Update-TestProgress
    Update-TestHeatMap

    if ($script:TestMode) {
        $script:HardwareTestStarted = $true
        Write-Feed 'TEST' "Keyboard Test Mode enabled. Capture is running; heat map is active and keys held longer than $($script:StuckKeyThresholdMs) ms will be flagged."
    } else {
        Write-Feed 'TEST' 'Keyboard Test Mode disabled. Capture stopped.'
        Stop-Capture 'Test Mode ended - capture stopped'
    }
})

$ResetTestButton.Add_Click({
    $script:TestKeyCounts.Clear()
    $script:TestKeyStats.Clear()
    $script:TestWheelEvents = 0
    $script:StuckWarned.Clear()
    $script:ChatterCounts.Clear()
    $script:LastKeyDownAt.Clear()
    $script:MaxSimultaneousKeys = 0
    $script:HardwareTestStarted = $false
    foreach($mk in @('LEFT','RIGHT','MIDDLE','X1','X2')){$script:MouseClickCounts[$mk]=0;$script:MouseChatterCounts[$mk]=0}
    $script:MouseLastDownAt.Clear()
    Update-TestHeatMap
    Update-TestModeButton
    Update-TestProgress
    Write-Feed 'TEST' 'Keyboard test counters, completion checklist, and heat map reset.'
})

$ChecklistButton.Add_Click({ Show-TestChecklist })
$ReportButton.Add_Click({ Show-DiagnosticReport })
$DeviceButton.Add_Click({ Show-DeviceInformation })
$TrackpadButton.Add_Click({ Show-TrackpadDiagnostics })
$TouchButton.Add_Click({ Show-TouchscreenDiagnostics })
$LayoutCombo.Add_SelectedIndexChanged({
    $script:KeyboardLayoutMode=[string]$LayoutCombo.SelectedItem
    Update-KeyboardLayoutVisuals
    Write-Feed 'TEST' "Keyboard layout profile changed to $($script:KeyboardLayoutMode)."
})

$SettingsButton.Add_Click({
    $d=New-Object System.Windows.Forms.Form;$d.Text='Settings';$d.Size=[System.Drawing.Size]::new(430,270);$d.StartPosition='CenterParent';$d.BackColor=$Colors.Background;$d.ForeColor=$Colors.Text;$d.FormBorderStyle='FixedDialog';$d.MaximizeBox=$false;$d.MinimizeBox=$false
    $cbTop=New-Object System.Windows.Forms.CheckBox;$cbTop.Text='Always on top';$cbTop.Checked=$Form.TopMost;$cbTop.Location=[System.Drawing.Point]::new(24,28);$cbTop.Size=[System.Drawing.Size]::new(180,25);$d.Controls.Add($cbTop)
    $lbl=New-Object System.Windows.Forms.Label;$lbl.Text='Stuck-key warning threshold (seconds)';$lbl.Location=[System.Drawing.Point]::new(24,78);$lbl.Size=[System.Drawing.Size]::new(280,22);$d.Controls.Add($lbl)
    $num=New-Object System.Windows.Forms.NumericUpDown;$num.Minimum=1;$num.Maximum=30;$num.DecimalPlaces=1;$num.Increment=.5;$num.Value=[decimal]($script:StuckKeyThresholdMs/1000);$num.Location=[System.Drawing.Point]::new(24,104);$num.Size=[System.Drawing.Size]::new(100,25);$d.Controls.Add($num)
    $ok=New-Object System.Windows.Forms.Button;$ok.Text='Save';$ok.Location=[System.Drawing.Point]::new(290,175);$ok.Size=[System.Drawing.Size]::new(95,32);Set-ActionButtonStyle -b $ok -back $Colors.Accent -fore ([System.Drawing.Color]::White);$ok.Add_Click({$Form.TopMost=$cbTop.Checked;$script:StuckKeyThresholdMs=[int]([double]$num.Value*1000);$ThresholdLabel.Text="Stuck key threshold:   $([Math]::Round($script:StuckKeyThresholdMs/1000,1)) sec";$d.Close()});$d.Controls.Add($ok)
    [void]$d.ShowDialog($Form)
})
function Show-AboutHelp {
    $help = New-Object System.Windows.Forms.Form
    $help.Text = 'About & Help - Input & Hardware Diagnostics'
    $help.Size = [System.Drawing.Size]::new(860,680)
    $help.MinimumSize = [System.Drawing.Size]::new(760,580)
    $help.StartPosition = 'CenterParent'
    $help.BackColor = $Colors.Background
    $help.ForeColor = $Colors.Text
    $help.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $help.FormBorderStyle = 'Sizable'
    $help.MaximizeBox = $true
    $help.MinimizeBox = $false
    $help.ShowInTaskbar = $false

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = 'Top'
    $header.Height = 86
    $header.BackColor = $Colors.Surface
    $help.Controls.Add($header)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Input & Hardware Diagnostics'
    $title.Location = [System.Drawing.Point]::new(22,15)
    $title.Size = [System.Drawing.Size]::new(500,28)
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold',16,[System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $Colors.Text
    $header.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = 'Version 8.0.0  •  Built-in Help Guide'
    $subtitle.Location = [System.Drawing.Point]::new(24,49)
    $subtitle.Size = [System.Drawing.Size]::new(600,22)
    $subtitle.Font = New-Object System.Drawing.Font('Segoe UI',9.5)
    $subtitle.ForeColor = $Colors.Muted
    $header.Controls.Add($subtitle)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = 'Fill'
    $tabs.Padding = [System.Drawing.Point]::new(18,6)
    $tabs.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9)
    $help.Controls.Add($tabs)
    $tabs.BringToFront()

    function Add-HelpTab {
        param(
            [string]$Name,
            [string]$Content
        )

        $page = New-Object System.Windows.Forms.TabPage
        $page.Text = $Name
        $page.BackColor = $Colors.Background
        $page.ForeColor = $Colors.Text
        $page.Padding = New-Object System.Windows.Forms.Padding(14)
        [void]$tabs.TabPages.Add($page)

        $box = New-Object System.Windows.Forms.RichTextBox
        $box.Dock = 'Fill'
        $box.ReadOnly = $true
        $box.BorderStyle = 'None'
        $box.BackColor = $Colors.Background
        $box.ForeColor = $Colors.Text
        $box.Font = New-Object System.Drawing.Font('Segoe UI',10)
        $box.DetectUrls = $false
        $box.ScrollBars = 'Vertical'
        $box.Text = $Content.Trim()
        $page.Controls.Add($box)
    }

    Add-HelpTab 'About' @"
INPUT & HARDWARE DIAGNOSTICS

Input & Hardware Diagnostics is a portable Windows troubleshooting utility
for testing common input devices and reviewing practical system information.

WHAT IT CAN TEST

• Keyboard key detection
• Key-down and key-up activity
• Key hold duration
• Stuck-key warnings
• Switch chatter / suspicious rapid repeat detection
• Keyboard heat-map activity
• Simultaneous key / rollover observation
• Common keyboard shortcut activity
• Mouse left, right, middle, X1 and X2 buttons
• Mouse wheel activity
• Trackpad movement, click and scroll diagnostics
• Touchscreen coverage and multi-touch diagnostics
• XInput game controller buttons, triggers, D-pad and analog sticks
• Laptop/system, Windows, BIOS, CPU, RAM and battery information

PRIVACY

The application processes keyboard and mouse events in memory for diagnostic purposes.

It does not reconstruct complete typed text and it does not automatically save keystrokes to disk.

The Diagnostic Report is generated in memory. It is copied only when you explicitly click Copy report.

The live diagnostic feed keeps only the most recent 50 entries on screen; older entries are discarded, not stored elsewhere. A counter beside the feed shows how full it is.

SAFETY BEHAVIOR

• Capture uses a keyboard/mouse hook that only exists while capture is running; it is fully removed when capture is stopped, paused, or the window is closed.
• Clicking Start Capture shows a one-time confirmation explaining that capture is system-wide (keeps receiving input even while this window is unfocused or behind other windows) and that no text is ever saved.
• Capture automatically stops after 2 minutes as a safety timeout, even if you forget it is running. Resuming via Pause/Resume restarts this timer.
• Capture automatically stops if the window is minimized or closed.
• While capture is active, the window title bar is prefixed with [CAPTURING] so it stays visible in Alt-Tab and the taskbar even when this window is not on top.
• This tool refuses to run when launched from an elevated (Administrator) PowerShell session, since it has no need for elevated rights.

VERSION

v8.0.0 — Final feature release
PowerShell 5.1 / Windows Forms
"@

    Add-HelpTab 'Quick Start' @"
QUICK START

1. For ordinary monitoring, click START CAPTURE.

2. For a hardware test, click TEST MODE.
   Test Mode automatically starts capture if it is stopped.

3. Press keyboard keys and test the mouse.
   The visual keyboard and live diagnostic feed should respond immediately.

4. Watch the dashboard.
   Events, Keys / Min, tested keys and stuck-key status update while capture is running.

5. Use CHECKLIST to see:
   • Keys already tested
   • Keys still missing
   • Press counts
   • Average hold time
   • Longest hold time

6. Test Mode also enables the keyboard heat map.
   Frequently used keys gradually change color.

7. When finished, turn TEST MODE off. This also stops capture.

8. Open DIAGNOSTIC REPORT to review the completed test.

TIP

For troubleshooting a specific bad key, press that key repeatedly 10-20 times while watching the Live Diagnostic Feed and Checklist.
"@

    Add-HelpTab 'Keyboard' @"
KEYBOARD TESTING

NORMAL CAPTURE

Every detected key lights up when pressed and returns to its normal color after release.

TEST MODE

Test Mode tracks which mapped keys have been pressed and builds the keyboard heat map.

Starting Test Mode automatically starts capture when needed. Turning Test Mode off stops capture while preserving the collected test results.


CHECKLIST

The Checklist shows test coverage and per-key information including:

• Tested / Not Tested
• Press count
• Average hold time
• Longest hold time
• Key category

STUCK-KEY DETECTION

A key that remains held longer than the configured threshold is highlighted and logged as a potential stuck key.

The default threshold is 5 seconds and can be changed in Settings.

SWITCH CHATTER

The program watches for suspiciously rapid duplicate key-down activity.

A chatter warning does not automatically prove the keyboard is defective. Repeat the test several times to confirm the behavior.

ROLLOVER / MULTI-KEY TESTING

Hold several keys at the same time.

The diagnostic report records the maximum number of simultaneous keys observed during the session.

HEAT MAP

In Test Mode:

Green / lower activity
Amber / moderate activity
Orange / higher activity
Red / highest relative activity

Heat-map colors are relative to the activity in the current test session.
"@

    Add-HelpTab 'Mouse' @"
MOUSE TESTING

The Mouse Status panel shows the current state of supported mouse inputs.

LEFT BUTTON
Press and release the primary mouse button.

RIGHT BUTTON
Press and release the secondary mouse button.

MIDDLE BUTTON
Press the scroll wheel down like a button.

X1 / X2
These are the common side buttons found on many mice.

WHEEL DELTA
Scroll up and down and watch the wheel activity change.

BASIC MOUSE TEST

1. Enable Test Mode. Capture starts automatically.
2. Click each mouse button several times.
3. Scroll both directions.
4. Test X1/X2 if your mouse has side buttons.
5. Watch the Live Diagnostic Feed for unexpected duplicate events.

A button that does not change state may indicate:
• A hardware problem
• Mouse software remapping
• A device/driver issue
• A button not supported by the mouse
"@

    Add-HelpTab 'Results' @"
UNDERSTANDING RESULTS

KEY HOLD TIME

Hold time is measured from the Windows key-down event to the matching key-up event.

It is useful for comparing key behavior, but it is NOT a measurement of true hardware input latency.

TRUE HARDWARE LATENCY

Accurate switch-to-display latency measurement requires external timing equipment or another known reference source.

POSSIBLE CHATTER

A chatter warning means the application observed key-down events unusually close together.

One warning by itself is not enough to declare a key defective.

Repeated warnings from the same key during controlled single presses are more meaningful.

STUCK KEY

A stuck-key warning means Windows reported the key as remaining down longer than the configured threshold.

KEYS TESTED

The completion percentage only covers keys mapped in the visual keyboard.

SIMULTANEOUS KEYS

The maximum simultaneous-key value can help investigate keyboard rollover limitations. It is measured only while Test Mode is active.

WPM / KEYS PER MINUTE

These values are estimates based on activity seen during the current session. They are diagnostic statistics, not a formal typing-speed test.
"@

    Add-HelpTab 'Troubleshooting' @"
TROUBLESHOOTING

A KEY DOES NOT REGISTER

• Test the key several times.
• Try another application.
• Check whether keyboard software is remapping the key.
• Disconnect/reconnect the keyboard.
• Try another USB port.
• Test the keyboard on another computer if possible.

A KEY TYPES TWICE

• Enable capture.
• Press the affected key slowly several times.
• Watch for repeated chatter warnings.
• Compare the affected key with nearby keys.

A KEY APPEARS STUCK

• Release the key completely.
• Press it again several times.
• Check for debris or physical binding.
• Review the stuck-key warning threshold in Settings.

CAPTURE WILL NOT START

• Close and reopen the application.
• Run it in Windows PowerShell 5.1.
• Make sure security software is not blocking low-level input hooks.
• Test from a local Windows session.

SOME SHORTCUTS BEHAVE DIFFERENTLY

Applications can intercept or remap shortcuts. The visualizer reports the events Windows exposes to the hook.


RESETTING A TEST

RESET TEST clears:
• Test completion
• Heat-map counters
• Chatter counters

It does not need to restart the application.
"@

    Add-HelpTab 'v7 Features' @"
V7 HARDWARE DIAGNOSTICS

PASS / ATTENTION RESULTS

The diagnostic report evaluates the keyboard and mouse test state.

PASS means the required test criteria were completed without current stuck-key or chatter warnings.

ATTENTION means something still needs review, such as missing keys or suspicious repeat activity.

KEYBOARD LAYOUT PROFILE

Full Size:
Includes the complete mapped keyboard and numpad.

TKL:
Excludes the numpad and Num Lock from completion.

Compact / Laptop:
Uses the core typing keyboard and excludes keys commonly absent from compact keyboards.

PROBLEM KEY COLORS

During Test Mode, results can be reviewed visually:
Green = detected/passed
Orange = suspicious chatter
Red = missing or currently problematic

MOUSE DIAGNOSTICS

Mouse button presses are counted individually and suspicious rapid duplicate clicks are flagged.

DEVICE INFORMATION

Use Hardware to view Windows-reported keyboard and pointing-device information, including device name, manufacturer, status and PNP device ID when available.

"@

    Add-HelpTab 'Controller & System' @"
GAME CONTROLLER DIAGNOSTICS

Open Hardware, then choose Controller test.

The controller window checks the four Windows XInput controller slots and
shows live information for:

• D-pad directions
• A, B, X and Y buttons
• Menu / View buttons
• Shoulder buttons
• Left/right stick clicks
• Analog trigger percentages
• Left/right analog-stick X and Y axes
• Raw axis values and button mask

Centered analog sticks should normally remain close to 0%. Small resting
values are expected because controllers and drivers use dead zones. A large
resting value that persists may indicate stick drift.

XInput is built into supported Windows versions and does not require
administrator rights. Xbox-compatible USB and Bluetooth controllers normally
use XInput. Older DirectInput-only devices may appear in Windows Device Manager
but may not expose live state in this test.

LAPTOP & SYSTEM INFORMATION

Open Hardware, then choose System info.

The window shows practical help-desk and inventory information reported by
Windows:

• Computer manufacturer, model, name and serial/service tag
• System UUID
• Windows edition, version, build, architecture and install date
• BIOS version and release date
• Processor and logical processor count
• Installed RAM and memory-module details when available
• Battery name, charge, charging state and estimated runtime when available

Use Refresh after a hardware or power-state change. Some firmware and battery
fields may be blank or generic when the manufacturer does not publish them
through Windows Management Instrumentation.
"@

    Add-HelpTab 'Trackpad & Touch' @"
TRACKPAD DIAGNOSTICS

Open Trackpad from the Mouse Status panel.

On most laptops Windows exposes trackpad pointer movement, clicks and scrolling through the mouse input path. The trackpad window provides:

• A live movement path
• Movement event count
• Approximate path distance
• Large movement-jump observations
• Left / right / middle click counts
• Vertical scroll up/down counts
• Horizontal scroll left/right counts when the driver exposes them

Keep the pointer inside the movement test area while sweeping across the trackpad.

A large movement jump is an observation, not an automatic failure. Very fast finger movement can also produce a large coordinate change.

TOUCHSCREEN DIAGNOSTICS

Open Touch from the Mouse Status panel.

The touchscreen window uses Windows pointer messages and only counts actual TOUCH input for coverage. Mouse clicks do not fill touchscreen cells.

Drag a finger across the full grid, including edges and corners.

The footer shows:

• Grid coverage percentage
• Touch event count
• Current active touch points
• Pen event count

For a multi-touch check, place two or more fingers on the screen and confirm Active touches increases.

The touchscreen test observes touch delivered to this application. It does not change Windows touch calibration or driver settings.
"@

    Add-HelpTab 'Privacy' @"
PRIVACY & DATA HANDLING

Input & Hardware Diagnostics is intended as a local troubleshooting utility.

DURING CAPTURE

The program observes low-level keyboard and mouse events so it can identify:

• Which key/button generated the event
• Down/up state
• Scan code / virtual-key information
• Modifier state
• Timing information

TYPED CONTENT

The program is intentionally designed not to reconstruct complete typed sentences, passwords or documents from the event stream.

STORAGE

Diagnostic activity remains in memory during the running session.

The application does not automatically create a keystroke log on disk.

REPORTS

The Diagnostic Report is generated from diagnostic statistics.

Copying or saving report information should only be done when you intentionally choose to keep or share the results.

SAFEGUARDS

• The keyboard/mouse hook only exists while capture is running and is fully removed the moment capture is stopped, paused, minimized, or the window is closed.
• Starting capture requires a one-time confirmation explaining that it is system-wide and that no text is saved.
• Capture automatically stops itself after 2 minutes as a safety timeout, even if you forget to stop it. Resuming restarts the timer.
• The window title shows [CAPTURING] while active so it is visible in Alt-Tab/taskbar even if this window is behind others or unfocused.
• This tool refuses to launch if started with Administrator rights.
• The live feed on screen keeps only the most recent 50 events; older ones are discarded, not written anywhere.

GOOD PRACTICE

Stop Capture when testing is complete, especially before entering sensitive information elsewhere on the computer. Do not rely on window visibility/focus alone — capture continues in the background until you Pause/Stop it, minimize the window, or the 2-minute safety timeout is reached.
"@

    $closePanel = New-Object System.Windows.Forms.Panel
    $closePanel.Dock = 'Bottom'
    $closePanel.Height = 56
    $closePanel.BackColor = $Colors.Surface
    $help.Controls.Add($closePanel)
    $closePanel.BringToFront()

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'Close'
    $close.Size = [System.Drawing.Size]::new(110,34)
    $close.Location = [System.Drawing.Point]::new(718,11)
    $close.Anchor = 'Top,Right'
    Set-ActionButtonStyle -b $close -back $Colors.Accent -fore ([System.Drawing.Color]::White)
    $close.Add_Click({ $help.Close() })
    $closePanel.Controls.Add($close)

    [void]$help.ShowDialog($Form)
}

$AboutButton.Add_Click({ Show-AboutHelp })


$PollTimer.Add_Tick({
    $raw=$null
    while([GlobalInputDiagnostics]::TryGetEvent([ref]$raw)){
        $parts=$raw -split '\|'
        $time=$parts[0];$type=$parts[1]
        if($type -eq 'KD'){
            $vk=[int]$parts[2];$scan=[int]$parts[3];$flags=[int]$parts[4];$mods=$parts[5]
            $name=Get-KeyName $vk;$color=Get-KeyCategoryColor $vk
            Set-KeyVisual $vk $color
            Register-ChatterSample $vk
            $script:KeyDownTimes[$vk]=Get-Date
            $script:Stats.Keys++

            if ($script:TestMode) {
                # Rollover is a hardware-test metric, so ignore simultaneous keys
                # pressed during ordinary capture.
                $heldNow = @($script:KeyDownTimes.Keys).Count
                if ($heldNow -gt $script:MaxSimultaneousKeys) {
                    $script:MaxSimultaneousKeys = $heldNow
                }
            }

            if ($script:TestMode) {
                if (-not $script:TestKeyCounts.ContainsKey($vk)) { $script:TestKeyCounts[$vk] = 0 }
                $script:TestKeyCounts[$vk] = [int]$script:TestKeyCounts[$vk] + 1
                $testStat = Get-OrCreateTestKeyStat $vk
                $testStat.Count++
                if ($script:StuckWarned.ContainsKey($vk)) { $script:StuckWarned.Remove($vk) }
                Update-TestModeButton
                Update-TestProgress
            }

            $stat=Get-OrCreateKeyStat $vk
            $stat.Count++
            $stat.LastUsed=Get-Date
            $stat.LastScan=$scan
            $stat.LastFlags=$flags
            $stat.IsDown=$true
            Update-KeyInspector $vk

            if((Test-PrintableKey $vk) -and -not ($mods -match 'CTRL|ALT|WIN')){
                [void]$script:PrintablePressTimes.Add((Get-Date))
                $script:PrintableKeyCount++
            }

            if($mods -and $vk -notin 16,17,18,91,92,160,161,162,163,164,165){
                $shortcut=Format-Shortcut $mods $name
                $description=Get-ShortcutDescription $shortcut
                if(-not $script:ShortcutCounts.ContainsKey($shortcut)){$script:ShortcutCounts[$shortcut]=@{Count=0;Last=Get-Date}}
                $script:ShortcutCounts[$shortcut].Count++
                $script:ShortcutCounts[$shortcut].Last=Get-Date
                $script:Stats.Shortcuts++
                $message=if($description){"$shortcut  [$description]"}else{$shortcut}
                Write-Feed 'SHORTCUT' $message $time
                Update-ShortcutAnalyzer
            }
            else{Write-Feed 'KEY DOWN' "$name  VK=$vk  SCAN=$scan  FLAGS=$flags" $time}
            if($vk -in 20,144,145){Update-LockIndicators}
        } elseif($type -eq 'KU'){
            $vk=[int]$parts[2];$scan=[int]$parts[3];$name=Get-KeyName $vk
            $heldMs=0
            if($script:KeyDownTimes.ContainsKey($vk)){
                $heldMs=[Math]::Round(((Get-Date)-$script:KeyDownTimes[$vk]).TotalMilliseconds)
                $script:KeyDownTimes.Remove($vk)
            }
            $stat=Get-OrCreateKeyStat $vk
            $stat.IsDown=$false
            if ($script:StuckWarned.ContainsKey($vk)) { $script:StuckWarned.Remove($vk) }
            $stat.TotalHoldMs += $heldMs
            if($heldMs -gt $stat.LongestHoldMs){$stat.LongestHoldMs=$heldMs}
            $stat.LastScan=$scan

            if ($script:TestMode) {
                $testStat = Get-OrCreateTestKeyStat $vk
                $testStat.TotalHoldMs += $heldMs
                if ($heldMs -gt $testStat.LongestHoldMs) {
                    $testStat.LongestHoldMs = $heldMs
                }
            }
            Write-Feed 'KEY UP' "$name  HELD=${heldMs}ms" $time
            $script:FadeQueue[$vk]=@{Start=Get-Date;Color=(Get-KeyCategoryColor $vk)}
            if($script:SelectedInspectorVk -eq $vk){Update-KeyInspector $vk}
        } elseif($type -eq 'M'){
            $name=$parts[2];$state=$parts[3];$detail=[int]$parts[4];$mx=[int]$parts[5];$my=[int]$parts[6]
            $MousePosition.Text="X: $mx   Y: $my"

            # Trackpad movement can be extremely high-volume, so it updates only
            # the optional trackpad window and is not added to the main feed.
            if($name -eq 'MOVE'){
                Update-TrackpadMovement -ScreenX $mx -ScreenY $my
                continue
            }

            $control=switch($name){'LEFT'{$MouseLeft};'RIGHT'{$MouseRight};'MIDDLE'{$MouseMiddle};'X1'{$MouseX1};'X2'{$MouseX2};default{$null}}

            if($name -eq 'WHEEL'){
                $script:Stats.Wheel++
                if($script:TestMode){$script:TestWheelEvents++}
                if($script:TrackpadDiagnosticsActive){
                    if($detail -gt 0){$script:TrackpadScrollUp++}else{$script:TrackpadScrollDown++}
                }
                if($MouseWheelState){$MouseWheelState.Text=[string]$detail;$MouseWheelState.ForeColor=$Colors.Accent}
                if($detail -gt 0){
                    $MouseWheelUp.BackColor=$Colors.Mouse
                    $script:FadeQueue['MWU']=Get-Date
                    Write-Feed 'MOUSE' "Wheel up at $mx,$my" $time
                }else{
                    $MouseWheelDown.BackColor=$Colors.Mouse
                    $script:FadeQueue['MWD']=Get-Date
                    Write-Feed 'MOUSE' "Wheel down at $mx,$my" $time
                }
            }
            elseif($name -eq 'HWHEEL'){
                if($script:TrackpadDiagnosticsActive){
                    if($detail -gt 0){$script:TrackpadScrollRight++}else{$script:TrackpadScrollLeft++}
                }
                Write-Feed 'MOUSE' "Horizontal wheel delta=$detail at $mx,$my" $time
            }
            elseif($control){
                if($state -eq 'DOWN'){
                    $control.BackColor=$Colors.Mouse
                    $script:Stats.MouseClicks++
                    Register-MouseDownDiagnostic $name
                    if($script:TrackpadDiagnosticsActive -and $script:TrackpadClicks.ContainsKey($name)){
                        $script:TrackpadClicks[$name]=[int]$script:TrackpadClicks[$name]+1
                    }
                    Write-Feed 'MOUSE' "$name click at $mx,$my" $time
                }else{
                    $control.BackColor=$Colors.Key
                }

                $stateLabel=switch($name){'LEFT'{$MouseLeftState};'RIGHT'{$MouseRightState};'MIDDLE'{$MouseMiddleState};'X1'{$MouseX1State};'X2'{$MouseX2State};default{$null}}
                if($stateLabel){
                    $stateLabel.Text=$state
                    $stateLabel.ForeColor=if($state -eq 'DOWN'){$Colors.Letter}else{$Colors.Text}
                }
            }
        }
    }
    Update-Stats
})

$UiTimer.Add_Tick({
    # Safety net: force-stop capture after CaptureAutoStopMinutes even if the
    # user forgot it was running.
    if ([GlobalInputDiagnostics]::IsRunning -and $script:CaptureRunSince) {
        $elapsedMinutes = ((Get-Date) - $script:CaptureRunSince).TotalMinutes
        if ($elapsedMinutes -ge $script:CaptureAutoStopMinutes) {
            Stop-Capture "Capture automatically stopped after $script:CaptureAutoStopMinutes minutes (safety timeout)."
        }
    }

    # staged fade after key release
    foreach($key in @($script:FadeQueue.Keys)){
        $age=if($key -in 'MWU','MWD'){((Get-Date)-$script:FadeQueue[$key]).TotalMilliseconds}else{0}
        if($key -eq 'MWU' -and $age -gt 140){$MouseWheelUp.BackColor=$Colors.Key;$script:FadeQueue.Remove($key);continue}
        if($key -eq 'MWD' -and $age -gt 140){$MouseWheelDown.BackColor=$Colors.Key;$script:FadeQueue.Remove($key);continue}
        if($key -is [int] -or "$key" -match '^\d+$'){
            $vk=[int]$key
            $ghost=$script:FadeQueue[$key]
            $age=((Get-Date)-$ghost.Start).TotalMilliseconds
            if($age -gt 650){Reset-KeyVisual $vk;$script:FadeQueue.Remove($key)}
            elseif($age -gt 450){Set-KeyVisual $vk (Get-GhostColor $ghost.Color 0.15)}
            elseif($age -gt 250){Set-KeyVisual $vk (Get-GhostColor $ghost.Color 0.30)}
            elseif($age -gt 100){Set-KeyVisual $vk (Get-GhostColor $ghost.Color 0.55)}
            else{Set-KeyVisual $vk (Get-GhostColor $ghost.Color 0.85)}
        }
    }
    if ($script:TestMode -and [GlobalInputDiagnostics]::IsRunning) {
        foreach ($vk in @($script:KeyDownTimes.Keys)) {
            $held = ((Get-Date) - $script:KeyDownTimes[$vk]).TotalMilliseconds
            if ($held -ge $script:StuckKeyThresholdMs) {
                Set-KeyVisual ([int]$vk) $Colors.Destructive
                if (-not $script:StuckWarned.ContainsKey($vk)) {
                    $script:StuckWarned[$vk] = $true
                    $name = Get-KeyName ([int]$vk)
                    Write-Feed 'WARNING' "Potential stuck key: $name has been held for $([Math]::Round($held)) ms."
                    if ($script:SelectedInspectorVk -eq [int]$vk) { Update-KeyInspector ([int]$vk) }
                }
            }
        }
    }

    if($StuckKeysValue){$stuck=@($script:StuckWarned.Keys).Count;$StuckKeysValue.Text=if($stuck -gt 0){"$stuck  !"}else{'0  ✓'};$StuckKeysValue.ForeColor=if($stuck -gt 0){$Colors.Destructive}else{$Colors.Text}}
    if($MouseLeftState){$MouseLeftState.Text="$($MouseLeftState.Text -replace '\s+\(\d+\)$','') ($($script:MouseClickCounts.LEFT))"}
    if($MouseRightState){$MouseRightState.Text="$($MouseRightState.Text -replace '\s+\(\d+\)$','') ($($script:MouseClickCounts.RIGHT))"}
    Update-LockIndicators
    $app=[GlobalInputDiagnostics]::GetForegroundWindowInfo()
    if($app -ne $script:LastAppInfo){$script:LastAppInfo=$app;$ap=$app -split '\|',2;$title=if($ap.Count -gt 1){$ap[1]}else{''};if($title.Length -gt 90){$title=$title.Substring(0,90)+'...'};$AppLabel.Text="Active app:   $($ap[0])"; if($title){$AppLabel.Text += " - $title"}}
})

$Form.Add_Resize({if($Form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized -and [GlobalInputDiagnostics]::IsRunning){Stop-Capture 'Capture automatically stopped because the window was minimized'}})
$Form.Add_FormClosing({
    [GlobalInputDiagnostics]::TrackpadTrackingEnabled = $false
    [GlobalInputDiagnostics]::Stop()
    [PointerDiagnostics]::Stop()
    $PollTimer.Stop()
    $UiTimer.Stop()
})
$Form.Add_Shown({Update-LockIndicators;Update-KeyInspector 65;Update-TestModeButton;Update-TestProgress;Update-KeyboardLayoutVisuals;$DpiLabel.Text="DPI Scaling:  $([Math]::Round(($Form.DeviceDpi/96.0)*100))%";$PollTimer.Start();$UiTimer.Start();Write-Feed 'SYSTEM' 'Ready. Click Start capture to begin visible, memory-only diagnostics.'})

[void]$Form.ShowDialog()
