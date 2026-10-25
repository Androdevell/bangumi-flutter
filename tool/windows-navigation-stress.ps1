[CmdletBinding()]
param([string]$Flutter='D:/flutter/bin/flutter.bat', [ValidateRange(1,3)][int]$Rounds=3)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (Get-Process bangumi_flutter -ErrorAction SilentlyContinue) { throw 'Bangumi is running; close it before the isolated benchmark' }
    $logs=Join-Path $root 'build/verification/navigation'
    New-Item -ItemType Directory -Force -Path $logs | Out-Null
    & $Flutter --no-version-check build windows --release --no-pub --target tool/windows_navigation_stress.dart --dart-define=IMAGE_DIAGNOSTICS=true *> (Join-Path $logs 'build.log')
    if ($LASTEXITCODE -ne 0) { Get-Content (Join-Path $logs 'build.log') -Tail 20; throw 'Navigation benchmark build failed' }
    $bundle=Join-Path $root 'build/windows/x64/runner/Release'
    Copy-Item -LiteralPath (Join-Path $bundle 'data/app.so') -Destination (Join-Path $logs 'app.so') -Force
    $results=@()
    for($round=1; $round -le $Rounds; $round++) {
        $arguments=@('stress')
        if ($round -eq 1) { $arguments += '--stress-cold' }
        if ($round -eq 3) { $arguments += '--stress-glass' }
        $stdout=Join-Path $logs "round-$round.stdout.log"
        $stderr=Join-Path $logs "round-$round.stderr.log"
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $process=Start-Process -FilePath (Join-Path $bundle 'bangumi_flutter.exe') -WorkingDirectory $bundle -WindowStyle Hidden -ArgumentList $arguments -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $reported=''
        while (-not $process.WaitForExit(1000)) {
            if ($watch.Elapsed.TotalMinutes -gt 8) {
                Stop-Process -Id $process.Id
                throw "Navigation benchmark timed out in round $round"
            }
            $progress=Get-Content -LiteralPath $stdout -Tail 1 -ErrorAction SilentlyContinue
            if ($progress -and $progress -ne $reported) { Write-Output "round=$round $progress"; $reported=$progress }
        }
        $text=Get-Content -LiteralPath $stdout -Raw
        $diagnostic=Join-Path ([IO.Path]::GetTempPath()) "bangumi-navigation-$($process.Id).jsonl"
        if (Test-Path -LiteralPath $diagnostic) { Copy-Item -LiteralPath $diagnostic -Destination (Join-Path $logs "round-$round.images.jsonl") -Force }
        $results += @{round=$round; exitCode=$process.ExitCode; elapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,1); passed=($process.ExitCode -eq 0 -and $text -match 'NAVIGATION PASS steps=300')}
        $results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logs 'results.json') -Encoding utf8
        if (-not $results[-1].passed) { Get-Content $stdout -Tail 5; Get-Content $stderr -Tail 5; throw "Navigation round $round failed with $($process.ExitCode)" }
    }
    Write-Output "Navigation stress passed: $Rounds rounds x 300 switches"
} finally { Pop-Location }
