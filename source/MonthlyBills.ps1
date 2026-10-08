Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$dataPath = Join-Path $PSScriptRoot 'bills.json'
$selectedId = $null
$isRefreshingGrid = $false
$isLoadingEditor = $false
$workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$windowWidth = [Math]::Min($workingArea.Width, [Math]::Max(1180, [int][Math]::Round($workingArea.Width * 0.70)))
$windowHeight = [Math]::Min($workingArea.Height, [Math]::Max(720, [int][Math]::Round($workingArea.Height * 0.70)))

$form = New-Object System.Windows.Forms.Form
$form.Text = '简易月费账单管理器'
$form.StartPosition = 'CenterScreen'
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.Size = New-Object System.Drawing.Size($windowWidth, $windowHeight)
$form.MinimumSize = New-Object System.Drawing.Size(1040, 620)
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.MultiSelect = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.AutoSizeColumnsMode = 'Fill'
$grid.RowHeadersVisible = $false
$grid.BackgroundColor = [System.Drawing.Color]::White
$grid.BorderStyle = 'Fixed3D'

$null = $grid.Columns.Add('Status', '状态')
$null = $grid.Columns.Add('Name', '项目')
$null = $grid.Columns.Add('Payee', '收款方')
$null = $grid.Columns.Add('Amount', '原币金额')
$null = $grid.Columns.Add('Currency', '币种')
$null = $grid.Columns.Add('Rate', '兑人民币汇率')
$null = $grid.Columns.Add('CnyAmount', '折合人民币')
$null = $grid.Columns.Add('Notes', '备注')
$null = $grid.Columns.Add('Id', 'Id')
$grid.Columns['Status'].FillWeight = 48
$grid.Columns['Name'].FillWeight = 105
$grid.Columns['Payee'].FillWeight = 100
$grid.Columns['Amount'].FillWeight = 70
$grid.Columns['Currency'].FillWeight = 48
$grid.Columns['Rate'].FillWeight = 76
$grid.Columns['CnyAmount'].FillWeight = 74
$grid.Columns['Notes'].FillWeight = 155
$grid.Columns['Id'].Visible = $false
@('Amount', 'Rate', 'CnyAmount') | ForEach-Object {
    $grid.Columns[$_].DefaultCellStyle.Alignment = 'MiddleRight'
}

$editor = New-Object System.Windows.Forms.TableLayoutPanel
$editor.Dock = 'Bottom'
$editor.Height = 235
$editor.ColumnCount = 12
$editor.RowCount = 4
$editor.Padding = New-Object System.Windows.Forms.Padding(10)
$editor.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
for ($column = 0; $column -lt 12; $column++) {
    $editor.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 8.333))) | Out-Null
}
$editor.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 48))) | Out-Null
$editor.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 48))) | Out-Null
$editor.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 58))) | Out-Null
$editor.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100))) | Out-Null

function New-Label([string]$Text) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $true
    $label.Anchor = 'Left'
    $label
}

function New-TextBox {
    $box = New-Object System.Windows.Forms.TextBox
    $box.Dock = 'Fill'
    $box
}

function New-Button([string]$Text, [int]$MinimumWidth = 90) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.AutoSize = $true
    $button.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $button.MinimumSize = New-Object System.Drawing.Size($MinimumWidth, 34)
    $button.Padding = New-Object System.Windows.Forms.Padding(10, 2, 10, 2)
    $button.Margin = New-Object System.Windows.Forms.Padding(0, 10, 8, 4)
    $button
}

$nameBox = New-TextBox
$payeeBox = New-TextBox
$amountBox = New-TextBox
$notesBox = New-TextBox
$currencyBox = New-Object System.Windows.Forms.ComboBox
$currencyBox.Dock = 'Fill'
$currencyBox.DropDownStyle = 'DropDownList'
$overrideCheck = New-Object System.Windows.Forms.CheckBox
$overrideCheck.Text = '使用项目自定义汇率'
$overrideCheck.AutoSize = $true
$overrideCheck.Anchor = 'Left'
$rateBox = New-TextBox
$rateHintLabel = New-Object System.Windows.Forms.Label
$rateHintLabel.Dock = 'Fill'
$rateHintLabel.TextAlign = 'MiddleLeft'
$rateHintLabel.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)

