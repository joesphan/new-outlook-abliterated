<#
.SYNOPSIS
    Reports whether the ad-delivery hosts are blocked and actually resolving to 0.0.0.0.

.DESCRIPTION
    Two independent checks:
      1. structural — is each hostname present as a 0.0.0.0 entry in the hosts file
      2. behavioural — does the resolver now return 0.0.0.0 for that name

    A host can pass check 1 and fail check 2 if the entry is malformed (tabs alone
    are fine, but an entry with a trailing space or an odd encoding is not).

.EXAMPLE
    .\Test-OutlookAdHosts.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$ListPath  = Join-Path $PSScriptRoot 'ad-hosts.txt'
$HostsPath = Join-Path $env:windir 'System32\drivers\etc\hosts'

if (-not (Test-Path $ListPath)) { throw "Host list not found: $ListPath" }

$hosts = Get-Content $ListPath |
    ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
    Where-Object { $_ -ne '' } |
    Select-Object -Unique

$raw = [IO.File]::ReadAllText($HostsPath)
$rows = foreach ($h in $hosts) {
    $inFile = [bool]($raw -match ('(?m)^\s*0\.0\.0\.0\s+' + [regex]::Escape($h) + '\s*$'))
    $resolved = $null
    $rec = Resolve-DnsName -Name $h -Type A -ErrorAction SilentlyContinue |
           Where-Object { $_.IPAddress } | Select-Object -First 1
    if ($rec) { $resolved = $rec.IPAddress }

    [pscustomobject]@{
        Host     = $h
        InHosts  = $inFile
        Resolves = if ($resolved) { $resolved } else { '(none)' }
        Ok       = $inFile -and ($resolved -eq '0.0.0.0')
    }
}

$rows | Format-Table -AutoSize | Out-String | Write-Host

$failed = @($rows | Where-Object { -not $_.Ok })
if ($failed.Count -eq 0) {
    Write-Host "PASS  all $($rows.Count) hosts blocked and resolving to 0.0.0.0" -ForegroundColor Green
}
else {
    Write-Host "FAIL  $($failed.Count) of $($rows.Count) hosts not blocked correctly:" -ForegroundColor Yellow
    $failed | ForEach-Object { Write-Host ("      {0}  inHosts={1} resolves={2}" -f $_.Host, $_.InHosts, $_.Resolves) }
    Write-Host '      Run Block-OutlookAdHosts.ps1 from an elevated PowerShell.' -ForegroundColor Yellow
}

$proc = Get-Process -Name olk -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host ''
    Write-Host "Outlook is running (pid $($proc[0].Id)). Restart it for host changes to take effect;"
    Write-Host 'existing connections and in-memory ad state survive until then.'
}

Write-Host ''
Write-Host 'Reminder: a passing result means third-party creatives are blocked. The Ad row itself'
Write-Host 'remains by design for free accounts and is backfilled by Microsoft (docs/dead-ends.md).'
