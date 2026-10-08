Set-StrictMode -Version Latest

function Get-DefaultCurrencies {
    $updatedAt = '2026-06-17T00:00:00+08:00'
    @(
        [pscustomobject]@{ Code = 'CNY'; Name = '人民币'; Symbol = '¥'; RateToCny = [decimal]1; UpdatedAt = $updatedAt }
        [pscustomobject]@{ Code = 'USD'; Name = '美元'; Symbol = '$'; RateToCny = [decimal]6.759469; UpdatedAt = $updatedAt }
        [pscustomobject]@{ Code = 'EUR'; Name = '欧元'; Symbol = '€'; RateToCny = [decimal]7.834900; UpdatedAt = $updatedAt }
        [pscustomobject]@{ Code = 'GBP'; Name = '英镑'; Symbol = '£'; RateToCny = [decimal]9.061564; UpdatedAt = $updatedAt }
        [pscustomobject]@{ Code = 'JPY'; Name = '日元'; Symbol = '¥'; RateToCny = [decimal]0.042164; UpdatedAt = $updatedAt }
        [pscustomobject]@{ Code = 'HKD'; Name = '港币'; Symbol = 'HK$'; RateToCny = [decimal]0.862675; UpdatedAt = $updatedAt }
    )
}

function New-EmptyBillsData {
    [pscustomobject]@{
        SchemaVersion = 2
        Currencies = @(Get-DefaultCurrencies)
        Bills = @()
    }
}

function ConvertTo-NormalizedCurrency {
    param(
        [Parameter(Mandatory)]
        $Currency
    )

    [pscustomobject]@{
        Code       = ([string]$Currency.Code).Trim().ToUpperInvariant()
        Name       = ([string]$Currency.Name).Trim()
        Symbol     = ([string]$Currency.Symbol).Trim()
        RateToCny  = [decimal]$Currency.RateToCny
        UpdatedAt  = [string]$Currency.UpdatedAt
    }
}

function Read-BillsData {
    param(
        [string]$Path = (Join-Path $PSScriptRoot 'bills.json')
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return New-EmptyBillsData
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return New-EmptyBillsData
    }

    $parsed = $raw | ConvertFrom-Json
    $schemaVersion = if ($parsed.PSObject.Properties.Name -contains 'SchemaVersion') {
        [int]$parsed.SchemaVersion
    }
    else {
        1
    }

    $currencies = if ($schemaVersion -ge 2 -and
        $parsed.PSObject.Properties.Name -contains 'Currencies' -and
        @($parsed.Currencies).Count -gt 0) {
        @($parsed.Currencies | ForEach-Object { ConvertTo-NormalizedCurrency -Currency $_ })
    }
    else {
        @(Get-DefaultCurrencies)
    }

    $normalized = @()
    foreach ($bill in @($parsed.Bills)) {
        if ($null -eq $bill) {
            continue
        }

        $active = $true
        if ($bill.PSObject.Properties.Name -contains 'Active') {
            $active = [bool]$bill.Active
        }

        $currencyCode = 'CNY'
        if ($bill.PSObject.Properties.Name -contains 'Currency' -and
            -not [string]::IsNullOrWhiteSpace([string]$bill.Currency)) {
            $currencyCode = ([string]$bill.Currency).Trim().ToUpperInvariant()
        }

        $override = $null
        if ($bill.PSObject.Properties.Name -contains 'ExchangeRateOverride' -and
            $null -ne $bill.ExchangeRateOverride -and
            -not [string]::IsNullOrWhiteSpace([string]$bill.ExchangeRateOverride)) {
            $override = [decimal]$bill.ExchangeRateOverride
        }

        $normalized += [pscustomobject]@{
            Id                   = if ($bill.Id) { [string]$bill.Id } else { [guid]::NewGuid().ToString() }
            Name                 = [string]$bill.Name
            Payee                = [string]$bill.Payee
            Amount               = [decimal]$bill.Amount
            Currency             = $currencyCode
            ExchangeRateOverride = $override
            Notes                = [string]$bill.Notes
            Active               = $active
            CreatedAt            = [string]$bill.CreatedAt
            UpdatedAt            = [string]$bill.UpdatedAt
        }
    }

    $data = [pscustomobject]@{
        SchemaVersion = 2
        Currencies = @($currencies)
        Bills = @($normalized)
    }
    Test-BillsData -Data $data
    $data
}

