# ps-gui-framework.ps1 (fixed: encoding-safe + responsive layout)
# Run: powershell -ExecutionPolicy Bypass -File .\ps-gui-framework.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Settings
$App = [ordered]@{
  Name          = 'PS GUI Framework'
  Version       = '0.1.1'
  Company       = 'likeBloodMoon'
  LogDir        = Join-Path $env:LOCALAPPDATA 'PSGUIFramework'
  LogFile       = $null
  Theme         = 'Dark' # Dark | Light
  StartCentered = $true

  Window = [ordered]@{
    Width          = 1050
    Height         = 720
    MinWidth       = 900
    MinHeight      = 600
    TopMost        = $false
    ShowInTaskbar  = $true
    Opacity        = 1.0
    StartMaximized = $false
  }

  Async = [ordered]@{ MaxRunspaces = 4 }

  UI = [ordered]@{
    TitleBarHeight = 44
    FontName       = 'Segoe UI'
    FontSize       = 10
  }
}

New-Item -ItemType Directory -Force $App.LogDir | Out-Null
$App.LogFile = Join-Path $App.LogDir ("{0}_{1:yyyy-MM-dd_HH-mm-ss}.log" -f ($App.Name -replace '\s','_'), (Get-Date))
#endregion

#region WinForms/Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
#endregion

#region Native helpers (drag title bar)
if (-not ('Win32.Native' -as [type])) {
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace Win32 {
  public static class Native {
    public const int WM_NCLBUTTONDOWN = 0xA1;
    public const int HTCAPTION = 0x2;

    [DllImport("user32.dll")]
    public static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);
  }
}
"@
}
#endregion

#region Font helpers (safe)
function Get-ValidFontFamilyName {
  param([string]$Preferred = 'Segoe UI')
  try {
    $names = [System.Drawing.FontFamily]::Families | ForEach-Object Name
    if ($names -contains $Preferred) { return $Preferred }
  } catch {}
  return 'Microsoft Sans Serif'
}
$App.UI.FontName = Get-ValidFontFamilyName $App.UI.FontName

function New-Font {
  param(
    [string]$Name,
    [double]$Size,
    [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
  )
  try { return [System.Drawing.Font]::new($Name, [single]$Size, $Style) }
  catch { return [System.Drawing.Font]::new('Microsoft Sans Serif', [single]$Size, $Style) }
}

$font       = New-Font $App.UI.FontName $App.UI.FontSize ([System.Drawing.FontStyle]::Regular)
$headerFont = New-Font $App.UI.FontName ($App.UI.FontSize + 1) ([System.Drawing.FontStyle]::Bold)
$titleFont  = New-Font $App.UI.FontName ($App.UI.FontSize + 3) ([System.Drawing.FontStyle]::Bold)
#endregion

#region Optional modules
# Visual layout designer (separate file to keep this script small)
$designerScript = Join-Path $PSScriptRoot 'layout-designer.ps1'
if (Test-Path -LiteralPath $designerScript) {
  . $designerScript
}
#endregion

#region Thread-safe state + logging
# Always ensure LogQueue exists (prevents null ref in timer)
# ---- create sync first ----
$sync = [hashtable]::Synchronized(@{
  LogQueue = $null
  Form     = $null
  Controls = @{}
  Theme    = $App.Theme
})

# ---- then hard-initialize LogQueue ----
$sync.LogQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()


function Invoke-UI {
  param([Parameter(Mandatory)][scriptblock]$Script)
  $f = $sync.Form
  if (-not $f -or $f.IsDisposed) { return }
  if ($f.InvokeRequired) {
    try { $null = $f.BeginInvoke($Script) } catch {}
  } else { & $Script }
}

function Write-Log {
  param(
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
  )
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
  $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
  try { Add-Content -Path $App.LogFile -Value $line -Encoding UTF8 } catch {}
  $sync.LogQueue.Enqueue([pscustomobject]@{ Timestamp=$ts; Level=$Level; Message=$Message }) | Out-Null
}

function Show-Notify {
  param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$Text,
    [ValidateSet('Info','Warning','Error','Success')][string]$Type = 'Info',
    [int]$TimeoutMs = 3500
  )

  try {
    if (Get-Module -ListAvailable -Name BurntToast) {
      Import-Module BurntToast -ErrorAction Stop | Out-Null
      New-BurntToastNotification -Text @($Title, $Text) | Out-Null
      return
    }
  } catch {}

  Invoke-UI {
    $ni = $sync.Controls.NotifyIcon
    if (-not $ni) { return }
    switch ($Type) {
      'Error'   { $ni.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Error }
      'Warning' { $ni.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning }
      default   { $ni.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info }
    }
    $ni.BalloonTipTitle = $Title
    $ni.BalloonTipText  = $Text
    $ni.ShowBalloonTip($TimeoutMs)
  }
}