$editor.Controls.Add((New-Label '项目名称'), 0, 0)
$editor.Controls.Add($nameBox, 1, 0)
$editor.SetColumnSpan($nameBox, 3)
$editor.Controls.Add((New-Label '收款方'), 4, 0)
$editor.Controls.Add($payeeBox, 5, 0)
$editor.SetColumnSpan($payeeBox, 3)
$editor.Controls.Add((New-Label '金额'), 8, 0)
$editor.Controls.Add($amountBox, 9, 0)
$editor.Controls.Add((New-Label '币种'), 10, 0)
$editor.Controls.Add($currencyBox, 11, 0)

$editor.Controls.Add((New-Label '备注'), 0, 1)
$editor.Controls.Add($notesBox, 1, 1)
$editor.SetColumnSpan($notesBox, 5)
$editor.Controls.Add($overrideCheck, 6, 1)
$editor.SetColumnSpan($overrideCheck, 2)
$editor.Controls.Add((New-Label '汇率'), 8, 1)
$editor.Controls.Add($rateBox, 9, 1)
$editor.Controls.Add($rateHintLabel, 10, 1)
$editor.SetColumnSpan($rateHintLabel, 2)

$buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonPanel.Dock = 'Fill'
$buttonPanel.FlowDirection = 'LeftToRight'
$buttonPanel.WrapContents = $false
$buttonPanel.AutoScroll = $true
$editor.SetColumnSpan($buttonPanel, 12)
$editor.Controls.Add($buttonPanel, 0, 2)

$addButton = New-Button '新增' 80
$saveButton = New-Button '保存修改' 100
$toggleButton = New-Button '停用/恢复' 110
$deleteButton = New-Button '彻底删除' 100
$clearButton = New-Button '清空输入' 100
$reportButton = New-Button '查看本月汇总' 130
$currencySettingsButton = New-Button '汇率设置' 100
$reminderButton = New-Button '提醒设置' 100
$refreshButton = New-Button '刷新' 80
@($addButton, $saveButton, $toggleButton, $deleteButton, $clearButton, $reportButton, $currencySettingsButton, $reminderButton, $refreshButton) |
    ForEach-Object { $buttonPanel.Controls.Add($_) }

$totalLabel = New-Object System.Windows.Forms.Label
$totalLabel.Dock = 'Fill'
$totalLabel.TextAlign = 'MiddleRight'
$totalLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 12, [System.Drawing.FontStyle]::Bold)
$editor.SetColumnSpan($totalLabel, 12)
$editor.Controls.Add($totalLabel, 0, 3)

$form.Controls.Add($grid)
$form.Controls.Add($editor)

