param(
    [ValidateSet('hp','lenovo','acer','auto')][string]$NodeId='auto',
    [int]$Port=17330,
    [switch]$InstallFirewall,
    [switch]$InstallStartup
)

$ErrorActionPreference='Stop'
$here=Split-Path -Parent $MyInvocation.MyCommand.Path
$agent=Join-Path $here 'NexQ-Suite-Agent.ps1'
if(!(Test-Path $agent)){throw "NexQ-Suite-Agent.ps1 not found beside this script."}

if($NodeId -eq 'auto'){
    $NodeId=$env:NEXQ_SUITE_NODE_ID
    if(!$NodeId){$NodeId=$env:COMPUTERNAME.ToLower()}
}

[Environment]::SetEnvironmentVariable('NEXQ_SUITE_NODE_ID',$NodeId,'User')
Write-Host "NexQ Suite node: $NodeId" -ForegroundColor Cyan
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Cyan

if($InstallFirewall){
    $ruleName="NexQ Suite Agent $Port"
    Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Private -ErrorAction Stop | Out-Null
    Write-Host "Firewall rule created for Private networks on TCP $Port." -ForegroundColor Green
}

if($InstallStartup){
    $startup=Join-Path ([Environment]::GetFolderPath('Startup')) 'NexQ Suite Agent.lnk'
    $w=New-Object -ComObject WScript.Shell
    $s=$w.CreateShortcut($startup)
    $s.TargetPath="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $s.Arguments="-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$agent`" -Port $Port -NodeId $NodeId"
    $s.WorkingDirectory=$here
    $s.Save()
    Write-Host "Startup shortcut installed." -ForegroundColor Green
}

Write-Host "Starting agent..." -ForegroundColor Yellow
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $agent -Port $Port -NodeId $NodeId