function With-ErrorToast {
  param([Parameter(Mandatory)][string]$Context, [Parameter(Mandatory)][scriptblock]$Script)
  try { & $Script }
  catch {
    $msg = "{0}: {1}" -f $Context, $_.Exception.Message
    Write-Log -Level ERROR -Message $msg
    Show-Notify -Title $App.Name -Text $msg -Type Error
  }
}
#endregion

#region Async runspace framework
$pool = [runspacefactory]::CreateRunspacePool(1, $App.Async.MaxRunspaces)
$pool.ApartmentState = 'STA'
$pool.ThreadOptions  = 'ReuseThread'
$pool.Open()

function Start-Async {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][scriptblock]$Script,
    [hashtable]$Arguments = @{},
    [scriptblock]$OnSuccess = $null,
    [scriptblock]$OnError = $null,
    [scriptblock]$OnFinally = $null
  )

  Write-Log -Level DEBUG -Message ("Async start: {0}" -f $Name)
  Invoke-UI { Set-Busy -IsBusy $true -Text ("Working: {0}" -f $Name) }

  $ps = [powershell]::Create()
  $ps.RunspacePool = $pool

  $null = $ps.AddScript({
    param($script, $args)
    & $script @args
  }).AddArgument($Script).AddArgument($Arguments)

  $handle = $ps.BeginInvoke()

  $task = [pscustomobject]@{
    Name      = $Name
    PS        = $ps
    Handle    = $handle
    OnSuccess = $OnSuccess
    OnError   = $OnError
    OnFinally = $OnFinally
  }

  [void]$sync.Controls.Tasks.Add($task)
}

function Complete-AsyncTask {
  param([Parameter(Mandatory)]$Task)

  try {
    $result = $Task.PS.EndInvoke($Task.Handle)
    Write-Log -Level INFO -Message ("Async done: {0}" -f $Task.Name)
    if ($Task.OnSuccess) { Invoke-UI { & $Task.OnSuccess $result } }
  } catch {
    $errMsg = "Async failed: {0}: {1}" -f $Task.Name, $_.Exception.Message
    Write-Log -Level ERROR -Message $errMsg
    if ($Task.OnError) { Invoke-UI { & $Task.OnError $_ } }
    else { Show-Notify -Title $App.Name -Text $errMsg -Type Error }
  } finally {
    try { $Task.PS.Dispose() } catch {}
    if ($Task.OnFinally) { Invoke-UI { & $Task.OnFinally } }

    Invoke-UI {
      if ($sync.Controls.Tasks.Count -eq 0) { Set-Busy -IsBusy $false -Text 'Ready' }
    }
  }
}
#endregion

#region Theme
$Themes = @{
  Dark = @{
    Back        = [System.Drawing.Color]::FromArgb(18,18,20)
    Panel       = [System.Drawing.Color]::FromArgb(24,24,28)
    Card        = [System.Drawing.Color]::FromArgb(30,30,36)
    Text        = [System.Drawing.Color]::FromArgb(230,230,235)
    MutedText   = [System.Drawing.Color]::FromArgb(160,160,170)
    Border      = [System.Drawing.Color]::FromArgb(50,50,60)
    ButtonBack  = [System.Drawing.Color]::FromArgb(38,38,46)
  }
  Light = @{
    Back        = [System.Drawing.Color]::FromArgb(245,246,248)
    Panel       = [System.Drawing.Color]::FromArgb(255,255,255)
    Card        = [System.Drawing.Color]::FromArgb(255,255,255)
    Text        = [System.Drawing.Color]::FromArgb(30,30,35)
    MutedText   = [System.Drawing.Color]::FromArgb(90,90,100)
    Border      = [System.Drawing.Color]::FromArgb(210,210,220)
    ButtonBack  = [System.Drawing.Color]::FromArgb(240,240,244)
  }
}

