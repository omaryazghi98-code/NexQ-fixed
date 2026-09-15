# NexQ Suite — Unified Launcher
# Windows PowerShell 5.1+ compatible. No third-party modules required.

$ErrorActionPreference = 'SilentlyContinue'

$NEXQ = Join-Path $env:USERPROFILE 'NexQ-fixed'
$EV0L = Join-Path $env:USERPROFILE 'Desktop\3v0l-interview'
$ALT_EV0L = Join-Path $env:USERPROFILE 'Desktop\3v0l-interview'
$DESKTOP = Join-Path $env:USERPROFILE 'Desktop'

# Auto-detect common local locations. Environment variables override detection.
if ($env:NEXQ_HOME) { $NEXQ = $env:NEXQ_HOME }
if ($env:EV0L_HOME) { $EV0L = $env:EV0L_HOME }

function First-ExistingPath([string[]]$Candidates) {
    foreach ($p in $Candidates) { if ($p -and (Test-Path $p)) { return $p } }
    return $Candidates[0]
}

$NEXQ = First-ExistingPath @(
    $NEXQ,
    (Join-Path $DESKTOP 'NexQ-fixed'),
    (Join-Path $env:USERPROFILE 'NexQ-fixed')
)
$EV0L = First-ExistingPath @($EV0L, $ALT_EV0L, (Join-Path $DESKTOP '3v0l-interview'))

$NOTION_HUB = 'https://app.notion.com/p/3dbda297902b81329c1ac23360d0d1fb?pvs=204'
$NOTION_CHEATSHEET = 'https://app.notion.com/p/3dbda297902b8139a3d5fa85426c41d7?pvs=204'
$NOTION_ROUTER = 'https://app.notion.com/p/3dbda297902b81419e35cbde00ee6586?pvs=204'
$NOTION_KB = 'https://app.notion.com/p/3dcda297902b81f19cf8e82c2efff761?pvs=204'
$GITHUB_NEXQ = 'https://github.com/omaryazghi98-code/NexQ-fixed'
$GITHUB_EV0L = 'https://github.com/omaryazghi98-code/3v0l-interview'
$REMOTE_DISPLAY = 'http://192.168.11.113:17321/'
$REMOTE_CONTROL = 'http://192.168.11.113:17321/control'

function Open-Url($Url) { Start-Process $Url }
function Open-Folder($Path) { if (Test-Path $Path) { Start-Process explorer.exe $Path } else { [System.Windows.MessageBox]::Show("Path not found:`n$Path", 'NexQ Suite') | Out-Null } }

function Start-Terminal([string]$WorkingDir, [string]$Command, [string]$Title) {
    if (!(Test-Path $WorkingDir)) {
        [System.Windows.MessageBox]::Show("Project folder not found:`n$WorkingDir`n`nSet NEXQ_HOME / EV0L_HOME or place the project in the detected folder.", 'NexQ Suite') | Out-Null
        return
    }
    $safe = $WorkingDir.Replace("'", "''")
    $cmd = "Set-Location -LiteralPath '$safe'; Write-Host '=== $Title ===' -ForegroundColor Cyan; $Command"
    Start-Process powershell.exe -ArgumentList '-NoExit','-ExecutionPolicy','Bypass','-Command',$cmd
}

function Start-NexQ { Start-Terminal $NEXQ 'npm.cmd run dev' 'NexQ Fixed — DEV' }
function Start-Ev0l {
    if (!(Test-Path $EV0L)) {
        [System.Windows.MessageBox]::Show("3V0L folder not found:`n$EV0L", 'NexQ Suite') | Out-Null
        return
    }
    $cmd = if (Test-Path (Join-Path $EV0L 'package.json')) { 'npm.cmd start' } else { 'node server.mjs' }
    Start-Terminal $EV0L $cmd '3V0L Interview — LIVE'
}
function Start-Both { Start-NexQ; Start-Sleep -Milliseconds 500; Start-Ev0l }
function Interview-Mode {
    Start-Both
    Start-Sleep -Seconds 1
    Open-Url $NOTION_CHEATSHEET
    Start-Sleep -Milliseconds 300
    Open-Url $REMOTE_DISPLAY
}

