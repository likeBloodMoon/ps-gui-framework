Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Convert-FontToDto {
  param([System.Drawing.Font]$Font)
  if (-not $Font) { return $null }
  [ordered]@{ Name=$Font.Name; Size=[double]$Font.Size; Style=[string]$Font.Style }
}

function Convert-FontFromDto {
  param([hashtable]$Dto)
  if (-not $Dto) { return $null }
  $style = [System.Drawing.FontStyle]::Regular
  try { $style = [System.Drawing.FontStyle]::Parse([System.Drawing.FontStyle], [string]$Dto.Style) } catch {}
  try { return [System.Drawing.Font]::new([string]$Dto.Name, [single]([double]$Dto.Size), $style) } catch { return $null }
}

function Convert-PaddingToDto {
  param([System.Windows.Forms.Padding]$Padding)
  if (-not $Padding) { return $null }
  [ordered]@{ L=$Padding.Left; T=$Padding.Top; R=$Padding.Right; B=$Padding.Bottom }
}

function Convert-PaddingFromDto {
  param([hashtable]$Dto)
  if (-not $Dto) { return $null }
  [System.Windows.Forms.Padding]::new([int]$Dto.L,[int]$Dto.T,[int]$Dto.R,[int]$Dto.B)
}

function Convert-AnchorToDto {
  param([System.Windows.Forms.AnchorStyles]$Anchor)
  $out = @()
  foreach ($n in 'Top','Bottom','Left','Right') {
    if (($Anchor -band ([System.Windows.Forms.AnchorStyles]::$n)) -ne 0) { $out += $n }
  }
  $out
}

function Convert-AnchorFromDto {
  param([object]$Dto)
  $a = [System.Windows.Forms.AnchorStyles]::None
  foreach ($n in @($Dto)) {
    try { $a = $a -bor ([System.Windows.Forms.AnchorStyles]::$n) } catch {}
  }
  if ($a -eq [System.Windows.Forms.AnchorStyles]::None) {
    $a = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
  }
  $a
}

function Set-CursorForResizeDir {
  param(
    [Parameter(Mandatory)][string]$Dir,
    [Parameter(Mandatory)][System.Windows.Forms.Control]$Control
  )
  switch ($Dir) {
    'N'  { $Control.Cursor = [System.Windows.Forms.Cursors]::SizeNS }
    'S'  { $Control.Cursor = [System.Windows.Forms.Cursors]::SizeNS }
    'E'  { $Control.Cursor = [System.Windows.Forms.Cursors]::SizeWE }
    'W'  { $Control.Cursor = [System.Windows.Forms.Cursors]::SizeWE }
    'NE' { $Control.Cursor = [System.Windows.Forms.Cursors]::SizeNESW }
    'SW' { $Control.Cursor = [System.Windows.Forms.Cursors]::SizeNESW }
    'NW' { $Control.Cursor = [System.Windows.Forms.Cursors]::SizeNWSE }
    'SE' { $Control.Cursor = [System.Windows.Forms.Cursors]::SizeNWSE }
    default { $Control.Cursor = [System.Windows.Forms.Cursors]::Default }
  }
}

function New-ControlFromType {
  param([Parameter(Mandatory)][string]$Type)
  switch ($Type) {
    'Panel'   { [System.Windows.Forms.Panel]::new() }
    'GroupBox'{ [System.Windows.Forms.GroupBox]::new() }
    'Label'   { [System.Windows.Forms.Label]::new() }
    'Button'  { [System.Windows.Forms.Button]::new() }
    'TextBox' { [System.Windows.Forms.TextBox]::new() }
    'CheckBox'{ [System.Windows.Forms.CheckBox]::new() }
    'ComboBox'{
      $c = [System.Windows.Forms.ComboBox]::new()
      $c.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
      [void]$c.Items.AddRange(@('Option 1','Option 2','Option 3'))
      $c.SelectedIndex = 0
      $c
    }
    default { throw "Unsupported control type '$Type'." }
  }
}

function Convert-ControlToNode {
  param([Parameter(Mandatory)][System.Windows.Forms.Control]$Control)
  $node = [ordered]@{
    Type   = $Control.GetType().Name
    Name   = [string]$Control.Name
    Text   = [string]$Control.Text
    Bounds = [ordered]@{ X=$Control.Left; Y=$Control.Top; W=$Control.Width; H=$Control.Height }
    Dock   = [string]$Control.Dock
    Anchor = (Convert-AnchorToDto -Anchor $Control.Anchor)
    Padding= (Convert-PaddingToDto -Padding $Control.Padding)
    Font   = (Convert-FontToDto -Font $Control.Font)
    Children = @()
  }
  foreach ($child in $Control.Controls) {
    if ($child -is [System.Windows.Forms.Control]) { $node.Children += (Convert-ControlToNode -Control $child) }
  }
  $node
}

function Apply-NodeToControl {
  param(
    [Parameter(Mandatory)][hashtable]$Node,
    [Parameter(Mandatory)][System.Windows.Forms.Control]$Control
  )
  if ($Node.ContainsKey('Name') -and $Node['Name']) { $Control.Name = [string]$Node['Name'] }
  if ($Node.ContainsKey('Text')) { $Control.Text = [string]$Node['Text'] }

  if ($Node.ContainsKey('Bounds') -and $Node['Bounds']) {
    $b = $Node['Bounds']
    $Control.SetBounds([int]$b['X'],[int]$b['Y'],[int]$b['W'],[int]$b['H'])
  }

  if ($Node.ContainsKey('Dock') -and $Node['Dock']) {
    try { $Control.Dock = [System.Windows.Forms.DockStyle]::$([string]$Node['Dock']) } catch {}
  }

  if ($Node.ContainsKey('Anchor') -and $Node['Anchor']) {
    $Control.Anchor = Convert-AnchorFromDto -Dto $Node['Anchor']
  }

  if ($Node.ContainsKey('Padding') -and $Node['Padding']) {
    $Control.Padding = Convert-PaddingFromDto -Dto $Node['Padding']
  }

  if ($Node.ContainsKey('Font') -and $Node['Font']) {
    $f = Convert-FontFromDto -Dto $Node['Font']
    if ($f) { $Control.Font = $f }
  }
}

function Convert-JsonToHashtable {
  param([Parameter(Mandatory)][string]$Json)
  function ConvertTo-DeepHashtable {
    param([Parameter(Mandatory)]$InputObject)

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [string] -or $InputObject -is [ValueType]) {
      return $InputObject
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
      $h = [ordered]@{}
      foreach ($k in $InputObject.Keys) {
        $h[$k] = ConvertTo-DeepHashtable -InputObject $InputObject[$k]
      }
      return $h
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
      $list = @()
      foreach ($item in $InputObject) {
        $list += (ConvertTo-DeepHashtable -InputObject $item)
      }
      return ,$list
    }

    # PSCustomObject / PSObject
    $props = $InputObject.PSObject.Properties
    if ($props) {
      $h = [ordered]@{}
      foreach ($p in $props) {
        $h[$p.Name] = ConvertTo-DeepHashtable -InputObject $p.Value
      }
      return $h
    }

    return $InputObject
  }

  $obj = $Json | ConvertFrom-Json
  ConvertTo-DeepHashtable -InputObject $obj
}