function Show-Error([string]$Message) {
    [System.Windows.Forms.MessageBox]::Show(
        $form,
        $Message,
        '月费账单',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Parse-PositiveDecimal {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$FieldName
    )

    [decimal]$value = 0
    $styles = [System.Globalization.NumberStyles]::Number
    $culture = [System.Globalization.CultureInfo]::CurrentCulture
    if (-not [decimal]::TryParse($Text.Trim(), $styles, $culture, [ref]$value)) {
        if (-not [decimal]::TryParse($Text.Trim(), $styles, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
            throw "请输入有效的$FieldName。"
        }
    }
    if ($value -le 0) {
        throw "$FieldName必须大于 0。"
    }
    $value
}

function Get-SelectedCurrencyCode {
    if ($null -eq $currencyBox.SelectedItem) {
        return 'CNY'
    }
    [string]$currencyBox.SelectedItem
}

function Reload-CurrencyChoices {
    param(
        [string]$PreferredCode = 'CNY'
    )

    $data = Read-BillsData -Path $dataPath
    $script:isLoadingEditor = $true
    try {
        $currencyBox.Items.Clear()
        foreach ($currency in @($data.Currencies | Sort-Object @{ Expression = { if ($_.Code -eq 'CNY') { 0 } else { 1 } } }, Code)) {
            [void]$currencyBox.Items.Add([string]$currency.Code)
        }
        $index = $currencyBox.Items.IndexOf($PreferredCode)
        $currencyBox.SelectedIndex = if ($index -ge 0) { $index } else { $currencyBox.Items.IndexOf('CNY') }
    }
    finally {
        $script:isLoadingEditor = $false
    }
}

function Update-RateEditor {
    if ($isLoadingEditor) { return }
    $data = Read-BillsData -Path $dataPath
    $code = Get-SelectedCurrencyCode
    $currency = Get-CurrencyDefinition -Data $data -Code $code

    if ($code -eq 'CNY') {
        $script:isLoadingEditor = $true
        try {
            $overrideCheck.Checked = $false
        }
        finally {
            $script:isLoadingEditor = $false
        }
        $overrideCheck.Enabled = $false
        $rateBox.Enabled = $false
        $rateBox.Clear()
        $rateHintLabel.Text = '1 CNY = 1 CNY'
        return
    }

    $overrideCheck.Enabled = $true
    $rateBox.Enabled = $overrideCheck.Checked
    if (-not $overrideCheck.Checked) {
        $rateBox.Text = ('{0:N6}' -f [decimal]$currency.RateToCny)
        $rateHintLabel.Text = "全局：1 $code = $('{0:N6}' -f [decimal]$currency.RateToCny) CNY"
    }
    else {
        $rateHintLabel.Text = "自定义：1 $code = X CNY"
    }
}

function Clear-Editor {
    $script:isLoadingEditor = $true
    try {
        $script:selectedId = $null
        $nameBox.Clear()
        $payeeBox.Clear()
        $amountBox.Clear()
        $notesBox.Clear()
        if ($currencyBox.Items.Count -eq 0) {
            Reload-CurrencyChoices -PreferredCode 'CNY'
        }
        else {
            $currencyBox.SelectedItem = 'CNY'
        }
        $overrideCheck.Checked = $false
        $rateBox.Clear()
        $grid.ClearSelection()
    }
    finally {
        $script:isLoadingEditor = $false
    }
    Update-RateEditor
    $nameBox.Focus()
}

function Get-EnteredAmount {
    Parse-PositiveDecimal -Text $amountBox.Text -FieldName '金额'
}

function Get-EnteredRateOverride {
    $code = Get-SelectedCurrencyCode
    if ($code -eq 'CNY' -or -not $overrideCheck.Checked) {
        return $null
    }
    Parse-PositiveDecimal -Text $rateBox.Text -FieldName '自定义汇率'
}

function Refresh-Grid {
    $script:isRefreshingGrid = $true
    try {
        $data = Read-BillsData -Path $dataPath
        $grid.Rows.Clear()
        foreach ($bill in @($data.Bills | Sort-Object @{ Expression = 'Active'; Descending = $true }, Name)) {
            $status = if ($bill.Active) { '有效' } else { '已停用' }
            $rate = Get-EffectiveExchangeRate -Data $data -Bill $bill
            $rateText = if ($null -ne $bill.ExchangeRateOverride) {
                ('{0:N6} *' -f $rate)
            }
            else {
                ('{0:N6}' -f $rate)
            }
            $rowIndex = $grid.Rows.Add(
                $status,
                $bill.Name,
                $bill.Payee,
                ('{0:N2}' -f $bill.Amount),
                $bill.Currency,
                $rateText,
                ('¥{0:N2}' -f (Get-BillCnyAmount -Data $data -Bill $bill)),
                $bill.Notes,
                $bill.Id
            )
            if (-not $bill.Active) {
                $grid.Rows[$rowIndex].DefaultCellStyle.ForeColor = [System.Drawing.Color]::Gray
            }
        }
        $totalLabel.Text = '有效项目：{0} 项    人民币月费合计：¥{1:N2}' -f (@($data.Bills | Where-Object Active).Count), (Get-MonthlyTotal -Data $data)
        Clear-Editor
    }
    finally {
        $script:isRefreshingGrid = $false
    }
}

function Show-CurrencySettings {
    try {
        $dialog = New-Object System.Windows.Forms.Form
        $dialog.Text = '汇率设置'
        $dialog.StartPosition = 'CenterParent'
$dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$dialog.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
        $currencyDialogWidth = [Math]::Min(1200, [Math]::Max(720, [int][Math]::Round($workingArea.Width * 0.45)))
        $currencyDialogHeight = [Math]::Min(900, [Math]::Max(520, [int][Math]::Round($workingArea.Height * 0.45)))
        $dialog.Size = New-Object System.Drawing.Size($currencyDialogWidth, $currencyDialogHeight)
        $dialog.MinimumSize = New-Object System.Drawing.Size(680, 480)
        $dialog.Font = $form.Font

        $currencyGrid = New-Object System.Windows.Forms.DataGridView
        $currencyGrid.Dock = 'Fill'
        $currencyGrid.ReadOnly = $true
        $currencyGrid.AllowUserToAddRows = $false
        $currencyGrid.AllowUserToDeleteRows = $false
        $currencyGrid.MultiSelect = $false
        $currencyGrid.SelectionMode = 'FullRowSelect'
        $currencyGrid.AutoSizeColumnsMode = 'Fill'
        $currencyGrid.RowHeadersVisible = $false
        $null = $currencyGrid.Columns.Add('Code', '代码')
        $null = $currencyGrid.Columns.Add('Name', '名称')
        $null = $currencyGrid.Columns.Add('Symbol', '符号')
        $null = $currencyGrid.Columns.Add('Rate', '1 单位兑 CNY')
        $null = $currencyGrid.Columns.Add('UpdatedAt', '更新时间')
        $currencyGrid.Columns['Code'].FillWeight = 50
        $currencyGrid.Columns['Name'].FillWeight = 75
        $currencyGrid.Columns['Symbol'].FillWeight = 50
        $currencyGrid.Columns['Rate'].FillWeight = 80
        $currencyGrid.Columns['UpdatedAt'].FillWeight = 125

        $currencyEditor = New-Object System.Windows.Forms.TableLayoutPanel
        $currencyEditor.Dock = 'Bottom'
        $currencyEditor.Height = 165
        $currencyEditor.Padding = New-Object System.Windows.Forms.Padding(10)
        $currencyEditor.ColumnCount = 8
        $currencyEditor.RowCount = 3
        for ($column = 0; $column -lt 8; $column++) {
            $currencyEditor.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 12.5))) | Out-Null
        }

        $codeBox = New-TextBox
        $currencyNameBox = New-TextBox
        $symbolBox = New-TextBox
        $currencyRateBox = New-TextBox
        $currencyEditor.Controls.Add((New-Label '代码'), 0, 0)
        $currencyEditor.Controls.Add($codeBox, 1, 0)
        $currencyEditor.Controls.Add((New-Label '名称'), 2, 0)
        $currencyEditor.Controls.Add($currencyNameBox, 3, 0)
        $currencyEditor.Controls.Add((New-Label '符号'), 4, 0)
        $currencyEditor.Controls.Add($symbolBox, 5, 0)
        $currencyEditor.Controls.Add((New-Label '汇率'), 6, 0)
        $currencyEditor.Controls.Add($currencyRateBox, 7, 0)

        $currencyButtons = New-Object System.Windows.Forms.FlowLayoutPanel
        $currencyButtons.Dock = 'Fill'
$currencyButtons.FlowDirection = 'LeftToRight'
$currencyButtons.WrapContents = $false
$currencyButtons.AutoScroll = $true
        $currencyEditor.SetColumnSpan($currencyButtons, 8)
        $currencyEditor.Controls.Add($currencyButtons, 0, 1)
        $newCurrencyButton = New-Button '新建输入' 90
        $addCurrencyButton = New-Button '新增币种' 90
        $saveCurrencyButton = New-Button '保存修改' 90
        $deleteCurrencyButton = New-Button '删除币种' 90
        $closeCurrencyButton = New-Button '关闭' 80
        @($newCurrencyButton, $addCurrencyButton, $saveCurrencyButton, $deleteCurrencyButton, $closeCurrencyButton) |
            ForEach-Object { $currencyButtons.Controls.Add($_) }

        $currencyStatusLabel = New-Object System.Windows.Forms.Label
        $currencyStatusLabel.Dock = 'Fill'
        $currencyStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(23, 78, 166)
        $currencyEditor.SetColumnSpan($currencyStatusLabel, 8)
        $currencyEditor.Controls.Add($currencyStatusLabel, 0, 2)

        $dialog.Controls.Add($currencyGrid)
        $dialog.Controls.Add($currencyEditor)
        $currencyState = [pscustomobject]@{
            SelectedCode = $null
            Loading = $false
        }

        function Clear-CurrencyEditor {
            $currencyState.SelectedCode = $null
            $codeBox.ReadOnly = $false
            $codeBox.Clear()
            $currencyNameBox.Clear()
            $symbolBox.Clear()
            $currencyRateBox.Clear()
            $currencyNameBox.Enabled = $true
            $symbolBox.Enabled = $true
            $currencyRateBox.Enabled = $true
            $saveCurrencyButton.Enabled = $false
            $deleteCurrencyButton.Enabled = $false
            $currencyGrid.ClearSelection()
            $codeBox.Focus()
        }

        function Refresh-CurrencyGrid {
            $currencyState.Loading = $true
            try {
                $data = Read-BillsData -Path $dataPath
                $currencyGrid.Rows.Clear()
                foreach ($currency in @($data.Currencies | Sort-Object @{ Expression = { if ($_.Code -eq 'CNY') { 0 } else { 1 } } }, Code)) {
                    [void]$currencyGrid.Rows.Add(
                        $currency.Code,
                        $currency.Name,
                        $currency.Symbol,
                        ('{0:N6}' -f [decimal]$currency.RateToCny),
                        $currency.UpdatedAt
                    )
                }
                Clear-CurrencyEditor
            }
            finally {
                $currencyState.Loading = $false
            }
        }

        $currencyGrid.Add_SelectionChanged({
            if ($currencyState.Loading -or $currencyGrid.SelectedRows.Count -eq 0) { return }
            $row = $currencyGrid.SelectedRows[0]
            $currencyState.SelectedCode = [string]$row.Cells['Code'].Value
            $codeBox.Text = $currencyState.SelectedCode
            $currencyNameBox.Text = [string]$row.Cells['Name'].Value
            $symbolBox.Text = [string]$row.Cells['Symbol'].Value
            $currencyRateBox.Text = [string]$row.Cells['Rate'].Value
            $codeBox.ReadOnly = $true
            $isCny = $currencyState.SelectedCode -eq 'CNY'
            $currencyNameBox.Enabled = -not $isCny
            $symbolBox.Enabled = -not $isCny
            $currencyRateBox.Enabled = -not $isCny
            $saveCurrencyButton.Enabled = -not $isCny
            $deleteCurrencyButton.Enabled = -not $isCny
        })

        $newCurrencyButton.Add_Click({ Clear-CurrencyEditor })
        $addCurrencyButton.Add_Click({
            try {
                $data = Read-BillsData -Path $dataPath
                Add-CurrencyDefinition -Data $data -Code $codeBox.Text -Name $currencyNameBox.Text -Symbol $symbolBox.Text -RateToCny (Parse-PositiveDecimal -Text $currencyRateBox.Text -FieldName '汇率')
                Write-BillsData -Data $data -Path $dataPath
                $currencyStatusLabel.Text = '币种已新增。'
                Refresh-CurrencyGrid
                Reload-CurrencyChoices
                Refresh-Grid
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show($dialog, $_.Exception.Message, '无法新增币种', 'OK', 'Error') | Out-Null
            }
        })
        $saveCurrencyButton.Add_Click({
            try {
                if ([string]::IsNullOrWhiteSpace($currencyState.SelectedCode)) { throw '请先选择要修改的币种。' }
                $data = Read-BillsData -Path $dataPath
                Update-CurrencyDefinition -Data $data -Code $currencyState.SelectedCode -Name $currencyNameBox.Text -Symbol $symbolBox.Text -RateToCny (Parse-PositiveDecimal -Text $currencyRateBox.Text -FieldName '汇率')
                Write-BillsData -Data $data -Path $dataPath
                $currencyStatusLabel.Text = '汇率已更新，未覆盖汇率的账单已重新计算。'
                Refresh-CurrencyGrid
                Reload-CurrencyChoices
                Refresh-Grid
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show($dialog, $_.Exception.Message, '无法保存币种', 'OK', 'Error') | Out-Null
            }
        })
        $deleteCurrencyButton.Add_Click({
            try {
                if ([string]::IsNullOrWhiteSpace($currencyState.SelectedCode)) { throw '请先选择要删除的币种。' }
                $data = Read-BillsData -Path $dataPath
                Remove-CurrencyDefinition -Data $data -Code $currencyState.SelectedCode
                Write-BillsData -Data $data -Path $dataPath
                $currencyStatusLabel.Text = '币种已删除。'
                Refresh-CurrencyGrid
                Reload-CurrencyChoices
                Refresh-Grid
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show($dialog, $_.Exception.Message, '无法删除币种', 'OK', 'Error') | Out-Null
            }
        })
        $closeCurrencyButton.Add_Click({ $dialog.Close() })
        $dialog.Add_Shown({ Refresh-CurrencyGrid })
        [void]$dialog.ShowDialog($form)
    }
    catch {
        Show-Error $_.Exception.Message
    }
}

