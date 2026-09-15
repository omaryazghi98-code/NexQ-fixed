# NexQ Suite Agent — lightweight LAN command/health node
# Designed for the three-PC NexQ Suite setup.
# Default: http://0.0.0.0:17330/
# Optional shared token: set NEXQ_SUITE_TOKEN before starting.

param(
    [int]$Port=17330,
    [string]$NodeId='',
    [string]$Token=''
)

$ErrorActionPreference='SilentlyContinue'
if(!$Token){$Token=$env:NEXQ_SUITE_TOKEN}
if(!$NodeId){$NodeId=$env:NEXQ_SUITE_NODE_ID}
if(!$NodeId){$NodeId=$env:COMPUTERNAME.ToLower()}

$Managed=@{}

function Register-App([string]$Name,[string]$File,[string]$Args='',[string]$Dir='',[string]$Url=''){
    $Managed[$Name]=[pscustomobject]@{Name=$Name;File=$File;Args=$Args;Dir=$Dir;Url=$Url;Pid=$null}
}

function Find-App($item){
    if(!$item){return $null}
    if($item.Pid){
        $p=Get-Process -Id $item.Pid -ErrorAction SilentlyContinue
        if($p){return $p}
    }
    $n=[IO.Path]::GetFileNameWithoutExtension($item.File)
    if($n){return Get-Process -Name $n -ErrorAction SilentlyContinue|Select-Object -First 1}
    return $null
}

function Start-App([string]$Name){
    $i=$Managed[$Name]
    if(!$i){return @{ok=$false;error='unknown-target'}}
    $p=Find-App $i
    if($p){$i.Pid=$p.Id;return @{ok=$true;state='already-running';pid=$p.Id}}
    try{
        if($i.Url){$p=Start-Process $i.Url -PassThru}
        else{$p=Start-Process -FilePath $i.File -ArgumentList $i.Args -WorkingDirectory $i.Dir -PassThru}
        $i.Pid=$p.Id
        return @{ok=$true;state='started';pid=$p.Id}
    }catch{return @{ok=$false;error=$_.Exception.Message}}
}

function Stop-App([string]$Name){
    $i=$Managed[$Name]
    if(!$i){return @{ok=$false;error='unknown-target'}}
    $p=Find-App $i
    if(!$p){$i.Pid=$null;return @{ok=$true;state='not-running'}}
    try{Stop-Process -Id $p.Id -Force;$i.Pid=$null;return @{ok=$true;state='stopped';pid=$p.Id}}
    catch{return @{ok=$false;error=$_.Exception.Message}}
}

function Stop-All{
    foreach($k in @($Managed.Keys)){[void](Stop-App $k)}
    @{ok=$true;state='stopped-managed'}
}

function Get-Status{
    $r=@()
    foreach($k in $Managed.Keys){
        $p=Find-App $Managed[$k]
        $r+=[pscustomobject]@{name=$k;running=[bool]$p;pid=if($p){$p.Id}else{$null}}
    }
    $r
}