function Apply-Theme {
  param([ValidateSet('Dark','Light')][string]$Theme)
  $sync.Theme = $Theme
  $t = $Themes[$Theme]

  Invoke-UI {
    $c = $sync.Controls

    $sync.Form.BackColor  = $t.Back
    $c.Root.BackColor     = $t.Back
    $c.TitleBar.BackColor = $t.Panel
    $c.LeftNav.BackColor  = $t.Panel
    $c.MainCard.BackColor = $t.Card
    $c.LogCard.BackColor  = $t.Card
    $c.StatusBar.BackColor= $t.Panel

    $c.TitleLabel.ForeColor   = $t.Text
    $c.SubTitleLabel.ForeColor= $t.MutedText
    $c.NavHeader.ForeColor    = $t.Text
    $c.NavInfo.ForeColor      = $t.MutedText
    $c.MainHeader.ForeColor   = $t.Text
    $c.LogHeader.ForeColor    = $t.Text
    $c.StatusLabel.ForeColor  = $t.MutedText

    foreach ($btn in @($c.BtnTheme,$c.BtnMin,$c.BtnMax,$c.BtnClose,$c.BtnTask1,$c.BtnTask2,$c.BtnOpenLog,$c.BtnClearLog)) {
      if (-not $btn) { continue }
      $btn.BackColor = $t.ButtonBack
      $btn.ForeColor = $t.Text
      $btn.FlatAppearance.BorderColor = $t.Border
    }

    $c.LogListView.BackColor = $t.Card
    $c.LogListView.ForeColor = $t.Text
  }
}
#endregion

#region UI helpers
function New-FlatButton {
  param([string]$Text, [int]$W = 140, [int]$H = 34)
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $Text
  $b.Width = $W
  $b.Height = $H
  $b.Font = $font
  $b.FlatStyle = 'Flat'
  $b.FlatAppearance.BorderSize = 1
  $b.Margin = '0,0,0,10'
  return $b
}

function Set-Busy {
  param([bool]$IsBusy, [string]$Text = 'Ready')
  $sync.Controls.StatusLabel.Text = $Text
  $sync.Controls.Progress.Visible = $IsBusy
}
#endregion

#region UI construction (responsive: Dock/Anchor + TableLayout)
$form = New-Object System.Windows.Forms.Form
$sync.Form = $form
$form.Text = "$($App.Name) $($App.Version)"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = if ($App.StartCentered) { 'CenterScreen' } else { 'Manual' }
$form.ClientSize = New-Object System.Drawing.Size($App.Window.Width, $App.Window.Height)
$form.MinimumSize = New-Object System.Drawing.Size($App.Window.MinWidth, $App.Window.MinHeight)
$form.TopMost = $App.Window.TopMost
$form.ShowInTaskbar = $App.Window.ShowInTaskbar
$form.Opacity = $App.Window.Opacity

# NotifyIcon
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Text = $App.Name
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
$notifyIcon.Visible = $true
$sync.Controls.NotifyIcon = $notifyIcon

$sync.Controls.Tasks = New-Object System.Collections.ArrayList

$form.SuspendLayout()

$root = New-Object System.Windows.Forms.Panel
$root.Dock = 'Fill'
$root.Padding = 10
$sync.Controls.Root = $root
$form.Controls.Add($root)

# Title bar
$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Dock = 'Top'
$titleBar.Height = $App.UI.TitleBarHeight
$titleBar.Padding = '12,8,12,8'
$titleBar.Cursor = 'SizeAll'
$sync.Controls.TitleBar = $titleBar
$root.Controls.Add($titleBar)

# Title area (left)
$titleStack = New-Object System.Windows.Forms.TableLayoutPanel
$titleStack.Dock = 'Left'
$titleStack.AutoSize = $true
$titleStack.RowCount = 2
$titleStack.ColumnCount = 1
$titleStack.Margin = 0
$titleStack.Padding = 0
$titleBar.Controls.Add($titleStack)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = $App.Name
$titleLabel.AutoSize = $true
$titleLabel.Font = $headerFont
$sync.Controls.TitleLabel = $titleLabel
$titleStack.Controls.Add($titleLabel, 0, 0)

$subTitleLabel = New-Object System.Windows.Forms.Label
$subTitleLabel.Text = 'Framework + Async + Logs + Theme'
$subTitleLabel.AutoSize = $true
$subTitleLabel.Font = $font
$sync.Controls.SubTitleLabel = $subTitleLabel
$titleStack.Controls.Add($subTitleLabel, 0, 1)

# Window buttons (right)
$winBtns = New-Object System.Windows.Forms.FlowLayoutPanel
$winBtns.Dock = 'Right'
$winBtns.FlowDirection = 'LeftToRight'
$winBtns.WrapContents = $false
$winBtns.AutoSize = $true
$winBtns.Margin = 0