function Show-ReminderSettings {
    try {
        $scheduleScript = Join-Path $PSScriptRoot 'Reminder-Schedule.ps1'
        $configuration = & $scheduleScript Get

        $dialog = New-Object System.Windows.Forms.Form
        $dialog.Text = '提醒设置'
        $dialog.StartPosition = 'CenterParent'
        $dialog.FormBorderStyle = 'FixedDialog'
        $dialog.MaximizeBox = $false
        $dialog.MinimizeBox = $false
        $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
        $dialog.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
        $dialog.ClientSize = New-Object System.Drawing.Size(600, 340)
        $dialog.Font = $form.Font

        $layout = New-Object System.Windows.Forms.TableLayoutPanel
        $layout.Dock = 'Fill'
        $layout.Padding = New-Object System.Windows.Forms.Padding(18)
        $layout.ColumnCount = 4
        $layout.RowCount = 5
        for ($column = 0; $column -lt 4; $column++) {
            $layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 25))) | Out-Null
        }
        $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 28))) | Out-Null
        $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 48))) | Out-Null
        $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 48))) | Out-Null
        $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 54))) | Out-Null
        $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100))) | Out-Null

        foreach ($item in @(
            @{ Text = '每月日期'; Column = 0 },
            @{ Text = '小时'; Column = 1 },
            @{ Text = '分钟'; Column = 2 },
            @{ Text = '秒'; Column = 3 }
        )) {
            $label = New-Label $item.Text
            $label.Dock = 'Fill'
            $label.TextAlign = 'BottomLeft'
            $layout.Controls.Add($label, $item.Column, 0)
        }

        function New-ScheduleNumber([int]$Minimum, [int]$Maximum, [int]$Value) {
            $control = New-Object System.Windows.Forms.NumericUpDown
            $control.Minimum = $Minimum
            $control.Maximum = $Maximum
            $control.Value = $Value
            $control.Dock = 'Fill'
            $control.TextAlign = 'Center'
            $control.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11)
            $control
        }

        $dayControl = New-ScheduleNumber 1 28 $configuration.Day
        $hourControl = New-ScheduleNumber 0 23 $configuration.Hour
        $minuteControl = New-ScheduleNumber 0 59 $configuration.Minute
        $secondControl = New-ScheduleNumber 0 59 $configuration.Second
        $layout.Controls.Add($dayControl, 0, 1)
        $layout.Controls.Add($hourControl, 1, 1)
        $layout.Controls.Add($minuteControl, 2, 1)
        $layout.Controls.Add($secondControl, 3, 1)

        $nextRunLabel = New-Object System.Windows.Forms.Label
        $nextRunLabel.Dock = 'Fill'
        $nextRunLabel.TextAlign = 'MiddleLeft'
        $nextRunLabel.Text = '下一次运行：{0:yyyy-MM-dd HH:mm:ss}' -f $configuration.NextRunTime
        $layout.SetColumnSpan($nextRunLabel, 4)
        $layout.Controls.Add($nextRunLabel, 0, 2)

        $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
        $buttons.Dock = 'Fill'
