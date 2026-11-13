$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ImageLoopIdle {
    [StructLayout(LayoutKind.Sequential)]
    struct LastInput { public uint size; public uint time; }
    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LastInput input);
    [DllImport("kernel32.dll")]
    public static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    public static uint Milliseconds() {
        var input = new LastInput { size = 8 };
        if (!GetLastInputInfo(ref input)) throw new Exception("GetLastInputInfo failed");
        return unchecked((uint)Environment.TickCount - input.time);
    }
}
'@
$idle = [ImageLoopIdle]::Milliseconds()
Write-Output "image-loop console idle-ms=$idle"
if ($idle -lt 60000) {
    Write-Error 'Console is in use; image-loop window was not opened'
    exit 3
}
$paths = @(
    'out/windows-image-loop.exe',
    'tests/platform/windowsImageLoop.cpp',
    'tests/platform/windowsImageLoop.h',
    'tests/platform/windowsImageLoop.ms',
    'src/platform/windows/image.cpp',
    'src/platform/windows/bridge.cpp',
    'src/platform/windows/ion.ms',
    'examples/windowsNative/split.png',
    'examples/windowsNative/wide.png'
)
foreach ($path in $paths) {
    $hash = (Get-FileHash -Algorithm SHA256 $path).Hash.ToLower()
    Write-Output "$hash $path"
}
$p = Start-Process -FilePath '.\out\windows-image-loop.exe' -PassThru `
    -RedirectStandardOutput 'out/image-loop.stdout' `
    -RedirectStandardError 'out/image-loop.stderr'
$handle = $p.Handle
if (!$p.WaitForExit(20000)) {
    Stop-Process -Id $p.Id -Force
    Write-Error 'image-loop executable exceeded 20s guard'
    exit 124
}
$p.WaitForExit()
Get-Content out/image-loop.stdout
Get-Content out/image-loop.stderr
[uint32]$code = 259
if (![ImageLoopIdle]::GetExitCodeProcess($handle, [ref]$code) -or $code -eq 259) {
    throw 'image-loop process exit code unavailable'
}
Write-Output "image-loop process-exit=$code"
exit $code
