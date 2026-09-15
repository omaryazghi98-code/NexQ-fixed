# NexQ Suite — Command Center
# Windows PowerShell 5.1+ compatible. No third-party PowerShell modules required.
#
# Three-machine layout:
#   HP     = interview host
#   Lenovo = AI core / services
#   Acer   = teleprompter + Barrier / controller surface
#
# Remote control uses NexQ Suite Agent. Configure IPs in nexq-suite.nodes.json.

$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$CONFIG_PATH = Join-Path $SCRIPT_DIR 'nexq-suite.nodes.json'
$DEFAULT_CONFIG = @{
    controller = @{ name = 'Acer'; host = ''; port = 17330 }
    nodes = @(
        @{ id='hp'; name='HP — Interview'; host=''; port=17330; role='Interview host'; launch=@('discord','googlemeet'); services=@('network') },
        @{ id='lenovo'; name='Lenovo — AI Core'; host=''; port=17330; role='NexQ + 3V0L + AI'; launch=@('nexq','ev0l'); services=@('nexq','ev0l','ollama','azure','requesty','cerebras','deepgram') },
        @{ id='acer'; name='Acer — Teleprompter'; host=''; port=17330; role='Teleprompter + Barrier'; launch=@('display','controller','notion'); services=@('teleprompter','barrier') }
    )
}
if (!(Test-Path $CONFIG_PATH)) { $DEFAULT_CONFIG | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $CONFIG_PATH -Encoding UTF8 }
try { $CONFIG = Get-Content -LiteralPath $CONFIG_PATH -Raw | ConvertFrom-Json } catch { $CONFIG = [pscustomobject]$DEFAULT_CONFIG }

function Get-Node([string]$id) { @($CONFIG.nodes | Where-Object { $_.id -eq $id })[0] }
function Test-Tcp([string]$HostName,[int]$Port) { try { [bool](Test-NetConnection -ComputerName $HostName -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue) } catch { $false } }
function Test-Http([string]$Url) { try { $r=Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 2 -UseBasicParsing; [pscustomobject]@{ok=$true;code=[int]$r.StatusCode} } catch { [pscustomobject]@{ok=$false;code=0} } }
function Invoke-Agent([object]$node,[string]$action,[string]$target='') {
    if (!$node -or !$node.host) { return $null }
    try { $body=@{action=$action;target=$target}|ConvertTo-Json; Invoke-RestMethod -Uri "http://$($node.host):$($node.port)/command" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 3 } catch { $null }
}
function Node-Status([object]$node) {
    if (!$node.host) { return [pscustomobject]@{state='CONFIGURE';detail='IP not configured'} }
    if (!(Test-Tcp $node.host $node.port)) { return [pscustomobject]@{state='OFFLINE';detail="$($node.host):$($node.port) unreachable"} }
    $h=Test-Http "http://$($node.host):$($node.port)/health"; if(!$h.ok){return [pscustomobject]@{state='ERROR';detail='agent health failed'}}
    return [pscustomobject]@{state='ONLINE';detail='agent online'}
}
function Open-Url($u){if($u){Start-Process $u}}
function Open-Folder($p){if(Test-Path $p){Start-Process explorer.exe $p}else{[System.Windows.MessageBox]::Show("Folder not found:`n$p",'NexQ Suite')|Out-Null}}
$NEXQ=if($env:NEXQ_HOME){$env:NEXQ_HOME}else{Join-Path $env:USERPROFILE 'NexQ-fixed'}
$EV0L=if($env:EV0L_HOME){$env:EV0L_HOME}else{Join-Path $env:USERPROFILE 'Desktop\3v0l-interview'}
$REMOTE_DISPLAY='http://192.168.11.113:17321/'
$REMOTE_CONTROL='http://192.168.11.113:17321/control'
$NOTION_HUB='https://app.notion.com/p/3dbda297902b81329c1ac23360d0d1fb?pvs=204'
$NOTION_CHEATSHEET='https://app.notion.com/p/3dbda297902b8139a3d5fa85426c41d7?pvs=204'
$NOTION_ROUTER='https://app.notion.com/p/3dbda297902b81419e35cbde00ee6586?pvs=204'
$NOTION_KB='https://app.notion.com/p/3dcda297902b81f19cf8e82c2efff761?pvs=204'
$GITHUB_NEXQ='https://github.com/omaryazghi98-code/NexQ-fixed'
$GITHUB_EV0L='https://github.com/omaryazghi98-code/3v0l-interview'
function Start-Terminal($dir,$cmd,$title){if(!(Test-Path $dir)){return};$safe=$dir.Replace("'","''");Start-Process powershell.exe -ArgumentList '-NoExit','-ExecutionPolicy','Bypass','-Command',"Set-Location -LiteralPath '$safe'; Write-Host '=== $title ===' -ForegroundColor Cyan; $cmd"}
function Start-LocalNexQ{Start-Terminal $NEXQ 'npm.cmd run dev' 'NexQ Fixed — DEV'}
function Start-LocalEv0l{$cmd=if(Test-Path (Join-Path $EV0L 'package.json')){'npm.cmd start'}else{'node server.mjs'};Start-Terminal $EV0L $cmd '3V0L Interview — LIVE'}

