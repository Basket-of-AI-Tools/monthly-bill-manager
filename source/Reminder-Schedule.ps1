param(
    [Parameter(Position = 0)]
    [ValidateSet('Get', 'Set', 'Test')]
    [string]$Action = 'Get',
    [int]$Day,
    [int]$Hour,
    [int]$Minute,
    [int]$Second
)

Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')

$taskName = '月费账单提醒'
$reportScript = Join-Path $PSScriptRoot 'Generate-Report.ps1'
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

function Get-ReminderConfiguration {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop
    [xml]$taskXml = Export-ScheduledTask -TaskName $taskName
    $namespace = New-Object System.Xml.XmlNamespaceManager($taskXml.NameTable)
    $namespace.AddNamespace('t', $taskXml.DocumentElement.NamespaceURI)

    $startNode = $taskXml.SelectSingleNode('//t:CalendarTrigger/t:StartBoundary', $namespace)
    $dayNode = $taskXml.SelectSingleNode('//t:ScheduleByMonth/t:DaysOfMonth/t:Day', $namespace)
    if ($null -eq $startNode -or $null -eq $dayNode) {
        throw '现有提醒任务不是受支持的每月单日计划。'
    }

    $start = [datetime]::Parse($startNode.InnerText, [System.Globalization.CultureInfo]::InvariantCulture)
    [pscustomobject]@{
        TaskName           = $taskName
        Day                = [int]$dayNode.InnerText
        Hour               = $start.Hour
        Minute             = $start.Minute
        Second             = $start.Second
        NextRunTime        = $taskInfo.NextRunTime
        State              = [string]$task.State
        RunLevel           = [string]$task.Principal.RunLevel
        LogonType          = [string]$task.Principal.LogonType
        StartWhenAvailable = [bool]$task.Settings.StartWhenAvailable
    }
}

function Set-ReminderConfiguration {
    param(
        [Parameter(Mandatory)][int]$ScheduleDay,
        [Parameter(Mandatory)][int]$ScheduleHour,
        [Parameter(Mandatory)][int]$ScheduleMinute,
        [Parameter(Mandatory)][int]$ScheduleSecond
    )

    $firstRun = Get-NextMonthlyRun -Day $ScheduleDay -Hour $ScheduleHour -Minute $ScheduleMinute -Second $ScheduleSecond
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $folder = $service.GetFolder('\')
    $task = $service.NewTask(0)

    $task.RegistrationInfo.Description = '每月 {0} 日 {1:00}:{2:00}:{3:00} 显示固定月费账单汇总，并生成本地 HTML 报表。' -f $ScheduleDay, $ScheduleHour, $ScheduleMinute, $ScheduleSecond
    $task.Settings.Enabled = $true
    $task.Settings.StartWhenAvailable = $true
    $task.Settings.AllowDemandStart = $true
    $task.Settings.DisallowStartIfOnBatteries = $false
    $task.Settings.StopIfGoingOnBatteries = $false
    $task.Settings.ExecutionTimeLimit = 'PT10M'
    $task.Settings.MultipleInstances = 2

    $userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $task.Principal.UserId = $userName
    $task.Principal.LogonType = 3
    $task.Principal.RunLevel = 0

    $trigger = $task.Triggers.Create(4)
    $trigger.StartBoundary = $firstRun.ToString('yyyy-MM-ddTHH:mm:ss')
    $trigger.DaysOfMonth = [int](1 -shl ($ScheduleDay - 1))
    $trigger.MonthsOfYear = 4095
    $trigger.Enabled = $true

    $taskAction = $task.Actions.Create(0)
    $taskAction.Path = $powerShellPath
    $taskAction.Arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $reportScript
    $taskAction.WorkingDirectory = $PSScriptRoot

    $null = $folder.RegisterTaskDefinition($taskName, $task, 6, $userName, $null, 3, $null)
    Get-ReminderConfiguration
}

function Start-ReminderTest {
    $arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $reportScript
    $process = Start-Process -FilePath $powerShellPath -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -PassThru
    [pscustomobject]@{
        Started   = $true
        ProcessId = $process.Id
    }
}

switch ($Action) {
    'Get' {
        Get-ReminderConfiguration
    }
    'Set' {
        if (-not $PSBoundParameters.ContainsKey('Day') -or
            -not $PSBoundParameters.ContainsKey('Hour') -or
            -not $PSBoundParameters.ContainsKey('Minute') -or
            -not $PSBoundParameters.ContainsKey('Second')) {
            throw 'Set 操作必须同时提供 Day、Hour、Minute 和 Second。'
        }
        Set-ReminderConfiguration -ScheduleDay $Day -ScheduleHour $Hour -ScheduleMinute $Minute -ScheduleSecond $Second
    }
    'Test' {
        Start-ReminderTest
    }
}