function Get-LocalAddresses{
    @(
        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {$_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown'} |
        Select-Object -ExpandProperty IPAddress
    ) | Select-Object -Unique
}

function Get-SystemInfo{
    [pscustomobject]@{
        node=$NodeId
        hostname=$env:COMPUTERNAME
        user=$env:USERNAME
        ips=@(Get-LocalAddresses)
        agentPort=$Port
        managed=@($Managed.Keys | Sort-Object)
        processes=Get-Status
    }
}

function Authorized($o){if(!$Token){return $true};return ($o.token -eq $Token)}
function Send-Json($ctx,$o,[int]$code=200){
    $b=[Text.Encoding]::UTF8.GetBytes(($o|ConvertTo-Json -Depth 10))
    $ctx.Response.StatusCode=$code
    $ctx.Response.ContentType='application/json; charset=utf-8'
    $ctx.Response.ContentLength64=$b.Length
    $ctx.Response.OutputStream.Write($b,0,$b.Length)
    $ctx.Response.Close()
}
function Read-Json($ctx){
    $sr=New-Object IO.StreamReader($ctx.Request.InputStream)
    $s=$sr.ReadToEnd();$sr.Dispose()
    if($s){try{$s|ConvertFrom-Json}catch{}}
    else{[pscustomobject]@{}}
}

$nexq=if($env:NEXQ_HOME){$env:NEXQ_HOME}else{Join-Path $env:USERPROFILE 'NexQ-fixed'}
$ev0l=if($env:EV0L_HOME){$env:EV0L_HOME}else{Join-Path $env:USERPROFILE 'Desktop\3v0l-interview'}
if(Test-Path $nexq){Register-App 'nexq' 'npm.cmd' 'run dev' $nexq}
if(Test-Path $ev0l){if(Test-Path (Join-Path $ev0l 'package.json')){Register-App 'ev0l' 'npm.cmd' 'start' $ev0l}else{Register-App 'ev0l' 'node.exe' 'server.mjs' $ev0l}}
$ollama=Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe';if(Test-Path $ollama){Register-App 'ollama' $ollama '' (Split-Path $ollama -Parent)}

# Common presentation/control apps; register only when found.
$chrome=(Get-Command chrome.exe -ErrorAction SilentlyContinue).Source
if(!$chrome -and (Test-Path "$env:ProgramFiles\Google\Chrome\Application\chrome.exe")){$chrome="$env:ProgramFiles\Google\Chrome\Application\chrome.exe"}
if(!$chrome -and (Test-Path "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe")){$chrome="${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"}
if($chrome){Register-App 'browser' $chrome '' (Split-Path $chrome -Parent)}

$barrier=(Get-Command barrier.exe -ErrorAction SilentlyContinue).Source
if(!$barrier -and (Test-Path "$env:ProgramFiles\Barrier\barrier.exe")){$barrier="$env:ProgramFiles\Barrier\barrier.exe"}
if(!$barrier -and (Test-Path "${env:ProgramFiles(x86)}\Barrier\barrier.exe")){$barrier="${env:ProgramFiles(x86)}\Barrier\barrier.exe"}
if($barrier){Register-App 'barrier' $barrier '' (Split-Path $barrier -Parent)}

$l=New-Object Net.HttpListener
$l.Prefixes.Add("http://+:$Port/")
try{$l.Start()}catch{Write-Host "Unable to bind port $Port: $($_.Exception.Message)" -ForegroundColor Red;exit 1}
Write-Host "NexQ Suite Agent [$NodeId] on $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ("IPs: " + ((Get-LocalAddresses) -join ', ')) -ForegroundColor DarkCyan
Write-Host "Listening on http://0.0.0.0:$Port/" -ForegroundColor DarkCyan

while($l.IsListening){
    try{$ctx=$l.GetContext()}catch{break}
    $path=$ctx.Request.Url.AbsolutePath
    if($path -eq '/health'){Send-Json $ctx @{ok=$true;node=$NodeId;hostname=$env:COMPUTERNAME;ips=@(Get-LocalAddresses);port=$Port};continue}
    if($path -eq '/info'){Send-Json $ctx (Get-SystemInfo);continue}
    if($path -eq '/status'){Send-Json $ctx @{ok=$true;node=$NodeId;hostname=$env:COMPUTERNAME;processes=Get-Status};continue}
    if($path -eq '/command' -and $ctx.Request.HttpMethod -eq 'POST'){
        $o=Read-Json $ctx
        if(!(Authorized $o)){Send-Json $ctx @{ok=$false;error='unauthorized'} 401;continue}
        $action=[string]$o.action;$target=[string]$o.target
        switch($action){
            'start'   {Send-Json $ctx (Start-App $target)}
            'stop'    {if($target -eq 'managed'){Send-Json $ctx (Stop-All)}else{Send-Json $ctx (Stop-App $target)}}
            'kill'    {if($target -eq 'managed'){Send-Json $ctx (Stop-All)}else{Send-Json $ctx (Stop-App $target)}}
            'restart' {if($target -eq 'managed') {[void](Stop-All);Start-Sleep -Milliseconds 400;foreach($k in $Managed.Keys){[void](Start-App $k)};Send-Json $ctx @{ok=$true;state='restarted'}} else {[void](Stop-App $target);Start-Sleep -Milliseconds 300;Send-Json $ctx (Start-App $target)}}
            'open-url' {
                if(!$o.url){Send-Json $ctx @{ok=$false;error='missing-url'} 400}
                else{try{Start-Process ([string]$o.url)|Out-Null;Send-Json $ctx @{ok=$true;state='opened';url=[string]$o.url}}catch{Send-Json $ctx @{ok=$false;error=$_.Exception.Message} 500}}
            }
            default {Send-Json $ctx @{ok=$false;error='unknown-action'} 400}
        }
        continue
    }
    Send-Json $ctx @{ok=$false;error='not-found'} 404
}
$l.Stop();$l.Close()