function Get-CurrencyDefinition {
    param(
        [Parameter(Mandatory)]
        $Data,
        [Parameter(Mandatory)]
        [string]$Code
    )

    $normalizedCode = $Code.Trim().ToUpperInvariant()
    $matches = @($Data.Currencies | Where-Object { $_.Code -eq $normalizedCode })
    if ($matches.Count -eq 0) {
        throw "不支持币种 $normalizedCode。请先在汇率设置中添加。"
    }
    if ($matches.Count -gt 1) {
        throw "币种 $normalizedCode 存在重复定义。"
    }
    $matches[0]
}

function Test-BillsData {
    param(
        [Parameter(Mandatory)]
        $Data
    )

    if ([int]$Data.SchemaVersion -ne 2) {
        throw '数据 SchemaVersion 必须为 2。'
    }

    $currencyCodes = @{}
    foreach ($currency in @($Data.Currencies)) {
        $code = ([string]$currency.Code).Trim().ToUpperInvariant()
        if ($code -notmatch '^[A-Z]{3}$') {
            throw "币种代码【$code】必须是三个大写英文字母。"
        }
        if ($currencyCodes.ContainsKey($code)) {
            throw "发现重复的币种代码：$code"
        }
        if ([string]::IsNullOrWhiteSpace([string]$currency.Name)) {
            throw "币种 $code 的名称不能为空。"
        }
        if ([string]::IsNullOrWhiteSpace([string]$currency.Symbol)) {
            throw "币种 $code 的符号不能为空。"
        }
        if ([decimal]$currency.RateToCny -le 0) {
            throw "币种 $code 的兑人民币汇率必须大于 0。"
        }
        if ($code -eq 'CNY' -and [decimal]$currency.RateToCny -ne 1) {
            throw 'CNY 汇率固定为 1。'
        }
        $currencyCodes[$code] = $true
    }
    if (-not $currencyCodes.ContainsKey('CNY')) {
        throw '币种表必须包含 CNY。'
    }

    $ids = @{}
    foreach ($bill in @($Data.Bills)) {
        if ([string]::IsNullOrWhiteSpace([string]$bill.Name)) {
            throw '项目名称不能为空。'
        }
        if ([decimal]$bill.Amount -le 0) {
            throw "项目【$($bill.Name)】的金额必须大于 0。"
        }
        $code = ([string]$bill.Currency).Trim().ToUpperInvariant()
        if (-not $currencyCodes.ContainsKey($code)) {
            throw "项目【$($bill.Name)】使用了未定义币种 $code。"
        }
        if ($null -ne $bill.ExchangeRateOverride) {
            if ($code -eq 'CNY') {
                throw "人民币项目【$($bill.Name)】不能设置自定义汇率。"
            }
            if ([decimal]$bill.ExchangeRateOverride -le 0) {
                throw "项目【$($bill.Name)】的自定义汇率必须大于 0。"
            }
        }
        if ([string]::IsNullOrWhiteSpace([string]$bill.Id)) {
            throw "项目【$($bill.Name)】缺少 ID。"
        }
        if ($ids.ContainsKey([string]$bill.Id)) {
            throw "发现重复的项目 ID：$($bill.Id)"
        }
        $ids[[string]$bill.Id] = $true
    }
}