function Save-LayoutToJson {
  param(
    [Parameter(Mandatory)][System.Windows.Forms.Control]$Canvas,
    [Parameter(Mandatory)][string]$Path
  )
  $layout = [ordered]@{
    SchemaVersion = 1
    CanvasSize = [ordered]@{ W=$Canvas.Width; H=$Canvas.Height }
    Children = @()
  }
  foreach ($c in $Canvas.Controls) { $layout.Children += (Convert-ControlToNode -Control $c) }
  Set-Content -Path $Path -Value ($layout | ConvertTo-Json -Depth 50) -Encoding UTF8
}

function Load-LayoutFromJson {
  param(
    [Parameter(Mandatory)][System.Windows.Forms.Control]$Canvas,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][scriptblock]$AttachSelectable
  )
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  $layout = Convert-JsonToHashtable -Json (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
  $Canvas.Controls.Clear()
  if ($layout.CanvasSize) {
    $Canvas.Size = [System.Drawing.Size]::new([int]$layout.CanvasSize.W,[int]$layout.CanvasSize.H)
  }
  foreach ($n in @($layout.Children)) {
    $c = New-ControlFromType -Type ([string]$n.Type)
    Apply-NodeToControl -Node $n -Control $c
    $Canvas.Controls.Add($c) | Out-Null
    & $AttachSelectable $c
    if ($n.Children -and $n.Children.Count -gt 0) {
      Add-ChildNodes -Parent $c -Nodes $n.Children -AttachSelectable $AttachSelectable
    }
  }
  $true
}

function Convert-XamlToLayout {
  param([Parameter(Mandatory)][string]$XamlText)

  try { [xml]$xml = $XamlText } catch { throw "Invalid XAML: $($_.Exception.Message)" }

  $window = $xml.DocumentElement
  $w = $null
  $h = $null
  if ($window -and $window.Attributes) {
    $wAttr = $window.Attributes['Width']
    $hAttr = $window.Attributes['Height']
    if ($wAttr) { [void][double]::TryParse($wAttr.Value, [ref]$w) }
    if ($hAttr) { [void][double]::TryParse($hAttr.Value, [ref]$h) }
  }

  $canvasNode = $xml.SelectSingleNode("//*[local-name()='Canvas']")
  if (-not $canvasNode) { throw "XAML must contain a Canvas element." }

  function Get-AttrValueLocal {
    param([System.Xml.XmlElement]$Element, [string]$Name)
    if (-not $Element -or -not $Element.Attributes) { return $null }
    $a = $Element.Attributes[$Name]
    if ($a) { return $a.Value }
    $a = $Element.Attributes | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($a) { return $a.Value }
    return $null
  }

  function Get-XNameLocal {
    param([System.Xml.XmlElement]$Element)
    if (-not $Element -or -not $Element.Attributes) { return $null }
    $a = $Element.Attributes | Where-Object { $_.LocalName -eq 'Name' } | Select-Object -First 1
    if ($a) { return $a.Value }
    return $null
  }

  $layout = [ordered]@{
    SchemaVersion = 1
    CanvasSize = [ordered]@{
      W = if ($w) { [int][Math]::Round($w) } else { 1200 }
      H = if ($h) { [int][Math]::Round($h) } else { 800 }
    }
    Children = @()
  }

  foreach ($child in @($canvasNode.ChildNodes)) {
    if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
    $el = [System.Xml.XmlElement]$child
    $type = $el.LocalName

    $x = 0; $y = 0; $cw = 140; $ch = 40
    $left = Get-AttrValueLocal -Element $el -Name 'Canvas.Left'
    $top  = Get-AttrValueLocal -Element $el -Name 'Canvas.Top'
    $ww   = Get-AttrValueLocal -Element $el -Name 'Width'
    $hh   = Get-AttrValueLocal -Element $el -Name 'Height'
    if ($left) { [void][int]::TryParse($left, [ref]$x) }
    if ($top)  { [void][int]::TryParse($top, [ref]$y) }
    if ($ww)   { [void][int]::TryParse($ww, [ref]$cw) }
    if ($hh)   { [void][int]::TryParse($hh, [ref]$ch) }

    $name = Get-XNameLocal -Element $el
    $text = ''
    switch ($type) {
      'Button'   { $text = [string](Get-AttrValueLocal -Element $el -Name 'Content') }
      'TextBlock'{ $text = [string](Get-AttrValueLocal -Element $el -Name 'Text') }
      'TextBox'  { $text = [string](Get-AttrValueLocal -Element $el -Name 'Text') }
      'CheckBox' { $text = [string](Get-AttrValueLocal -Element $el -Name 'Content') }
      'GroupBox' { $text = [string](Get-AttrValueLocal -Element $el -Name 'Header') }
      default    { $text = '' }
    }

    $mapped = switch ($type) {
      'Button'    { 'Button' }
      'TextBlock' { 'Label' }
      'TextBox'   { 'TextBox' }
      'Border'    { 'Panel' }
      'GroupBox'  { 'GroupBox' }
      'CheckBox'  { 'CheckBox' }
      'ComboBox'  { 'ComboBox' }
      default     { $null }
    }
    if (-not $mapped) { continue }

    $layout.Children += [ordered]@{
      Type   = $mapped
      Name   = $name
      Text   = $text
      Bounds = [ordered]@{ X=$x; Y=$y; W=$cw; H=$ch }
      Dock   = 'None'
      Anchor = @('Top','Left')
      Padding= [ordered]@{ L=0; T=0; R=0; B=0 }
      Children = @()
    }
  }

  return $layout
}

function Load-LayoutFromXaml {
  param(
    [Parameter(Mandatory)][System.Windows.Forms.Control]$Canvas,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][scriptblock]$AttachSelectable
  )

  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  $xamlText = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  $layout = Convert-XamlToLayout -XamlText $xamlText

  $Canvas.Controls.Clear()
  if ($layout.CanvasSize) {
    $Canvas.Size = [System.Drawing.Size]::new([int]$layout.CanvasSize.W,[int]$layout.CanvasSize.H)
  }

  foreach ($n in @($layout.Children)) {
    $c = New-ControlFromType -Type ([string]$n.Type)
    Apply-NodeToControl -Node $n -Control $c
    $Canvas.Controls.Add($c) | Out-Null
    & $AttachSelectable $c
  }
  return $true
}

function Add-ChildNodes {
  param(
    [Parameter(Mandatory)][System.Windows.Forms.Control]$Parent,
    [Parameter(Mandatory)][object[]]$Nodes,
    [Parameter(Mandatory)][scriptblock]$AttachSelectable
  )
  foreach ($n in @($Nodes)) {
    $c = New-ControlFromType -Type ([string]$n.Type)
    Apply-NodeToControl -Node $n -Control $c
    $Parent.Controls.Add($c) | Out-Null
    & $AttachSelectable $c
    if ($n.Children -and $n.Children.Count -gt 0) {
      Add-ChildNodes -Parent $c -Nodes $n.Children -AttachSelectable $AttachSelectable
    }
  }
}