$buttons.FlowDirection = 'LeftToRight'
$buttons.WrapContents = $false
$buttons.AutoScroll = $true
        $layout.SetColumnSpan($buttons, 4)
        $layout.Controls.Add($buttons, 0, 3)
        $saveScheduleButton = New-Button '保存定时' 105
        $testReminderButton = New-Button '立即测试提醒' 125
        $closeScheduleButton = New-Button '关闭' 90
        @($saveScheduleButton, $testReminderButton, $closeScheduleButton) | ForEach-Object { $buttons.Controls.Add($_) }

        $statusLabel = New-Object System.Windows.Forms.Label
        $statusLabel.Dock = 'Fill'
        $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(23, 78, 166)
        $layout.SetColumnSpan($statusLabel, 4)
        $layout.Controls.Add($statusLabel, 0, 4)

        $saveScheduleButton.Add_Click({
            try {
                $updated = & $scheduleScript Set -Day ([int]$dayControl.Value) -Hour ([int]$hourControl.Value) -Minute ([int]$minuteControl.Value) -Second ([int]$secondControl.Value)
                $nextRunLabel.Text = '下一次运行：{0:yyyy-MM-dd HH:mm:ss}' -f $updated.NextRunTime
                $statusLabel.Text = '定时已保存。'
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show($dialog, $_.Exception.Message, '无法保存提醒设置', 'OK', 'Error') | Out-Null
            }
        })
        $testReminderButton.Add_Click({
            try {
                $null = & $scheduleScript Test
                $statusLabel.Text = '测试提醒已启动：将弹出人民币总额并打开本月报表。'
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show($dialog, $_.Exception.Message, '无法启动测试提醒', 'OK', 'Error') | Out-Null
            }
        })
        $closeScheduleButton.Add_Click({ $dialog.Close() })
        $dialog.Controls.Add($layout)
        [void]$dialog.ShowDialog($form)
    }
    catch {
        Show-Error $_.Exception.Message
    }
}