function Test-Port([string]$HostName, [int]$Port) {
    try { return (Test-NetConnection -ComputerName $HostName -Port $Port -InformationLevel Quiet) } catch { return $false }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NexQ Suite" Width="1120" Height="760" MinWidth="980" MinHeight="680"
        WindowStartupLocation="CenterScreen" Background="#0B0E14" Foreground="#E8ECF4">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#F4F7FB"/>
      <Setter Property="Background" Value="#171C26"/>
      <Setter Property="BorderBrush" Value="#2A3342"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="16,11"/>
      <Setter Property="Margin" Value="0,0,10,10"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="#E8ECF4"/>
    </Style>
  </Window.Resources>
  <Grid Margin="26">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Grid Grid.Row="0" Margin="0,0,0,18">
      <StackPanel>
        <TextBlock Text="NEXQ SUITE" FontSize="30" FontWeight="Bold" Foreground="#FFFFFF"/>
        <TextBlock Text="One cockpit for NexQ Fixed, 3V0L Interview Intelligence, Notion memory and live interview ops." FontSize="14" Foreground="#98A3B5" Margin="0,5,0,0"/>
      </StackPanel>
      <Border HorizontalAlignment="Right" Padding="14,8" Background="#10151E" BorderBrush="#253043" BorderThickness="1" CornerRadius="10">
        <StackPanel Orientation="Horizontal">
          <Ellipse x:Name="StatusDot" Width="9" Height="9" Fill="#36E0A1" Margin="0,0,8,0" VerticalAlignment="Center"/>
          <TextBlock x:Name="StatusText" Text="READY" FontWeight="SemiBold" Foreground="#B9C5D8"/>
        </StackPanel>
      </Border>
    </Grid>

    <UniformGrid Grid.Row="1" Columns="4" Margin="0,0,0,18">
      <Border Background="#111722" BorderBrush="#273243" BorderThickness="1" CornerRadius="14" Padding="16" Margin="0,0,10,0">
        <StackPanel><TextBlock Text="NexQ Fixed" FontSize="17" FontWeight="Bold"/><TextBlock x:Name="NexQStatus" Text="checking…" Foreground="#8FA0B8" Margin="0,6,0,0"/></StackPanel>
      </Border>
      <Border Background="#111722" BorderBrush="#273243" BorderThickness="1" CornerRadius="14" Padding="16" Margin="0,0,10,0">
        <StackPanel><TextBlock Text="3V0L Interview" FontSize="17" FontWeight="Bold"/><TextBlock x:Name="Ev0lStatus" Text="checking…" Foreground="#8FA0B8" Margin="0,6,0,0"/></StackPanel>
      </Border>
      <Border Background="#111722" BorderBrush="#273243" BorderThickness="1" CornerRadius="14" Padding="16" Margin="0,0,10,0">
        <StackPanel><TextBlock Text="Remote Display" FontSize="17" FontWeight="Bold"/><TextBlock x:Name="RemoteStatus" Text="checking…" Foreground="#8FA0B8" Margin="0,6,0,0"/></StackPanel>
      </Border>
      <Border Background="#111722" BorderBrush="#273243" BorderThickness="1" CornerRadius="14" Padding="16">
        <StackPanel><TextBlock Text="Node / Git" FontSize="17" FontWeight="Bold"/><TextBlock x:Name="ToolStatus" Text="checking…" Foreground="#8FA0B8" Margin="0,6,0,0"/></StackPanel>
      </Border>
    </UniformGrid>

    <Grid Grid.Row="2">
      <Grid.ColumnDefinitions><ColumnDefinition Width="2*"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="#0F141D" BorderBrush="#222C3A" BorderThickness="1" CornerRadius="16" Padding="20" Margin="0,0,14,0">
        <StackPanel>
          <TextBlock Text="LAUNCHPAD" FontSize="13" FontWeight="Bold" Foreground="#7F8DA5" Margin="0,0,0,14"/>
          <WrapPanel>
            <Button x:Name="BtnNexQ" Width="190" Content="▶  Launch NexQ Fixed"/>
            <Button x:Name="BtnEv0l" Width="190" Content="▶  Launch 3V0L"/>
            <Button x:Name="BtnBoth" Width="190" Content="⚡  Launch Both"/>
            <Button x:Name="BtnInterview" Width="190" Content="🎯  Interview Mode"/>
          </WrapPanel>
          <TextBlock Text="LIVE TOOLS" FontSize="13" FontWeight="Bold" Foreground="#7F8DA5" Margin="0,18,0,14"/>
          <WrapPanel>
            <Button x:Name="BtnDisplay" Width="190" Content="▣  Remote Display"/>
            <Button x:Name="BtnControl" Width="190" Content="⌁  iPhone Controller"/>
            <Button x:Name="BtnNotion" Width="190" Content="🧠  Interview Hub"/>
            <Button x:Name="BtnCheat" Width="190" Content="⚡  Live Cheat Sheet"/>
          </WrapPanel>
          <TextBlock Text="DEV / FILES" FontSize="13" FontWeight="Bold" Foreground="#7F8DA5" Margin="0,18,0,14"/>
          <WrapPanel>
            <Button x:Name="BtnNexQFolder" Width="190" Content="📁  NexQ Folder"/>
            <Button x:Name="BtnEv0lFolder" Width="190" Content="📁  3V0L Folder"/>
            <Button x:Name="BtnGitNexQ" Width="190" Content="↗  NexQ GitHub"/>
            <Button x:Name="BtnGitEv0l" Width="190" Content="↗  3V0L GitHub"/>
          </WrapPanel>
          <Border Background="#151B25" BorderBrush="#263246" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,18,0,0">
            <StackPanel>
              <TextBlock Text="Interview Mode" FontSize="15" FontWeight="Bold"/>
              <TextBlock Text="Starts NexQ + 3V0L, opens the silent Notion cheat sheet, then opens the LAN display." Foreground="#96A4BA" Margin="0,5,0,0" TextWrapping="Wrap"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </Border>

      <Border Grid.Column="1" Background="#0F141D" BorderBrush="#222C3A" BorderThickness="1" CornerRadius="16" Padding="20">
        <StackPanel>
          <TextBlock Text="REFERENCE" FontSize="13" FontWeight="Bold" Foreground="#7F8DA5" Margin="0,0,0,14"/>
          <Button x:Name="BtnKB" Content="🧠  Career Knowledge Base" HorizontalContentAlignment="Left"/>
          <Button x:Name="BtnRouter" Content="📊  Interview Question Router" HorizontalContentAlignment="Left"/>
          <Button x:Name="BtnCheat2" Content="🎮  TransPerfect Cheat Sheet" HorizontalContentAlignment="Left"/>
          <Button x:Name="BtnNotionFiles" Content="☷  Open Notion Hub" HorizontalContentAlignment="Left"/>
          <TextBlock Text="PATHS" FontSize="13" FontWeight="Bold" Foreground="#7F8DA5" Margin="0,18,0,10"/>
          <TextBlock Text="NexQ" FontWeight="SemiBold"/>
          <TextBlock x:Name="NexQPath" Text="—" Foreground="#8391A7" TextWrapping="Wrap" Margin="0,3,0,10"/>
          <TextBlock Text="3V0L" FontWeight="SemiBold"/>
          <TextBlock x:Name="Ev0lPath" Text="—" Foreground="#8391A7" TextWrapping="Wrap" Margin="0,3,0,10"/>
          <Button x:Name="BtnRefresh" Content="↻  Refresh Status" Margin="0,8,0,0"/>
        </StackPanel>
      </Border>
    </Grid>

    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <TextBlock Text="NexQ Suite • local cockpit" Foreground="#66758C" VerticalAlignment="Center"/>
    </StackPanel>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$names = @(
    'StatusDot','StatusText','NexQStatus','Ev0lStatus','RemoteStatus','ToolStatus','NexQPath','Ev0lPath',
    'BtnNexQ','BtnEv0l','BtnBoth','BtnInterview','BtnDisplay','BtnControl','BtnNotion','BtnCheat',
    'BtnNexQFolder','BtnEv0lFolder','BtnGitNexQ','BtnGitEv0l','BtnKB','BtnRouter','BtnCheat2','BtnNotionFiles','BtnRefresh'
)
$ui = @{}
foreach ($n in $names) { $ui[$n] = $window.FindName($n) }

function Refresh-Status {
    $ui.NexQPath.Text = $NEXQ
    $ui.Ev0lPath.Text = $EV0L
    $ui.NexQStatus.Text = if (Test-Path $NEXQ) { '✓ project found' } else { '✕ not found' }
    $ui.Ev0lStatus.Text = if (Test-Path $EV0L) { '✓ project found' } else { '✕ not found' }
    $remote = Test-Port '127.0.0.1' 17321
    $ui.RemoteStatus.Text = if ($remote) { '✓ 17321 responding' } else { '○ 17321 offline' }
    $node = Get-Command node.exe
    $git = Get-Command git.exe
    $ui.ToolStatus.Text = "$(if ($node) {'✓ Node'} else {'✕ Node'})  $(if ($git) {'✓ Git'} else {'✕ Git'})"
    $ready = (Test-Path $NEXQ) -and (Test-Path $EV0L) -and [bool]$node
    $ui.StatusText.Text = if ($ready) { 'READY' } else { 'CHECK PATHS' }
    $ui.StatusDot.Fill = if ($ready) { '#36E0A1' } else { '#F2B84B' }
}

$ui.BtnNexQ.Add_Click({ Start-NexQ })
$ui.BtnEv0l.Add_Click({ Start-Ev0l })
$ui.BtnBoth.Add_Click({ Start-Both })
$ui.BtnInterview.Add_Click({ Interview-Mode })
$ui.BtnDisplay.Add_Click({ Open-Url $REMOTE_DISPLAY })
$ui.BtnControl.Add_Click({ Open-Url $REMOTE_CONTROL })
$ui.BtnNotion.Add_Click({ Open-Url $NOTION_HUB })
$ui.BtnCheat.Add_Click({ Open-Url $NOTION_CHEATSHEET })
$ui.BtnCheat2.Add_Click({ Open-Url $NOTION_CHEATSHEET })
$ui.BtnKB.Add_Click({ Open-Url $NOTION_KB })
$ui.BtnRouter.Add_Click({ Open-Url $NOTION_ROUTER })
$ui.BtnNotionFiles.Add_Click({ Open-Url $NOTION_HUB })
$ui.BtnGitNexQ.Add_Click({ Open-Url $GITHUB_NEXQ })
$ui.BtnGitEv0l.Add_Click({ Open-Url $GITHUB_EV0L })
$ui.BtnNexQFolder.Add_Click({ Open-Folder $NEXQ })
$ui.BtnEv0lFolder.Add_Click({ Open-Folder $EV0L })
$ui.BtnRefresh.Add_Click({ Refresh-Status })

Refresh-Status
$window.ShowDialog() | Out-Null