function Generate-WinFormsPs1 {
  param([Parameter(Mandatory)][hashtable]$Layout)
  $sb = [System.Text.StringBuilder]::new()
  $null = $sb.AppendLine("Set-StrictMode -Version Latest")
  $null = $sb.AppendLine("$ErrorActionPreference = 'Stop'")
  $null = $sb.AppendLine("Add-Type -AssemblyName System.Windows.Forms")
  $null = $sb.AppendLine("Add-Type -AssemblyName System.Drawing")
  $null = $sb.AppendLine("[System.Windows.Forms.Application]::EnableVisualStyles()")
  $null = $sb.AppendLine()
  $null = $sb.AppendLine('$form = New-Object System.Windows.Forms.Form')
  if ($Layout.CanvasSize) {
    $null = $sb.AppendLine(('$form.ClientSize = New-Object System.Drawing.Size({0},{1})' -f ([int]$Layout.CanvasSize.W),([int]$Layout.CanvasSize.H)))
  }
  $null = $sb.AppendLine()

  $counter = 0
  function EmitLocal {
    param([hashtable]$Node,[string]$ParentVar,[int]$Indent=0)
    $counter++
    $pad = ('  ' * $Indent)
    $type = [string]$Node.Type
    $name = if ($Node.Name) { [string]$Node.Name } else { ($type.ToLowerInvariant() + $counter) }
    $var = ('$' + ($name -replace '[^a-zA-Z0-9_]', '_'))
    $null = $sb.AppendLine("$pad$var = New-Object System.Windows.Forms.$type")
    if ($Node.Name) {
      $safe = ([string]$Node.Name) -replace "'","''"
      $null = $sb.AppendLine("$pad$var.Name = '$safe'")
    }
    if ($Node.ContainsKey('Text')) {
      $safe = ([string]$Node.Text) -replace "'","''"
      $null = $sb.AppendLine("$pad$var.Text = '$safe'")
    }
    if ($Node.Bounds) {
      $null = $sb.AppendLine("$pad$var.Location = New-Object System.Drawing.Point($([int]$Node.Bounds.X),$([int]$Node.Bounds.Y))")
      $null = $sb.AppendLine("$pad$var.Size = New-Object System.Drawing.Size($([int]$Node.Bounds.W),$([int]$Node.Bounds.H))")
    }
    if ($Node.Dock -and $Node.Dock -ne 'None') { $null = $sb.AppendLine("$pad$var.Dock = '$([string]$Node.Dock)'") }
    if ($Node.Anchor) { $null = $sb.AppendLine("$pad$var.Anchor = '$(@($Node.Anchor) -join ',')'") }
    if ($Node.Padding) { $null = $sb.AppendLine("$pad$var.Padding = New-Object System.Windows.Forms.Padding($([int]$Node.Padding.L),$([int]$Node.Padding.T),$([int]$Node.Padding.R),$([int]$Node.Padding.B))") }
    if ($Node.Font) {
      $null = $sb.AppendLine("$pad$var.Font = New-Object System.Drawing.Font('$([string]$Node.Font.Name)', [single]$([double]$Node.Font.Size), [System.Drawing.FontStyle]::$([string]$Node.Font.Style))")
    }
    $null = $sb.AppendLine("$pad$ParentVar.Controls.Add($var) | Out-Null")
    foreach ($ch in @($Node.Children)) { EmitLocal -Node $ch -ParentVar $var -Indent ($Indent+1) }
  }

  foreach ($n in @($Layout.Children)) { EmitLocal -Node $n -ParentVar '$form' -Indent 0 }
  $null = $sb.AppendLine('[void]$form.ShowDialog()')
  $sb.ToString()
}

