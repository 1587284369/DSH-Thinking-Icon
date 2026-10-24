#requires -Version 5.1
<#
  DSH Thinking Icon - 安装脚本
  把 DeepSeek Harness 聊天界面「深度思考中」左侧的运行图标替换成自定义贴纸 GIF。

  原理：在 app.asar 内嵌的 ui-chat client.js 中，把运行图标的 CSS 规则体做等长字节替换，
       不改 asar 结构、不改文件大小。规则通过特征匹配定位（不依赖构建哈希），
       因此小版本更新后通常仍可使用。
#>
[CmdletBinding()]
param(
    [string]$AsarPath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$b64File = Join-Path $here 'icon.b64'
$toolVersion = '1.1.0'

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

function Read-AsarHeader([string]$path) {
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    try {
        $head = New-Object byte[] 16
        $n = $fs.Read($head, 0, 16)
        if ($n -ne 16) { throw '不是有效的 asar 文件' }
        $headerSize = [BitConverter]::ToUInt32($head, 4)
        $jsonLen = [BitConverter]::ToUInt32($head, 12)
        $jsonBytes = New-Object byte[] $jsonLen
        $fs.Position = 16
        $read = 0
        while ($read -lt $jsonLen) {
            $r = $fs.Read($jsonBytes, $read, $jsonLen - $read)
            if ($r -le 0) { throw 'asar 头读取不完整' }
            $read += $r
        }
        return @{
            Text = [Text.Encoding]::UTF8.GetString($jsonBytes)
            Base = [int64](8 + $headerSize)
        }
    } finally { $fs.Dispose() }
}

function Get-Entry($header, [string[]]$parts) {
    $node = $header
    foreach ($name in $parts) {
        if (-not $node.files) { return $null }
        $prop = $node.files.PSObject.Properties[$name]
        if (-not $prop) { return $null }
        $node = $prop.Value
    }
    return $node
}

function Read-Range([string]$path, [int64]$offset, [int]$length) {
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    try {
        $fs.Position = $offset
        $buf = New-Object byte[] $length
        $read = 0
        while ($read -lt $length) {
            $r = $fs.Read($buf, $read, $length - $read)
            if ($r -le 0) { throw '读取 asar 内容失败' }
            $read += $r
        }
        return $buf
    } finally { $fs.Dispose() }
}

Write-Host ''
Write-Host "  DSH Thinking Icon $toolVersion" -ForegroundColor Cyan
Write-Host '  ----------------------------------------' -ForegroundColor DarkGray

$b64 = (Get-Content -LiteralPath $b64File -Raw).Trim()
if ($b64 -notmatch '^[A-Za-z0-9+/=]+$') { throw 'icon.b64 内容无效' }

$asar = if ($AsarPath) { (Resolve-Path -LiteralPath $AsarPath).Path } else { Find-AsarPath }
if (-not $asar) {
    Say '未找到 DeepSeek Harness 的 app.asar。' 'Red'
    Say '可用参数手动指定：install.ps1 -AsarPath "D:\...\resources\app.asar"' 'Yellow'
    exit 2
}
Say ("安装目录：" + $asar)

$raw = Read-AsarHeader $asar
$header = $raw.Text | ConvertFrom-Json

$appVersion = ''
$pkgEntry = Get-Entry $header @('dsh', 'package.json')
if ($pkgEntry) {
    try {
        $pkgText = [Text.Encoding]::UTF8.GetString((Read-Range $asar ($raw.Base + [int64]$pkgEntry.offset) ([int]$pkgEntry.size)))
        $appVersion = ($pkgText | ConvertFrom-Json).version
    } catch { }
}
if ($appVersion) { Say ("应用版本：" + $appVersion) }

$entry = Get-Entry $header @('dsh', 'node_modules', '@deepseek-ai', 'dsh-client-ui-chat', 'lib', 'client.js')
if (-not $entry) {
    Say '这个版本里没有找到 ui-chat 的 client.js，无法安装。' 'Red'
    exit 3
}

$offset = [int64]$entry.offset
$size = [int]$entry.size
$text = [Text.Encoding]::ASCII.GetString((Read-Range $asar ($raw.Base + $offset) $size))

$maskToken = 'mask:url(data:image/png;base64,'
$patchedToken = '_runningWhaleAnimated{will-change:transform;background-image:url(data:image/gif;base64,'

if ($text.Contains($patchedToken)) {
    Say '检测到已经安装过，无需重复安装。' 'Yellow'
    Say '重启 DeepSeek Harness 后即可生效。'
    exit 0
}
if (-not $text.Contains($maskToken)) {
    Say '当前版本未找到运行图标的遮罩规则，可能版本不兼容。' 'Red'
    Say ('请反馈应用版本号（' + $appVersion + '），等待工具更新。') 'Yellow'
    exit 4
}

$maskPos = $text.IndexOf($maskToken, [StringComparison]::Ordinal)
$open = $text.LastIndexOf('{', $maskPos)
$close = $text.IndexOf('}', $maskPos)
if ($open -lt 0 -or $close -lt 0 -or $close -le $open) {
    Say '运行图标规则结构异常，已中止。' 'Red'
    exit 5
}
$selectorStart = $text.LastIndexOf('}', $open) + 1
$selector = $text.Substring($selectorStart, $open - $selectorStart)
if ($selector -notmatch '_runningWhaleAnimated$') {
    Say ('定位到的规则不是运行图标（' + $selector + '），已中止。') 'Red'
    exit 5
}
$oldBodyLength = $close - $open - 1

$newBody = "will-change:transform;background-image:url(data:image/gif;base64,$b64);background-position:center;background-size:contain;background-repeat:no-repeat;display:block;mask:none;-webkit-mask:none"
if ($newBody.Length -gt $oldBodyLength) {
    Say ("贴纸数据过大：需要 $($newBody.Length) 字符，可用 $oldBodyLength 字符。") 'Red'
    exit 6
}
$newBody = $newBody + (' ' * ($oldBodyLength - $newBody.Length))

# 图标 14px -> 18px（等长替换）
$iconPatch = $null
$iconPos = $text.IndexOf('_runningIcon{', [StringComparison]::Ordinal)
if ($iconPos -ge 0) {
    $iconEnd = $text.IndexOf('}', $iconPos) + 1
    $iconRule = $text.Substring($iconPos, $iconEnd - $iconPos)
    if ($iconRule.Contains('calc(14px +')) {
        $newIconRule = $iconRule.Replace('calc(14px +', 'calc(18px +')
        $iconPatch = @{
            Index = $iconPos
            Bytes = [Text.Encoding]::ASCII.GetBytes($newIconRule)
        }
    }
}

if ($DryRun) {
    Say '预演模式：检查通过，未写入任何内容。' 'Green'
    exit 0
}

$bak = $asar + '.bak'
$metaPath = $asar + '.meta.json'
$originalLength = (Get-Item -LiteralPath $asar).Length

if (Test-Path -LiteralPath $bak) {
    # 当前文件此刻是未打补丁的原版（补丁态在上面已提前退出），直接刷新备份即可
    Say '刷新原始文件备份...'
} else {
    Say '备份原始文件...'
}
Copy-Item -LiteralPath $asar -Destination $bak -Force
Say '备份完成。' 'DarkGray'

$stream = [IO.File]::Open($asar, 'Open', 'ReadWrite', 'ReadWrite')
try {
    $bodyBytes = [Text.Encoding]::ASCII.GetBytes($newBody)
    $stream.Position = $raw.Base + $offset + $open + 1
    $stream.Write($bodyBytes, 0, $bodyBytes.Length)
    if ($iconPatch) {
        $stream.Position = $raw.Base + $offset + $iconPatch.Index
        $stream.Write($iconPatch.Bytes, 0, $iconPatch.Bytes.Length)
    }
} finally { $stream.Dispose() }

$checkText = [Text.Encoding]::ASCII.GetString((Read-Range $asar ($raw.Base + $offset) $size))
$newLength = (Get-Item -LiteralPath $asar).Length
if (-not $checkText.Contains($patchedToken) -or $newLength -ne $originalLength) {
    Say '写入校验失败，正在回滚...' 'Red'
    if (Test-Path -LiteralPath $bak) { Copy-Item -LiteralPath $bak -Destination $asar -Force }
    exit 7
}

try {
    $meta = [ordered]@{
        tool = 'DSH-Thinking-Icon'
        version = $toolVersion
        appVersion = $appVersion
        originalSha256 = (Get-FileHash -LiteralPath $bak -Algorithm SHA256).Hash
        patchedSha256 = (Get-FileHash -LiteralPath $asar -Algorithm SHA256).Hash
        installedAt = (Get-Date).ToString('s')
    }
    $meta | ConvertTo-Json | Set-Content -LiteralPath $metaPath -Encoding UTF8
} catch {
    Say '安装信息写入失败（不影响使用）。' 'DarkGray'
}

Say '安装完成。' 'Green'
Write-Host ''
Write-Host '  请完全退出并重新启动 DeepSeek Harness，' -ForegroundColor Cyan
Write-Host '  之后「深度思考中」左侧的小图标就会变成这张贴纸。' -ForegroundColor Cyan
Write-Host ''
Write-Host '  想还原：运行同目录下的“还原.cmd”' -ForegroundColor DarkGray
Write-Host ''