$btnTheme = New-FlatButton 'Theme' 70 26
$btnTheme.Margin = '0,0,8,0'
$btnMin   = New-FlatButton '-' 40 26
$btnMin.Margin = '0,0,8,0'
$btnMax   = New-FlatButton '[]' 40 26
$btnMax.Margin = '0,0,8,0'
$btnClose = New-FlatButton 'X' 40 26
$btnClose.Margin = 0

$sync.Controls.BtnTheme = $btnTheme
$sync.Controls.BtnMin   = $btnMin
$sync.Controls.BtnMax   = $btnMax
$sync.Controls.BtnClose = $btnClose

$winBtns.Controls.AddRange(@($btnTheme,$btnMin,$btnMax,$btnClose))
$titleBar.Controls.Add($winBtns)

# Main layout: 2 columns (nav + content), 2 rows (content + status)
$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.Padding = '0,10,0,0'
$layout.ColumnCount = 2
$layout.RowCount = 2
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 240)))
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))
$root.Controls.Add($layout)

# Left nav
$leftNav = New-Object System.Windows.Forms.Panel
$leftNav.Dock = 'Fill'
$leftNav.Padding = 14
$sync.Controls.LeftNav = $leftNav
$layout.Controls.Add($leftNav, 0, 0)

$navHeader = New-Object System.Windows.Forms.Label
$navHeader.Text = 'Quick'
$navHeader.AutoSize = $true
$navHeader.Font = $titleFont
$sync.Controls.NavHeader = $navHeader
$leftNav.Controls.Add($navHeader)

$navInfo = New-Object System.Windows.Forms.Label
$navInfo.Text = @"
- Borderless window + drag title bar
- Theme toggle
- Async runspace jobs
- UI-safe updates
- Log to UI + file
- Status + progress
- Notifications
"@
$navInfo.AutoSize = $true
$navInfo.Font = $font
$navInfo.Top = 42
$sync.Controls.NavInfo = $navInfo
$leftNav.Controls.Add($navInfo)

# Right side: split vertically (actions + log)
$right = New-Object System.Windows.Forms.TableLayoutPanel
$right.Dock = 'Fill'
$right.ColumnCount = 1
$right.RowCount = 2
$right.RowStyles.Clear()
# Actions takes remaining space
$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
# Log gets fixed minimum height
$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 320)))
$right.Padding = '10,0,0,0'
$layout.Controls.Add($right, 1, 0)

# Actions card
$mainCard = New-Object System.Windows.Forms.Panel
$mainCard.Dock = 'Fill'
$mainCard.Padding = New-Object System.Windows.Forms.Padding(16,24,16,16)
$sync.Controls.MainCard = $mainCard
$right.Controls.Add($mainCard, 0, 0)

# --- Actions card layout (no clipping) ---
$mainGrid = New-Object System.Windows.Forms.TableLayoutPanel
$mainGrid.Dock = 'Fill'
$mainGrid.ColumnCount = 1
$mainGrid.RowCount = 2
$mainGrid.Padding = New-Object System.Windows.Forms.Padding(0)
$mainGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$mainGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$mainCard.Controls.Add($mainGrid)

$mainHeader = New-Object System.Windows.Forms.Label
$mainHeader.Text = 'Actions'
$mainHeader.AutoSize = $true
$mainHeader.Font = $titleFont
$mainHeader.Margin = New-Object System.Windows.Forms.Padding(0,0,0,10)
$sync.Controls.MainHeader = $mainHeader
$mainGrid.Controls.Add($mainHeader, 0, 0)

$actions = New-Object System.Windows.Forms.FlowLayoutPanel
$actions.Dock = 'Top'
$actions.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$actions.WrapContents = $false
$actions.AutoSize = $true
$actions.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$actions.Margin  = New-Object System.Windows.Forms.Padding(0)
$actions.Padding = New-Object System.Windows.Forms.Padding(0)
$mainGrid.Controls.Add($actions, 0, 1)

# Buttons (taller to avoid clipping on DPI)
$btnTask1   = New-FlatButton 'Run sample task (slow)'  360 42
$btnTask2   = New-FlatButton 'Run sample task (error)' 360 42
$btnDesigner= New-FlatButton 'Open layout designer'    360 42
$btnOpenLog = New-FlatButton 'Open log file'           360 42
$btnOpenLog.Margin = New-Object System.Windows.Forms.Padding(0)

