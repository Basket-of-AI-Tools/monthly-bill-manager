Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

$testRoot = Join-Path $env:TEMP "MonthlyBills-Test-$([guid]::NewGuid().ToString('N'))"
$dataPath = Join-Path $testRoot 'bills.json'
$reportDirectory = Join-Path $testRoot 'reports'
$passed = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "断言失败：$Message" }
    $script:passed++
}

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw "断言失败：$Message；实际值=$Actual，期望值=$Expected"
    }
    $script:passed++
}

function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $threw = $false
    try { & $Action } catch { $threw = $true }
    Assert-True $threw $Message
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    $empty = Read-BillsData -Path $dataPath
    Assert-Equal $empty.SchemaVersion 2 '不存在的数据文件应返回 v2 数据'
    Assert-Equal $empty.Bills.Count 0 '不存在的数据文件应返回空账单'
    Assert-Equal $empty.Currencies.Count 6 '默认应包含六种币种'
    Assert-Equal (Get-MonthlyTotal -Data $empty) 0 '空账单合计应为 0'

    $legacy = [pscustomobject]@{
        SchemaVersion = 1
        Bills = @(
            [pscustomobject]@{
                Id = [guid]::NewGuid().ToString()
                Name = '旧人民币账单'
                Payee = '测试'
                Amount = 39
                Currency = 'CNY'
                Notes = ''
                Active = $true
                CreatedAt = '2026-01-01'
                UpdatedAt = '2026-01-01'
            }
        )
    }
    $legacy | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $dataPath -Encoding utf8
    $migrated = Read-BillsData -Path $dataPath
    Assert-Equal $migrated.SchemaVersion 2 '读取 v1 数据时应在内存中迁移到 v2'
    Assert-Equal $migrated.Bills[0].Currency 'CNY' '旧账单应迁移为 CNY'
    Assert-True ($null -eq $migrated.Bills[0].ExchangeRateOverride) '旧账单不应设置汇率覆盖'
    Assert-Equal (Get-MonthlyTotal -Data $migrated) 39 '迁移前后人民币总额应一致'
    Write-BillsData -Data $migrated -Path $dataPath
    Assert-True (Test-Path -LiteralPath (Join-Path $testRoot 'bills.schema-v1.backup.json')) '首次写入 v2 前应保存 v1 备份'
    Assert-Equal ((Get-Content -LiteralPath $dataPath -Raw -Encoding utf8 | ConvertFrom-Json).SchemaVersion) 2 '写入后文件版本应为 2'

    $data = New-EmptyBillsData
    $phone = New-BillRecord -Name '中国移动套餐' -Payee '中国移动' -Amount 39 -Currency CNY -Notes '测试'
    $usdGlobal = New-BillRecord -Name '美元订阅' -Payee 'Global' -Amount 10 -Currency USD
    $usdOverride = New-BillRecord -Name '锁定美元订阅' -Payee 'Global' -Amount 10 -Currency USD -ExchangeRateOverride 7
    $inactiveEur = New-BillRecord -Name '停用欧元订阅' -Amount 5 -Currency EUR
    $inactiveEur.Active = $false
    $data.Bills = @($phone, $usdGlobal, $usdOverride, $inactiveEur)
    Write-BillsData -Data $data -Path $dataPath

    $loaded = Read-BillsData -Path $dataPath
    Assert-Equal $loaded.Bills.Count 4 '应能读回多币种项目'
    Assert-Equal (Get-EffectiveExchangeRate -Data $loaded -Bill ($loaded.Bills | Where-Object Name -eq '美元订阅')) ([decimal]6.759469) '无覆盖时应使用全局汇率'
    Assert-Equal (Get-EffectiveExchangeRate -Data $loaded -Bill ($loaded.Bills | Where-Object Name -eq '锁定美元订阅')) ([decimal]7) '项目覆盖应优先于全局汇率'
    Assert-Equal (Get-BillCnyAmount -Data $loaded -Bill ($loaded.Bills | Where-Object Name -eq '美元订阅')) ([decimal]67.59) '单项人民币金额应四舍五入到两位'
    Assert-Equal (Get-MonthlyTotal -Data $loaded) ([decimal]176.59) '人民币总额应汇总逐项折算值并忽略停用项目'

    $subtotals = @(Get-CurrencySubtotals -Data $loaded)
    Assert-Equal $subtotals.Count 2 '停用币种不应出现在有效小计中'
    $usdSubtotal = $subtotals | Where-Object Currency -eq 'USD'
    Assert-Equal $usdSubtotal.OriginalTotal ([decimal]20) 'USD 原币小计应正确'
    Assert-Equal $usdSubtotal.CnyTotal ([decimal]137.59) 'USD 人民币小计应包含全局及覆盖汇率'

    $usd = Get-CurrencyDefinition -Data $loaded -Code USD
    $usd.RateToCny = [decimal]8
    $usd.UpdatedAt = (Get-Date).ToString('o')
    Write-BillsData -Data $loaded -Path $dataPath
    $rerated = Read-BillsData -Path $dataPath
    Assert-Equal (Get-BillCnyAmount -Data $rerated -Bill ($rerated.Bills | Where-Object Name -eq '美元订阅')) ([decimal]80) '修改全局汇率后普通项目应更新'
    Assert-Equal (Get-BillCnyAmount -Data $rerated -Bill ($rerated.Bills | Where-Object Name -eq '锁定美元订阅')) ([decimal]70) '修改全局汇率不应影响覆盖项目'

    $overrideBill = $rerated.Bills | Where-Object Name -eq '锁定美元订阅'
    $overrideBill.ExchangeRateOverride = $null
    Assert-Equal (Get-BillCnyAmount -Data $rerated -Bill $overrideBill) ([decimal]80) '取消覆盖后应恢复全局汇率'

    Add-CurrencyDefinition -Data $rerated -Code aud -Name '澳元' -Symbol 'A$' -RateToCny 4.8
    Assert-Equal (Get-CurrencyDefinition -Data $rerated -Code AUD).Code 'AUD' '新增币种代码应标准化为大写'
    Update-CurrencyDefinition -Data $rerated -Code AUD -Name '澳大利亚元' -Symbol 'A$' -RateToCny 4.9
    Assert-Equal (Get-CurrencyDefinition -Data $rerated -Code AUD).RateToCny ([decimal]4.9) '应能修改全局汇率'
    Remove-CurrencyDefinition -Data $rerated -Code AUD
    Assert-Throws { Get-CurrencyDefinition -Data $rerated -Code AUD } '删除后币种应不存在'

    Assert-Throws { Add-CurrencyDefinition -Data $rerated -Code US -Name '错误' -Symbol '?' -RateToCny 1 } '非法币种代码应被拒绝'
    Assert-Throws { Add-CurrencyDefinition -Data $rerated -Code AUD -Name '澳元' -Symbol 'A$' -RateToCny 0 } '非正数汇率应被拒绝'
    Assert-Throws { Update-CurrencyDefinition -Data $rerated -Code CNY -Name '人民币' -Symbol '¥' -RateToCny 2 } 'CNY 汇率不可修改'
    Assert-Throws { Remove-CurrencyDefinition -Data $rerated -Code CNY } 'CNY 不可删除'
    Assert-Throws { Remove-CurrencyDefinition -Data $rerated -Code USD } '使用中的币种不可删除'

    $badCnyOverride = New-EmptyBillsData
    $badBill = New-BillRecord -Name '错误人民币覆盖' -Amount 10
    $badBill.ExchangeRateOverride = 2
    $badCnyOverride.Bills = @($badBill)
    Assert-Throws { Write-BillsData -Data $badCnyOverride -Path (Join-Path $testRoot 'bad.json') } 'CNY 项目不可设置覆盖汇率'

    $reportPath = & (Join-Path $PSScriptRoot 'Generate-Report.ps1') -DataPath $dataPath -OutputDirectory $reportDirectory -NoOpen -NoPopup
    Assert-True (Test-Path -LiteralPath $reportPath) '应生成 HTML 报表'
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
    Assert-True $report.Contains('币种小计') '报表应包含币种小计'
    Assert-True $report.Contains('美元订阅') '报表应包含有效外币项目'
    Assert-True (-not $report.Contains('停用欧元订阅')) '报表不应包含停用项目'
    Assert-True $report.Contains('USD') '报表应显示原币币种'
    Assert-True $report.Contains('¥189.00') '报表人民币总额应与当前汇率一致'

    $beforeTime = Get-Date '2026-06-18 18:30:00'
    $nextThisMonth = Get-NextMonthlyRun -Day 20 -Hour 9 -Minute 8 -Second 7 -Now $beforeTime
    Assert-Equal $nextThisMonth (Get-Date '2026-06-20 09:08:07') '未来日期应安排在当月'
    $nextMonth = Get-NextMonthlyRun -Day 1 -Hour 20 -Minute 0 -Second 0 -Now $beforeTime
    Assert-Equal $nextMonth (Get-Date '2026-07-01 20:00:00') '已过日期应安排在下月'
    Assert-Throws { Get-NextMonthlyRun -Day 29 -Hour 0 -Minute 0 -Second 0 } '日期超过 28 应被拒绝'
    Assert-Throws { Get-NextMonthlyRun -Day 1 -Hour 24 -Minute 0 -Second 0 } '小时超过 23 应被拒绝'
    Assert-Throws { Get-NextMonthlyRun -Day 1 -Hour 0 -Minute 60 -Second 0 } '分钟超过 59 应被拒绝'
    Assert-Throws { Get-NextMonthlyRun -Day 1 -Hour 0 -Minute 0 -Second 60 } '秒超过 59 应被拒绝'

    $parseErrors = @()
    foreach ($scriptPath in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath.FullName, [ref]$tokens, [ref]$errors)
        $parseErrors += @($errors)
    }
    Assert-Equal $parseErrors.Count 0 '所有 PowerShell 脚本应通过语法检查'

    Write-Host "测试通过：$passed 项断言。"
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
