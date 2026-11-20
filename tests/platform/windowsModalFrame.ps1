$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ModalFrameConsole {
    [StructLayout(LayoutKind.Sequential)]
    struct LastInput { public uint size; public uint time; }
    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LastInput input);
    [DllImport("kernel32.dll")]
    static extern uint GetTickCount();
    [DllImport("kernel32.dll")]
    public static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    [DllImport("user32.dll", SetLastError=true)]
    static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")]
    static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool GetUserObjectInformation(IntPtr obj, int index, StringBuilder value, uint length, out uint needed);
    public static string InputDesktop() {
        IntPtr desktop = OpenInputDesktop(0, false, 1);
        if (desktop == IntPtr.Zero) return "unavailable-error-"+Marshal.GetLastWin32Error();
        try {
            var value = new StringBuilder(256);
            uint needed;
            if (!GetUserObjectInformation(desktop, 2, value, 512, out needed)) return "unavailable-error-"+Marshal.GetLastWin32Error();
            return value.ToString();
        } finally { CloseDesktop(desktop); }
    }
    public static uint IdleMs() {
        var input = new LastInput { size = 8 };
        if (!GetLastInputInfo(ref input)) throw new Exception("GetLastInputInfo failed");
        return unchecked(GetTickCount() - input.time);
    }
}
'@
$idle = [ModalFrameConsole]::IdleMs()
$desktop = [ModalFrameConsole]::InputDesktop()
Write-Output "modal console idle-ms=$idle input-desktop=$desktop"
if ($idle -lt 60000 -or $desktop -ne 'Default' -or @(Get-Process -Name LogonUI -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Console is in use or locked; modal windows were not opened'
}
foreach ($path in @(
    'out/windows-modal-fade.exe', 'out/windows-modal-slide.exe',
    'tests/platform/windowsModalFrame.c', 'tests/platform/windowsModalFrame.h',
    'tests/platform/windowsModalFrame.ms', 'tests/platform/windowsModalFrame.ps1',
    'src/platform/windows/bridge.cpp', 'src/platform/windows/modal.cpp',
    'src/animation/frame.ms'
)) {
    Write-Output ((Get-FileHash -Algorithm SHA256 $path).Hash.ToLower() + " $path")
}
foreach ($mode in @('fade', 'slide')) {
    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath ".\out\windows-modal-$mode.exe" -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $handle = $p.Handle
        if (!$p.WaitForExit(20000)) {
            Stop-Process -Id $p.Id -Force
            throw "modal $mode exceeded 20s guard"
        }
        $p.WaitForExit()
        $output = @(Get-Content $stdout)
        $output
        Get-Content $stderr
        [uint32]$code = 259
        if (![ModalFrameConsole]::GetExitCodeProcess($handle, [ref]$code) -or $code -eq 259) {
            throw "modal $mode exit code unavailable"
        }
        Write-Output "modal $mode process-exit=$code"
        if ($code -ne 0) { exit $code }
        if ($output -notcontains 'modal pre-show transition hr=0x00000000 visible=0') {
            throw "modal $mode pre-show transition receipt unavailable"
        }
        if (($output -join "`n") -notmatch '(?m)^modal frame marker observed rgb=\d+,\d+,\d+$') {
            throw "modal $mode screen frame marker unavailable"
        }
    } finally {
        Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue
    }
}
exit 0
