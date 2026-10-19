# Real OS input into the window titled $Title: click at a logical point, type text, or save a screenshot.
# usage: win.ps1 click <x> <y> | type <text> | shot <png> | find | close
param([string]$Action, [string]$A = "", [string]$B = "", [string]$Title = "Neon refresh window")
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class W {
	[StructLayout(LayoutKind.Sequential)] public struct P { public int X, Y; }
	[StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, Bt; }
	[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
	[DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref P p);
	[DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out R r);
	[DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
	[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
	[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
	[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
	[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
	[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
	[DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
	[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
	[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
	[DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
}
"@
[W]::SetProcessDPIAware() | Out-Null
$owner = Get-Process | Where-Object { $_.MainWindowTitle -eq $Title } | Select-Object -First 1
$h = if ($owner) { $owner.MainWindowHandle } else { [IntPtr]::Zero }
if ($h -eq [IntPtr]::Zero) { Write-Output "win: no window '$Title'"; exit 1 }
$origin = New-Object W+P
[W]::ClientToScreen($h, [ref]$origin) | Out-Null
$scale = [W]::GetDpiForWindow($h) / 96.0
$front = [W]::GetWindowThreadProcessId([W]::GetForegroundWindow(), [IntPtr]::Zero)
$me = [W]::GetCurrentThreadId()
[W]::AttachThreadInput($me, $front, $true) | Out-Null
[W]::BringWindowToTop($h) | Out-Null
[W]::SetForegroundWindow($h) | Out-Null
[W]::AttachThreadInput($me, $front, $false) | Out-Null
Start-Sleep -Milliseconds 150
if (($Action -eq "click" -or $Action -eq "type") -and [W]::GetForegroundWindow() -ne $h) { Write-Output "win: '$Title' is not in the foreground, no input sent"; exit 3 }
switch ($Action) {
	"find" { Write-Output "win: at $($origin.X),$($origin.Y) scale $scale" }
	"click" {
		[W]::SetCursorPos([int]($origin.X + [double]$A * $scale), [int]($origin.Y + [double]$B * $scale)) | Out-Null
		Start-Sleep -Milliseconds 50
		[W]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
		Start-Sleep -Milliseconds 50
		[W]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
	}
	"type" { [System.Windows.Forms.SendKeys]::SendWait($A) }
	"shot" {
		$r = New-Object W+R
		[W]::GetClientRect($h, [ref]$r) | Out-Null
		$bmp = New-Object System.Drawing.Bitmap($r.Rt, $r.Bt)
		$g = [System.Drawing.Graphics]::FromImage($bmp)
		$g.CopyFromScreen($origin.X, $origin.Y, 0, 0, $bmp.Size)
		$bmp.Save($A, [System.Drawing.Imaging.ImageFormat]::Png)
		$g.Dispose(); $bmp.Dispose()
	}
	"close" { [W]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null }
	default { Write-Output "win: unknown action '$Action'"; exit 2 }
}
