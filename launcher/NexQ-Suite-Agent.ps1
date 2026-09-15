# NexQ Suite Agent — lightweight LAN control/health node
# Run on HP/Lenovo/Acer when linking that machine to the command center.
# Windows PowerShell 5.1+; no third-party modules required.
# Default port: 17330
#
# Start:
#   powershell -ExecutionPolicy Bypass -File .\NexQ-Suite-Agent.ps1
#
# This agent only manages explicitly registered Suite processes.

param(
    [int]$Port = 17330,
    [string]$NodeId = 'unknown',
    [string]$Token = ''
)

$ErrorActionPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (!$Token) { $Token = $env:NEXQ_SUITE_TOKEN }

$Managed = @{}

function Add-Managed([string]$Name,[string]$File,[string]$Arguments='',[string]$WorkingDirectory='') {
    $Managed[$Name] = [pscustomobject]@{ Name=$Name; File=$File; Arguments=$Arguments; WorkingDirectory=$WorkingDirectory; ProcessId=$null }
}

# The common project locations can be overridden with environment variables.
$nexq = if($env:NEXQ_HOME){$env:NEXQ_HOME}else{Join-Path $env:USERPROFILE 'NexQ-fixed'}
$ev0l = if($env:EV0L_HOME){$env:EV0L_HOME}else{Join-Path $env:USERPROFILE 'Desktop\3v0l-interview'}

if(Test-Path $nexq){ Add-Managed 'nexq' 'npm.cmd' 'run dev' $nexq }
if(Test-Path $ev0l){
    if(Test-Path (Join-Path $ev0l 'package.json')){ Add-Managed 'ev0l' 'npm.cmd' 'start' $ev0l }
    else { Add-Managed 'ev0l' 'node.exe' 'server.mjs' $ev0l }
}
# Ollama is usually installed here. Start is intentionally opt-in through this agent.
$ollama = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
if(Test-Path $ollama){ Add-Managed 'ollama' $ollama '' (Split-Path $ollama -Parent) }

function Find-ProcessFor([object]$item) {
    if(!$item){return $null}
    if($item.ProcessId){
        $p=Get-Process -Id $item.ProcessId -ErrorAction SilentlyContinue
        if($p){return $p}
    }
    $leaf=[IO.Path]::GetFileNameWithoutExtension($item.File)
    if($leaf){ return Get-Process -Name $leaf -ErrorAction SilentlyContinue | Select-Object -First 1 }
    return $null
}
function Start-Managed([string]$name){
    $item=$Managed[$name];if(!$item){return @{ok=$false;message='unknown target'}}
    $p=Find-ProcessFor $item
    if($p){$item.ProcessId=$p.Id;return @{ok=$true;state='already-running';pid=$p.Id}}
    try{
        $args=if($item.Arguments){$item.Arguments}else{$null}
        $p=Start-Process -FilePath $item.File -ArgumentList $args -WorkingDirectory $item.WorkingDirectory -PassThru
        $item.ProcessId=$p.Id
        return @{ok=$true;state='started';pid=$p.Id}
    }catch{return @{ok=$false;message=$_.Exception.Message}}
}
function Stop-Managed([string]$name){
    $item=$Managed[$name];if(!$item){return @{ok=$false;message='unknown target'}}
    $p=Find-ProcessFor $item
    if(!$p){$item.ProcessId=$null;return @{ok=$true;state='not-running'}}
    try{Stop-Process -Id $p.Id -Force; $item.ProcessId=$null;return @{ok=$true;state='stopped';pid=$p.Id}}catch{return @{ok=$false;message=$_.Exception.Message}}
}
function Stop-AllManaged { foreach($k in @($Managed.Keys)){[void](Stop-Managed $k)}; return @{ok=$true;state='stopped-managed'} }
function Status {
    $list=@();foreach($k in $Managed.Keys){$item=$Managed[$k];$p=Find-ProcessFor $item;$list += [pscustomobject]@{name=$k;running=[bool]$p;pid=if($p){$p.Id}else{$null}}}
    return $list
}
function Authorized($request){
    if(!$Token){return $true}
    return ($request.token -eq $Token)
}
function Send-Json($ctx,$obj,[int]$status=200){
    $bytes=[Text.Encoding]::UTF8.GetBytes(($obj|ConvertTo-Json -Depth 8))
    $ctx.Response.StatusCode=$status;$ctx.Response.ContentType='application/json';$ctx.Response.ContentLength64=$bytes.Length;$ctx.Response.OutputStream.Write($bytes,0,$bytes.Length);$ctx.Response.Close()
}
function Read-Body($ctx){
    $sr=New-Object IO.StreamReader($ctx.Request.InputStream);$s=$sr.ReadToEnd();$sr.Dispose();if($s){try{return $s|ConvertFrom-Json}catch{}};return [pscustomobject]@{}
}

$listener=New-Object Net.HttpListener
$listener.Prefixes.Add("http://+:$Port/")
try{$listener.Start()}catch{Write-Host "Could not bind port $Port. Try another port or run PowerShell as needed.`n$($_.Exception.Message)" -ForegroundColor Red;exit 1}
Write-Host "NexQ Suite Agent [$NodeId] listening on http://0.0.0.0:$Port/" -ForegroundColor Cyan

while($listener.IsListening){
    try{$ctx=$listener.GetContext()}catch{break}
    $path=$ctx.Request.Url.AbsolutePath
    if($path -eq '/health'){Send-Json $ctx @{ok=$true;node=$NodeId;hostname=$env:COMPUTERNAME;port=$Port};continue}
    if($path -eq '/status'){Send-Json $ctx @{ok=$true;node=$NodeId;hostname=$env:COMPUTERNAME;processCount=@(Status|Where-Object{$_.running}).Count;processes=Status};continue}
    if($path -eq '/command' -and $ctx.Request.HttpMethod -eq 'POST'){
        $req=Read-Body $ctx
        if(!(Authorized $req)) {Send-Json $ctx @{ok=$false;error='unauthorized'} 401;continue}
        $action=[string]$req.action;$target=[string]$req.target
        switch($action){
            'start' {Send-Json $ctx (Start-Managed $target)}
            'stop' {if($target -eq 'managed'){Send-Json $ctx (Stop-AllManaged)} else {Send-Json $ctx (Stop-Managed $target)}}
            'kill' {if($target -eq 'managed'){Send-Json $ctx (Stop-AllManaged)} else {Send-Json $ctx (Stop-Managed $target)}}
            'restart' {if($target -eq 'managed'){[void](Stop-AllManaged);Start-Sleep -Milliseconds 400;$r=@();foreach($k in $Managed.Keys){$r += Start-Managed $k};Send-Json $ctx @{ok=$true;state='restarted';results=$r}} else {[void](Stop-Managed $target);Start-Sleep -Milliseconds 250;Send-Json $ctx (Start-Managed $target)}}
            default {Send-Json $ctx @{ok=$false;error='unknown-action'} 400}
        }
        continue
    }
    Send-Json $ctx @{ok=$false;error='not-found'} 404
}

$listener.Stop();$listener.Close()
