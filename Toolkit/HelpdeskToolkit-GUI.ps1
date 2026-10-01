<#
.SYNOPSIS
    Graphical front-end for the IT Helpdesk Toolkit (WPF, no extra modules needed).

.DESCRIPTION
    Loads the same Core\ and Modules\ files as the console version into a background runspace,
    plus Gui\GuiHost.ps1 which routes the tools' console input/output to this window.
    Tools run in the background so the window stays responsive; long jobs can be stopped.
    Light and dark themes; the choice is saved in the toolkit's Settings folder for portability.

.PARAMETER NoElevate
    Do not offer to relaunch as Administrator.

.EXAMPLE
    .\HelpdeskToolkit-GUI.ps1
#>
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$NoElevate)

$Script:Root = $PSScriptRoot
$Script:Exe  = (Get-Process -Id $PID).Path

# WPF needs a single-threaded apartment
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $argLine = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
    if ($NoElevate) { $argLine += ' -NoElevate' }
    Start-Process -FilePath $Script:Exe -ArgumentList $argLine
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-Elevated {
    $argLine = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -NoElevate"
    try { Start-Process -FilePath $Script:Exe -Verb RunAs -ArgumentList $argLine -ErrorAction Stop; return $true }
    catch { return $false }
}

$Script:IsAdmin = Test-IsAdmin
if (-not $Script:IsAdmin -and -not $NoElevate) {
    $answer = [System.Windows.MessageBox]::Show("Some tools need Administrator rights.`n`nRestart the toolkit as Administrator?", 'IT Helpdesk Toolkit', 'YesNo', 'Question')
    if ($answer -eq 'Yes' -and (Start-Elevated)) { return }
}

#region BUILD:GUISOURCES - Build-SingleFile.ps1 replaces this region with embedded copies of these files
function Get-ToolkitSources {
    $coreDir = Join-Path $Script:Root 'Core'
    $moduleDir = Join-Path $Script:Root 'Modules'
    $guiDir = Join-Path $Script:Root 'Gui'

    # Load Core files in dependency order (not alphabetical)
    $coreOrder = @('Common.ps1', 'Config.ps1', 'Dependencies.ps1', 'Validation.ps1', 'Cache.ps1', 'ResourceManagement.ps1', 'ErrorHandling.ps1', 'SecurityManagement.ps1')
    $coreFiles = @()
    foreach ($name in $coreOrder) {
        $path = Join-Path $coreDir $name
        if (Test-Path $path) { $coreFiles += Get-Item $path }
    }
    # Add any additional Core files not in the order
    $coreFiles += @(Get-ChildItem $coreDir -Filter *.ps1 | Where-Object { $_.Name -notin $coreOrder } | Sort-Object Name)

    # Load Module files in alphabetical order
    $moduleFiles = @(Get-ChildItem $moduleDir -Filter *.ps1 | Sort-Object Name)

    # Load GUI file last
    $guiFile = Get-Item (Join-Path $guiDir 'GuiHost.ps1')

    $files = @($coreFiles) + @($moduleFiles) + @($guiFile)
    foreach ($f in $files) {
        @{ Name = $f.FullName.Substring($Script:Root.Length + 1); Text = [IO.File]::ReadAllText($f.FullName) }
    }
}
#endregion BUILD:GUISOURCES

#region ---------------------------------------------------------------- Background runspace

$Script:Sync = [hashtable]::Synchronized(@{
    Queue          = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    CurrentProcess = $null
})

$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
try { $iss.ExecutionPolicy = 'Bypass' } catch { }
$Script:Runspace = [runspacefactory]::CreateRunspace($iss)
$Script:Runspace.ApartmentState = 'STA'
$Script:Runspace.ThreadOptions  = 'ReuseThread'
$Script:Runspace.Open()
$Script:Runspace.SessionStateProxy.SetVariable('HdtSync', $Script:Sync)
$Script:Runspace.SessionStateProxy.SetVariable('HdtRoot', $Script:Root)

$loader = {
    param($Sources)
    foreach ($s in $Sources) {
        try { . ([scriptblock]::Create($s.Text)) }
        catch {
            if ($s.Name -like 'Modules*') { $Script:ModuleErrors += "$($s.Name): $($_.Exception.Message)" }
            else { throw "$($s.Name): $($_.Exception.Message)" }
        }
    }
    [pscustomobject]@{
        Version = $Script:Version
        OutDir  = $Script:OutDir
        Tools   = @($Script:Tools | Select-Object Id, Category, Name, Description, Admin)
        Errors  = @($Script:ModuleErrors)
    }
}

try {
    $init = [PowerShell]::Create()
    $init.Runspace = $Script:Runspace
    [void]$init.AddScript($loader.ToString()).AddArgument(@(Get-ToolkitSources))
    $Script:Info = $init.Invoke() | Select-Object -Last 1
    if ($init.Streams.Error.Count -and -not $Script:Info) { throw $init.Streams.Error[0].Exception }
    $init.Dispose()
    if (-not $Script:Info) { throw 'The toolkit did not return a tool list.' }
} catch {
    $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }
    [System.Windows.MessageBox]::Show("The toolkit failed to load:`n`n$($e.Message)", 'IT Helpdesk Toolkit', 'OK', 'Error') | Out-Null
    return
}

# Status indicator symbols (using Segoe Fluent Icons)
$Script:StatusIcons = @{
    'ready'     = [string][char]0xE001  # Green circle (empty for ready state)
    'running'   = [string][char]0xE9C9  # Animated indicator
    'completed' = [string][char]0xE930  # Checkmark
    'error'     = [string][char]0xE783  # X mark
}

$Script:AllTools = @($Script:Info.Tools | ForEach-Object {
    $toolId = $_.Id
    [pscustomobject]@{
        Id          = $toolId
        Category    = $_.Category
        Name        = $_.Name
        Description = $_.Description
        Admin       = [bool]$_.Admin
        AdminMark   = if ($_.Admin) { 'admin' } else { '' }
        Status      = 'ready'      # ready|running|completed|error
        StatusIcon  = ' '          # Status indicator symbol
        Fav         = ''           # star glyph when the tool is a favorite
    }
})

#endregion

#region ---------------------------------------------------------------- Themes

$Script:Themes = @{
    Light = @{
        WindowBg = '#F3F4F6'; CardBg = '#FFFFFF'; CardBorder = '#E5E7EB'; Text = '#111827'; BodyText = '#374151'
        SubText = '#6B7280'; Faint = '#9CA3AF'; HoverBg = '#F3F4F6'; SelectedBg = '#DBEAFE'; InputBg = '#FFFFFF'
        InputBorder = '#D1D5DB'; BtnBg = '#FFFFFF'; BtnBorder = '#D1D5DB'; BtnText = '#111827'; StatusBg = '#E5E7EB'
        StatusText = '#374151'; Accent = '#1D4ED8'; Warn = '#B45309'; OutputBg = '#111827'; HeaderBg = '#1F2937'
        ScrollThumb = '#C4C9D1'; ContextBg = '#F3F4F6'
    }
    Dark = @{
        WindowBg = '#0F1115'; CardBg = '#181B21'; CardBorder = '#2A2F38'; Text = '#E6E8EB'; BodyText = '#C5CAD3'
        SubText = '#9CA3AF'; Faint = '#6B7280'; HoverBg = '#222730'; SelectedBg = '#1E3A5F'; InputBg = '#101318'
        InputBorder = '#353B46'; BtnBg = '#222730'; BtnBorder = '#353B46'; BtnText = '#E6E8EB'; StatusBg = '#14171C'
        StatusText = '#9CA3AF'; Accent = '#93C5FD'; Warn = '#FBBF24'; OutputBg = '#0A0C0F'; HeaderBg = '#0B0D11'
        ScrollThumb = '#3F4550'; ContextBg = '#101318'
    }
}

