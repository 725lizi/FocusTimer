<#
.SYNOPSIS
    FocusTimer 发版辅助脚本：校验工作区 -> 打 tag -> 推送 tag。
    推送 tag 后 GitHub Actions 会自动创建「草稿 Release」，
    再把本地 DevEco Studio 构建的 HAP 拖入草稿并发布即可。

.EXAMPLE
    .\scripts\New-Release.ps1 -Version v1.1.0
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v\d+\.\d+\.\d+$')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "==> FocusTimer 发版：$Version" -ForegroundColor Cyan

# 1. 工作区必须干净，避免把未提交内容漏出版
$dirty = git status --porcelain
if ($dirty) {
    throw "工作区有未提交改动，请先 commit/stash：`n$dirty"
}

# 2. 本地 main 必须与 origin/main 一致，避免基于过期代码发版
git fetch origin --quiet
$remote = (git rev-parse origin/main).Trim()
$local  = (git rev-parse HEAD).Trim()
if ($remote -ne $local) {
    throw "本地 HEAD 与 origin/main 不一致（本地 $($local.Substring(0,7)) / 远端 $($remote.Substring(0,7))），请先 pull/push 再发版。"
}

# 3. tag 不能已存在
if (git tag -l $Version) {
    throw "tag $Version 已存在，请换一个版本号。"
}

# 4. 确认 HAP 已在本地构建
Write-Host ""
Write-Host "请确认已在 DevEco Studio 构建 release HAP：" -ForegroundColor Yellow
Write-Host "  Build > Build Hap(s)/APP(s) > Build Hap(s)" -ForegroundColor Yellow
Write-Host "  产物目录：entry\build\default\outputs\default\*.hap" -ForegroundColor Yellow
$answer = Read-Host "已构建好 HAP？(y/N)"
if ($answer -ne 'y') {
    Write-Host "已取消。构建好后重新运行本脚本即可。" -ForegroundColor Yellow
    exit 1
}

# 5. 打带注释的 tag 并推送（触发 release.yml）
git tag -a $Version -m "Release $Version"
git push origin $Version

Write-Host ""
Write-Host "==> 完成！CI 正在创建草稿 Release。" -ForegroundColor Green
Write-Host "    打开 https://github.com/725lizi/FocusTimer/releases" -ForegroundColor Green
Write-Host "    把 .hap 拖入 $Version 草稿的附件区，点 Publish release 即正式发布。" -ForegroundColor Green
