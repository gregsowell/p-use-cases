<#
.SYNOPSIS
  Simulate Netcool or Dynatrace posting to an AAP 2.6 Event Stream (Windows PowerShell 5.1+).

.EXAMPLE
  .\Send-TestEvent.ps1 -Kind netcool -Url https://aap.example.com/eda-event-streams/api/eda/v1/external_event_stream/<id>/post/ -Secret <netcool-token>
.EXAMPLE
  .\Send-TestEvent.ps1 -Kind dynatrace -Url <url> -Secret 'dynatrace:<password>' -TargetHost node01 -Path /tmp
#>
param(
  [Parameter(Mandatory)] [ValidateSet('netcool', 'netcool-clear', 'dynatrace')] [string] $Kind,
  [Parameter(Mandatory)] [string] $Url,
  [Parameter(Mandatory)] [string] $Secret,   # token for Netcool, user:password for Dynatrace
  [string] $TargetHost,
  [string] $Path,
  [string] $Incident,
  [switch] $SkipCertificateCheck
)

$files = @{
  'netcool'       = 'netcool_filesystem_alert.json'
  'netcool-clear' = 'netcool_resolution_ignored.json'
  'dynatrace'     = 'dynatrace_low_disk_problem.json'
}
$payload = Get-Content -Raw -Path (Join-Path $PSScriptRoot "payloads\$($files[$Kind])")

if ($TargetHost) { $payload = $payload -replace 'node01(\.lab\.example\.com)?', $TargetHost }
if ($Path)       { $payload = $payload -replace '"/var"', "`"$Path`"" -replace 'system /var ', "system $Path " -replace ':/var:', ":$Path:" }
if ($Incident)   { $payload = $payload -replace 'INC0010042', $Incident }

$headers = @{}
if ($Kind -eq 'dynatrace') {
  $headers['Authorization'] = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Secret))
} else {
  $headers['X-Event-Token'] = $Secret
}

if ($SkipCertificateCheck) {
  [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

Write-Host "POST $Kind event to $Url"
Invoke-RestMethod -Method Post -Uri $Url -Headers $headers -ContentType 'application/json' -Body $payload