$Script:SettingsFile = Join-Path $Script:Root 'Settings\gui-settings.json'

# Saved per user: theme, favorites, recent tool IDs, and collapsed categories
$Script:Favorites = New-Object System.Collections.Generic.List[string]
$Script:RecentTools = New-Object System.Collections.Generic.List[string]
$Script:CollapsedCategories = New-Object System.Collections.Generic.HashSet[string]
$Script:SavedTheme = $null
try {
    $s = Get-Content -LiteralPath $Script:SettingsFile -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($s.Theme -in 'Light', 'Dark') { $Script:SavedTheme = $s.Theme }
    foreach ($id in @($s.Favorites)) { if ($id -and -not $Script:Favorites.Contains("$id")) { $Script:Favorites.Add("$id") } }
    foreach ($id in @($s.RecentTools)) { if ($id -and -not $Script:RecentTools.Contains("$id")) { $Script:RecentTools.Add("$id") } }
    foreach ($cat in @($s.CollapsedCategories)) { if ($cat) { [void]$Script:CollapsedCategories.Add("$cat") } }
} catch { }

function Get-InitialTheme {
    if ($Script:SavedTheme) { return $Script:SavedTheme }
    # First run: follow the Windows app theme
    $light = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue).AppsUseLightTheme
    if ($light -eq 0) { 'Dark' } else { 'Light' }
}

function Save-Settings {
    try {
        $dir = Split-Path $Script:SettingsFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        @{
            Theme = $Script:Theme
            Favorites = @($Script:Favorites)
            RecentTools = @($Script:RecentTools)
            CollapsedCategories = @($Script:CollapsedCategories | Sort-Object)
        } | ConvertTo-Json | Set-Content -LiteralPath $Script:SettingsFile -Encoding UTF8
    } catch { }
}

try {
    Add-Type -Namespace HdtNative -Name Dwm -ErrorAction Stop -MemberDefinition @'
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int value, int size);
'@
} catch { }

# Pushes the theme brushes into a window's resources; everything else uses DynamicResource
function Set-WindowTheme {
    param($Window, [string]$Name)
    foreach ($kv in $Script:Themes[$Name].GetEnumerator()) {
        $b = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($kv.Value))
        $b.Freeze()
        # pass the real brush, not PowerShell's PSObject wrapper, or WPF can't use it
        $Window.Resources.Remove($kv.Key)
        $Window.Resources.Add($kv.Key, $b.PSObject.BaseObject)
    }
    # Dark title bar (Windows 10 20H1+ / Windows 11)
    try {
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($Window)).EnsureHandle()
        $v = [int]($Name -eq 'Dark')
        [void][HdtNative.Dwm]::DwmSetWindowAttribute($hwnd, 20, [ref]$v, 4)
    } catch { }
}

# Styles shared by the main window and the dialogs
$Script:SharedStyles = @'
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Padding" Value="14,6"/>
      <Setter Property="Background" Value="{DynamicResource BtnBg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BtnBorder}"/>
      <Setter Property="Foreground" Value="{DynamicResource BtnText}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="5" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="#3B82F6"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#2563EB"/>
      <Setter Property="BorderBrush" Value="#2563EB"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="26,8"/>
    </Style>
    <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#DC2626"/>
      <Setter Property="BorderBrush" Value="#DC2626"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Padding" Value="18,8"/>
    </Style>
    <Style x:Key="HeaderButton" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#374151"/>
      <Setter Property="BorderBrush" Value="#4B5563"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Padding" Value="10,4"/>
    </Style>
    <Style x:Key="GhostButton" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource SubText}"/>
      <Setter Property="Padding" Value="6,3"/>
    </Style>
    <Style TargetType="ListBox">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource InputBorder}"/>
    </Style>
    <Style TargetType="ListBoxItem">
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="Bd" Background="Transparent" Padding="{TemplateBinding Padding}" CornerRadius="4" Margin="6,1">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource HoverBg}"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource SelectedBg}"/></Trigger>
              <DataTrigger Binding="{Binding IsSearchMatch}" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource SelectedBg}"/>
                <Setter TargetName="Bd" Property="Opacity" Value="0.7"/>
              </DataTrigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource InputBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource InputBorder}"/>
      <Setter Property="CaretBrush" Value="{DynamicResource Text}"/>
    </Style>
    <Style TargetType="PasswordBox">
      <Setter Property="Background" Value="{DynamicResource InputBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource InputBorder}"/>
      <Setter Property="CaretBrush" Value="{DynamicResource Text}"/>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Width" Value="10"/>
      <Setter Property="MinWidth" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb><Thumb.Template><ControlTemplate TargetType="Thumb">
                  <Border Background="{DynamicResource ScrollThumb}" CornerRadius="4" Margin="2"/>
                </ControlTemplate></Thumb.Template></Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/>
          <Setter Property="MinWidth" Value="0"/>
          <Setter Property="Height" Value="10"/>
          <Setter Property="MinHeight" Value="10"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Track x:Name="PART_Track" IsDirectionReversed="False">
                  <Track.Thumb>
                    <Thumb><Thumb.Template><ControlTemplate TargetType="Thumb">
                      <Border Background="{DynamicResource ScrollThumb}" CornerRadius="4" Margin="2"/>
                    </ControlTemplate></Thumb.Template></Thumb>
                  </Track.Thumb>
                </Track>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="PanelHeader" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource SubText}"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="16,12,0,6"/>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource CardBg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource CardBorder}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="6"/>
    </Style>
'@

#endregion

#region ---------------------------------------------------------------- Window

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="IT Helpdesk Toolkit" Width="1340" Height="840" MinWidth="1000" MinHeight="600"
        WindowStartupLocation="CenterScreen" Background="{DynamicResource WindowBg}" Foreground="{DynamicResource Text}"
        FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
