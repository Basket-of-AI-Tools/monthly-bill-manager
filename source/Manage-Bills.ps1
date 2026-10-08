param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('List', 'Add', 'Update', 'Disable', 'Enable', 'Delete')]
    [string]$Action,
    [string]$Id,
    [string]$Name,
    [string]$Payee,
    [decimal]$Amount,
    [string]$Currency,
    [decimal]$ExchangeRateOverride,
    [switch]$ClearExchangeRateOverride,
    [string]$Notes,
    [string]$DataPath = (Join-Path $PSScriptRoot 'bills.json')
)

Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')

$data = Read-BillsData -Path $DataPath

switch ($Action) {
    'List' {
        $data.Bills |
            Sort-Object @{ Expression = 'Active'; Descending = $true }, Name |
            ForEach-Object {
                [pscustomobject]@{
                    Id                    = $_.Id
                    Name                  = $_.Name
                    Payee                 = $_.Payee
                    Amount                = $_.Amount
                    Currency              = $_.Currency
                    EffectiveRateToCny    = Get-EffectiveExchangeRate -Data $data -Bill $_
                    ExchangeRateOverride  = $_.ExchangeRateOverride
                    CnyAmount             = Get-BillCnyAmount -Data $data -Bill $_
                    Active                = $_.Active
                    Notes                 = $_.Notes
                }
            }
        Write-Host ('每月有效账单人民币合计：¥{0:N2}' -f (Get-MonthlyTotal -Data $data))
        return
    }
    'Add' {
        if (-not $PSBoundParameters.ContainsKey('Amount')) {
            throw '新增项目必须提供 Amount。'
        }
        $currencyCode = if ($PSBoundParameters.ContainsKey('Currency')) { $Currency } else { 'CNY' }
        $null = Get-CurrencyDefinition -Data $data -Code $currencyCode
        $override = if ($PSBoundParameters.ContainsKey('ExchangeRateOverride')) {
            [Nullable[decimal]]$ExchangeRateOverride
        }
        else {
            $null
        }
        $bill = New-BillRecord -Name $Name -Payee $Payee -Amount $Amount -Currency $currencyCode -ExchangeRateOverride $override -Notes $Notes
        $data.Bills = @($data.Bills) + $bill
    }
    'Update' {
        $bill = Find-OneBill -Data $data -Id $Id -Name $Name
        if ($PSBoundParameters.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace($Id)) {
            if ([string]::IsNullOrWhiteSpace($Name)) { throw '项目名称不能为空。' }
            $bill.Name = $Name.Trim()
        }
        if ($PSBoundParameters.ContainsKey('Payee')) { $bill.Payee = $Payee.Trim() }
        if ($PSBoundParameters.ContainsKey('Amount')) {
            if ($Amount -le 0) { throw '金额必须大于 0。' }
            $bill.Amount = $Amount
        }
        if ($PSBoundParameters.ContainsKey('Currency')) {
            $currencyDefinition = Get-CurrencyDefinition -Data $data -Code $Currency
            $bill.Currency = $currencyDefinition.Code
            if ($bill.Currency -eq 'CNY') {
                $bill.ExchangeRateOverride = $null
            }
        }
        if ($ClearExchangeRateOverride) {
            $bill.ExchangeRateOverride = $null
        }
        elseif ($PSBoundParameters.ContainsKey('ExchangeRateOverride')) {
            if ($bill.Currency -eq 'CNY') { throw '人民币项目不能设置自定义汇率。' }
            if ($ExchangeRateOverride -le 0) { throw '自定义汇率必须大于 0。' }
            $bill.ExchangeRateOverride = $ExchangeRateOverride
        }
        if ($PSBoundParameters.ContainsKey('Notes')) { $bill.Notes = $Notes.Trim() }
        $bill.UpdatedAt = (Get-Date).ToString('o')
    }
    'Disable' {
        $bill = Find-OneBill -Data $data -Id $Id -Name $Name
        $bill.Active = $false
        $bill.UpdatedAt = (Get-Date).ToString('o')
    }
    'Enable' {
        $bill = Find-OneBill -Data $data -Id $Id -Name $Name
        $bill.Active = $true
        $bill.UpdatedAt = (Get-Date).ToString('o')
    }
    'Delete' {
        $bill = Find-OneBill -Data $data -Id $Id -Name $Name
        $data.Bills = @($data.Bills | Where-Object { $_.Id -ne $bill.Id })
    }
}

Write-BillsData -Data $data -Path $DataPath
Write-Host ('操作完成。每月有效账单人民币合计：¥{0:N2}' -f (Get-MonthlyTotal -Data $data))
