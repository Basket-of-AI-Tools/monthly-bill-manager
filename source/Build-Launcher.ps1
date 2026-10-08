Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
$root = $PSScriptRoot
$iconPath = Join-Path $root '月费账单管理器.ico'
$sourcePath = Join-Path $root 'Launcher.cs'
$outputPath = Join-Path $root '月费账单管理器.exe'

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw '缺少 Launcher.cs。'
}

$bitmap = New-Object System.Drawing.Bitmap(256, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::Transparent)
$brand = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(15, 118, 110))
$paper = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$soft = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(204, 251, 241))
$gold = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 158, 11))
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddArc(16, 16, 48, 48, 180, 90)
$path.AddArc(192, 16, 48, 48, 270, 90)
$path.AddArc(192, 192, 48, 48, 0, 90)
$path.AddArc(16, 192, 48, 48, 90, 90)
$path.CloseFigure()
$graphics.FillPath($brand, $path)

# Receipt, recurring bill rows, and a coin badge.
$graphics.FillRectangle($paper, 54, 48, 126, 160)
$graphics.FillRectangle($soft, 72, 70, 90, 14)
$graphics.FillRectangle($brand, 72, 101, 66, 9)
$graphics.FillRectangle($brand, 72, 122, 83, 9)
$graphics.FillRectangle($brand, 72, 143, 55, 9)
$graphics.FillEllipse($gold, 146, 150, 70, 70)
$graphics.FillEllipse($paper, 158, 162, 46, 46)
$graphics.FillRectangle($gold, 176, 171, 10, 28)

$iconHandle = $bitmap.GetHicon()
try {
    $icon = [System.Drawing.Icon]::FromHandle($iconHandle)
    $stream = [System.IO.File]::Open($iconPath, [System.IO.FileMode]::Create)
    try { $icon.Save($stream) } finally { $stream.Dispose() }
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
    $brand.Dispose()
    $paper.Dispose()
    $soft.Dispose()
    $gold.Dispose()
    $path.Dispose()
}

$compiler = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($compiler)) {
    throw '没有找到 .NET Framework C# 编译器。'
}

$arguments = @(
    '/nologo',
    '/target:winexe',
    '/platform:anycpu',
    '/optimize+',
    "/win32icon:$iconPath",
    '/reference:System.dll',
    '/reference:System.Windows.Forms.dll',
    "/out:$outputPath",
    $sourcePath
)

& $compiler $arguments
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath)) {
    throw '便携启动器编译失败。'
}

Write-Output $outputPath