$Script:SharedStyles
  </Window.Resources>

  <DockPanel>
    <Border DockPanel.Dock="Top" Background="{DynamicResource HeaderBg}" Padding="18,10">
      <Grid>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="IT Helpdesk Toolkit" Foreground="White" FontSize="18" FontWeight="SemiBold"/>
          <TextBlock x:Name="VersionText" Foreground="#9CA3AF" Margin="10,5,0,0"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <TextBlock x:Name="MachineText" Foreground="#D1D5DB" VerticalAlignment="Center" Margin="0,0,14,0"/>
          <Border x:Name="AdminBadge" CornerRadius="10" Padding="10,3" VerticalAlignment="Center">
            <TextBlock x:Name="AdminText" Foreground="White" FontWeight="SemiBold" FontSize="12"/>
          </Border>
          <Button x:Name="ElevateButton" Content="Restart as Administrator" Margin="10,0,0,0" Style="{StaticResource HeaderButton}"/>
          <Button x:Name="HelpButton" Margin="10,0,0,0" Style="{StaticResource HeaderButton}" ToolTip="Keyboard shortcuts (F1)">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="?" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="13" VerticalAlignment="Center" FontWeight="SemiBold"/>
              <TextBlock Text="Help" Margin="7,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
          <Button x:Name="ThemeButton" Margin="10,0,0,0" Style="{StaticResource HeaderButton}" ToolTip="Switch light / dark mode (Ctrl+D)">
            <StackPanel Orientation="Horizontal">
              <TextBlock x:Name="ThemeIcon" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="13" VerticalAlignment="Center" Margin="0,1,7,0"/>
              <TextBlock x:Name="ThemeLabel" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
        </StackPanel>
      </Grid>
    </Border>

    <Border DockPanel.Dock="Bottom" Background="{DynamicResource StatusBg}" Padding="14,5">
      <Grid>
        <TextBlock x:Name="StatusText" Text="Ready" Foreground="{DynamicResource StatusText}"/>
        <TextBlock x:Name="ProgressText" HorizontalAlignment="Right" Foreground="{DynamicResource Accent}" FontFamily="Consolas"/>
      </Grid>
    </Border>

    <Grid Margin="12">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="210"/>
        <ColumnDefinition Width="340"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <Border Grid.Column="0" Style="{StaticResource Card}" Margin="0,0,10,0">
        <DockPanel>
          <StackPanel x:Name="QuickAccessPanel" DockPanel.Dock="Top" Visibility="Collapsed">
            <TextBlock Text="QUICK ACCESS" Style="{StaticResource PanelHeader}"/>
            <ItemsControl x:Name="QuickAccessList" ItemsSource="{Binding}">
              <ItemsControl.ItemsPanel>
                <ItemsPanelTemplate>
                  <WrapPanel/>
                </ItemsPanelTemplate>
              </ItemsControl.ItemsPanel>
              <ItemsControl.ItemTemplate>
                <DataTemplate>
                  <Button Content="{Binding Id}" Margin="4,2" Padding="8,4" Style="{StaticResource Btn}" FontSize="11" ToolTip="{Binding Name}"/>
                </DataTemplate>
              </ItemsControl.ItemTemplate>
            </ItemsControl>
          </StackPanel>
          <TextBlock DockPanel.Dock="Top" Text="CATEGORIES" Style="{StaticResource PanelHeader}"/>
          <ListBox x:Name="CategoryList" BorderThickness="0" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
            <ListBox.ItemTemplate>
              <DataTemplate>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <TextBlock x:Name="Ic" Text="{Binding Icon}" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="13"
                             Foreground="{DynamicResource SubText}" VerticalAlignment="Center"/>
                  <TextBlock Grid.Column="1" Text="{Binding Display}" TextTrimming="CharacterEllipsis"/>
                  <TextBlock Grid.Column="2" Text="{Binding Count}" Foreground="{DynamicResource Faint}"/>
                </Grid>
                <DataTemplate.Triggers>
                  <DataTrigger Binding="{Binding Kind}" Value="fav"><Setter TargetName="Ic" Property="Foreground" Value="#F59E0B"/></DataTrigger>
                </DataTemplate.Triggers>
              </DataTemplate>
            </ListBox.ItemTemplate>
          </ListBox>
        </DockPanel>
      </Border>

      <Border Grid.Column="1" Style="{StaticResource Card}" Margin="0,0,10,0">
        <DockPanel>
          <Grid DockPanel.Dock="Top" Margin="12,12,12,6">
            <TextBox x:Name="SearchBox" Padding="8,5,30,5"/>
            <TextBlock x:Name="SearchHint" Text="Search all tools  (Ctrl+F)" Foreground="{DynamicResource Faint}" Margin="11,6,30,0"
                       IsHitTestVisible="False" TextTrimming="CharacterEllipsis"/>
            <Button x:Name="ClearSearchButton" Style="{StaticResource GhostButton}" HorizontalAlignment="Right" VerticalAlignment="Center"
                    Margin="0,0,3,0" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="10" Visibility="Collapsed" ToolTip="Clear search (Esc)"/>
          </Grid>
          <TextBlock x:Name="ToolListHeader" DockPanel.Dock="Top" Style="{StaticResource PanelHeader}"/>
          <Grid>
            <ListBox x:Name="ToolList" BorderThickness="0" ScrollViewer.HorizontalScrollBarVisibility="Disabled" AllowDrop="True">
              <ListBox.GroupStyle>
                <GroupStyle>
                  <GroupStyle.ContainerStyle>
                    <Style TargetType="{x:Type GroupItem}">
                      <Setter Property="Template">
                        <Setter.Value>
                          <ControlTemplate TargetType="{x:Type GroupItem}">
                            <StackPanel>
                              <Border Background="{DynamicResource SubText}" Padding="8,2" Margin="6,4,6,2" CornerRadius="3">
                                <TextBlock Text="{Binding Name}" Foreground="{DynamicResource CardBg}" FontSize="11" FontWeight="SemiBold"/>
                              </Border>
                              <ItemsPresenter/>
                            </StackPanel>
                          </ControlTemplate>
                        </Setter.Value>
                      </Setter>
                    </Style>
                  </GroupStyle.ContainerStyle>
                </GroupStyle>
              </ListBox.GroupStyle>
              <ListBox.ItemTemplate>
                <DataTemplate>
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="14"/><ColumnDefinition Width="56"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Text="{Binding StatusIcon}" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="10"
                               Foreground="{DynamicResource SubText}" VerticalAlignment="Center" ToolTip="{Binding Status}"/>
                    <TextBlock Grid.Column="1" Text="{Binding Id}" Foreground="{DynamicResource SubText}" FontFamily="Consolas" FontSize="12" VerticalAlignment="Center"/>
                    <TextBlock Grid.Column="2" Text="{Binding Name}" TextTrimming="CharacterEllipsis" ToolTip="{Binding Description}"/>
                    <TextBlock Grid.Column="3" Text="{Binding Fav}" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="11"
                               Foreground="#F59E0B" VerticalAlignment="Center" Margin="6,0,0,0" ToolTip="Favorite"/>
                    <TextBlock Grid.Column="4" Text="{Binding AdminMark}" Foreground="{DynamicResource Warn}" FontSize="10.5" FontWeight="SemiBold"
                               VerticalAlignment="Center" Margin="6,0,0,0" ToolTip="Requires Administrator"/>
                  </Grid>
                </DataTemplate>
              </ListBox.ItemTemplate>
            </ListBox>
            <TextBlock x:Name="EmptyHint" Visibility="Collapsed" TextWrapping="Wrap" TextAlignment="Center"
                       Foreground="{DynamicResource SubText}" Margin="24,16,24,0" VerticalAlignment="Top"/>
          </Grid>
        </DockPanel>
      </Border>

      <Grid Grid.Column="2">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Border Style="{StaticResource Card}" Padding="16,12" Margin="0,0,0,10">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel>
              <TextBlock x:Name="ToolTitle" FontSize="17" FontWeight="SemiBold" Text="Select a tool" TextWrapping="Wrap"/>
              <TextBlock x:Name="ToolMeta" Foreground="{DynamicResource SubText}" FontSize="12" Margin="0,2,0,0"/>
              <TextBlock x:Name="ToolDesc" Foreground="{DynamicResource BodyText}" TextWrapping="Wrap" Margin="0,6,0,0"
                         Text="Pick a category on the left, or search. Double-click a tool (or press Enter / F5) to run it."/>
              <TextBlock x:Name="ToolAdminNote" Foreground="{DynamicResource Warn}" Margin="0,6,0,0" Visibility="Collapsed" TextWrapping="Wrap"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="12,0,0,0">
              <Button x:Name="FavButton" Style="{StaticResource Btn}" Padding="12,8" Margin="0,0,8,0" IsEnabled="False" ToolTip="Add to favorites (Ctrl+B)">
                <StackPanel Orientation="Horizontal">
                  <TextBlock x:Name="FavIcon" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center"/>
                  <TextBlock x:Name="FavLabel" Text="Favorite" Margin="7,0,0,0" VerticalAlignment="Center"/>
                </StackPanel>
              </Button>
              <Button x:Name="RunButton" Content="Run" Style="{StaticResource PrimaryButton}" IsEnabled="False"/>
              <Button x:Name="StopButton" Content="Stop" Style="{StaticResource DangerButton}" IsEnabled="False" Margin="8,0,0,0"/>
            </StackPanel>
          </Grid>
        </Border>

        <Border Grid.Row="1" Background="{DynamicResource OutputBg}" CornerRadius="6">
          <RichTextBox x:Name="Output" IsReadOnly="True" Background="Transparent" BorderThickness="0"
                       Foreground="#E5E7EB" FontFamily="Consolas" FontSize="12.5" Padding="10"
                       VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto">
            <FlowDocument PageWidth="1400"><Paragraph Margin="0"/></FlowDocument>
          </RichTextBox>
        </Border>

        <Grid Grid.Row="2" Margin="0,10,0,0">
          <StackPanel Orientation="Horizontal">
            <Button x:Name="CopyButton" Content="Copy output" Style="{StaticResource Btn}"/>
            <Button x:Name="SaveButton" Content="Save output..." Style="{StaticResource Btn}" Margin="8,0,0,0"/>
            <Button x:Name="ClearButton" Content="Clear" Style="{StaticResource Btn}" Margin="8,0,0,0"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="FolderButton" Content="Open output folder" Style="{StaticResource Btn}"/>
            <Button x:Name="ConsoleButton" Content="Console version" Style="{StaticResource Btn}" Margin="8,0,0,0"/>
          </StackPanel>
        </Grid>
      </Grid>
    </Grid>
  </DockPanel>
