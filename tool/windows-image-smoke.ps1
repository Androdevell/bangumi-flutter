[CmdletBinding()]
param([string]$Flutter = 'flutter')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (Get-Process bangumi_flutter -ErrorAction SilentlyContinue) { throw '请先关闭 Bangumi 测试进程，避免回归被单实例入口跳过' }
    # 独立入口不恢复会话、不联网、不发送真实消息；正式打包随后必须重新构建 main.dart。
    & $Flutter --no-version-check build windows --release --no-pub --target tool/windows_image_smoke.dart
    if ($LASTEXITCODE -ne 0) { throw 'Windows AOT 图片回归构建失败' }
    $folder = Join-Path $root 'build/verification'
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $bundle = Join-Path $root 'build/windows/x64/runner/Release'
    $process = Start-Process -FilePath (Join-Path $bundle 'bangumi_flutter.exe') -WorkingDirectory $bundle -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $folder 'windows-image-smoke.stdout.log') -RedirectStandardError (Join-Path $folder 'windows-image-smoke.stderr.log')
    if (-not $process.WaitForExit(45000)) {
        Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        throw 'Windows AOT 图片回归超时'
    }
    if ($process.ExitCode -ne 0) { throw "Windows AOT 图片回归失败：退出码 $($process.ExitCode)" }
    $result = Get-Content -LiteralPath (Join-Path $folder 'windows-image-smoke.stdout.log') -Raw
    if ($result -notmatch 'Windows AOT image smoke passed: 90 cases') { throw '缺少 Windows AOT 回归完成标记' }
    Write-Output 'Windows AOT image smoke passed: 90 cases'
} finally {
    Pop-Location
}