$currencyBox.Add_SelectedIndexChanged({
    if (-not $isLoadingEditor) {
        Update-RateEditor
    }
})
$overrideCheck.Add_CheckedChanged({
    if (-not $isLoadingEditor) {
        Update-RateEditor
    }
})

$grid.Add_SelectionChanged({
    if ($isRefreshingGrid -or $grid.SelectedRows.Count -eq 0) { return }
    try {
        $data = Read-BillsData -Path $dataPath
        $row = $grid.SelectedRows[0]
        $bill = Find-OneBill -Data $data -Id ([string]$row.Cells['Id'].Value)
        $script:isLoadingEditor = $true
        try {
            $script:selectedId = $bill.Id
            $nameBox.Text = $bill.Name
            $payeeBox.Text = $bill.Payee
            $amountBox.Text = ('{0:N2}' -f $bill.Amount)
            $notesBox.Text = $bill.Notes
            if ($currencyBox.Items.IndexOf($bill.Currency) -lt 0) {
                Reload-CurrencyChoices -PreferredCode $bill.Currency
            }
            else {
                $currencyBox.SelectedItem = $bill.Currency
            }
            $overrideCheck.Checked = $null -ne $bill.ExchangeRateOverride
            $rateBox.Text = ('{0:N6}' -f (Get-EffectiveExchangeRate -Data $data -Bill $bill))
        }
        finally {
            $script:isLoadingEditor = $false
        }
        Update-RateEditor
    }
    catch {
        Show-Error $_.Exception.Message
    }
})

