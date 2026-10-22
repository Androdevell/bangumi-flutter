[CmdletBinding()]
param([ValidateSet('quick','full')][string]$Mode='quick', [string[]]$Tests=@(), [string]$Flutter='D:/flutter/bin/flutter.bat')
$ErrorActionPreference='Stop'
$watch=[Diagnostics.Stopwatch]::StartNew()
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    New-Item -ItemType Directory -Force build/verification | Out-Null
    $log=Join-Path $root 'build/verification/flutter.jsonl'
    if ($Mode -eq 'full' -and $Tests.Count -gt 0) { throw 'full 不允许缩小测试集合' }
    if ($Mode -eq 'quick' -and $Tests.Count -eq 0) {
        $mapping=Get-Content (Join-Path $PSScriptRoot 'test-map.json') -Raw | ConvertFrom-Json -AsHashtable
        $changes=@((& git diff --name-only HEAD); (& git ls-files --others --exclude-standard)) | Sort-Object -Unique
        $selected=@()
        foreach($path in $changes) {
            if ($path -notmatch '^(lib/|test/|android/|windows/|tool/|pubspec)') { continue }
            if ($path -match '^test/.+_test\.dart$') { $selected += $path; continue }
            $rules=@($mapping.Keys | Where-Object { $path.StartsWith($_) })
            if ($rules.Count -eq 0) { $Mode='full'; break }
            foreach($rule in $rules) { $selected += $mapping[$rule] }
        }
        if ($Mode -eq 'quick') {
            $Tests=@($selected | Sort-Object -Unique)
            if ($Tests.Count -eq 0) { throw '未检测到可映射的程序改动；文档检查不冒充测试通过。可显式提供 -Tests。' }
            if (@($Tests | Where-Object { -not (Test-Path -LiteralPath $_) }).Count -gt 0) { $Mode='full'; $Tests=@() }
        }
        if ($Mode -eq 'full') { $Tests=@(); Write-Output '公共层或未映射改动：回退完整回归。' }
    }
    & $Flutter --no-version-check analyze --no-pub --fatal-infos > build/verification/analyze.log 2>&1
    if ($LASTEXITCODE -ne 0) { Get-Content build/verification/analyze.log -Tail 35; throw '静态分析失败' }
    & $Flutter --no-version-check test --no-pub --machine @Tests > $log 2>&1
    $testExit=$LASTEXITCODE
    $events=Get-Content -LiteralPath $log | ForEach-Object { try { $_ | ConvertFrom-Json -ErrorAction Stop } catch {} }
    $done=@($events | Where-Object { $_.type -eq 'testDone' -and -not $_.hidden })
    $summary=@{mode=$Mode; source=((& git rev-parse HEAD) -join ''); passed=@($done | Where-Object { $_.result -eq 'success' -and -not $_.skipped }).Count; skipped=@($done | Where-Object { $_.skipped }).Count; exitCode=$testExit; evidenceReusable=$false}
    $summary | ConvertTo-Json | Set-Content build/verification/summary.json -Encoding utf8
    Write-Output "耗时 $([math]::Round($watch.Elapsed.TotalSeconds,1)) 秒；完整日志保存在 build/verification/"
    $summary | ConvertTo-Json -Compress
    if ($testExit -ne 0) {
        $events | Where-Object { $_.type -eq 'error' } | Select-Object -First 4 error,stackTrace | Format-List
        throw '回归失败；完整日志位于 build/verification/flutter.jsonl'
    }
} finally { Pop-Location }