function Write-BillsData {
    param(
        [Parameter(Mandatory)]
        $Data,
        [string]$Path = (Join-Path $PSScriptRoot 'bills.json')
    )

    $Data.SchemaVersion = 2
    Test-BillsData -Data $Data

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $Path) {
        try {
            $existingRaw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            $existing = $existingRaw | ConvertFrom-Json
            $existingVersion = if ($existing.PSObject.Properties.Name -contains 'SchemaVersion') {
                [int]$existing.SchemaVersion
            }
            else {
                1
            }
            if ($existingVersion -lt 2) {
                $backupPath = Join-Path $parent (([IO.Path]::GetFileNameWithoutExtension($Path)) + '.schema-v1.backup.json')
                if (-not (Test-Path -LiteralPath $backupPath)) {
                    Copy-Item -LiteralPath $Path -Destination $backupPath
                }
            }
        }
        catch {
            throw "写入前无法检查旧数据版本：$($_.Exception.Message)"
        }
    }

    $json = $Data | ConvertTo-Json -Depth 8
    $tempPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $replaceBackupPath = "$Path.bak"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    try {
        [System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)
        if (Test-Path -LiteralPath $Path) {
            try {
                [System.IO.File]::Replace($tempPath, $Path, $replaceBackupPath, $true)
                Remove-Item -LiteralPath $replaceBackupPath -Force -ErrorAction SilentlyContinue
            }
            catch {
                Move-Item -LiteralPath $tempPath -Destination $Path -Force
            }
        }
        else {
            Move-Item -LiteralPath $tempPath -Destination $Path
        }
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

function New-BillRecord {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$Payee = '',
        [Parameter(Mandatory)]
        [decimal]$Amount,
        [string]$Currency = 'CNY',
        [Nullable[decimal]]$ExchangeRateOverride = $null,
        [string]$Notes = ''
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw '项目名称不能为空。'
    }
    if ($Amount -le 0) {
        throw '金额必须大于 0。'
    }

    $currencyCode = $Currency.Trim().ToUpperInvariant()
    if ($currencyCode -notmatch '^[A-Z]{3}$') {
        throw '币种代码必须是三个大写英文字母。'
    }
    if ($currencyCode -eq 'CNY' -and $null -ne $ExchangeRateOverride) {
        throw '人民币项目不能设置自定义汇率。'
    }
    if ($null -ne $ExchangeRateOverride -and $ExchangeRateOverride -le 0) {
        throw '自定义汇率必须大于 0。'
    }

    $now = (Get-Date).ToString('o')
    [pscustomobject]@{
        Id                   = [guid]::NewGuid().ToString()
        Name                 = $Name.Trim()
        Payee                = $Payee.Trim()
        Amount               = [decimal]$Amount
        Currency             = $currencyCode
        ExchangeRateOverride = if ($null -eq $ExchangeRateOverride) { $null } else { [decimal]$ExchangeRateOverride }
        Notes                = $Notes.Trim()
        Active               = $true
        CreatedAt            = $now
        UpdatedAt            = $now
    }
}

function Get-ActiveBills {
    param(
        [Parameter(Mandatory)]
        $Data
    )

    @($Data.Bills | Where-Object { $_.Active } | Sort-Object Name, Payee)
}

function Get-EffectiveExchangeRate {
    param(
        [Parameter(Mandatory)]
        $Data,
        [Parameter(Mandatory)]
        $Bill
    )

    if ($null -ne $Bill.ExchangeRateOverride) {
        return [decimal]$Bill.ExchangeRateOverride
    }
    [decimal](Get-CurrencyDefinition -Data $Data -Code $Bill.Currency).RateToCny
}

function Get-BillCnyAmount {
    param(
        [Parameter(Mandatory)]
        $Data,
        [Parameter(Mandatory)]
        $Bill
    )

    $converted = [decimal]$Bill.Amount * (Get-EffectiveExchangeRate -Data $Data -Bill $Bill)
    [decimal]::Round($converted, 2, [System.MidpointRounding]::AwayFromZero)
}

function Get-MonthlyTotal {
    param(
        [Parameter(Mandatory)]
        $Data
    )

    [decimal]$total = 0
    foreach ($bill in @($Data.Bills)) {
        if ($bill.Active) {
            $total += Get-BillCnyAmount -Data $Data -Bill $bill
        }
    }
    $total
}

function Get-CurrencySubtotals {
    param(
        [Parameter(Mandatory)]
        $Data
    )

    $results = @()
    foreach ($group in @($Data.Bills | Where-Object Active | Group-Object Currency | Sort-Object Name)) {
        [decimal]$originalTotal = 0
        [decimal]$cnyTotal = 0
        foreach ($bill in @($group.Group)) {
            $originalTotal += [decimal]$bill.Amount
            $cnyTotal += Get-BillCnyAmount -Data $Data -Bill $bill
        }
        $currency = Get-CurrencyDefinition -Data $Data -Code $group.Name
        $results += [pscustomobject]@{
            Currency      = $group.Name
            Name          = $currency.Name
            Symbol        = $currency.Symbol
            OriginalTotal = $originalTotal
            CnyTotal      = $cnyTotal
            ItemCount     = @($group.Group).Count
        }
    }
    @($results)
}