</Window>
"@

$Script:Window = [Windows.Markup.XamlReader]::Parse($xaml)
$ui = @{}
foreach ($name in 'VersionText', 'MachineText', 'AdminBadge', 'AdminText', 'ElevateButton', 'HelpButton', 'ThemeButton', 'ThemeIcon', 'ThemeLabel',
                  'StatusText', 'ProgressText', 'CategoryList', 'SearchBox', 'SearchHint', 'ClearSearchButton', 'ToolListHeader', 'ToolList', 'ToolTitle',
                  'ToolMeta', 'ToolDesc', 'ToolAdminNote', 'RunButton', 'StopButton', 'Output', 'CopyButton', 'SaveButton',
                  'FavButton', 'FavIcon', 'FavLabel', 'EmptyHint', 'QuickAccessPanel', 'QuickAccessList',
                  'ClearButton', 'FolderButton', 'ConsoleButton') {
    $ui[$name] = $Script:Window.FindName($name)
}
$Script:Ui = $ui
$Script:Para = $ui.Output.Document.Blocks.FirstBlock

function Set-Theme {
    param([string]$Name)
    $Script:Theme = $Name
    Set-WindowTheme -Window $Script:Window -Name $Name
    foreach ($w in $Script:Window.OwnedWindows) { Set-WindowTheme -Window $w -Name $Name }
    # The button offers the other mode: moon = go dark, sun = go light
    if ($Name -eq 'Dark') { $Script:Ui.ThemeIcon.Text = [string][char]0xE706; $Script:Ui.ThemeLabel.Text = 'Light mode' }
    else                  { $Script:Ui.ThemeIcon.Text = [string][char]0xE708; $Script:Ui.ThemeLabel.Text = 'Dark mode' }
}

#endregion

#region ---------------------------------------------------------------- Output pane

$Script:Brushes = @{}
$colors = @{
    ''         = '#E5E7EB'; 'Gray'      = '#D1D5DB'; 'DarkGray'    = '#9CA3AF'; 'White'     = '#FFFFFF'
    'Cyan'     = '#67E8F9'; 'DarkCyan'  = '#22D3EE'; 'Green'       = '#86EFAC'; 'DarkGreen' = '#4ADE80'
    'Yellow'   = '#FDE68A'; 'DarkYellow'= '#FBBF24'; 'Red'         = '#FCA5A5'; 'DarkRed'   = '#F87171'
    'Magenta'  = '#F0ABFC'; 'DarkMagenta' = '#E879F9'; 'Blue'      = '#93C5FD'; 'DarkBlue'  = '#60A5FA'
}
foreach ($k in $colors.Keys) {
    $b = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($colors[$k]))
    $b.Freeze()
    $Script:Brushes[$k] = $b
}

function Add-OutputText {
    param([string]$Text, [string]$Color = '', [bool]$NewLine = $true)
    $brush = $Script:Brushes[$Color]
    if (-not $brush) { $brush = $Script:Brushes[''] }
    $lines = $Text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i]) {
            $run = New-Object System.Windows.Documents.Run($lines[$i])
            $run.Foreground = $brush
            $Script:Para.Inlines.Add($run)
        }
        if ($i -lt $lines.Count - 1 -or $NewLine) { $Script:Para.Inlines.Add((New-Object System.Windows.Documents.LineBreak)) }
    }
}

function Get-OutputText {
    $doc = $Script:Ui.Output.Document
    (New-Object System.Windows.Documents.TextRange($doc.ContentStart, $doc.ContentEnd)).Text
}

#endregion

#region ---------------------------------------------------------------- Dialogs (shown on the UI thread)

$Script:DialogButtons = @'
<StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
  <Button Name="OkBtn" Content="OK" MinWidth="90" Style="{StaticResource PrimaryButton}" IsDefault="True"/>
  <Button Name="CancelBtn" Content="Cancel" MinWidth="90" Style="{StaticResource Btn}" Margin="8,0,0,0" IsCancel="True"/>
</StackPanel>
'@