$sync.Controls.BtnTask1   = $btnTask1
$sync.Controls.BtnTask2   = $btnTask2
$sync.Controls.BtnDesigner= $btnDesigner
$sync.Controls.BtnOpenLog = $btnOpenLog

$actions.Controls.AddRange(@($btnTask1,$btnTask2,$btnDesigner,$btnOpenLog))

# Log card
$logCard = New-Object System.Windows.Forms.Panel
$logCard.Dock = 'Fill'
$logCard.Padding = New-Object System.Windows.Forms.Padding(16)
$sync.Controls.LogCard = $logCard
$right.Controls.Add($logCard, 0, 1)

# --- Log card layout (no clipping) ---
$logGrid = New-Object System.Windows.Forms.TableLayoutPanel
$logGrid.Dock = 'Fill'
$logGrid.ColumnCount = 1
$logGrid.RowCount = 2
$logGrid.Padding = New-Object System.Windows.Forms.Padding(0)
$logGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$logGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$logCard.Controls.Add($logGrid)

$logHeaderRow = New-Object System.Windows.Forms.TableLayoutPanel
$logHeaderRow.Dock = 'Top'
$logHeaderRow.AutoSize = $true
$logHeaderRow.ColumnCount = 2
$logHeaderRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$logHeaderRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 90)))
$logHeaderRow.Margin = New-Object System.Windows.Forms.Padding(0,0,0,10)
$logGrid.Controls.Add($logHeaderRow, 0, 0)

$logHeader = New-Object System.Windows.Forms.Label
$logHeader.Text = 'Log'
$logHeader.AutoSize = $true
$logHeader.Font = $titleFont
$sync.Controls.LogHeader = $logHeader
$logHeaderRow.Controls.Add($logHeader, 0, 0)

$btnClearLog = New-FlatButton 'Clear' 80 30
$btnClearLog.Margin = New-Object System.Windows.Forms.Padding(0)
$sync.Controls.BtnClearLog = $btnClearLog
$logHeaderRow.Controls.Add($btnClearLog, 1, 0)

$logList = New-Object System.Windows.Forms.ListView
$logList.Dock = 'Fill'
$logList.View = 'Details'
$logList.FullRowSelect = $true
$logList.HideSelection = $false
$logList.Font = $font
$logList.Margin = New-Object System.Windows.Forms.Padding(0)
$logList.Columns.Add('Time', 180) | Out-Null
$logList.Columns.Add('Level', 70)  | Out-Null
$logList.Columns.Add('Message', 1200) | Out-Null
$sync.Controls.LogListView = $logList
$logGrid.Controls.Add($logList, 0, 1)

# Status bar (bottom row)
$statusBar = New-Object System.Windows.Forms.Panel
$statusBar.Dock = 'Fill'
$statusBar.Padding = '12,10,12,10'
$sync.Controls.StatusBar = $statusBar
$layout.Controls.Add($statusBar, 0, 1)
$layout.SetColumnSpan($statusBar, 2)

$statusRow = New-Object System.Windows.Forms.TableLayoutPanel
$statusRow.Dock = 'Fill'
$statusRow.ColumnCount = 2
$statusRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$statusRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 220)))
$statusBar.Controls.Add($statusRow)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = 'Ready'
$statusLabel.AutoSize = $true
$statusLabel.Font = $font
$sync.Controls.StatusLabel = $statusLabel
$statusRow.Controls.Add($statusLabel, 0, 0)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Dock = 'Fill'
$progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 30
$progress.Visible = $false
$sync.Controls.Progress = $progress
$statusRow.Controls.Add($progress, 1, 0)

$form.ResumeLayout($true)
#endregion

#region Timers (log + task pump)
$logTimer = New-Object System.Windows.Forms.Timer
$logTimer.Interval = 150
$logTimer.Add_Tick({
  try {
    if (-not $sync -or -not $sync.LogQueue) {
      # recover if something cleared it
      $sync.LogQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
      return
    }

    for ($i=0; $i -lt 80; $i++) {
      $item = $null
      if (-not $sync.LogQueue.TryDequeue([ref]$item)) { break }
      if (-not $item) { continue }

      $lv = $sync.Controls.LogListView
      if ($lv -and -not $lv.IsDisposed) {
        $lvi = New-Object System.Windows.Forms.ListViewItem([string]$item.Timestamp)
        $null = $lvi.SubItems.Add([string]$item.Level)
        $null = $lvi.SubItems.Add([string]$item.Message)
        $null = $lv.Items.Add($lvi)
        $lv.EnsureVisible($lv.Items.Count - 1) | Out-Null
      }
    }
  } catch {
    # don't let the timer die
  }
})


