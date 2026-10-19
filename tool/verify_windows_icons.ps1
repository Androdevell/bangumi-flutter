param([Parameter(Mandatory = $true)][string]$Executable)
$ErrorActionPreference = 'Stop'
$resolvedExecutable = (Resolve-Path -LiteralPath $Executable).Path
if (-not ('BangumiIconResourceProbe' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class BangumiIconResourceProbe {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr LoadLibraryEx(string path, IntPtr reserved, uint flags);
    [DllImport("kernel32.dll")]
    public static extern bool FreeLibrary(IntPtr module);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr LoadImage(IntPtr module, IntPtr name, uint type, int cx, int cy, uint flags);
    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr icon);
}
'@
}
$module = [BangumiIconResourceProbe]::LoadLibraryEx($resolvedExecutable, [IntPtr]::Zero, 2)
if ($module -eq [IntPtr]::Zero) { throw 'Cannot read executable resources' }
try {
    foreach ($resourceId in @(101, 102)) {
        foreach ($size in @(16, 24, 32, 48, 64, 128, 256)) {
            $icon = [BangumiIconResourceProbe]::LoadImage($module, [IntPtr]$resourceId, 1, $size, $size, 0)
            if ($icon -eq [IntPtr]::Zero) { throw "Missing icon resource $resourceId at size $size" }
            [void][BangumiIconResourceProbe]::DestroyIcon($icon)
        }
    }
    Write-Output 'Both Windows icon resources load successfully at 16-256px'
} finally {
    [void][BangumiIconResourceProbe]::FreeLibrary($module)
}