function New-Dialog {
    param([string]$Title, [string]$Size, [string]$Body)
    $d = [Windows.Markup.XamlReader]::Parse(@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title" $Size WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13"
        Background="{DynamicResource CardBg}" Foreground="{DynamicResource Text}" ShowInTaskbar="False">
  <Window.Resources>
$Script:SharedStyles
  </Window.Resources>
  $Body
</Window>
"@)
    $d.Owner = $Script:Window
    Set-WindowTheme -Window $d -Name $Script:Theme
    $d.FindName('OkBtn').Add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    $d
}

function Show-InputDialog {
    param([string]$Prompt, [string[]]$Context, [switch]$Secure)
    $d = New-Dialog -Title 'Input needed' -Size 'SizeToContent="WidthAndHeight" MinWidth="460" MaxWidth="820" ResizeMode="NoResize"' -Body @"
  <StackPanel Margin="20,16">
    <Border Name="CtxBorder" Background="{DynamicResource ContextBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1"
            CornerRadius="4" Padding="10,8" Margin="0,0,0,14">
      <TextBlock Name="CtxText" FontFamily="Consolas" FontSize="12"/>
    </Border>
    <TextBlock Name="PromptText" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,0,0,6"/>
    <TextBox Name="InputBox" Padding="6,4"/>
    <PasswordBox Name="PwBox" Padding="6,4"/>
    <TextBlock Name="HintText" Foreground="{DynamicResource SubText}" FontSize="11.5" Margin="0,6,0,0" TextWrapping="Wrap"/>
    $Script:DialogButtons
  </StackPanel>
"@
    $ctx = @($Context | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
    if ($ctx.Count) { $d.FindName('CtxText').Text = $ctx -join "`n" } else { $d.FindName('CtxBorder').Visibility = 'Collapsed' }
    $d.FindName('PromptText').Text = $Prompt
    $hint = @()
    if ($Prompt -match '\[[^\]]+\]') { $hint += 'Leave blank to use the default shown in [brackets].' }
    if ($Prompt -match 'blank to cancel') { $hint += 'Cancel also cancels.' }
    if ($hint) { $d.FindName('HintText').Text = $hint -join ' ' } else { $d.FindName('HintText').Visibility = 'Collapsed' }
    $box = $d.FindName('InputBox'); $pw = $d.FindName('PwBox')
    if ($Secure) { $box.Visibility = 'Collapsed' } else { $pw.Visibility = 'Collapsed' }
    $d.Add_ContentRendered({ if ($Secure) { [void]$pw.Focus() } else { [void]$box.Focus() } })
    if ($d.ShowDialog()) {
        if ($Secure) { return $pw.SecurePassword }
        return $box.Text
    }
    return $null
}

function Show-SelectDialog {
    param([string]$Prompt, [string[]]$Items)
    $d = New-Dialog -Title 'Choose' -Size 'Width="640" Height="460" MinWidth="400" MinHeight="260"' -Body @"
  <DockPanel Margin="18,14">
    <TextBlock DockPanel.Dock="Top" Name="PromptText" FontWeight="SemiBold" Margin="0,0,0,8" TextWrapping="Wrap"/>
    <ContentControl DockPanel.Dock="Bottom">$Script:DialogButtons</ContentControl>
    <ListBox Name="Choices" FontFamily="Consolas" FontSize="12.5" Background="{DynamicResource InputBg}" BorderThickness="1" Padding="0,4"/>
  </DockPanel>
"@
    $d.FindName('PromptText').Text = ($Prompt -replace '\s*\(number, blank to cancel\)', '')
    $list = $d.FindName('Choices')
    foreach ($i in $Items) { [void]$list.Items.Add($i) }
    $list.SelectedIndex = 0
    $list.Add_MouseDoubleClick({ if ($this.SelectedIndex -ge 0) { [System.Windows.Window]::GetWindow($this).DialogResult = $true } })
    $d.Add_ContentRendered({ [void]$list.Focus() })
    if ($d.ShowDialog()) { return $list.SelectedIndex }
    return -1
}

function Show-ConfirmDialog {
    param([string]$Message, [string]$Title = 'Please confirm')
    $buttons = $Script:DialogButtons.Replace('Content="OK"', 'Content="Yes"').Replace('Content="Cancel"', 'Content="No"')
    $d = New-Dialog -Title $Title -Size 'SizeToContent="WidthAndHeight" MinWidth="420" MaxWidth="720" ResizeMode="NoResize"' -Body @"
  <StackPanel Margin="22,18">
    <TextBlock Name="MsgText" TextWrapping="Wrap" FontSize="13.5"/>
    $buttons
  </StackPanel>
"@
    $d.FindName('MsgText').Text = $Message
    [bool]$d.ShowDialog()
}

function Resolve-Prompt {
    param($Request)
    switch ($Request.PromptKind) {
        'confirm' { return (Show-ConfirmDialog -Message $Request.Prompt) }
        'select'  { return (Show-SelectDialog -Prompt $Request.Prompt -Items $Request.Items) }
        'secure'  { return (Show-InputDialog -Prompt $Request.Prompt -Context $Request.Context -Secure) }
        default   { return (Show-InputDialog -Prompt $Request.Prompt -Context $Request.Context) }
    }
}

#endregion

#region ---------------------------------------------------------------- Running tools

$Script:Current  = $null
$Script:InDialog = $false

function Set-Busy {
    param([bool]$Busy)
    $Script:Ui.StopButton.IsEnabled = $Busy
    $Script:Ui.ProgressText.Text = ''
    Update-RunButton
}

function Update-RunButton {
    $t = $Script:Ui.ToolList.SelectedItem
    $Script:Ui.RunButton.IsEnabled = ($null -ne $t) -and (-not $Script:Current) -and ($Script:IsAdmin -or -not $t.Admin)
}

function Start-Tool {
    param($Tool)
    if (-not $Tool -or $Script:Current) { return }
    if ($Tool.Admin -and -not $Script:IsAdmin) { return }
    if ($Script:Para.Inlines.Count) { Add-OutputText '' }
    Add-OutputText ('=== {0}  {1}   [{2}] ===' -f $Tool.Id, $Tool.Name, (Get-Date -Format 'HH:mm:ss')) 'Cyan'
    $p = [PowerShell]::Create()
    $p.Runspace = $Script:Runspace
    [void]$p.AddCommand('Invoke-GuiTool').AddParameter('Id', $Tool.Id)
    $Script:Current = @{ PS = $p; Handle = $p.BeginInvoke(); Tool = $Tool; Start = Get-Date }
    # Update tool status to running
    $Tool.Status = 'running'
    $Tool.StatusIcon = $Script:StatusIcons['running']
    Update-ToolList
    $Script:Ui.StatusText.Text = "Running $($Tool.Id) $($Tool.Name)..."
    Set-Busy $true
    $Script:Ui.Output.ScrollToEnd()
}

function Stop-Tool {
    if (-not $Script:Current) { return }
    $proc = $Script:Sync.CurrentProcess
    if ($proc) { try { $proc.Kill() } catch { } }
    [void]$Script:Current.PS.BeginStop($null, $null)
    $Script:Ui.StatusText.Text = 'Stopping...'
}

function Complete-Tool {
    $c = $Script:Current
    $Script:Current = $null
    $stopped = $false
    $hasError = $false
    try { [void]$c.PS.EndInvoke($c.Handle) }
    catch {
        $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }
        if ($e -is [System.Management.Automation.PipelineStoppedException]) { $stopped = $true }
        else { Add-OutputText "  [x] $($e.Message)" 'Red'; $hasError = $true }
    }
    foreach ($err in $c.PS.Streams.Error) { Add-OutputText "  [x] $($err.Exception.Message)" 'Red'; $hasError = $true }
    $c.PS.Dispose()
    $secs = [math]::Round(((Get-Date) - $c.Start).TotalSeconds, 1)
    # Update tool status based on completion result
    if ($stopped) {
        $c.Tool.Status = 'ready'
        $c.Tool.StatusIcon = ' '
        Add-OutputText '  [x] Stopped by user.' 'Red'
        $Script:Ui.StatusText.Text = "Stopped $($c.Tool.Id) after $secs s"
    } elseif ($hasError) {
        $c.Tool.Status = 'error'
        $c.Tool.StatusIcon = $Script:StatusIcons['error']
        $Script:Ui.StatusText.Text = "Finished $($c.Tool.Id) $($c.Tool.Name) in $secs s (with errors)"
    } else {
        $c.Tool.Status = 'completed'
        $c.Tool.StatusIcon = $Script:StatusIcons['completed']
        $Script:Ui.StatusText.Text = "Finished $($c.Tool.Id) $($c.Tool.Name) in $secs s"
    }
    # Track tool as recently used
    if ($Script:RecentTools.Contains($c.Tool.Id)) { $Script:RecentTools.Remove($c.Tool.Id) }
    $Script:RecentTools.Insert(0, $c.Tool.Id)
    while ($Script:RecentTools.Count -gt 10) { $Script:RecentTools.RemoveAt($Script:RecentTools.Count - 1) }
    Save-Settings
    Update-ToolList
    Set-Busy $false
    $Script:Ui.Output.ScrollToEnd()
}

$Script:Timer = New-Object System.Windows.Threading.DispatcherTimer
$Script:Timer.Interval = [TimeSpan]::FromMilliseconds(60)
$Script:Timer.Add_Tick({
    if ($Script:InDialog) { return }
    try {
        $completed = $Script:Current -and $Script:Current.Handle.IsCompleted
        $msg = $null
        $added = $false
        $n = 0
        while ($n -lt 500 -and $Script:Sync.Queue.TryDequeue([ref]$msg)) {
            $n++
            if ($msg.Kind -eq 'text') {
                Add-OutputText $msg.Text $msg.Color $msg.NewLine
                $added = $true
            } elseif ($msg.Kind -eq 'progress') {
                $Script:Ui.ProgressText.Text = $msg.Text
            } elseif ($msg.Kind -eq 'prompt') {
                if ($added) { $Script:Ui.Output.ScrollToEnd(); $added = $false }
                $Script:InDialog = $true
                try { $msg.Result = Resolve-Prompt $msg }
                catch { $msg.Result = $null; Add-OutputText "  [x] Dialog error: $($_.Exception.Message)" 'Red' }
                finally { $Script:InDialog = $false; $msg.Done.Set() }
            }
        }
        if ($added) { $Script:Ui.Output.ScrollToEnd() }
        if ($completed -and $Script:Sync.Queue.IsEmpty) { Complete-Tool }
    } catch {
        $Script:InDialog = $false
        Add-OutputText "  [x] UI error: $($_.Exception.Message)" 'Red'
    }
})

#endregion

#region ---------------------------------------------------------------- Lists and wiring

$Script:Categories = @($Script:AllTools | ForEach-Object Category | Select-Object -Unique | Sort-Object)
$Script:StarFilled  = [string][char]0xE735
$Script:StarOutline = [string][char]0xE734
$Script:Gold = (New-Object System.Windows.Media.BrushConverter).ConvertFromString('#F59E0B')
# Segoe Fluent / MDL2 icon per category; categories added later get a folder icon
$Script:CategoryIcons = @{
    'System Information' = 0xE770; 'Network' = 0xE774; 'Maintenance & Repair' = 0xE90F; 'Apps & Office' = 0xE71D
    'Security' = 0xEA18; 'Users & Accounts' = 0xE716; 'Troubleshooting' = 0xE9D9; 'Remote Computers' = 0xE8AF
    'Reports' = 0xE9F9; 'Quick Launch' = 0xE945; 'Hardware & Peripherals' = 0xE772; 'Active Directory' = 0xE902
    'Microsoft 365' = 0xE753; 'Tickets & Cases' = 0xE70B
}

function Get-FavoriteTools {
    # In the order they were added; IDs of tools that no longer exist are skipped
    @(foreach ($id in $Script:Favorites) { $Script:AllTools | Where-Object Id -eq $id | Select-Object -First 1 })
}

function Update-FavMarks {
    foreach ($t in $Script:AllTools) { $t.Fav = if ($Script:Favorites.Contains($t.Id)) { $Script:StarFilled } else { '' } }
}

# Rebuilds the category list (to refresh the Favorites count) and keeps the current selection
function Get-RecentTools {
    @($Script:AllTools | Where-Object { $Script:RecentTools.Contains($_.Id) } | Sort-Object { $Script:RecentTools.IndexOf($_.Id) })
}

function Get-QuickAccessTools {
    @(Get-RecentTools | Select-Object -First 5)
}

function Update-CategoryList {
    param([string]$SelectKey)
    if (-not $SelectKey -and $Script:Ui.CategoryList.SelectedItem) { $SelectKey = $Script:Ui.CategoryList.SelectedItem.Key }
    $items = @(
        [pscustomobject]@{ Key = 'fav'; Kind = 'fav'; Name = ''; Display = 'Favorites'; Icon = $Script:StarFilled; Count = @(Get-FavoriteTools).Count }
    )
    $recentCount = @(Get-RecentTools).Count
    if ($recentCount -gt 0) {
        $items += [pscustomobject]@{ Key = 'recent'; Kind = 'recent'; Name = ''; Display = 'Recent'; Icon = [string][char]0xE81C; Count = $recentCount }
    }
    $items += [pscustomobject]@{ Key = 'all'; Kind = 'all'; Name = ''; Display = 'All tools'; Icon = [string][char]0xE8FD; Count = $Script:AllTools.Count }
    foreach ($c in $Script:Categories) {
        $glyph = if ($Script:CategoryIcons.ContainsKey($c)) { $Script:CategoryIcons[$c] } else { 0xE8B7 }
        $items += [pscustomobject]@{ Key = "cat:$c"; Kind = 'cat'; Name = $c; Display = $c; Icon = [string][char]$glyph; Count = @($Script:AllTools | Where-Object Category -eq $c).Count }
    }
    # Update quick access bar
    $quickTools = @(Get-QuickAccessTools)
    if ($quickTools.Count -gt 0) {
        $Script:Ui.QuickAccessPanel.Visibility = 'Visible'
        $Script:Ui.QuickAccessList.ItemsSource = @($quickTools)
    } else {
        $Script:Ui.QuickAccessPanel.Visibility = 'Collapsed'
    }
    $Script:SuppressCategoryEvent = $true
    $Script:Ui.CategoryList.ItemsSource = $items
    $idx = 0
    for ($i = 0; $i -lt $items.Count; $i++) { if ($items[$i].Key -eq $SelectKey) { $idx = $i } }
    $Script:Ui.CategoryList.SelectedIndex = $idx
    $Script:SuppressCategoryEvent = $false
}

function Find-GuiTools {
    param([object[]]$Tools, [string]$Query)
    $pattern = "*$([WildcardPattern]::Escape($Query))*"
    @($Tools | Where-Object { $_.Name -like $pattern -or $_.Description -like $pattern -or $_.Id -like $pattern })
}

# The search box searches all tools globally; category selection narrows results when no search active
function Update-ToolList {
    $keepId = if ($Script:Ui.ToolList.SelectedItem) { $Script:Ui.ToolList.SelectedItem.Id } else { $null }
    $q = $Script:Ui.SearchBox.Text.Trim()
    $cat = $Script:Ui.CategoryList.SelectedItem
    $kind = if ($cat) { $cat.Kind } else { 'all' }
    switch ($kind) {
        'fav'    { $scope = @(Get-FavoriteTools); $label = 'FAVORITES'; $hint = 'Search all tools  (Ctrl+F)' }
        'recent' { $scope = @(Get-RecentTools); $label = 'RECENT TOOLS'; $hint = 'Search all tools  (Ctrl+F)' }
        'cat'    { $scope = @($Script:AllTools | Where-Object Category -eq $cat.Name); $label = $cat.Name.ToUpper(); $hint = 'Search all tools  (Ctrl+F)' }
        default  { $scope = $Script:AllTools; $label = 'ALL TOOLS'; $hint = 'Search all tools  (Ctrl+F)' }
    }
    $Script:Ui.SearchHint.Text = $hint
    $empty = ''
    # @() everywhere: a single result would otherwise lose .Count on Windows PowerShell 5.1
    if ($q) {
        $matchedItems = @(Find-GuiTools $Script:AllTools $q)
        $items = @($matchedItems | ForEach-Object {
            $_ | Add-Member -NotePropertyName 'IsSearchMatch' -NotePropertyValue $true -PassThru -Force
        })
        $header = "GLOBAL SEARCH - $($items.Count) MATCH$(if ($items.Count -ne 1) { 'ES' })"
        if (-not $items.Count) { $empty = 'No tools match your search.' }
        $Script:Ui.ToolListHeader.Text = $header
    } else {
        $items = @($scope | ForEach-Object {
            $_ | Add-Member -NotePropertyName 'IsSearchMatch' -NotePropertyValue $false -PassThru -Force
        })
        $Script:Ui.ToolListHeader.Text = $label
        if (-not $empty) {
            if ($kind -eq 'fav' -and -not $items.Count) {
                $empty = "No favorites yet.`n`nSelect a tool and click the star next to Run, right-click it, or press Ctrl+B."
            }
        }
    }
    $Script:Ui.EmptyHint.Text = $empty
    $Script:Ui.EmptyHint.Visibility = if ($empty) { 'Visible' } else { 'Collapsed' }
    # Create grouped view if not in search mode and showing a single category
    if (-not $q -and $kind -eq 'cat' -and $items.Count -gt 3) {
        try {
            $collection = New-Object System.Windows.Data.ListCollectionView @($items)
            $groupDesc = New-Object System.Windows.Data.PropertyGroupDescription('Category')
            $collection.GroupDescriptions.Add($groupDesc)
            $Script:Ui.ToolList.ItemsSource = $collection
        } catch {
            # Fallback to simple list if grouping fails
            $Script:Ui.ToolList.ItemsSource = @($items)
        }
    } else {
        $Script:Ui.ToolList.ItemsSource = @($items)
    }
    if ($keepId) {
        $sources = $Script:Ui.ToolList.ItemsSource
        $again = $null
        if ($sources -is [System.Windows.Data.ListCollectionView]) {
            $again = @($sources | Where-Object Id -eq $keepId) | Select-Object -First 1
        } else {
            $again = $sources | Where-Object Id -eq $keepId | Select-Object -First 1
        }
        if ($again) { $Script:Ui.ToolList.SelectedItem = $again }
    }
}

function Update-FavButton {
    $t = $Script:Ui.ToolList.SelectedItem
    $Script:Ui.FavButton.IsEnabled = [bool]$t
    if ($t -and $Script:Favorites.Contains($t.Id)) {
        $Script:Ui.FavIcon.Text = $Script:StarFilled
        $Script:Ui.FavIcon.Foreground = $Script:Gold
        $Script:Ui.FavLabel.Text = 'Favorited'
        $Script:Ui.FavButton.ToolTip = 'Remove from favorites (Ctrl+B)'
    } else {
        $Script:Ui.FavIcon.Text = $Script:StarOutline
        $Script:Ui.FavIcon.ClearValue([System.Windows.Controls.TextBlock]::ForegroundProperty)
        $Script:Ui.FavLabel.Text = 'Favorite'
        $Script:Ui.FavButton.ToolTip = 'Add to favorites (Ctrl+B)'
    }
}

function Switch-Favorite {
    param($Tool)
    if (-not $Tool) { return }
    if ($Script:Favorites.Contains($Tool.Id)) {
        [void]$Script:Favorites.Remove($Tool.Id)
        $Script:Ui.StatusText.Text = "Removed $($Tool.Name) from favorites."
    } else {
        $Script:Favorites.Add($Tool.Id)
        $Script:Ui.StatusText.Text = "Added $($Tool.Name) to favorites."
    }
    Save-Settings
    Update-FavMarks
    Update-CategoryList
    Update-ToolList
    Show-ToolDetails
}

function Show-ToolDetails {
    $t = $Script:Ui.ToolList.SelectedItem
    Update-FavButton
    if (-not $t) {
        $Script:Ui.ToolTitle.Text = 'Select a tool'
        $Script:Ui.ToolMeta.Text  = ''
        $Script:Ui.ToolDesc.Text  = 'Pick a category on the left, or search. Double-click a tool (or press Enter / F5) to run it.'
        $Script:Ui.ToolAdminNote.Visibility = 'Collapsed'
        Update-RunButton
        return
    }
    $Script:Ui.ToolTitle.Text = $t.Name
    $Script:Ui.ToolMeta.Text  = "$($t.Id)  |  $($t.Category)"
    $Script:Ui.ToolDesc.Text  = $t.Description
    if ($t.Admin) {
        $Script:Ui.ToolAdminNote.Visibility = 'Visible'
        $Script:Ui.ToolAdminNote.Text = if ($Script:IsAdmin) { 'Requires Administrator - you are running as Administrator.' } else { 'Requires Administrator - click "Restart as Administrator" at the top to use this tool.' }
    } else {
        $Script:Ui.ToolAdminNote.Visibility = 'Collapsed'
    }
    Update-RunButton
}

# Right-click menu on the tool list
$Script:ToolMenu = New-Object System.Windows.Controls.ContextMenu
$Script:MenuRun = New-Object System.Windows.Controls.MenuItem
$Script:MenuRun.Header = 'Run'
$Script:MenuRun.InputGestureText = 'Enter'
$Script:MenuRun.Add_Click({ Start-Tool $Script:Ui.ToolList.SelectedItem })
$Script:MenuFav = New-Object System.Windows.Controls.MenuItem
$Script:MenuFav.InputGestureText = 'Ctrl+B'
$Script:MenuFav.Add_Click({ Switch-Favorite $Script:Ui.ToolList.SelectedItem })
[void]$Script:ToolMenu.Items.Add($Script:MenuRun)
[void]$Script:ToolMenu.Items.Add($Script:MenuFav)
$Script:ToolMenu.Add_Opened({
    $t = $Script:Ui.ToolList.SelectedItem
    $Script:MenuRun.IsEnabled = $Script:Ui.RunButton.IsEnabled
    $Script:MenuFav.IsEnabled = [bool]$t
    $Script:MenuFav.Header = if ($t -and $Script:Favorites.Contains($t.Id)) { 'Remove from favorites' } else { 'Add to favorites' }
})
$ui.ToolList.ContextMenu = $Script:ToolMenu

$ui.VersionText.Text = "v$($Script:Info.Version)"
$ui.MachineText.Text = "$env:COMPUTERNAME   |   $env:USERDOMAIN\$env:USERNAME"
$brushConverter = New-Object System.Windows.Media.BrushConverter
if ($Script:IsAdmin) {
    $ui.AdminText.Text = 'ADMINISTRATOR'
    $ui.AdminBadge.Background = $brushConverter.ConvertFromString('#15803D')
    $ui.ElevateButton.Visibility = 'Collapsed'
} else {
    $ui.AdminText.Text = 'STANDARD USER'
    $ui.AdminBadge.Background = $brushConverter.ConvertFromString('#B45309')
}
$Script:Window.Title = "IT Helpdesk Toolkit - $env:COMPUTERNAME"

$consoleScript = Join-Path $Script:Root 'HelpdeskToolkit.ps1'
if (-not (Test-Path $consoleScript)) { $ui.ConsoleButton.Visibility = 'Collapsed' }

$ui.ClearSearchButton.Content = [string][char]0xE711
$ui.QuickAccessList.Add_MouseLeftButtonUp({
    if ($Script:Ui.QuickAccessList.SelectedItem) {
        Start-Tool $Script:Ui.QuickAccessList.SelectedItem
        $Script:Ui.QuickAccessList.SelectedItem = $null
    }
})
$ui.CategoryList.Add_SelectionChanged({
    if (-not $Script:SuppressCategoryEvent) {
        $Script:Ui.SearchBox.Text = ''
        Update-ToolList
    }
})
$ui.FavButton.Add_Click({ Switch-Favorite $Script:Ui.ToolList.SelectedItem })
$ui.SearchBox.Add_TextChanged({
    $has = [bool]$Script:Ui.SearchBox.Text
    $Script:Ui.SearchHint.Visibility = if ($has) { 'Collapsed' } else { 'Visible' }
    $Script:Ui.ClearSearchButton.Visibility = if ($has) { 'Visible' } else { 'Collapsed' }
    Update-ToolList
})
$ui.ClearSearchButton.Add_Click({ $Script:Ui.SearchBox.Text = ''; [void]$Script:Ui.SearchBox.Focus() })
$ui.ToolList.Add_SelectionChanged({ Show-ToolDetails })
$ui.ToolList.Add_MouseDoubleClick({ Start-Tool $Script:Ui.ToolList.SelectedItem })
$ui.ToolList.Add_KeyDown({ if ($_.Key -eq 'Return') { Start-Tool $Script:Ui.ToolList.SelectedItem } })

# Drag-to-reorder favorites
$Script:DraggedItem = $null
$Script:DraggedFromIndex = -1
$ui.ToolList.Add_PreviewMouseLeftButtonDown({
    $cat = $Script:Ui.CategoryList.SelectedItem
    if ($cat -and $cat.Kind -eq 'fav') {
        $Script:DraggedItem = $Script:Ui.ToolList.SelectedItem
        $Script:DraggedFromIndex = $Script:Ui.ToolList.SelectedIndex
    }
})
$ui.ToolList.Add_DragOver({
    $cat = $Script:Ui.CategoryList.SelectedItem
    if ($cat -and $cat.Kind -eq 'fav') {
        $_.Effects = 'Move'
        $_.Handled = $true
    } else {
        $_.Effects = 'None'
    }
})
$ui.ToolList.Add_Drop({
    $cat = $Script:Ui.CategoryList.SelectedItem
    if ($Script:DraggedItem -and $cat -and $cat.Kind -eq 'fav') {
        $dropIndex = $Script:Ui.ToolList.SelectedIndex
        if ($dropIndex -ge 0 -and $dropIndex -ne $Script:DraggedFromIndex) {
            $dragId = $Script:DraggedItem.Id
            if ($Script:Favorites.Contains($dragId)) {
                $Script:Favorites.Remove($dragId)
                $Script:Favorites.Insert($dropIndex, $dragId)
                Save-Settings
                Update-ToolList
            }
        }
    }
    $Script:DraggedItem = $null
    $Script:DraggedFromIndex = -1
    $_.Handled = $true
})
$ui.SearchBox.Add_KeyDown({
    if ($_.Key -eq 'Down' -and $Script:Ui.ToolList.Items.Count) { $Script:Ui.ToolList.SelectedIndex = 0; [void]$Script:Ui.ToolList.Focus() }
    elseif ($_.Key -eq 'Return' -and $Script:Ui.ToolList.Items.Count -eq 1) { $Script:Ui.ToolList.SelectedIndex = 0; Start-Tool $Script:Ui.ToolList.SelectedItem }
    elseif ($_.Key -eq 'Escape' -and $Script:Ui.SearchBox.Text) { $Script:Ui.SearchBox.Text = ''; $_.Handled = $true }
})
$ui.RunButton.Add_Click({ Start-Tool $Script:Ui.ToolList.SelectedItem })
$ui.StopButton.Add_Click({ Stop-Tool })
$ui.ClearButton.Add_Click({ $Script:Para.Inlines.Clear() })
$ui.CopyButton.Add_Click({
    [System.Windows.Clipboard]::SetText((Get-OutputText))
    $Script:Ui.StatusText.Text = 'Output copied to clipboard.'
})
$ui.SaveButton.Add_Click({
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    if (-not (Test-Path $Script:Info.OutDir)) { New-Item -ItemType Directory -Path $Script:Info.OutDir -Force | Out-Null }
    $dlg.InitialDirectory = $Script:Info.OutDir
    $dlg.FileName = '{0}_output_{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss')
    $dlg.Filter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
    if ($dlg.ShowDialog($Script:Window)) {
        [IO.File]::WriteAllText($dlg.FileName, (Get-OutputText), (New-Object System.Text.UTF8Encoding($true)))
        $Script:Ui.StatusText.Text = "Saved $($dlg.FileName)"
    }
})
$ui.FolderButton.Add_Click({
    if (-not (Test-Path $Script:Info.OutDir)) { New-Item -ItemType Directory -Path $Script:Info.OutDir -Force | Out-Null }
    Invoke-Item $Script:Info.OutDir
})
$ui.ConsoleButton.Add_Click({
    Start-Process -FilePath $Script:Exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$consoleScript`""
})
$ui.ThemeButton.Add_Click({
    if ($Script:Theme -eq 'Dark') { Set-Theme 'Light' } else { Set-Theme 'Dark' }
    Save-Settings
})
$ui.ElevateButton.Add_Click({
    if ($Script:Current) {
        if (-not (Show-ConfirmDialog -Message 'A tool is still running. Stop it and restart as Administrator?' -Title 'IT Helpdesk Toolkit')) { return }
        Stop-Tool
    }
    if (Start-Elevated) { $Script:ForceClose = $true; $Script:Window.Close() }
})
$ui.HelpButton.Add_Click({
    $shortcuts = @"
Keyboard Shortcuts
================================

Ctrl+F      Search tools across all categories
Ctrl+B      Add/remove tool from favorites
Ctrl+D      Toggle dark/light theme
Ctrl+E      Open output folder
Enter / F5  Run selected tool
F1          Show this help (Keyboard Shortcuts)
Esc         Clear search box
Ctrl+L      Clear output pane

Tips
================================
- Star your favorite tools to quick-access them at the top
- Search finds tools by name, description, and tool ID
- Background runs keep the window responsive
- Click Stop to cancel long-running operations
- All output is saved to Documents\HelpdeskToolkit
- Right-click any tool to star it
- Use Analytics category to see tool usage statistics
"@
    [System.Windows.MessageBox]::Show($shortcuts, 'Keyboard Shortcuts & Tips', 'OK', 'Information') | Out-Null
})
$Script:Window.Add_PreviewKeyDown({
    $ctrl = [System.Windows.Input.Keyboard]::Modifiers -eq 'Control'
    if ($ctrl -and $_.Key -eq 'F') { [void]$Script:Ui.SearchBox.Focus(); $Script:Ui.SearchBox.SelectAll(); $_.Handled = $true }
    elseif ($ctrl -and $_.Key -eq 'B') { Switch-Favorite $Script:Ui.ToolList.SelectedItem; $_.Handled = $true }
    elseif ($ctrl -and $_.Key -eq 'D') { $Script:Ui.ThemeButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))); $_.Handled = $true }
    elseif ($_.Key -eq 'F1') { $Script:Ui.HelpButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))); $_.Handled = $true }
    elseif ($_.Key -eq 'F5') { Start-Tool $Script:Ui.ToolList.SelectedItem; $_.Handled = $true }
})
$Script:Window.Add_Closing({
    if ($Script:Current -and -not $Script:ForceClose) {
        if (-not (Show-ConfirmDialog -Message 'A tool is still running. Stop it and exit?' -Title 'IT Helpdesk Toolkit')) { $_.Cancel = $true; return }
        Stop-Tool
    }
    $Script:Timer.Stop()
})

Set-Theme (Get-InitialTheme)
Update-FavMarks
# Open on Favorites when there are some, otherwise All tools
Update-CategoryList -SelectKey $(if (@(Get-FavoriteTools).Count) { 'fav' } else { 'all' })
Update-ToolList
Update-FavButton
Add-OutputText "IT Helpdesk Toolkit v$($Script:Info.Version) - $($Script:AllTools.Count) tools loaded." 'Cyan'
Add-OutputText 'Select a tool and press Run (or double-click it). Output from every run stays here until you clear it.' 'DarkGray'
foreach ($e in $Script:Info.Errors) { Add-OutputText "  [!] Module skipped - $e" 'Yellow' }
if (-not $Script:IsAdmin) { Add-OutputText '  [!] Running as a standard user - tools marked "admin" are disabled.' 'Yellow' }

$Script:Timer.Start()
[void]$Script:Window.ShowDialog()

# Clean up only if nothing is still running; otherwise let process exit end the runspace
if (-not $Script:Current) { try { $Script:Runspace.Dispose() } catch { } }

#endregion