$taskTimer = New-Object System.Windows.Forms.Timer
$taskTimer.Interval = 120
$taskTimer.Add_Tick({
  $tasks = @($sync.Controls.Tasks)
  foreach ($t in $tasks) {
    if ($t.Handle -and $t.Handle.IsCompleted) {
      [void]$sync.Controls.Tasks.Remove($t)
      Complete-AsyncTask -Task $t
    }
  }
})
#endregion

#region Behavior + actions
$titleDrag = {
  try {
    [Win32.Native]::ReleaseCapture() | Out-Null
    [Win32.Native]::SendMessage($form.Handle, [Win32.Native]::WM_NCLBUTTONDOWN, [Win32.Native]::HTCAPTION, 0) | Out-Null
  } catch {}
}
$sync.Controls.TitleBar.Add_MouseDown($titleDrag)
$sync.Controls.TitleLabel.Add_MouseDown($titleDrag)
$sync.Controls.SubTitleLabel.Add_MouseDown($titleDrag)

$sync.Controls.BtnMin.Add_Click({ $form.WindowState = 'Minimized' })
$sync.Controls.BtnMax.Add_Click({
  if ($form.WindowState -eq 'Maximized') { $form.WindowState = 'Normal' }
  else { $form.WindowState = 'Maximized' }
})
$sync.Controls.BtnClose.Add_Click({ $form.Close() })

$sync.Controls.BtnTheme.Add_Click({
  $new = if ($sync.Theme -eq 'Dark') { 'Light' } else { 'Dark' }
  Apply-Theme -Theme $new
  Write-Log -Level INFO -Message ("Theme switched to {0}" -f $new)
})

$sync.Controls.BtnClearLog.Add_Click({
  $sync.Controls.LogListView.Items.Clear()
  Write-Log -Level INFO -Message 'Log cleared (UI only).'
})

$sync.Controls.BtnOpenLog.Add_Click({
  With-ErrorToast -Context 'Open log file' -Script { Start-Process -FilePath $App.LogFile }
})

$sync.Controls.BtnTask1.Add_Click({
  Start-Async -Name 'Sample slow task' -Script {
    Start-Sleep -Seconds 2
    $ip = [System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
  Where-Object {
    $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
    $_.ToString() -notlike '169.254*'
  } |
  Select-Object -First 1 -ExpandProperty IPAddressToString

    if (-not $ip) { $ip = 'Unknown' }
    [pscustomobject]@{ IPv4 = $ip; Time = (Get-Date) }
  } -OnSuccess {
    param($result)
    Write-Log -Level INFO -Message ("Slow task result: IPv4={0}" -f $result.IPv4)
    Show-Notify -Title $App.Name -Text ("Done. IPv4: {0}" -f $result.IPv4) -Type Success
  }
})

$sync.Controls.BtnTask2.Add_Click({
  Start-Async -Name 'Sample error task' -Script {
    Start-Sleep -Milliseconds 300
    throw "This is a sample exception."
  }
})

$sync.Controls.BtnDesigner.Add_Click({
  if (-not (Get-Command -Name Start-GuiLayoutDesigner -ErrorAction SilentlyContinue)) {
    Show-Notify -Title $App.Name -Text "Missing layout designer: $designerScript" -Type Error
    return
  }
  Start-GuiLayoutDesigner -LayoutPath (Join-Path $PSScriptRoot 'layout.json') -DefaultFont $font
})
#endregion

#region Startup/shutdown
$form.Add_Shown({
  Apply-Theme -Theme $sync.Theme
  Write-Log -Level INFO -Message ("{0} started. Log: {1}" -f $App.Name, $App.LogFile)
  Show-Notify -Title $App.Name -Text 'Ready.' -Type Info

  if ($App.Window.StartMaximized) { $form.WindowState = 'Maximized' }

  $logTimer.Start()
  $taskTimer.Start()
})

$form.Add_FormClosing({
  try { $logTimer.Stop(); $taskTimer.Stop() } catch {}
  try { $notifyIcon.Visible = $false; $notifyIcon.Dispose() } catch {}
  try { $pool.Close(); $pool.Dispose() } catch {}
})

[void]$form.ShowDialog()
#endregion
