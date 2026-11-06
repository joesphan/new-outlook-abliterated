<#
.SYNOPSIS
    Blocks (or unblocks) the ad-delivery hosts used by the new Outlook for Windows.

.DESCRIPTION
    Writes a marked, idempotent section into the system hosts file pointing every
    hostname in tools/ad-hosts.txt at 0.0.0.0, then flushes the DNS cache.

    This stops third-party ad creatives and bidder/tracking calls from loading in
    the desktop app. It does NOT remove the Ad-labelled row from the message list —
    that slot is a free-tier product surface and is backfilled by Microsoft itself.
    See docs/dead-ends.md.

    Requires an elevated PowerShell: the hosts file is Administrators-only.

.PARAMETER Remove
    Delete the marked section instead of writing it.

.PARAMETER DryRun
    Print the section that would be written and exit. Needs no elevation.

.EXAMPLE
    .\Block-OutlookAdHosts.ps1 -DryRun
    .\Block-OutlookAdHosts.ps1
    .\Block-OutlookAdHosts.ps1 -Remove
#>
[CmdletBinding()]
param(
    [switch]$Remove,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$BeginMarker = '# >>> new-outlook-abliterated >>>'
$EndMarker   = '# <<< new-outlook-abliterated <<<'
$HostsPath   = Join-Path $env:windir 'System32\drivers\etc\hosts'
$ListPath    = Join-Path $PSScriptRoot 'ad-hosts.txt'

function Assert-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Elevation required. Open PowerShell as Administrator and re-run this script (the hosts file is Administrators-only). Use -DryRun to preview without elevation.'
    }
}

function Get-BlockHosts {
    if (-not (Test-Path $ListPath)) { throw "Host list not found: $ListPath" }
    Get-Content $ListPath |
        ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
        Where-Object { $_ -ne '' } |
        Select-Object -Unique
}

function New-HostsSection {
    param([string[]]$Hosts)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine($BeginMarker)
    [void]$sb.AppendLine('# Ads in the new Outlook for Windows: MS SSP (Xandr) auction, bidder syncs, Audience Network.')
    [void]$sb.AppendLine('# Unblock with: Block-OutlookAdHosts.ps1 -Remove')
    foreach ($h in $Hosts) { [void]$sb.AppendLine("0.0.0.0 $h") }
    [void]$sb.AppendLine($EndMarker)
    $sb.ToString()
}

$hosts = @(Get-BlockHosts)
if ($hosts.Count -eq 0) { throw "No hostnames found in $ListPath" }

$section = New-HostsSection -Hosts $hosts

if ($DryRun) {
    Write-Host "Would write $($hosts.Count) entries to $HostsPath :"
    Write-Host ''
    Write-Host $section
    if ($Remove) { Write-Host '(-Remove specified: the marked section above would instead be deleted.)' }
    return
}

Assert-Elevated

$original = [IO.File]::ReadAllText($HostsPath)
$backup = Join-Path $env:TEMP ('hosts.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
Copy-Item -LiteralPath $HostsPath -Destination $backup -Force
Write-Host "Backup: $backup"

# Strip any section we wrote previously so this is idempotent.
$sectionRx = [regex]('(?s)\r?\n?' + [regex]::Escape($BeginMarker) + '.*?' + [regex]::Escape($EndMarker) + '\r?\n?')
$clean = $sectionRx.Replace($original, "`r`n")

# Adopt hand-written duplicates: drop bare "0.0.0.0 <listed host>" lines so the
# file ends up with exactly one authoritative block, whether applied or removed.
$alt = ($hosts | ForEach-Object { [regex]::Escape($_) }) -join '|'
$bareRx = [regex]('(?im)^[ \t]*0\.0\.0\.0[ \t]+(?:' + $alt + ')[ \t]*\r?\n?')
$clean = $bareRx.Replace($clean, '')

if ($Remove) {
    [IO.File]::WriteAllText($HostsPath, $clean)
    Write-Host "Removed the blocked-host section ($($hosts.Count) names were listed)."
}
else {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append($clean.TrimEnd("`r", "`n"))
    [void]$sb.Append("`r`n")
    [void]$sb.Append($section)
    [IO.File]::WriteAllText($HostsPath, $sb.ToString())
    Write-Host "Wrote $($hosts.Count) block entries."
}

& ipconfig /flushdns | Out-Null
Write-Host 'DNS cache flushed. Restart Outlook so it re-resolves.'
