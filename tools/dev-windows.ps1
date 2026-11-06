# CrossPet Windows 开发启动器：编译 → 组装运行目录 → 用独立数据目录启动。
# 用法：dev.cmd [-NoBuild] [-Reset] [-Inspect] [-Force]
#   -NoBuild  跳过编译，只重启（只改了 app/web 里的网页时用）
#   -Reset    清空 build\dev-data（设置、角色偏好、WebView2 缓存）再启动
#   -Inspect  给 WebView2 开远程调试端口 9222，可在 Edge 里打开 http://localhost:9222 检查页面
#   -Force    连已安装的 CrossPet 也一起关掉（默认只关这个仓库启动的那只，避免单实例锁冲突）
#
# 和正式安装版的区别：运行目录在 build\dev\CrossPet，数据在 build\dev-data，不碰
# %LOCALAPPDATA%\Programs\CrossPet 和 %LOCALAPPDATA%\CrossPet。
param(
    [switch]$NoBuild,
    [switch]$Reset,
    [switch]$Inspect,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$proj = Join-Path $root 'app\windows\CrossPet.Dev.csproj'
$bin = Join-Path $root 'app\windows\bin\Debug\net481'
$stage = Join-Path $root 'build\dev\CrossPet'
$data = Join-Path $root 'build\dev-data'
$exe = Join-Path $stage 'CrossPet.exe'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Fail($text) { Say "`n$text" 'Red'; exit 1 }

# 目录链接（junction）：改 app/web、characters 里的文件不用重新复制，重载即可看到
function Set-Link($link, $target) {
    if (Test-Path -LiteralPath $link) {
        $item = Get-Item -LiteralPath $link -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { [IO.Directory]::Delete($link) }
        else { Remove-Item -LiteralPath $link -Recurse -Force }
    }
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Fail '找不到 dotnet。请先安装 .NET 8 SDK：https://dotnet.microsoft.com/download/dotnet/8.0'
}

# ---- 找本机 NuGet 缓存里的 WebView2（离线也能编译，不用联网还原） ----
$pkgRoot = Join-Path $env:USERPROFILE '.nuget\packages\microsoft.web.webview2'
$webView2Lib = $null
if (Test-Path $pkgRoot) {
    $dirs = Get-ChildItem $pkgRoot -Directory | Sort-Object Name -Descending
    foreach ($d in $dirs) {
        $lib = Join-Path $d.FullName 'lib\net462'
        if ((Test-Path (Join-Path $lib 'Microsoft.Web.WebView2.Core.dll')) -and
            (Test-Path (Join-Path $lib 'Microsoft.Web.WebView2.Wpf.dll')) -and
            (Test-Path (Join-Path $lib 'Microsoft.Web.WebView2.WinForms.dll'))) {
            $webView2Lib = $lib
            $pkgDir = $d.FullName
            break
        }
    }
}
if (-not $webView2Lib) {
    Fail "本机 NuGet 缓存里没有 WebView2。`n先联网跑一次：dotnet restore app\windows\CrossPet.csproj`n然后再运行 dev.cmd。"
}

# ---- 编译 ----
if (-not $NoBuild) {
    $version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim().Split('-')[0]
    Say '1/3 编译 Windows 外壳…' 'Cyan'
    $buildArgs = @('build', $proj, '-c', 'Debug', '-nologo', '-v', 'minimal',
        "-p:WebView2Lib=$webView2Lib", "-p:Version=$version")
    & dotnet @buildArgs
    if ($LASTEXITCODE -ne 0) { Fail '编译失败，上面的错误信息里能看到文件和行号。' }
} elseif (-not (Test-Path $exe)) {
    Fail '还没有编译过，去掉 -NoBuild 再运行一次。'
}

# ---- 关掉上一次由仓库启动的那只 ----
$devPath = [IO.Path]::GetFullPath($exe)
$running = @(Get-Process CrossPet -ErrorAction SilentlyContinue)
$mine = @($running | Where-Object { $_.Path -and ([IO.Path]::GetFullPath($_.Path) -ieq $devPath) })
$others = @($running | Where-Object { -not ($_.Path -and ([IO.Path]::GetFullPath($_.Path) -ieq $devPath)) })
if ($mine.Count -gt 0) {
    Say '2/3 关掉上一次的开发版…' 'Cyan'
    $mine | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20; $i++) {
        if (-not (Get-Process -Id ($mine | ForEach-Object Id) -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 200
    }
}
if ($others.Count -gt 0) {
    if ($Force) {
        Say '按 -Force 关掉已安装的 CrossPet…' 'Yellow'
        $others | Stop-Process -Force -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt 25; $i++) {
            if (-not (Get-Process CrossPet -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 200
        }
    } else {
        Fail "已安装的 CrossPet 正在运行（$($others[0].Path)）。`n它和开发版共用同一个单实例锁，会抢着显示。请先从托盘右键「退出」，或者加 -Force 参数。"
    }
}

# ---- 组装运行目录 ----
Say '3/3 组装运行目录…' 'Cyan'
New-Item -ItemType Directory -Force $stage | Out-Null
New-Item -ItemType Directory -Force (Join-Path $stage 'runtimes\win-x64\native') | Out-Null
New-Item -ItemType Directory -Force (Join-Path $stage 'runtimes\win-arm64\native') | Out-Null
New-Item -ItemType Directory -Force (Join-Path $stage 'runtimes\win-x86\native') | Out-Null

Copy-Item (Join-Path $bin 'CrossPet.exe') $stage -Force
Copy-Item (Join-Path $bin 'CrossPet.exe.config') $stage -Force
Copy-Item (Join-Path $bin 'CrossPet.pdb') $stage -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $bin 'Microsoft.Web.WebView2.*.dll') $stage -Force
Copy-Item (Join-Path $root 'VERSION') $stage -Force
Copy-Item (Join-Path $root 'app\windows\apps.json') $stage -Force
Copy-Item (Join-Path $root 'app\icon\AppIcon.ico') $stage -Force

# WebView2 的原生加载器按架构放在 runtimes 下（和正式包一样；AnyCPU 在 x64 / ARM64 上都能用）
foreach ($arch in 'win-x64', 'win-arm64', 'win-x86') {
    $from = Join-Path $pkgDir "runtimes\$arch\native\WebView2Loader.dll"
    if (Test-Path $from) { Copy-Item $from (Join-Path $stage "runtimes\$arch\native") -Force }
}

# 资源直接用链接指回仓库：改网页 / 立绘 / 钩子脚本不用等复制
Set-Link (Join-Path $stage 'web') (Join-Path $root 'app\web')
Set-Link (Join-Path $stage 'characters') (Join-Path $root 'characters')
Set-Link (Join-Path $stage 'integrations') (Join-Path $root 'integrations')
Set-Link (Join-Path $stage 'tools') (Join-Path $root 'tools')

# 随包 Python 只给「接入 AI」和钩子用；开发时借本机 Python（没有也能启动，只是接不了 AI）
$pyExe = $null
$py = Get-Command py -ErrorAction SilentlyContinue
if ($py) {
    foreach ($line in (& py -0p 2>$null)) {
        if ($line -match '([A-Za-z]:\\.*?python\.exe)') { $pyExe = $Matches[1]; break }
    }
}
if (-not $pyExe) {
    $p = Get-Command python -ErrorAction SilentlyContinue
    if ($p -and $p.Source -and ($p.Source -notmatch '\\WindowsApps\\')) { $pyExe = $p.Source }
}
$pyLink = Join-Path $stage 'python'
try {
    if ($pyExe -and (Test-Path $pyExe)) {
        Set-Link $pyLink (Split-Path $pyExe)
    } else {
        if (Test-Path $pyLink) { Remove-Item $pyLink -Recurse -Force }
        New-Item -ItemType Directory -Force $pyLink | Out-Null
        Say '  没找到可用的 Python；桌宠能开，但「设置 → 接入 AI」会不可用。' 'Yellow'
    }
} catch {
    if (-not (Test-Path $pyLink)) { New-Item -ItemType Directory -Force $pyLink | Out-Null }
    Say "  链接本机 Python 失败（$($_.Exception.Message)）；桌宠能开，但「接入 AI」会不可用。" 'Yellow'
}

# ---- 启动 ----
if ($Reset -and (Test-Path $data)) {
    Say '清空开发数据…' 'Yellow'
    Remove-Item -LiteralPath $data -Recurse -Force
}
New-Item -ItemType Directory -Force $data | Out-Null

$env:CROSSPET_DATA_DIR = $data
$env:CROSSPET_STATE_DIR = Join-Path $data 'state'
if ($Inspect) {
    $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = '--remote-debugging-port=9222'
    Say '已打开 WebView2 远程调试：http://localhost:9222' 'Yellow'
}

$startedAt = Get-Date
$proc = Start-Process -FilePath $exe -WorkingDirectory $stage -PassThru
Start-Sleep -Seconds 8
$proc.Refresh()

# 启动失败时外壳会弹一个消息框再退出；不管进程还在不在，都先看这一轮日志里有没有明确的失败
$log = Join-Path $data 'windows.log'
$bad = @()
if (Test-Path $log) {
    $bad = @(Get-Content $log -Encoding UTF8 -Tail 80 | Where-Object {
        if ($_ -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
            ([datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null) -ge $startedAt.AddSeconds(-1)) -and ($_ -match 'WebView2 初始化失败|启动失败|崩溃:')
        } else { $false }
    })
}
if ($proc.HasExited -or $bad.Count -gt 0) {
    if (-not $proc.HasExited) { $proc | Stop-Process -Force -ErrorAction SilentlyContinue }
    Say "`n启动失败。日志最后几行：" 'Red'
    if (Test-Path $log) { Get-Content $log -Encoding UTF8 -Tail 25 | ForEach-Object { Write-Host "  $_" } }
    Say "`n完整日志：$log" 'Red'
    exit 1
}

Say "`nCrossPet 开发版已在运行（PID $($proc.Id)）" 'Green'
Say "  源码      $root"
Say "  运行目录  $stage"
Say "  数据目录  $data"
Say "  日志      $(Join-Path $data 'windows.log')"
Say ''
Say '改网页：Shift + 右键桌宠 →「开发者控制台」→「⟳ 重新载入桌宠」，不用重启。'
Say '改 C#：再运行一次 dev.cmd（自动关掉旧实例、增量编译、重开）。'
Say '数据是独立的；想恢复默认加 -Reset。'
exit 0