[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="NexQ Suite — Command Center" Width="1240" Height="860" MinWidth="1100" MinHeight="760" WindowStartupLocation="CenterScreen" Background="#080B11" Foreground="#EDF2FA">
<Window.Resources><Style TargetType="Button"><Setter Property="Foreground" Value="#F4F7FB"/><Setter Property="Background" Value="#151B26"/><Setter Property="BorderBrush" Value="#263246"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="14,10"/><Setter Property="Margin" Value="0,0,8,8"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/></Style><Style TargetType="TextBlock"><Setter Property="Foreground" Value="#E8ECF4"/></Style></Window.Resources>
<Grid Margin="22"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<Grid Grid.Row="0" Margin="0,0,0,18"><StackPanel><TextBlock Text="NEXQ SUITE" FontSize="30" FontWeight="Bold" Foreground="#FFFFFF"/><TextBlock Text="COMMAND CENTER" FontSize="12" FontWeight="SemiBold" Foreground="#71809A"/><TextBlock Text="Multi-PC interview cockpit • NexQ Fixed + 3V0L + teleprompter + AI services" FontSize="14" Foreground="#98A3B5" Margin="0,5,0,0"/></StackPanel><StackPanel HorizontalAlignment="Right" Orientation="Horizontal" VerticalAlignment="Top"><Border Background="#111722" BorderBrush="#263246" BorderThickness="1" CornerRadius="9" Padding="12,8" Margin="0,0,8,0"><StackPanel Orientation="Horizontal"><Ellipse x:Name="OverallDot" Width="9" Height="9" Fill="#EAB308" Margin="0,0,8,0"/><TextBlock x:Name="OverallText" Text="SCANNING" FontWeight="SemiBold"/></StackPanel></Border><Button x:Name="BtnRefresh" Content="⟳ Refresh" Margin="0"/></StackPanel></Grid>
<Grid Grid.Row="1" Margin="0,0,0,18"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
<Border Grid.Column="0" Background="#0F141D" BorderBrush="#253044" BorderThickness="1" CornerRadius="14" Padding="16" Margin="0,0,10,0"><StackPanel><TextBlock Text="HP" FontSize="18" FontWeight="Bold"/><TextBlock Text="INTERVIEW HOST" Foreground="#71809A" FontSize="11"/><TextBlock x:Name="HpState" Text="—" Margin="0,8,0,0"/><TextBlock x:Name="HpDetail" Foreground="#6F7E96" FontSize="11"/></StackPanel></Border>
<Border Grid.Column="1" Background="#0F141D" BorderBrush="#253044" BorderThickness="1" CornerRadius="14" Padding="16" Margin="0,0,10,0"><StackPanel><TextBlock Text="LENOVO" FontSize="18" FontWeight="Bold"/><TextBlock Text="AI CORE" Foreground="#71809A" FontSize="11"/><TextBlock x:Name="LenovoState" Text="—" Margin="0,8,0,0"/><TextBlock x:Name="LenovoDetail" Foreground="#6F7E96" FontSize="11"/></StackPanel></Border>
<Border Grid.Column="2" Background="#0F141D" BorderBrush="#253044" BorderThickness="1" CornerRadius="14" Padding="16"><StackPanel><TextBlock Text="ACER" FontSize="18" FontWeight="Bold"/><TextBlock Text="TELEPROMPTER / BARRIER" Foreground="#71809A" FontSize="11"/><TextBlock Text="LOCAL" Foreground="#86EFAC" Margin="0,8,0,0"/><TextBlock Text="Teleprompter + control surface" Foreground="#6F7E96" FontSize="11"/></StackPanel></Border></Grid>
<Grid Grid.Row="2"><Grid.ColumnDefinitions><ColumnDefinition Width="1.25*"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
<ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto" Margin="0,0,12,0"><StackPanel>
<Border Background="#0F141D" BorderBrush="#222C3A" BorderThickness="1" CornerRadius="16" Padding="18" Margin="0,0,0,12"><StackPanel><TextBlock Text="INTERVIEW PROFILES" FontSize="12" FontWeight="Bold" Foreground="#7F8DA5" Margin="0,0,0,12"/><WrapPanel><Button x:Name="BtnInterview" Width="185" Content="🎯 START INTERVIEW"/><Button x:Name="BtnAiCore" Width="185" Content="⚡ START AI CORE"/><Button x:Name="BtnAll" Width="185" Content="🚀 START EVERYTHING"/><Button x:Name="BtnStopAll" Width="185" Content="■ STOP MANAGED"/></WrapPanel><WrapPanel><Button x:Name="BtnKillAll" Width="185" Content="☠ KILL ALL MANAGED"/><Button x:Name="BtnRestart" Width="185" Content="↻ RESTART SELECTED"/><Button x:Name="BtnDisplay" Width="185" Content="▣ TELEPROMPTER"/><Button x:Name="BtnPhone" Width="185" Content="⌁ PHONE CONTROL"/></WrapPanel></StackPanel></Border>
<Border Background="#0F141D" BorderBrush="#222C3A" BorderThickness="1" CornerRadius="16" Padding="18" Margin="0,0,0,12"><StackPanel><TextBlock Text="SERVICES" FontSize="12" FontWeight="Bold" Foreground="#7F8DA5" Margin="0,0,0,12"/><WrapPanel><Button x:Name="BtnNexQ" Width="140" Content="NexQ"/><Button x:Name="BtnEv0l" Width="140" Content="3V0L"/><Button x:Name="BtnOllama" Width="140" Content="Ollama"/><Button x:Name="BtnNexQLan" Width="140" Content="LAN 17321"/></WrapPanel><WrapPanel><Button x:Name="BtnAzure" Width="140" Content="Azure"/><Button x:Name="BtnRequesty" Width="140" Content="Requesty"/><Button x:Name="BtnCerebras" Width="140" Content="Cerebras"/><Button x:Name="BtnDeepgram" Width="140" Content="Deepgram"/></WrapPanel><WrapPanel><Button x:Name="BtnBarrier" Width="140" Content="Barrier"/><Button x:Name="BtnStopNexQ" Width="140" Content="Stop NexQ"/><Button x:Name="BtnStopEv0l" Width="140" Content="Stop 3V0L"/><Button x:Name="BtnStopOllama" Width="140" Content="Stop Ollama"/></WrapPanel></StackPanel></Border>
<Border Background="#0F141D" BorderBrush="#222C3A" BorderThickness="1" CornerRadius="16" Padding="18"><StackPanel><TextBlock Text="REFERENCE" FontSize="12" FontWeight="Bold" Foreground="#7F8DA5" Margin="0,0,0,12"/><WrapPanel><Button x:Name="BtnHub" Width="180" Content="🧠 Notion Hub"/><Button x:Name="BtnCheat" Width="180" Content="⚡ Live Cheat Sheet"/><Button x:Name="BtnRouter" Width="180" Content="📊 Question Router"/><Button x:Name="BtnKB" Width="180" Content="📚 Career KB"/></WrapPanel><WrapPanel><Button x:Name="BtnNexQFolder" Width="180" Content="📁 NexQ Folder"/><Button x:Name="BtnEv0lFolder" Width="180" Content="📁 3V0L Folder"/><Button x:Name="BtnGitNexQ" Width="180" Content="↗ NexQ GitHub"/><Button x:Name="BtnGitEv0l" Width="180" Content="↗ 3V0L GitHub"/></WrapPanel></StackPanel></Border>
</StackPanel></ScrollViewer>
<ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto"><StackPanel>
<Border Background="#0F141D" BorderBrush="#222C3A" BorderThickness="1" CornerRadius="16" Padding="18" Margin="0,0,0,12"><StackPanel><TextBlock Text="API / ENGINE HEALTH" FontSize="12" FontWeight="Bold" Foreground="#7F8DA5" Margin="0,0,0,12"/><TextBlock x:Name="ApiAzure" Text="Azure OpenAI / Speech   …" Margin="0,0,0,8"/><TextBlock x:Name="ApiRequesty" Text="Requesty               …" Margin="0,0,0,8"/><TextBlock x:Name="ApiCerebras" Text="Cerebras               …" Margin="0,0,0,8"/><TextBlock x:Name="ApiDeepgram" Text="Deepgram               …" Margin="0,0,0,8"/><TextBlock x:Name="ApiOllama" Text="Ollama                 …" Margin="0,0,0,8"/><TextBlock x:Name="ApiLan" Text="NexQ LAN              …"/></StackPanel></Border>
<Border Background="#0F141D" BorderBrush="#222C3A" BorderThickness="1" CornerRadius="16" Padding="18" Margin="0,0,0,12"><StackPanel><TextBlock Text="MACHINE ACTIONS" FontSize="12" FontWeight="Bold" Foreground="#7F8DA5" Margin="0,0,0,12"/><TextBlock Text="Remote commands go to the NexQ Suite Agent on each configured machine." Foreground="#8997AC" TextWrapping="Wrap" Margin="0,0,0,10"/><TextBlock x:Name="NodeIps" Text="No remote IPs configured yet." Foreground="#B7C2D3" TextWrapping="Wrap"/></StackPanel></Border>
<Border Background="#121923" BorderBrush="#324057" BorderThickness="1" CornerRadius="16" Padding="18"><StackPanel><TextBlock Text="SAFETY SWITCHES" FontSize="12" FontWeight="Bold" Foreground="#F0B96B" Margin="0,0,0,12"/><TextBlock Text="Kill commands target only processes registered with the Suite Agent. Windows services are never mass-terminated." Foreground="#98A6BA" TextWrapping="Wrap"/></StackPanel></Border>
</StackPanel></ScrollViewer></Grid>
<Grid Grid.Row="3" Margin="0,14,0,0"><TextBlock Text="NexQ Suite • Command Center foundation • link Lenovo + HP tomorrow" Foreground="#5E6D85"/><TextBlock x:Name="ClockText" HorizontalAlignment="Right" Foreground="#5E6D85"/></Grid>
</Grid></Window>
'@
$window=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui=@{};foreach($n in @('OverallDot','OverallText','HpState','HpDetail','LenovoState','LenovoDetail','ApiAzure','ApiRequesty','ApiCerebras','ApiDeepgram','ApiOllama','ApiLan','NodeIps','ClockText','BtnRefresh','BtnInterview','BtnAiCore','BtnAll','BtnStopAll','BtnKillAll','BtnRestart','BtnDisplay','BtnPhone','BtnNexQ','BtnEv0l','BtnOllama','BtnNexQLan','BtnAzure','BtnRequesty','BtnCerebras','BtnDeepgram','BtnBarrier','BtnStopNexQ','BtnStopEv0l','BtnStopOllama','BtnHub','BtnCheat','BtnRouter','BtnKB','BtnNexQFolder','BtnEv0lFolder','BtnGitNexQ','BtnGitEv0l')){$ui[$n]=$window.FindName($n)}
function Set-Health($tb,$label,$state){switch($state){'OK'{$tb.Text="✓ $label    ONLINE";$tb.Foreground='#86EFAC'}'CONFIGURE'{$tb.Text="○ $label    CONFIGURE";$tb.Foreground='#F2C46D'}'OFFLINE'{$tb.Text="○ $label    OFFLINE";$tb.Foreground='#94A3B8'}default{$tb.Text="✕ $label    ERROR";$tb.Foreground='#FCA5A5'}}}
function Refresh-All{
 $hp=Get-Node 'hp';$lv=Get-Node 'lenovo';
 foreach($n in @($hp,$lv)){if($n){$s=Node-Status $n;$state=$s.state;if($n.id -eq 'hp'){$ui.HpState.Text=$state;$ui.HpDetail.Text=$s.detail;$ui.HpState.Foreground=if($state -eq 'ONLINE'){'#86EFAC'}elseif($state -eq 'CONFIGURE'){'#F2C46D'}else{'#94A3B8'}};if($n.id -eq 'lenovo'){$ui.LenovoState.Text=$state;$ui.LenovoDetail.Text=$s.detail;$ui.LenovoState.Foreground=if($state -eq 'ONLINE'){'#86EFAC'}elseif($state -eq 'CONFIGURE'){'#F2C46D'}else{'#94A3B8'}}}}
 Set-Health $ui.ApiLan 'NexQ LAN :17321' (if(Test-Tcp '192.168.11.113' 17321){'OK'}else{'OFFLINE'});Set-Health $ui.ApiOllama 'Ollama :11434' (if(Test-Tcp '127.0.0.1' 11434){'OK'}else{'OFFLINE'});
 $ui.ApiAzure.Text='◐ Azure OpenAI / Speech    provider check on Lenovo';$ui.ApiRequesty.Text='◐ Requesty              provider check on Lenovo';$ui.ApiCerebras.Text='◐ Cerebras              provider check on Lenovo';$ui.ApiDeepgram.Text='◐ Deepgram              provider check on Lenovo';foreach($x in @($ui.ApiAzure,$ui.ApiRequesty,$ui.ApiCerebras,$ui.ApiDeepgram)){$x.Foreground='#AFC0D8'}
 $ips=@();foreach($n in @($hp,$lv)){if($n -and $n.host){$ips+="$($n.name): $($n.host):$($n.port)"}};$ui.NodeIps.Text=if($ips.Count){$ips -join "`n"}{'No remote IPs configured yet. Tomorrow we can add Lenovo + HP here.'};$cfg=(@($hp,$lv)|Where-Object{$_.host}).Count;if($cfg -eq 0){$ui.OverallText.Text='LOCAL READY';$ui.OverallDot.Fill='#86EFAC'}else{$online=(@($hp,$lv)|ForEach-Object{if((Node-Status $_).state -eq 'ONLINE'){1}else{0}}|Measure-Object -Sum).Sum;$ui.OverallText.Text=if($online -eq $cfg){'ALL NODES ONLINE'}else{'PARTIAL'};$ui.OverallDot.Fill=if($online -eq $cfg){'#86EFAC'}else{'#F2C46D'}};$ui.ClockText.Text=(Get-Date).ToString('HH:mm:ss')
}
$ui.BtnRefresh.Add_Click({Refresh-All});$ui.BtnNexQ.Add_Click({Start-LocalNexQ});$ui.BtnEv0l.Add_Click({Start-LocalEv0l});$ui.BtnNexQFolder.Add_Click({Open-Folder $NEXQ});$ui.BtnEv0lFolder.Add_Click({Open-Folder $EV0L});$ui.BtnDisplay.Add_Click({Open-Url $REMOTE_DISPLAY});$ui.BtnPhone.Add_Click({Open-Url $REMOTE_CONTROL});$ui.BtnHub.Add_Click({Open-Url $NOTION_HUB});$ui.BtnCheat.Add_Click({Open-Url $NOTION_CHEATSHEET});$ui.BtnRouter.Add_Click({Open-Url $NOTION_ROUTER});$ui.BtnKB.Add_Click({Open-Url $NOTION_KB});$ui.BtnGitNexQ.Add_Click({Open-Url $GITHUB_NEXQ});$ui.BtnGitEv0l.Add_Click({Open-Url $GITHUB_EV0L});$ui.BtnAzure.Add_Click({Open-Url 'https://portal.azure.com/'});$ui.BtnRequesty.Add_Click({Open-Url 'https://requesty.ai/'});$ui.BtnCerebras.Add_Click({Open-Url 'https://cloud.cerebras.ai/'});$ui.BtnDeepgram.Add_Click({Open-Url 'https://console.deepgram.com/'});$ui.BtnNexQLan.Add_Click({Open-Url $REMOTE_DISPLAY});$ui.BtnBarrier.Add_Click({Start-Process 'barrier'});$ui.BtnAiCore.Add_Click({$n=Get-Node 'lenovo';if($n.host){foreach($t in @('nexq','ev0l','ollama')){Invoke-Agent $n 'start' $t}}else{Start-LocalNexQ;Start-Sleep -Milliseconds 300;Start-LocalEv0l}});$ui.BtnAll.Add_Click({$n=Get-Node 'lenovo';if($n.host){foreach($t in @('nexq','ev0l')){Invoke-Agent $n 'start' $t}}else{Start-LocalNexQ;Start-Sleep -Milliseconds 300;Start-LocalEv0l};Open-Url $REMOTE_DISPLAY});$ui.BtnInterview.Add_Click({$n=Get-Node 'lenovo';if($n.host){foreach($t in @('nexq','ev0l')){Invoke-Agent $n 'start' $t}}else{Start-LocalNexQ;Start-Sleep -Milliseconds 300;Start-LocalEv0l};Open-Url $NOTION_CHEATSHEET;Start-Sleep -Milliseconds 300;Open-Url $REMOTE_DISPLAY});$ui.BtnStopAll.Add_Click({foreach($n in @($hp,$lv)){if($n.host){Invoke-Agent $n 'stop' 'managed'}}});$ui.BtnKillAll.Add_Click({foreach($n in @($hp,$lv)){if($n.host){Invoke-Agent $n 'kill' 'managed'}}});$ui.BtnStopNexQ.Add_Click({$n=Get-Node 'lenovo';if($n.host){Invoke-Agent $n 'stop' 'nexq'}});$ui.BtnStopEv0l.Add_Click({$n=Get-Node 'lenovo';if($n.host){Invoke-Agent $n 'stop' 'ev0l'}});$ui.BtnStopOllama.Add_Click({$n=Get-Node 'lenovo';if($n.host){Invoke-Agent $n 'stop' 'ollama'}});$ui.BtnOllama.Add_Click({$n=Get-Node 'lenovo';if($n.host){Invoke-Agent $n 'start' 'ollama'}});$ui.BtnStopAll.Add_Click({});
Refresh-All;$timer=New-Object System.Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromSeconds(5);$timer.Add_Tick({Refresh-All});$timer.Start();$window.ShowDialog()|Out-Null