function Add-CurrencyDefinition {
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Symbol,
        [Parameter(Mandatory)][decimal]$RateToCny
    )

    $normalizedCode = $Code.Trim().ToUpperInvariant()
    if (@($Data.Currencies | Where-Object Code -eq $normalizedCode).Count -gt 0) {
        throw "币种 $normalizedCode 已存在。"
    }
    $Data.Currencies = @($Data.Currencies) + [pscustomobject]@{
        Code = $normalizedCode
        Name = $Name.Trim()
        Symbol = $Symbol.Trim()
        RateToCny = $RateToCny
        UpdatedAt = (Get-Date).ToString('o')
    }
    Test-BillsData -Data $Data
}

function Update-CurrencyDefinition {
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Symbol,
        [Parameter(Mandatory)][decimal]$RateToCny
    )

    $currency = Get-CurrencyDefinition -Data $Data -Code $Code
    if ($currency.Code -eq 'CNY') {
        if ($RateToCny -ne 1) {
            throw 'CNY 汇率固定为 1。'
        }
        $currency.Name = '人民币'
        $currency.Symbol = '¥'
    }
    else {
        $currency.Name = $Name.Trim()
        $currency.Symbol = $Symbol.Trim()
        $currency.RateToCny = $RateToCny
    }
    $currency.UpdatedAt = (Get-Date).ToString('o')
    Test-BillsData -Data $Data
}

function Remove-CurrencyDefinition {
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][string]$Code
    )

    $normalizedCode = $Code.Trim().ToUpperInvariant()
    if ($normalizedCode -eq 'CNY') {
        throw 'CNY 是基准币种，不能删除。'
    }
    $null = Get-CurrencyDefinition -Data $Data -Code $normalizedCode
    $usageCount = @($Data.Bills | Where-Object Currency -eq $normalizedCode).Count
    if ($usageCount -gt 0) {
        throw "币种 $normalizedCode 正被 $usageCount 个账单项目使用，不能删除。"
    }
    $Data.Currencies = @($Data.Currencies | Where-Object Code -ne $normalizedCode)
    Test-BillsData -Data $Data
}

function Find-OneBill {
    param(
        [Parameter(Mandatory)]
        $Data,
        [string]$Id,
        [string]$Name
    )

    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        $matches = @($Data.Bills | Where-Object { $_.Id -eq $Id })
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Name)) {
        $matches = @($Data.Bills | Where-Object { $_.Name -eq $Name })
    }
    else {
        throw '必须提供项目 ID 或准确的项目名称。'
    }

    if ($matches.Count -eq 0) {
        throw '没有找到对应的账单项目。'
    }
    if ($matches.Count -gt 1) {
        throw '找到多个同名项目，请改用项目 ID 指定。'
    }
    $matches[0]
}

function Get-NextMonthlyRun {
    param(
        [Parameter(Mandatory)]
        [int]$Day,
        [Parameter(Mandatory)]
        [int]$Hour,
        [Parameter(Mandatory)]
        [int]$Minute,
        [Parameter(Mandatory)]
        [int]$Second,
        [datetime]$Now = (Get-Date)
    )

    if ($Day -lt 1 -or $Day -gt 28) {
        throw '每月日期必须在 1—28 之间。'
    }
    if ($Hour -lt 0 -or $Hour -gt 23) {
        throw '小时必须在 0—23 之间。'
    }
    if ($Minute -lt 0 -or $Minute -gt 59) {
        throw '分钟必须在 0—59 之间。'
    }
    if ($Second -lt 0 -or $Second -gt 59) {
        throw '秒必须在 0—59 之间。'
    }

    $candidate = [datetime]::new($Now.Year, $Now.Month, $Day, $Hour, $Minute, $Second, $Now.Kind)
    if ($candidate -le $Now) {
        $candidate = $candidate.AddMonths(1)
    }
    $candidate
}
