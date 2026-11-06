<#
.SYNOPSIS
    Captures the new Outlook window to a PNG — the visual check used to verify the ad row.

.DESCRIPTION
    WebView2 content does not render through PrintWindow, so this must read the
    screen. SetForegroundWindow is refused to background processes, so the script
    presses ALT (satisfying the foreground lock), raises the window and retries
    until Windows actually reports it as foreground. It prints whether the window
    became foreground before capturing; if that says match=False the image is
    whatever happened to be on top, and the check is invalid.

.PARAMETER Out
    Output PNG path. Defaults to $env:TEMP\outlook-window.png

.EXAMPLE
    .\Capture-OutlookWindow.ps1 -Out .\before.png
#>
[CmdletBinding()]
param(
    [string]$Out = (Join-Path $env:TEMP 'outlook-window.png')
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class OlkCapture {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

[void][OlkCapture]::SetProcessDPIAware()

$proc = Get-Process -Name olk -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1
if (-not $proc) { throw 'Outlook (olk.exe) is not running with a visible window.' }

$hwnd = $proc.MainWindowHandle

# Satisfy the foreground lock, then raise the window.
[OlkCapture]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
[OlkCapture]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
if ([OlkCapture]::IsIconic($hwnd)) { [void][OlkCapture]::ShowWindow($hwnd, 9) }   # SW_RESTORE
[void][OlkCapture]::BringWindowToTop($hwnd)
[void][OlkCapture]::SetForegroundWindow($hwnd)

$isForeground = $false
for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Milliseconds 350
    if ([OlkCapture]::GetForegroundWindow() -eq $hwnd) { $isForeground = $true; break }
    [void][OlkCapture]::SetForegroundWindow($hwnd)
}

$titleSb = New-Object System.Text.StringBuilder 512
[void][OlkCapture]::GetWindowTextW($hwnd, $titleSb, 512)
Write-Output ("window  = '" + $titleSb.ToString() + "'")
Write-Output ("match   = $isForeground")
if (-not $isForeground) {
    Write-Warning 'Window did not become foreground — the capture will be unreliable.'
}
Start-Sleep -Milliseconds 900

$rect = New-Object OlkCapture+RECT
[void][OlkCapture]::GetWindowRect($hwnd, [ref]$rect)
$width  = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
if ($width -le 0 -or $height -le 0) { throw "Bad window rect: $width x $height" }

$bmp = New-Object System.Drawing.Bitmap($width, $height)
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
$gfx.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Output ("saved   = $Out ($width x $height)")
