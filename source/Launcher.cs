using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("月费账单管理器")]
[assembly: AssemblyDescription("便携月费账单管理器启动器")]
[assembly: AssemblyProduct("月费账单管理器")]
[assembly: AssemblyCompany("Basket-of-AI-Tools")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class MonthlyBillsLauncher
{
    [STAThread]
    private static void Main()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(root, "MonthlyBills.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show(
                "启动器旁边缺少 MonthlyBills.ps1。",
                "月费账单管理器",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
            return;
        }

        string powerShell = FindOnPath("pwsh.exe");
        if (powerShell == null)
        {
            string windowsPowerShell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "System32",
                "WindowsPowerShell",
                "v1.0",
                "powershell.exe"
            );
            powerShell = File.Exists(windowsPowerShell) ? windowsPowerShell : FindOnPath("powershell.exe");
        }

        if (powerShell == null)
        {
            MessageBox.Show(
                "没有找到 PowerShell 7 或 Windows PowerShell。",
                "月费账单管理器",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
            return;
        }

        try
        {
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = powerShell;
            startInfo.Arguments =
                "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" +
                script.Replace("\"", "\\\"") +
                "\"";
            startInfo.WorkingDirectory = root;
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            Process.Start(startInfo);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "无法启动月费账单管理器：\r\n" + ex.Message,
                "月费账单管理器",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
        }
    }

    private static string FindOnPath(string fileName)
    {
        string path = Environment.GetEnvironmentVariable("PATH");
        if (String.IsNullOrEmpty(path))
        {
            return null;
        }

        foreach (string rawDirectory in path.Split(Path.PathSeparator))
        {
            string directory = rawDirectory.Trim().Trim('"');
            if (directory.Length == 0)
            {
                continue;
            }

            try
            {
                string candidate = Path.Combine(directory, fileName);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
            catch
            {
            }
        }
        return null;
    }
}