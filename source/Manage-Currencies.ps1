param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('List', 'Add', 'Update', 'Delete')]
    [string]$Action,
    [string]$Code,
    [string]$Name,
    [string]$Symbol,
    [decimal]$RateToCny,
    [string]$DataPath = (Join-Path $PSScriptRoot 'bills.json')
)

Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')

$data = Read-BillsData -Path $DataPath

switch ($Action) {
    'List' {
        $data.Currencies |
            Sort-Object @{ Expression = { if ($_.Code -eq 'CNY') { 0 } else { 1 } } }, Code |
            Select-Object Code, Name, Symbol, @{ Name = 'RateToCny'; Expression = { '{0:0.######}' -f [decimal]$_.RateToCny } }, UpdatedAt
        return
    }
    'Add' {
        if (-not $PSBoundParameters.ContainsKey('RateToCny')) {
            throw '新增币种必须提供 RateToCny。'
        }
        Add-CurrencyDefinition -Data $data -Code $Code -Name $Name -Symbol $Symbol -RateToCny $RateToCny
    }
    'Update' {
        if (-not $PSBoundParameters.ContainsKey('RateToCny')) {
            throw '修改币种必须提供 RateToCny。'
        }
        Update-CurrencyDefinition -Data $data -Code $Code -Name $Name -Symbol $Symbol -RateToCny $RateToCny
    }
    'Delete' {
        Remove-CurrencyDefinition -Data $data -Code $Code
    }
}

Write-BillsData -Data $data -Path $DataPath
Write-Host ('币种操作完成。当前人民币月费合计：¥{0:N2}' -f (Get-MonthlyTotal -Data $data))