$addButton.Add_Click({
    try {
        $data = Read-BillsData -Path $dataPath
        $currencyCode = Get-SelectedCurrencyCode
        $null = Get-CurrencyDefinition -Data $data -Code $currencyCode
        $override = Get-EnteredRateOverride
        if ($null -eq $override) {
            $bill = New-BillRecord -Name $nameBox.Text -Payee $payeeBox.Text -Amount (Get-EnteredAmount) -Currency $currencyCode -Notes $notesBox.Text
        }
        else {
            $bill = New-BillRecord -Name $nameBox.Text -Payee $payeeBox.Text -Amount (Get-EnteredAmount) -Currency $currencyCode -ExchangeRateOverride $override -Notes $notesBox.Text
        }
        $data.Bills = @($data.Bills) + $bill
        Write-BillsData -Data $data -Path $dataPath
        Refresh-Grid
    }
    catch { Show-Error $_.Exception.Message }
})

$saveButton.Add_Click({
    try {
        if ([string]::IsNullOrWhiteSpace($selectedId)) { throw '请先选择要修改的项目。' }
        if ([string]::IsNullOrWhiteSpace($nameBox.Text)) { throw '项目名称不能为空。' }
        $data = Read-BillsData -Path $dataPath
        $bill = Find-OneBill -Data $data -Id $selectedId
        $currencyCode = Get-SelectedCurrencyCode
        $null = Get-CurrencyDefinition -Data $data -Code $currencyCode
        $bill.Name = $nameBox.Text.Trim()
        $bill.Payee = $payeeBox.Text.Trim()
        $bill.Amount = Get-EnteredAmount
        $bill.Currency = $currencyCode
        $bill.ExchangeRateOverride = Get-EnteredRateOverride
        $bill.Notes = $notesBox.Text.Trim()
        $bill.UpdatedAt = (Get-Date).ToString('o')
        Write-BillsData -Data $data -Path $dataPath
        Refresh-Grid
    }
    catch { Show-Error $_.Exception.Message }
})

