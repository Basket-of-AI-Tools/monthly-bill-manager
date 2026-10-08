param(
    [switch]$SkipTask,
    [switch]$SkipShortcut
)

Set-StrictMode -Version Latest
$appRoot = $PSScriptRoot
$pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
$powerShellPath = if ($pwshCommand) { $pwshCommand.Source } else {
    $windowsPowerShellPath = Join-Path ([Environment]::GetFolderPath('Windows')) 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $windowsPowerShellPath) { $windowsPowerShellPath } else {
        (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    }
}
if ([string]::IsNullOrWhiteSpace($powerShellPath)) {
    throw '没有找到 PowerShell 7 或 Windows PowerShell。'
}

if (-not $SkipShortcut) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop '月费账单管理器.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powerShellPath
    $shortcut.Arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $appRoot 'MonthlyBills.ps1')
    $shortcut.WorkingDirectory = $appRoot
    $shortcut.Description = '新增、修改和查看固定月费账单'
    $shortcut.IconLocation = "$env:SystemRoot\System32\imageres.dll,102"
    $shortcut.Save()
    Write-Host "桌面快捷方式已创建：$shortcutPath"
}

if (-not $SkipTask) {
    $scheduleScript = Join-Path $appRoot 'Reminder-Schedule.ps1'
    try {
        $existing = & $scheduleScript Get -ErrorAction Stop
        $day = $existing.Day
        $hour = $existing.Hour
        $minute = $existing.Minute
        $second = $existing.Second
    }
    catch {
        $day = 1
        $hour = 20
        $minute = 0
        $second = 0
    }

    $configuration = & $scheduleScript Set -Day $day -Hour $hour -Minute $minute -Second $second
    Write-Host ('计划任务已创建或更新：每月 {0} 日 {1:00}:{2:00}:{3:00}' -f $configuration.Day, $configuration.Hour, $configuration.Minute, $configuration.Second)
}
