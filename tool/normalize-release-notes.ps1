[CmdletBinding()]
param([switch]$Apply, [string]$Proxy='http://127.0.0.1:7890')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$notes=Get-Content (Join-Path $root 'docs/release-notes.json') -Raw | ConvertFrom-Json -AsHashtable
$env:GIT_TERMINAL_PROMPT='0'; $env:GCM_INTERACTIVE='Never'
$credentials="protocol=https`nhost=github.com`n`n" | git -C $root credential fill
$secret=($credentials | Where-Object { $_.StartsWith('password=') } | Select-Object -First 1).Substring(9)
$headers=@{Authorization="Bearer $secret";Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'}
$base='https://api.github.com/repos/Androdevell/bangumi-flutter/releases'
$releases=Invoke-RestMethod "$($base)?per_page=100" -Headers $headers -Proxy $Proxy
if($releases.Count -ge 100) { throw '需要分页备份后再继续，不允许只处理首批。' }
$backup=Join-Path $root "build/release-notes-backup/$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
New-Item -ItemType Directory -Force (Split-Path -Parent $backup) | Out-Null
$releases | ConvertTo-Json -Depth 30 | Set-Content $backup -Encoding utf8
foreach($release in $releases) {
    if (-not $notes.ContainsKey($release.tag_name)) { throw "缺少原版本说明：$($release.tag_name)；未修改远端" }
}
function Identity($release) {
    [ordered]@{id=$release.id;tag=$release.tag_name;target=$release.target_commitish;draft=$release.draft;prerelease=$release.prerelease;created=$release.created_at;published=$release.published_at;
      assets=@($release.assets | ForEach-Object { "$($_.id)|$($_.name)|$($_.size)|$($_.digest)" } | Sort-Object)} | ConvertTo-Json -Depth 5 -Compress
}
foreach($release in $releases) {
    $entry=$notes[$release.tag_name]
    $sections=@()
    if($entry.features.Count) { $sections += "## 功能与优化`n`n" + (($entry.features | ForEach-Object { "- $_" }) -join "`n") }
    if($entry.fixes.Count) { $sections += "## 修复`n`n" + (($entry.fixes | ForEach-Object { "- $_" }) -join "`n") }
    if($sections.Count -eq 0) { throw '不能提交空说明' }
    $body=$sections -join "`n`n"
    Write-Output "$($release.tag_name)：$($release.body.Length) → $($body.Length) 字符"
    if ($Apply) {
        # 只修改文字，禁止改变标签、附件、发布日期或最新版本选择。
        $payload=@{name=$release.tag_name;body=$body} | ConvertTo-Json
        $updated=Invoke-RestMethod "$base/$($release.id)" -Method Patch -Headers $headers -Proxy $Proxy -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload))
        if((Identity $updated) -ne (Identity $release)) { throw "发行身份或附件出现变化：$($release.tag_name)" }
        if($updated.body -ne $body -or $updated.name -ne $release.tag_name) { throw '远端文本回读不一致' }
    }
}
Write-Output "已保存可恢复备份：$backup；Apply=$Apply"
