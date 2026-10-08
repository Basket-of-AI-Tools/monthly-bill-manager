# 月费账单管理器

Windows 便携式固定月费管理工具。解压 dist/monthly-bill-manager.zip 后，双击 月费账单管理器.exe 即可启动。

## 便携使用

- 整个解压目录可复制或移动；账单数据和报表都保存在软件目录中。
- 启动器隐藏 PowerShell 窗口。需要 Windows PowerShell 5.1 或 PowerShell 7。
- 账单保存在 bills.json；月度 HTML 报表保存在 报表/。
- ZIP 内的初始数据为虚构演示项目。个人使用时请将账单文件保存在自己的本地副本中。
- 软件仅在本机处理账单，不会联网上传数据。

## 可选提醒

运行 Install.ps1 可创建桌面快捷方式和 Windows 每月提醒任务。将软件目录移到新位置后，再运行一次设置脚本以更新任务路径。无需提醒时，直接双击 EXE 即可，不必安装。

## 新手操作演示

这张图按程序实际按钮整理了启动、添加、停用/恢复和查看报表的步骤。图中的界面和账单是示意与虚构样例。

![月费账单管理器新手操作图](demo/使用演示.svg)

- [打开图文演示页](demo/使用演示.html)
- [打开虚构样例月报](demo/报表/2026-10.html)
- 样例数据：`demo/bills.json`

## 源码与构建

源码及启动器构建脚本位于 source/。可在 Windows 上运行：

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ".\source\Build-Launcher.ps1"

构建需 PowerShell 与 Windows .NET Framework C# 编译器。

## 许可

MIT
