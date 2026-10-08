param(
    [string]$DataPath = (Join-Path $PSScriptRoot 'bills.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '报表'),
    [switch]$NoOpen,
    [switch]$NoPopup
)

Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')

$data = Read-BillsData -Path $DataPath
$activeBills = @(Get-ActiveBills -Data $data)
$subtotals = @(Get-CurrencySubtotals -Data $data)
$total = Get-MonthlyTotal -Data $data
$month = Get-Date -Format 'yyyy-MM'
$generatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportPath = Join-Path $OutputDirectory "$month.html"

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$rows = if ($activeBills.Count -eq 0) {
    '<tr><td colspan="7" class="empty">暂无有效月费账单</td></tr>'
}
else {
    ($activeBills | ForEach-Object {
        $currency = Get-CurrencyDefinition -Data $data -Code $_.Currency
        $rate = Get-EffectiveExchangeRate -Data $data -Bill $_
        $cnyAmount = Get-BillCnyAmount -Data $data -Bill $_
        $rateSource = if ($null -ne $_.ExchangeRateOverride) { '项目自定义' } else { '全局' }
        $name = [System.Net.WebUtility]::HtmlEncode([string]$_.Name)
        $payee = [System.Net.WebUtility]::HtmlEncode([string]$_.Payee)
        $notes = [System.Net.WebUtility]::HtmlEncode([string]$_.Notes)
        $symbol = [System.Net.WebUtility]::HtmlEncode([string]$currency.Symbol)
        '<tr><td>{0}</td><td>{1}</td><td class="money">{2}{3:N2}</td><td>{4}</td><td class="money">{5:N6}<span class="muted"> {6}</span></td><td class="money">¥{7:N2}</td><td>{8}</td></tr>' -f `
            $name, $payee, $symbol, ([decimal]$_.Amount), $_.Currency, $rate, $rateSource, $cnyAmount, $notes
    }) -join [Environment]::NewLine
}

$subtotalRows = if ($subtotals.Count -eq 0) {
    '<tr><td colspan="4" class="empty">暂无币种小计</td></tr>'
}
else {
    ($subtotals | ForEach-Object {
        $symbol = [System.Net.WebUtility]::HtmlEncode([string]$_.Symbol)
        '<tr><td>{0} · {1}</td><td>{2}</td><td class="money">{3}{4:N2}</td><td class="money">¥{5:N2}</td></tr>' -f `
            $_.Currency, ([System.Net.WebUtility]::HtmlEncode([string]$_.Name)), $_.ItemCount, $symbol, $_.OriginalTotal, $_.CnyTotal
    }) -join [Environment]::NewLine
}

$html = @"
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$month 月费账单</title>
<style>
body { font-family: "Segoe UI", "Microsoft YaHei", sans-serif; background: #f5f7fa; color: #1f2937; margin: 0; padding: 32px; }
.card { max-width: 1160px; margin: 0 auto; background: white; border-radius: 14px; box-shadow: 0 8px 24px rgba(0,0,0,.08); overflow: hidden; }
header { padding: 28px 32px 20px; background: #174ea6; color: white; }
h1 { margin: 0 0 8px; font-size: 26px; }
h2 { margin: 28px 32px 4px; font-size: 18px; }
.meta { opacity: .86; font-size: 14px; }
.summary { display: flex; gap: 36px; padding: 22px 32px; background: #eef4ff; }
.summary strong { display: block; font-size: 25px; color: #174ea6; margin-top: 4px; }
table { width: calc(100% - 64px); margin: 14px 32px 30px; border-collapse: collapse; }
th, td { padding: 12px 10px; border-bottom: 1px solid #e5e7eb; text-align: left; vertical-align: top; }
th { color: #4b5563; font-size: 13px; }
.money { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
.muted { color: #6b7280; font-size: 11px; }
.empty { text-align: center; color: #6b7280; padding: 36px; }
footer { padding: 0 32px 26px; color: #6b7280; font-size: 12px; }
</style>
</head>
<body>
<main class="card">
<header><h1>$month 月费账单</h1><div class="meta">生成时间：$generatedAt</div></header>
<section class="summary">
<div>有效项目<strong>$($activeBills.Count)</strong></div>
<div>人民币月费合计<strong>¥$('{0:N2}' -f $total)</strong></div>
</section>
<h2>币种小计</h2>
<table>
<thead><tr><th>币种</th><th>项目数</th><th class="money">原币小计</th><th class="money">折合人民币</th></tr></thead>
<tbody>
$subtotalRows
</tbody>
</table>
<h2>账单明细</h2>
<table>
<thead><tr><th>项目</th><th>收款方</th><th class="money">原币金额</th><th>币种</th><th class="money">兑人民币汇率</th><th class="money">折合人民币</th><th>备注</th></tr></thead>
<tbody>
$rows
</tbody>
</table>
<footer>汇率定义：1 单位原币 = X CNY。每项折合人民币先四舍五入至两位后再汇总。</footer>
</main>
</body>
</html>
"@

$tempPath = "$reportPath.$([guid]::NewGuid().ToString('N')).tmp"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
try {
    [System.IO.File]::WriteAllText($tempPath, $html, $utf8NoBom)
    Move-Item -LiteralPath $tempPath -Destination $reportPath -Force
}
finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
}

if (-not $NoOpen) {
    Start-Process -FilePath $reportPath
}

if (-not $NoPopup) {
    $message = "有效项目：$($activeBills.Count) 项$([Environment]::NewLine)$([Environment]::NewLine)人民币月费合计：¥$('{0:N2}' -f $total)$([Environment]::NewLine)$([Environment]::NewLine)详细原币金额和币种小计已写入本月报表。"
    $shell = New-Object -ComObject WScript.Shell
    $null = $shell.Popup($message, 30, "$month 月费账单", 64)
}

Write-Output $reportPath
