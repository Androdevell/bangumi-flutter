[CmdletBinding()]
param(
    [string]$Flutter = 'flutter',
    [string]$OAuthConfig = '',
    [Parameter(Mandatory = $true)][string]$PreviousApk,
    [switch]$ValidateOnly,
    [switch]$NoPub
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $versionMatch = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
    if (-not $versionMatch.Success) { throw 'pubspec.yaml 必须定义版本名和数字构建号' }
    $name = $versionMatch.Groups[1].Value
    $code = [int]$versionMatch.Groups[2].Value
    if ($OAuthConfig) {
        $configuration = Get-Content -LiteralPath $OAuthConfig -Raw | ConvertFrom-Json
        $clientId = $configuration.BGM_OAUTH_APP_ID
        $clientSecret = $configuration.BGM_OAUTH_APP_SECRET
    } else {
        $clientId = $env:BGM_OAUTH_APP_ID
        $clientSecret = $env:BGM_OAUTH_APP_SECRET
    }
    if ([string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($clientSecret)) {
        throw '正式发布必须提供完整 OAuthConfig 或 BGM_OAUTH_APP_ID/BGM_OAUTH_APP_SECRET 环境变量'
    }
    $sdkRoot = $env:ANDROID_HOME
    if (-not $sdkRoot) { $sdkRoot = $env:ANDROID_SDK_ROOT }
    if (-not $sdkRoot) { throw '请设置 ANDROID_HOME 或 ANDROID_SDK_ROOT' }
    $buildTools = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $buildTools) { throw '找不到 Android build-tools' }
    $aapt = Join-Path $buildTools.FullName 'aapt.exe'
    $signer = Join-Path $buildTools.FullName 'apksigner.bat'
    function Read-Package([string]$Path) {
        $badging = (& $aapt dump badging $Path) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw '读取 APK 元数据失败' }
        $match = [regex]::Match($badging, "package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'")
        if (-not $match.Success) { throw 'APK 元数据格式错误' }
        return @{Id=$match.Groups[1].Value; Code=[int]$match.Groups[2].Value; Name=$match.Groups[3].Value; Badging=$badging}
    }
    function Read-Certificate([string]$Path) {
        $certificates = (& $signer verify --print-certs $Path) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw 'APK 签名验证失败' }
        $match = [regex]::Match($certificates, 'Signer #1 certificate SHA-256 digest:\s*([a-fA-F0-9]+)')
        if (-not $match.Success) { throw '找不到 APK 签名证书指纹' }
        return $match.Groups[1].Value.ToLowerInvariant()
    }
    $previous = Read-Package (Resolve-Path -LiteralPath $PreviousApk).Path
    if ($previous.Id -ne 'com.bgm.irena') { throw '基准 APK 不是本应用' }
    if ($code -le $previous.Code) { throw '构建号不高于已发布 APK，拒绝发布降级包' }
    Write-Output "发布预检通过：$name+$code，高于旧版 $($previous.Name)+$($previous.Code)，OAuth 已配置（不输出凭据）"
    if ($ValidateOnly) { return }
    $output = Join-Path $projectRoot "dist/$name"
    if (Test-Path -LiteralPath $output) { throw '发布目录已存在，请保留已有文件或提升版本' }
    $defines = @("--dart-define=BGM_OAUTH_APP_ID=$clientId", "--dart-define=BGM_OAUTH_APP_SECRET=$clientSecret")
    [string[]]$pubArguments = @()
    if ($NoPub) { $pubArguments += '--no-pub' }
    & $Flutter build apk --release --target-platform android-arm64 @pubArguments @defines
    if ($LASTEXITCODE -ne 0) { throw 'Android Release 构建失败' }
    & $Flutter build windows --release @pubArguments @defines
    if ($LASTEXITCODE -ne 0) { throw 'Windows Release 构建失败' }
    $apk = Join-Path $projectRoot 'build/app/outputs/flutter-apk/app-release.apk'
    $current = Read-Package $apk
    if ($current.Name -ne $name -or $current.Code -ne $code -or $current.Id -ne $previous.Id) { throw '构建产物版本或包名与发布配置不一致' }
    if ($current.Badging -notmatch "native-code: 'arm64-v8a'\s*$") { throw 'APK 必须且仅包含 arm64-v8a' }
    $fingerprint = Read-Certificate $apk
    if ($fingerprint -ne (Read-Certificate (Resolve-Path -LiteralPath $PreviousApk).Path)) { throw '新旧 APK 签名不一致，不能覆盖安装' }
    $windowsBundle = Join-Path $projectRoot 'build/windows/x64/runner/Release'
    if ((Get-Item (Join-Path $windowsBundle 'bangumi_flutter.exe')).VersionInfo.ProductVersion -ne "$name+$code") { throw 'Windows 产物版本不一致' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($apk)
    try {
        $entry = $archive.GetEntry('lib/arm64-v8a/libapp.so')
        if (-not $entry) { throw 'APK 缺少 arm64 主程序' }
        $stream = $entry.Open()
        $buffer = New-Object System.IO.MemoryStream
        try { $stream.CopyTo($buffer); $androidAot = [System.Text.Encoding]::UTF8.GetString($buffer.ToArray()) }
        finally { $stream.Dispose(); $buffer.Dispose() }
    } finally { $archive.Dispose() }
    $windowsAot = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Join-Path $windowsBundle 'data/app.so')))
    foreach ($binary in @($androidAot, $windowsAot)) {
        if ($binary.IndexOf($clientId, [StringComparison]::Ordinal) -lt 0 -or
            $binary.IndexOf($clientSecret, [StringComparison]::Ordinal) -lt 0) {
            throw '最终程序未检测到完整 OAuth 配置，拒绝发布（不输出凭据）'
        }
    }
    New-Item -ItemType Directory -Path $output | Out-Null
    Copy-Item -LiteralPath $apk -Destination (Join-Path $output "bangumi-$name-arm64-v8a.apk")
    Copy-Item -LiteralPath $windowsBundle -Destination (Join-Path $output 'windows-x64') -Recurse
    Compress-Archive -LiteralPath (Join-Path $output 'windows-x64') -DestinationPath (Join-Path $output "bangumi-$name-windows-x64.zip") -CompressionLevel Optimal
    $manifest = @{version=$name; versionCode=$code; oauthConfigured=$true; oauthCompiledInBothPlatforms=$true; previousVersionCode=$previous.Code; signerSha256=$fingerprint}
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'release-verification.json') -Encoding utf8
    Write-Output "正式包已核对并生成：$output"
} finally {
    Pop-Location
}
