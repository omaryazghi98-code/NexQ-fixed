# NexQ Suite Agent — lightweight LAN command/health node
# Run on HP / Lenovo / Acer when we link that machine to the command center.
# Default: http://0.0.0.0:17330/
# Optional shared token: set NEXQ_SUITE_TOKEN before starting.

param([int]$Port=17330,[string]$NodeId='unknown',[string]$Token='')
$ErrorActionPreference='SilentlyContinue'
if(!$Token){$Token=$env:NEXQ_SUITE_TOKEN}
$Managed=@{}

function Register-App([string]$Name,[string]$File,[string]$Args='',[string]$Dir=''){$Managed[$Name]=[pscustomobject]@{Name=$Name;File=$File;Args=$Args;Dir=$Dir;Pid=$null}}
function Find-App($item){if(!$item){return $null};if($item.Pid){$p=Get-Process -Id $item.Pid -ErrorAction SilentlyContinue;if($p){return $p}};$n=[IO.Path]::GetFileNameWithoutExtension($item.File);if($n){return Get-Process -Name $n -ErrorAction SilentlyContinue|Select-Object -First 1};return $null}
function Start-App([string]$Name){$i=$Managed[$Name];if(!$i){return @{ok=$false;error='unknown-target'}};$p=Find-App $i;if($p){$i.Pid=$p.Id;return @{ok=$true;state='already-running';pid=$p.Id}};try{$p=Start-Process -FilePath $i.File -ArgumentList $i.Args -WorkingDirectory $i.Dir -PassThru;$i.Pid=$p.Id;return @{ok=$true;state='started';pid=$p.Id}}catch{return @{ok=$false;error=$_.Exception.Message}}}
function Stop-App([string]$Name){$i=$Managed[$Name];if(!$i){return @{ok=$false;error='unknown-target'}};$p=Find-App $i;if(!$p){$i.Pid=$null;return @{ok=$true;state='not-running'}};try{Stop-Process -Id $p.Id -Force;$i.Pid=$null;return @{ok=$true;state='stopped';pid=$p.Id}}catch{return @{ok=$false;error=$_.Exception.Message}}}
function Stop-All{foreach($k in @($Managed.Keys)){[void](Stop-App $k)};@{ok=$true;state='stopped-managed'}}
function Get-Status{$r=@();foreach($k in $Managed.Keys){$p=Find-App $Managed[$k];$r+=[pscustomobject]@{name=$k;running=[bool]$p;pid=if($p){$p.Id}else{$null}}};$r}
function Authorized($o){if(!$Token){return $true};return ($o.token -eq $Token)}
function Send-Json($ctx,$o,[int]$code=200){$b=[Text.Encoding]::UTF8.GetBytes(($o|ConvertTo-Json -Depth 8));$ctx.Response.StatusCode=$code;$ctx.Response.ContentType='application/json';$ctx.Response.ContentLength64=$b.Length;$ctx.Response.OutputStream.Write($b,0,$b.Length);$ctx.Response.Close()}
function Read-Json($ctx){$sr=New-Object IO.StreamReader($ctx.Request.InputStream);$s=$sr.ReadToEnd();$sr.Dispose();if($s){try{$s|ConvertFrom-Json}catch{}}else{[pscustomobject]@{}}}

$nexq=if($env:NEXQ_HOME){$env:NEXQ_HOME}else{Join-Path $env:USERPROFILE 'NexQ-fixed'}
$ev0l=if($env:EV0L_HOME){$env:EV0L_HOME}else{Join-Path $env:USERPROFILE 'Desktop\3v0l-interview'}
if(Test-Path $nexq){Register-App 'nexq' 'npm.cmd' 'run dev' $nexq}
if(Test-Path $ev0l){if(Test-Path (Join-Path $ev0l 'package.json')){Register-App 'ev0l' 'npm.cmd' 'start' $ev0l}else{Register-App 'ev0l' 'node.exe' 'server.mjs' $ev0l}}
$ollama=Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe';if(Test-Path $ollama){Register-App 'ollama' $ollama '' (Split-Path $ollama -Parent)}

$l=New-Object Net.HttpListener;$l.Prefixes.Add("http://+:$Port/");try{$l.Start()}catch{Write-Host "Unable to bind port $Port: $($_.Exception.Message)" -ForegroundColor Red;exit 1}
Write-Host "NexQ Suite Agent [$NodeId] listening on port $Port" -ForegroundColor Cyan
while($l.IsListening){try{$ctx=$l.GetContext()}catch{break};$path=$ctx.Request.Url.AbsolutePath;if($path -eq '/health'){Send-Json $ctx @{ok=$true;node=$NodeId;hostname=$env:COMPUTERNAME};continue};if($path -eq '/status'){Send-Json $ctx @{ok=$true;node=$NodeId;hostname=$env:COMPUTERNAME;processes=Get-Status};continue};if($path -eq '/command' -and $ctx.Request.HttpMethod -eq 'POST'){$o=Read-Json $ctx;if(!(Authorized $o)){Send-Json $ctx @{ok=$false;error='unauthorized'} 401;continue};switch([string]$o.action){'start'{Send-Json $ctx (Start-App ([string]$o.target))};'stop'{if($o.target -eq 'managed'){Send-Json $ctx (Stop-All)}else{Send-Json $ctx (Stop-App ([string]$o.target))}};'kill'{if($o.target -eq 'managed'){Send-Json $ctx (Stop-All)}else{Send-Json $ctx (Stop-App ([string]$o.target))}};'restart'{if($o.target -eq 'managed'){[void](Stop-All);Start-Sleep -Milliseconds 300;foreach($k in $Managed.Keys){[void](Start-App $k)};Send-Json $ctx @{ok=$true;state='restarted'}}else{[void](Stop-App ([string]$o.target));Start-Sleep -Milliseconds 250;Send-Json $ctx (Start-App ([string]$o.target))}};default{Send-Json $ctx @{ok=$false;error='unknown-action'} 400}};continue};Send-Json $ctx @{ok=$false;error='not-found'} 404}
$l.Stop();$l.Close()