$toggleButton.Add_Click({
    try {
        if ([string]::IsNullOrWhiteSpace($selectedId)) { throw '请先选择要停用或恢复的项目。' }
        $data = Read-BillsData -Path $dataPath
        $bill = Find-OneBill -Data $data -Id $selectedId
        $bill.Active = -not $bill.Active
        $bill.UpdatedAt = (Get-Date).ToString('o')
        Write-BillsData -Data $data -Path $dataPath
        Refresh-Grid
    }
    catch { Show-Error $_.Exception.Message }
})

$deleteButton.Add_Click({
    try {
        if ([string]::IsNullOrWhiteSpace($selectedId)) { throw '请先选择要删除的项目。' }
        $answer = [System.Windows.Forms.MessageBox]::Show(
            $form,
            '该操作会永久删除所选项目，是否继续？',
            '确认彻底删除',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $data = Read-BillsData -Path $dataPath
        $data.Bills = @($data.Bills | Where-Object { $_.Id -ne $selectedId })
        Write-BillsData -Data $data -Path $dataPath
        Refresh-Grid
    }
    catch { Show-Error $_.Exception.Message }
})

$clearButton.Add_Click({ Clear-Editor })
$refreshButton.Add_Click({ Reload-CurrencyChoices; Refresh-Grid })
$reportButton.Add_Click({
    try {
        & (Join-Path $PSScriptRoot 'Generate-Report.ps1') -NoPopup | Out-Null
    }
    catch { Show-Error $_.Exception.Message }
})
$currencySettingsButton.Add_Click({ Show-CurrencySettings })
$reminderButton.Add_Click({ Show-ReminderSettings })

$form.Add_Shown({
    Reload-CurrencyChoices
    Refresh-Grid
    $nameBox.Focus()
})
[void][System.Windows.Forms.Application]::Run($form)
