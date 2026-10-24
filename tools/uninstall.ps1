#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$AsarPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Say($text, $color = 'Gray') { Write-Host ("  " + $text) -ForegroundColor $color }

function Find-AsarPath {
    $cands = New-Object System.Collections.Generic.List[string]
    foreach ($p in (Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue)) {
        if ($p.Path) { $cands.Add((Join-Path (Split-Path $p.Path) 'resources\app.asar')) }
    }
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $uninstallRoots) {
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $item = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($item -and $item.DisplayName -and $item.DisplayName -match 'DeepSeek') {
                if ($item.InstallLocation) { $cands.Add((Join-Path $item.InstallLocation 'resources\app.asar')) }
                if ($item.DisplayIcon) {
                    $exe = ($item.DisplayIcon -split ',')[0].Trim('"')
                    if ($exe) { $cands.Add((Join-Path (Split-Path $exe) 'resources\app.asar')) }
                }
            }
        }
    }
    $cands.Add((Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\resources\app.asar'))
    $cands.Add((Join-Path $env:ProgramFiles 'DeepSeek Harness\resources\app.asar'))
    $cands.Add((Join-Path 'D:\DeepSeek DSH' 'resources\app.asar'))
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath $c)) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

Write-Host ''
Write-Host '  DSH Thinking Icon - 还原' -ForegroundColor Cyan
Write-Host '  ----------------------------------------' -ForegroundColor DarkGray

$asar = if ($AsarPath) { (Resolve-Path -LiteralPath $AsarPath).Path } else { Find-AsarPath }
if (-not $asar) { Say '未找到 DeepSeek Harness 的 app.asar。' 'Red'; exit 2 }
Say ("安装目录：" + $asar)

$bak = $asar + '.bak'
if (-not (Test-Path -LiteralPath $bak)) {
    Say '没有找到备份文件 app.asar.bak，无法还原。' 'Red'
    Say '如果界面异常，可重新安装 DeepSeek Harness 覆盖修复。' 'Yellow'
    exit 3
}

$metaPath = $asar + '.meta.json'
if ((Test-Path -LiteralPath $metaPath) -and -not $Force) {
    try {
        $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
        $current = (Get-FileHash -LiteralPath $asar -Algorithm SHA256).Hash
        if ($meta.patchedSha256 -and $current -ne $meta.patchedSha256) {
            Say '注意：当前 app.asar 与安装时的指纹不一致，应用可能已升级或被改动。' 'Yellow'
            Say '继续还原会把应用恢复到备份时的版本。' 'Yellow'
            $answer = Read-Host '  继续还原？输入 y 确认'
            if ($answer -notmatch '^(y|Y|yes|YES)$') {
                Say '已取消。' 'Gray'
                exit 8
            }
        }
    } catch {
        Say '读取安装信息失败，跳过指纹检查。' 'DarkGray'
    }
}

Copy-Item -LiteralPath $bak -Destination $asar -Force
Say '已还原为原始文件。' 'Green'
if (Test-Path -LiteralPath $metaPath) { Remove-Item -LiteralPath $metaPath -Force -ErrorAction SilentlyContinue }
Write-Host ''
Write-Host '  请重启 DeepSeek Harness 生效。' -ForegroundColor Cyan
Write-Host ''