function Generate-WpfXaml {
  param([Parameter(Mandatory)][hashtable]$Layout)
  $w = 900; $h = 600
  if ($Layout.CanvasSize) { $w=[int]$Layout.CanvasSize.W; $h=[int]$Layout.CanvasSize.H }

  function XEsc([string]$s) {
    if ($null -eq $s) { return '' }
    $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'",'&apos;'
  }

  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($n in @($Layout.Children)) {
    $x=0;$y=0;$cw=100;$ch=30
    if ($n.Bounds) { $x=[int]$n.Bounds.X; $y=[int]$n.Bounds.Y; $cw=[int]$n.Bounds.W; $ch=[int]$n.Bounds.H }
    $nameAttr = if ($n.Name) { " x:Name=""$([string]$n.Name)""" } else { '' }
    $text = XEsc ([string]$n.Text)
    switch ([string]$n.Type) {
      'Button' { $lines.Add("    <Button$nameAttr Content=""$text"" Canvas.Left=""$x"" Canvas.Top=""$y"" Width=""$cw"" Height=""$ch"" />") | Out-Null }
      'Label'  { $lines.Add("    <TextBlock$nameAttr Text=""$text"" Canvas.Left=""$x"" Canvas.Top=""$y"" Width=""$cw"" Height=""$ch"" />") | Out-Null }
      'TextBox'{ $lines.Add("    <TextBox$nameAttr Text=""$text"" Canvas.Left=""$x"" Canvas.Top=""$y"" Width=""$cw"" Height=""$ch"" />") | Out-Null }
      'Panel'  { $lines.Add("    <Border$nameAttr BorderBrush=""#66000000"" BorderThickness=""1"" Canvas.Left=""$x"" Canvas.Top=""$y"" Width=""$cw"" Height=""$ch"" />") | Out-Null }
      'GroupBox' { $lines.Add("    <GroupBox$nameAttr Header=""$text"" Canvas.Left=""$x"" Canvas.Top=""$y"" Width=""$cw"" Height=""$ch"" />") | Out-Null }
      'CheckBox' { $lines.Add("    <CheckBox$nameAttr Content=""$text"" Canvas.Left=""$x"" Canvas.Top=""$y"" Width=""$cw"" Height=""$ch"" />") | Out-Null }
      'ComboBox' { $lines.Add("    <ComboBox$nameAttr Canvas.Left=""$x"" Canvas.Top=""$y"" Width=""$cw"" Height=""$ch"" />") | Out-Null }
      default  { $lines.Add("    <!-- Unsupported: $([string]$n.Type) -->") | Out-Null }
    }
  }

  (@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Layout" Width="$w" Height="$h">
  <Canvas>
$($lines -join "`n")
  </Canvas>
</Window>
"@)
}

function Start-GuiLayoutDesigner {
  param(
    [string]$LayoutPath = (Join-Path $PSScriptRoot 'layout.json'),
    [System.Drawing.Font]$DefaultFont = ([System.Drawing.SystemFonts]::MessageBoxFont)
  )

  $themes = @{
    Dark = @{ Back=[System.Drawing.Color]::FromArgb(18,18,20); Panel=[System.Drawing.Color]::FromArgb(24,24,28); Canvas=[System.Drawing.Color]::FromArgb(35,35,40); Text=[System.Drawing.Color]::FromArgb(235,235,240) }
    Light = @{ Back=[System.Drawing.Color]::FromArgb(245,246,248); Panel=[System.Drawing.Color]::FromArgb(255,255,255); Canvas=[System.Drawing.Color]::FromArgb(255,255,255); Text=[System.Drawing.Color]::FromArgb(25,25,30) }
    Blue = @{ Back=[System.Drawing.Color]::FromArgb(18,27,44); Panel=[System.Drawing.Color]::FromArgb(25,40,70); Canvas=[System.Drawing.Color]::FromArgb(235,242,255); Text=[System.Drawing.Color]::FromArgb(235,235,240) }
  }

  $f = [System.Windows.Forms.Form]::new()
  $f.Text = 'PS Layout Designer'
  $f.StartPosition = 'CenterScreen'
  $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
  $f.Width = 1500
  $f.Height = 920
  $f.MinimumSize = [System.Drawing.Size]::new(1200, 760)
  $f.KeyPreview = $true

  $root = [System.Windows.Forms.TableLayoutPanel]::new()
  $root.Dock = 'Fill'
  $root.ColumnCount = 1
  $root.RowCount = 3
  $root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
  $root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
  $root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
  $f.Controls.Add($root)

  $headerFont = [System.Drawing.Font]::new($DefaultFont.FontFamily, [single]($DefaultFont.Size + 1), [System.Drawing.FontStyle]::Bold)

  $tool = [System.Windows.Forms.ToolStrip]::new()
  $tool.Dock = 'Fill'
  $tool.GripStyle = 'Hidden'
  $tool.Font = $DefaultFont
  $tool.Padding = New-Object System.Windows.Forms.Padding(6,4,6,4)
  $root.Controls.Add($tool, 0, 0)

  $btnDesign = [System.Windows.Forms.ToolStripButton]::new('Design mode')
  $btnDesign.CheckOnClick = $true
  $btnDesign.Checked = $true
  $tool.Items.Add($btnDesign) | Out-Null
  $tool.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null

  $btnOpen = [System.Windows.Forms.ToolStripButton]::new('Open')
  $btnSave = [System.Windows.Forms.ToolStripButton]::new('Save')
  $tool.Items.AddRange(@($btnOpen,$btnSave)) | Out-Null
  $tool.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null

  $btnExportPs1 = [System.Windows.Forms.ToolStripButton]::new('Export .ps1')
  $btnExportXaml = [System.Windows.Forms.ToolStripButton]::new('Export .xaml')
  $tool.Items.AddRange(@($btnExportPs1,$btnExportXaml)) | Out-Null
  $tool.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null

  $examplesDrop = [System.Windows.Forms.ToolStripDropDownButton]::new('Examples')
  $tool.Items.Add($examplesDrop) | Out-Null
  $tool.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null

  $tool.Items.Add([System.Windows.Forms.ToolStripLabel]::new('Theme')) | Out-Null
  $cmbTheme = [System.Windows.Forms.ToolStripComboBox]::new()
  $cmbTheme.DropDownStyle = 'DropDownList'
  [void]$cmbTheme.Items.AddRange(@('Dark','Light','Blue'))
  $cmbTheme.SelectedIndex = 0
  $tool.Items.Add($cmbTheme) | Out-Null

  $status = [System.Windows.Forms.StatusStrip]::new()
  $status.SizingGrip = $false
  $statusLbl = [System.Windows.Forms.ToolStripStatusLabel]::new("Layout: $LayoutPath")
  $statusLbl.Spring = $true
  $status.Items.Add($statusLbl) | Out-Null
  $root.Controls.Add($status, 0, 2)

  $outer = [System.Windows.Forms.SplitContainer]::new()
  $outer.Dock = 'Fill'
  $outer.Orientation = [System.Windows.Forms.Orientation]::Vertical
  $outer.SplitterWidth = 6
  # Min sizes + splitter distance are set on Shown (SplitContainer.Width can be 0 during construction).
  $root.Controls.Add($outer, 0, 1)

  $toolboxHost = [System.Windows.Forms.Panel]::new()
  $toolboxHost.Dock = 'Fill'
  $toolboxHost.Padding = New-Object System.Windows.Forms.Padding(12)
  $outer.Panel1.Controls.Add($toolboxHost)

  $toolboxLayout = [System.Windows.Forms.TableLayoutPanel]::new()
  $toolboxLayout.Dock = 'Fill'
  $toolboxLayout.ColumnCount = 1
  $toolboxLayout.RowCount = 3
  $toolboxLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
  $toolboxLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
  $toolboxLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
  $toolboxHost.Controls.Add($toolboxLayout)

  $toolboxTitle = [System.Windows.Forms.Label]::new()
  $toolboxTitle.Text = 'Toolbox'
  $toolboxTitle.AutoSize = $true
  $toolboxTitle.Font = $headerFont
  $toolboxLayout.Controls.Add($toolboxTitle, 0, 0)

  $toolboxHint = [System.Windows.Forms.Label]::new()
  $toolboxHint.Text = 'Double-click to add. Select + Delete removes.'
  $toolboxHint.AutoSize = $true
  $toolboxHint.Padding = New-Object System.Windows.Forms.Padding(0,6,0,8)
  $toolboxLayout.Controls.Add($toolboxHint, 0, 1)

  $toolbox = [System.Windows.Forms.ListBox]::new()
  $toolbox.Dock = 'Fill'
  $toolbox.Font = $DefaultFont
  $toolbox.IntegralHeight = $false
  $toolbox.ItemHeight = [int]([Math]::Ceiling($DefaultFont.Height * 1.35))
  $toolbox.SelectionMode = 'One'
  $toolbox.Items.Clear()
  [void]$toolbox.Items.AddRange(@('Panel','GroupBox','Label','Button','TextBox','CheckBox','ComboBox'))
  try { $toolbox.TopIndex = 0 } catch {}
  $toolboxLayout.Controls.Add($toolbox, 0, 2)

  $inner = [System.Windows.Forms.SplitContainer]::new()
  $inner.Dock = 'Fill'
  $inner.Orientation = [System.Windows.Forms.Orientation]::Vertical
  $inner.SplitterWidth = 6
  # Min sizes + splitter distance are set on Shown (SplitContainer.Width can be 0 during construction).
  $outer.Panel2.Controls.Add($inner)

  $surfaceHost = [System.Windows.Forms.Panel]::new()
  $surfaceHost.Dock = 'Fill'
  $surfaceHost.Padding = New-Object System.Windows.Forms.Padding(12)
  $inner.Panel1.Controls.Add($surfaceHost)

  $surfaceTitle = [System.Windows.Forms.Label]::new()
  $surfaceTitle.Text = 'Design Surface'
  $surfaceTitle.Dock = 'Top'
  $surfaceTitle.AutoSize = $true
  $surfaceTitle.Font = $headerFont
  $surfaceHost.Controls.Add($surfaceTitle)

  $surfaceScroll = [System.Windows.Forms.Panel]::new()
  $surfaceScroll.Dock = 'Fill'
  $surfaceScroll.AutoScroll = $true
  $surfaceScroll.BorderStyle = 'FixedSingle'
  $surfaceScroll.Margin = New-Object System.Windows.Forms.Padding(0,10,0,0)
  $surfaceHost.Controls.Add($surfaceScroll)

  $canvas = [System.Windows.Forms.Panel]::new()
  $canvas.Location = [System.Drawing.Point]::new(20,20)
  $canvas.Size = [System.Drawing.Size]::new(1200,800)
  $canvas.BorderStyle = 'FixedSingle'
  $surfaceScroll.Controls.Add($canvas)

  $propHost = [System.Windows.Forms.Panel]::new()
  $propHost.Dock = 'Fill'
  $propHost.Padding = New-Object System.Windows.Forms.Padding(12)
  $inner.Panel2.Controls.Add($propHost)

  $propTitle = [System.Windows.Forms.Label]::new()
  $propTitle.Text = 'Properties'
  $propTitle.Dock = 'Top'
  $propTitle.AutoSize = $true
  $propTitle.Font = $headerFont
  $propHost.Controls.Add($propTitle)

  $pg = [System.Windows.Forms.PropertyGrid]::new()
  $pg.Dock = 'Fill'
  $pg.Font = $DefaultFont
  $pg.Margin = New-Object System.Windows.Forms.Padding(0,10,0,0)
  $propHost.Controls.Add($pg)

  function Set-SplitterDistanceSafe {
    param(
      [Parameter(Mandatory)][System.Windows.Forms.SplitContainer]$Split,
      [Parameter(Mandatory)][int]$Distance
    )
    $min = [int]$Split.Panel1MinSize
    $max = [int]($Split.Width - $Split.Panel2MinSize - $Split.SplitterWidth)
    if ($max -lt $min) { return }
    $Split.SplitterDistance = [int]([Math]::Min([Math]::Max($Distance, $min), $max))
  }

  $f.Add_Shown({
    try {
      # Outer: toolbox + editor
      $outer.Panel1MinSize = 240
      $outer.Panel2MinSize = 700
      $targetLeft = [int]([Math]::Max($outer.Panel1MinSize, [Math]::Min(340, $f.ClientSize.Width * 0.22)))
      Set-SplitterDistanceSafe -Split $outer -Distance $targetLeft

      # Inner: editor + properties
      $inner.Panel1MinSize = 550
      $inner.Panel2MinSize = 360
      $targetProp = 440
      Set-SplitterDistanceSafe -Split $inner -Distance ([int]($inner.Width - $targetProp - $inner.SplitterWidth))
    } catch {}
  })

  $f.Add_Resize({
    if ($f.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return }
    try {
      $targetProp = 440
      Set-SplitterDistanceSafe -Split $inner -Distance ([int]($inner.Width - $targetProp - $inner.SplitterWidth))
    } catch {}
  })

  $state = [hashtable]::Synchronized(@{
    DesignMode = $true
    Selected = $null
    Dragging = $false
    Resizing = $false
    ResizeDir = $null
    StartMouse = $null
    StartBounds = $null
    LayoutPath = $LayoutPath
  })

  $sel = [System.Windows.Forms.Panel]::new()
  $sel.Visible = $false
  $sel.BorderStyle = 'FixedSingle'
  $sel.BackColor = [System.Drawing.Color]::Transparent
  $sel.Cursor = [System.Windows.Forms.Cursors]::SizeAll

  $gripSize = 8
  $grips = @{}
  foreach ($dir in @('NW','NE','SE','SW')) {
    $g = [System.Windows.Forms.Panel]::new()
    $g.Width = $gripSize; $g.Height = $gripSize
    $g.BackColor = [System.Drawing.Color]::White
    $g.Tag = $dir
    Set-CursorForResizeDir -Dir $dir -Control $g
    $sel.Controls.Add($g)
    $grips[$dir] = $g
  }

  function Position-Selection {
    if (-not $state.Selected -or -not $sel.Visible) { return }
    $sel.Bounds = $state.Selected.Bounds
    $sel.BringToFront()
    $grips.NW.Location = [System.Drawing.Point]::new(-($gripSize/2), -($gripSize/2))
    $grips.NE.Location = [System.Drawing.Point]::new($sel.Width-($gripSize/2), -($gripSize/2))
    $grips.SE.Location = [System.Drawing.Point]::new($sel.Width-($gripSize/2), $sel.Height-($gripSize/2))
    $grips.SW.Location = [System.Drawing.Point]::new(-($gripSize/2), $sel.Height-($gripSize/2))
  }

  function Set-Selected {
    param([System.Windows.Forms.Control]$c)
    $state.Selected = $c
    $pg.SelectedObject = $c
    if (-not $state.DesignMode -or -not $c) { $sel.Visible = $false; return }
    if ($sel.Parent -ne $c.Parent) {
      if ($sel.Parent) { $sel.Parent.Controls.Remove($sel) }
      $c.Parent.Controls.Add($sel) | Out-Null
    }
    $sel.Visible = $true
    Position-Selection
  }

  $attachSelectable = {
    param([System.Windows.Forms.Control]$c)
    $c.Font = $DefaultFont
    try {
      $t = $themes[[string]$cmbTheme.SelectedItem]
      if ($t) { Set-DefaultControlStyle -Control $c -Theme $t }
    } catch {}
    $c.Add_MouseDown({ if ($state.DesignMode) { Set-Selected -c $this } })
    if ($c -is [System.Windows.Forms.Panel]) {
      $c.BorderStyle = 'FixedSingle'
      $c.Add_ControlAdded({ if ($args[1].Control -is [System.Windows.Forms.Control]) { & $attachSelectable $args[1].Control } })
    } elseif ($c -is [System.Windows.Forms.GroupBox]) {
      $c.Add_ControlAdded({ if ($args[1].Control -is [System.Windows.Forms.Control]) { & $attachSelectable $args[1].Control } })
    }
  }

  function Set-DefaultControlStyle {
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$Control, [Parameter(Mandatory)][hashtable]$Theme)
    $Control.ForeColor = $Theme.Text
    if ($Control -is [System.Windows.Forms.Label]) {
      $Control.BackColor = [System.Drawing.Color]::Transparent
      try { $Control.AutoSize = $false } catch {}
      try { $Control.TextAlign = 'MiddleLeft' } catch {}
    } elseif ($Control -is [System.Windows.Forms.TextBox]) {
      $Control.BackColor = $Theme.Panel
      $Control.BorderStyle = 'FixedSingle'
    } elseif ($Control -is [System.Windows.Forms.Button]) {
      $Control.BackColor = $Theme.Panel
      $Control.FlatStyle = 'Flat'
      $Control.FlatAppearance.BorderColor = [System.Drawing.ControlPaint]::Dark($Theme.Panel)
      $Control.FlatAppearance.BorderSize = 1
    } elseif ($Control -is [System.Windows.Forms.CheckBox]) {
      $Control.BackColor = [System.Drawing.Color]::Transparent
      try { $Control.AutoSize = $false } catch {}
    } elseif ($Control -is [System.Windows.Forms.ComboBox]) {
      $Control.BackColor = $Theme.Panel
    } elseif ($Control -is [System.Windows.Forms.GroupBox]) {
      $Control.BackColor = [System.Drawing.Color]::Transparent
    } elseif ($Control -is [System.Windows.Forms.Panel]) {
      $Control.BackColor = $Theme.Panel
    }
  }

  function Apply-ThemeToControlTree {
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$RootControl, [Parameter(Mandatory)][hashtable]$Theme)
    foreach ($child in $RootControl.Controls) {
      if ($child -isnot [System.Windows.Forms.Control]) { continue }
      Set-DefaultControlStyle -Control $child -Theme $Theme
      if ($child.Controls.Count -gt 0) { Apply-ThemeToControlTree -RootControl $child -Theme $Theme }
    }
  }

  function Clear-Canvas {
    Set-Selected -c $null
    $canvas.Controls.Clear()
    $sel.Visible = $false
  }

  function Add-Example {
    param([Parameter(Mandatory)][ValidateSet('Blank','Login','Settings','Dashboard')][string]$Name)

    Clear-Canvas

    switch ($Name) {
      'Blank' {
        $canvas.Size = [System.Drawing.Size]::new(1200,800)
      }

      'Login' {
        $canvas.Size = [System.Drawing.Size]::new(900,620)

        $title = New-ControlFromType -Type 'Label'
        $title.Name = 'lblTitle'
        $title.Text = 'Sign in'
        $title.SetBounds(40,40,320,34)
        $title.Font = [System.Drawing.Font]::new($DefaultFont.FontFamily, [single]($DefaultFont.Size + 6), [System.Drawing.FontStyle]::Bold)
        $canvas.Controls.Add($title) | Out-Null
        & $attachSelectable $title

        $lblUser = New-ControlFromType -Type 'Label'
        $lblUser.Name = 'lblUser'
        $lblUser.Text = 'Username'
        $lblUser.SetBounds(40,110,160,22)
        $canvas.Controls.Add($lblUser) | Out-Null
        & $attachSelectable $lblUser

        $txtUser = New-ControlFromType -Type 'TextBox'
        $txtUser.Name = 'txtUser'
        $txtUser.SetBounds(40,136,420,32)
        $txtUser.Anchor = 'Top,Left,Right'
        $canvas.Controls.Add($txtUser) | Out-Null
        & $attachSelectable $txtUser

        $lblPass = New-ControlFromType -Type 'Label'
        $lblPass.Name = 'lblPass'
        $lblPass.Text = 'Password'
        $lblPass.SetBounds(40,190,160,22)
        $canvas.Controls.Add($lblPass) | Out-Null
        & $attachSelectable $lblPass

        $txtPass = New-ControlFromType -Type 'TextBox'
        $txtPass.Name = 'txtPass'
        $txtPass.SetBounds(40,216,420,32)
        $txtPass.Anchor = 'Top,Left,Right'
        $txtPass.UseSystemPasswordChar = $true
        $canvas.Controls.Add($txtPass) | Out-Null
        & $attachSelectable $txtPass

        $btn = New-ControlFromType -Type 'Button'
        $btn.Name = 'btnLogin'
        $btn.Text = 'Sign in'
        $btn.SetBounds(40,270,140,40)
        $canvas.Controls.Add($btn) | Out-Null
        & $attachSelectable $btn

        $hint = New-ControlFromType -Type 'Label'
        $hint.Name = 'lblHint'
        $hint.Text = 'Tip: use Anchors to keep inputs responsive.'
        $hint.SetBounds(40,330,520,22)
        $canvas.Controls.Add($hint) | Out-Null
        & $attachSelectable $hint
      }

      'Settings' {
        $canvas.Size = [System.Drawing.Size]::new(1100,720)

        $top = New-ControlFromType -Type 'Panel'
        $top.Name = 'pnlTop'
        $top.Dock = 'Top'
        $top.Height = 56
        $canvas.Controls.Add($top) | Out-Null
        & $attachSelectable $top

        $topTitle = New-ControlFromType -Type 'Label'
        $topTitle.Name = 'lblSettingsTitle'
        $topTitle.Text = 'Settings'
        $topTitle.SetBounds(16,16,260,24)
        $topTitle.Font = [System.Drawing.Font]::new($DefaultFont.FontFamily, [single]($DefaultFont.Size + 3), [System.Drawing.FontStyle]::Bold)
        $top.Controls.Add($topTitle) | Out-Null
        & $attachSelectable $topTitle

        $nav = New-ControlFromType -Type 'Panel'
        $nav.Name = 'pnlNav'
        $nav.Dock = 'Left'
        $nav.Width = 260
        $canvas.Controls.Add($nav) | Out-Null
        & $attachSelectable $nav

        $navGeneral = New-ControlFromType -Type 'Button'
        $navGeneral.Name = 'btnGeneral'
        $navGeneral.Text = 'General'
        $navGeneral.SetBounds(16,20,220,36)
        $nav.Controls.Add($navGeneral) | Out-Null
        & $attachSelectable $navGeneral

        $navAccount = New-ControlFromType -Type 'Button'
        $navAccount.Name = 'btnAccount'
        $navAccount.Text = 'Account'
        $navAccount.SetBounds(16,66,220,36)
        $nav.Controls.Add($navAccount) | Out-Null
        & $attachSelectable $navAccount

        $content = New-ControlFromType -Type 'Panel'
        $content.Name = 'pnlContent'
        $content.Dock = 'Fill'
        $canvas.Controls.Add($content) | Out-Null
        & $attachSelectable $content

        $lbl1 = New-ControlFromType -Type 'Label'
        $lbl1.Name = 'lblDisplay'
        $lbl1.Text = 'Display name'
        $lbl1.SetBounds(24,24,200,22)
        $content.Controls.Add($lbl1) | Out-Null
        & $attachSelectable $lbl1

        $txt1 = New-ControlFromType -Type 'TextBox'
        $txt1.Name = 'txtDisplay'
        $txt1.SetBounds(24,50,520,32)
        $txt1.Anchor = 'Top,Left,Right'
        $content.Controls.Add($txt1) | Out-Null
        & $attachSelectable $txt1

        $lbl2 = New-ControlFromType -Type 'Label'
        $lbl2.Name = 'lblEmail'
        $lbl2.Text = 'Email'
        $lbl2.SetBounds(24,104,200,22)
        $content.Controls.Add($lbl2) | Out-Null
        & $attachSelectable $lbl2

        $txt2 = New-ControlFromType -Type 'TextBox'
        $txt2.Name = 'txtEmail'
        $txt2.SetBounds(24,130,520,32)
        $txt2.Anchor = 'Top,Left,Right'
        $content.Controls.Add($txt2) | Out-Null
        & $attachSelectable $txt2

        $save = New-ControlFromType -Type 'Button'
        $save.Name = 'btnSaveSettings'
        $save.Text = 'Save'
        $save.SetBounds(24,190,120,40)
        $content.Controls.Add($save) | Out-Null
        & $attachSelectable $save
      }

      'Dashboard' {
        $canvas.Size = [System.Drawing.Size]::new(1200,780)

        $top = New-ControlFromType -Type 'Panel'
        $top.Name = 'pnlTop'
        $top.Dock = 'Top'
        $top.Height = 62
        $canvas.Controls.Add($top) | Out-Null
        & $attachSelectable $top

        $title = New-ControlFromType -Type 'Label'
        $title.Name = 'lblTitle'
        $title.Text = 'Dashboard'
        $title.SetBounds(16,18,240,24)
        $title.Font = [System.Drawing.Font]::new($DefaultFont.FontFamily, [single]($DefaultFont.Size + 3), [System.Drawing.FontStyle]::Bold)
        $top.Controls.Add($title) | Out-Null
        & $attachSelectable $title

        $btnNew = New-ControlFromType -Type 'Button'
        $btnNew.Name = 'btnPrimary'
        $btnNew.Text = 'New'
        $btnNew.SetBounds(1040,14,120,36)
        $btnNew.Anchor = 'Top,Right'
        $top.Controls.Add($btnNew) | Out-Null
        & $attachSelectable $btnNew

        $nav = New-ControlFromType -Type 'Panel'
        $nav.Name = 'pnlNav'
        $nav.Dock = 'Left'
        $nav.Width = 240
        $canvas.Controls.Add($nav) | Out-Null
        & $attachSelectable $nav

        $nav1 = New-ControlFromType -Type 'Button'
        $nav1.Name = 'btnHome'
        $nav1.Text = 'Home'
        $nav1.SetBounds(16,20,200,36)
        $nav.Controls.Add($nav1) | Out-Null
        & $attachSelectable $nav1

        $nav2 = New-ControlFromType -Type 'Button'
        $nav2.Name = 'btnReports'
        $nav2.Text = 'Reports'
        $nav2.SetBounds(16,66,200,36)
        $nav.Controls.Add($nav2) | Out-Null
        & $attachSelectable $nav2

        $content = New-ControlFromType -Type 'Panel'
        $content.Name = 'pnlContent'
        $content.Dock = 'Fill'
        $canvas.Controls.Add($content) | Out-Null
        & $attachSelectable $content

        $h1 = New-ControlFromType -Type 'Label'
        $h1.Name = 'lblKpi'
        $h1.Text = 'KPIs'
        $h1.SetBounds(24,24,200,22)
        $content.Controls.Add($h1) | Out-Null
        & $attachSelectable $h1

        $kpi1 = New-ControlFromType -Type 'TextBox'
        $kpi1.Name = 'txtKpi1'
        $kpi1.Text = '42'
        $kpi1.SetBounds(24,52,200,32)
        $content.Controls.Add($kpi1) | Out-Null
        & $attachSelectable $kpi1

        $kpi2 = New-ControlFromType -Type 'TextBox'
        $kpi2.Name = 'txtKpi2'
        $kpi2.Text = '99'
        $kpi2.SetBounds(240,52,200,32)
        $content.Controls.Add($kpi2) | Out-Null
        & $attachSelectable $kpi2
      }
    }

    try {
      $t = $themes[[string]$cmbTheme.SelectedItem]
      Apply-ThemeToControlTree -RootControl $canvas -Theme $t
      $statusLbl.Text = "Example: $Name   |   Layout: $($state.LayoutPath)"
    } catch {}
  }

  foreach ($ex in @('Blank','Login','Settings','Dashboard')) {
    $mi = [System.Windows.Forms.ToolStripMenuItem]::new($ex)
    $mi.Tag = $ex
    $examplesDrop.DropDownItems.Add($mi) | Out-Null
    $mi.Add_Click({ Add-Example -Name ([string]$this.Tag) })
  }

  $canvas.Add_MouseDown({ if ($state.DesignMode) { Set-Selected -c $null } })

  $sel.Add_MouseDown({
    if (-not $state.DesignMode -or -not $state.Selected) { return }
    if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $state.StartMouse = [System.Windows.Forms.Control]::MousePosition
    $state.StartBounds = $state.Selected.Bounds
    $state.Dragging = $true
  })
  $sel.Add_MouseMove({
    if (-not $state.DesignMode -or -not $state.Dragging -or -not $state.Selected) { return }
    $now = [System.Windows.Forms.Control]::MousePosition
    $dx = $now.X - $state.StartMouse.X
    $dy = $now.Y - $state.StartMouse.Y
    $b = $state.StartBounds
    $state.Selected.SetBounds($b.X + $dx, $b.Y + $dy, $b.Width, $b.Height)
    Position-Selection
    $pg.Refresh()
  })
  $sel.Add_MouseUp({ $state.Dragging = $false })

  foreach ($g in $grips.Values) {
    $g.Add_MouseDown({
      if (-not $state.DesignMode -or -not $state.Selected) { return }
      if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
      $state.StartMouse = [System.Windows.Forms.Control]::MousePosition
      $state.StartBounds = $state.Selected.Bounds
      $state.ResizeDir = [string]$this.Tag
      $state.Resizing = $true
    })
    $g.Add_MouseMove({
      if (-not $state.DesignMode -or -not $state.Resizing -or -not $state.Selected) { return }
      $now = [System.Windows.Forms.Control]::MousePosition
      $dx = $now.X - $state.StartMouse.X
      $dy = $now.Y - $state.StartMouse.Y
      $b = $state.StartBounds
      $r = [System.Drawing.Rectangle]::new($b.X,$b.Y,$b.Width,$b.Height)
      switch ($state.ResizeDir) {
        'SE' { $r.Width=[Math]::Max(10,$b.Width+$dx); $r.Height=[Math]::Max(10,$b.Height+$dy) }
        'NW' { $r.X=$b.X+$dx; $r.Y=$b.Y+$dy; $r.Width=[Math]::Max(10,$b.Width-$dx); $r.Height=[Math]::Max(10,$b.Height-$dy) }
        'NE' { $r.Y=$b.Y+$dy; $r.Width=[Math]::Max(10,$b.Width+$dx); $r.Height=[Math]::Max(10,$b.Height-$dy) }
        'SW' { $r.X=$b.X+$dx; $r.Width=[Math]::Max(10,$b.Width-$dx); $r.Height=[Math]::Max(10,$b.Height+$dy) }
      }
      $state.Selected.Bounds = $r
      Position-Selection
      $pg.Refresh()
    })
    $g.Add_MouseUp({ $state.Resizing = $false; $state.ResizeDir = $null })
  }

  $btnDesign.Add_Click({
    $state.DesignMode = $btnDesign.Checked
    if (-not $state.DesignMode) { $sel.Visible = $false }
    else { Set-Selected -c $state.Selected }
  })

  function Apply-Theme([string]$name) {
    $t = $themes[$name]
    $f.BackColor = $t.Back
    $tool.BackColor = $t.Panel
    $tool.ForeColor = $t.Text
    $outer.Panel1.BackColor = $t.Panel
    $outer.Panel2.BackColor = $t.Back
    $outer.BackColor = $t.Panel
    $inner.BackColor = $t.Panel
    $toolboxHost.BackColor = $t.Panel
    $toolboxLayout.BackColor = $t.Panel
    $toolboxTitle.ForeColor = $t.Text
    $toolboxHint.ForeColor = $t.Text
    $surfaceHost.BackColor = $t.Back
    $surfaceTitle.ForeColor = $t.Text
    $surfaceScroll.BackColor = $t.Back
    $propHost.BackColor = $t.Back
    $propTitle.ForeColor = $t.Text
    $canvas.BackColor = $t.Canvas
    $toolbox.BackColor = $t.Panel
    $toolbox.ForeColor = $t.Text
    $pg.ViewBackColor = $t.Panel
    $pg.ViewForeColor = $t.Text
    try {
      $pg.HelpBackColor = $t.Panel
      $pg.HelpForeColor = $t.Text
      $pg.CommandsBackColor = $t.Panel
      $pg.CommandsForeColor = $t.Text
      $pg.CategoryForeColor = $t.Text
      $pg.LineColor = [System.Drawing.ControlPaint]::Dark($t.Panel)
      $pg.SelectedGridItemColor = [System.Drawing.ControlPaint]::Dark($t.Panel)
    } catch {}

    # Toolstrip items + dropdown menus
    foreach ($it in $tool.Items) {
      if ($it -is [System.Windows.Forms.ToolStripItem]) { $it.ForeColor = $t.Text }
    }
    try {
      $examplesDrop.DropDown.BackColor = $t.Panel
      foreach ($mi in $examplesDrop.DropDownItems) {
        $mi.BackColor = $t.Panel
        $mi.ForeColor = $t.Text
      }
    } catch {}

    # Apply to existing canvas controls
    try { Apply-ThemeToControlTree -RootControl $canvas -Theme $t } catch {}

    $statusLbl.ForeColor = $t.Text
    $status.BackColor = $t.Panel
  }
  $cmbTheme.Add_SelectedIndexChanged({ Apply-Theme -name ([string]$cmbTheme.SelectedItem) })
  Apply-Theme -name 'Dark'

  $toolbox.Add_DoubleClick({
    if (-not $toolbox.SelectedItem) { return }
    $type = [string]$toolbox.SelectedItem
    $parent = if ($state.Selected -and ($state.Selected -is [System.Windows.Forms.Panel] -or $state.Selected -is [System.Windows.Forms.GroupBox])) { $state.Selected } else { $canvas }
    $c = New-ControlFromType -Type $type
    $c.Name = ('{0}{1}' -f $type.ToLowerInvariant(), ([guid]::NewGuid().ToString('N').Substring(0,6)))
    $c.Text = $c.Name
    switch ($type) {
      'Label'   { $c.SetBounds(20,20,220,26) }
      'TextBox' { $c.SetBounds(20,20,260,32) }
      'Button'  { $c.SetBounds(20,20,140,40) }
      'CheckBox'{ $c.SetBounds(20,20,220,26) }
      'ComboBox'{ $c.SetBounds(20,20,220,32) }
      'GroupBox'{ $c.SetBounds(20,20,360,220) }
      'Panel'   { $c.SetBounds(20,20,360,220) }
      default   { $c.SetBounds(20,20,140,40) }
    }
    $parent.Controls.Add($c) | Out-Null
    & $attachSelectable $c
    Set-Selected -c $c
  })

  $f.Add_KeyDown({
    if (-not $state.DesignMode) { return }
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Delete -and $state.Selected) {
      $p = $state.Selected.Parent
      $p.Controls.Remove($state.Selected)
      Set-Selected -c $null
    }
  })

  $btnSave.Add_Click({
    try { Save-LayoutToJson -Canvas $canvas -Path $state.LayoutPath; $statusLbl.Text = "Saved: $($state.LayoutPath)" }
    catch { [System.Windows.Forms.MessageBox]::Show("Save failed: $($_.Exception.Message)","Designer") | Out-Null }
  })
  $btnOpen.Add_Click({
    $ofd = [System.Windows.Forms.OpenFileDialog]::new()
    $ofd.Filter = 'Layout JSON (*.json)|*.json|WPF XAML (*.xaml)|*.xaml|All files (*.*)|*.*'
    $ofd.CheckFileExists = $true
    $ofd.RestoreDirectory = $true
    $ofd.FileName = $state.LayoutPath
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $picked = $ofd.FileName
    $ext = [System.IO.Path]::GetExtension($picked).ToLowerInvariant()

    if ($ext -eq '.json') {
      $state.LayoutPath = $picked
      try {
        if (Load-LayoutFromJson -Canvas $canvas -Path $state.LayoutPath -AttachSelectable $attachSelectable) {
          $statusLbl.Text = "Loaded JSON: $($state.LayoutPath)"
          Set-Selected -c $null
        } else {
          $statusLbl.Text = "Load failed: $($state.LayoutPath)"
        }
      } catch {
        [System.Windows.Forms.MessageBox]::Show(
          "Failed to open layout JSON:`n$($state.LayoutPath)`n`n$($_.Exception.Message)",
          "PS Layout Designer",
          [System.Windows.Forms.MessageBoxButtons]::OK,
          [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        $statusLbl.Text = "Load failed: $($state.LayoutPath)"
      }
      return
    }

    if ($ext -eq '.xaml') {
      try {
        if (Load-LayoutFromXaml -Canvas $canvas -Path $picked -AttachSelectable $attachSelectable) {
          $statusLbl.Text = "Imported XAML: $picked"
          Set-Selected -c $null
        } else {
          $statusLbl.Text = "Import failed: $picked"
        }
      } catch {
        [System.Windows.Forms.MessageBox]::Show(
          "Failed to import XAML:`n$picked`n`n$($_.Exception.Message)",
          "PS Layout Designer",
          [System.Windows.Forms.MessageBoxButtons]::OK,
          [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        $statusLbl.Text = "Import failed: $picked"
      }
      return
    }

    [System.Windows.Forms.MessageBox]::Show(
      "Unsupported file type:`n$picked",
      "PS Layout Designer",
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
  })
  $btnExportPs1.Add_Click({
    try {
      $layout = Convert-JsonToHashtable -Json (Get-Content -LiteralPath $state.LayoutPath -Raw -Encoding UTF8)
    } catch {
      $layout = Convert-JsonToHashtable -Json (([ordered]@{ SchemaVersion=1; CanvasSize=[ordered]@{W=$canvas.Width;H=$canvas.Height}; Children=@() } | ConvertTo-Json -Depth 5))
      foreach ($c in $canvas.Controls) { $layout.Children += (Convert-ControlToNode -Control $c) }
    }
    $ps1 = Generate-WinFormsPs1 -Layout $layout
    $sfd = [System.Windows.Forms.SaveFileDialog]::new()
    $sfd.Filter = 'PowerShell (*.ps1)|*.ps1|All files (*.*)|*.*'
    $sfd.FileName = 'layout.generated.ps1'
    if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    Set-Content -Path $sfd.FileName -Value $ps1 -Encoding UTF8
    $statusLbl.Text = "Exported: $($sfd.FileName)"
  })
  $btnExportXaml.Add_Click({
    try {
      $layout = Convert-JsonToHashtable -Json (Get-Content -LiteralPath $state.LayoutPath -Raw -Encoding UTF8)
    } catch {
      $layout = Convert-JsonToHashtable -Json (([ordered]@{ SchemaVersion=1; CanvasSize=[ordered]@{W=$canvas.Width;H=$canvas.Height}; Children=@() } | ConvertTo-Json -Depth 5))
      foreach ($c in $canvas.Controls) { $layout.Children += (Convert-ControlToNode -Control $c) }
    }
    $xaml = Generate-WpfXaml -Layout $layout
    $sfd = [System.Windows.Forms.SaveFileDialog]::new()
    $sfd.Filter = 'XAML (*.xaml)|*.xaml|All files (*.*)|*.*'
    $sfd.FileName = 'layout.generated.xaml'
    if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    Set-Content -Path $sfd.FileName -Value $xaml -Encoding UTF8
    $statusLbl.Text = "Exported: $($sfd.FileName)"
  })

  if (Test-Path -LiteralPath $state.LayoutPath) {
    [void](Load-LayoutFromJson -Canvas $canvas -Path $state.LayoutPath -AttachSelectable $attachSelectable)
    $statusLbl.Text = "Loaded: $($state.LayoutPath)"
  }

  [void]$f.ShowDialog()
}
