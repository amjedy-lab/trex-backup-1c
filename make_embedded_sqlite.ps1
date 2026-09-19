# make_embedded_sqlite.ps1 — встраивает SQLite-драйвер (обе редакции PowerShell) в backup-1c-gui.ps1.
#
# Встраиваются 4 файла из модуля PSSQLite (или по явным путям):
#   x64\System.Data.SQLite.dll + x64\SQLite.Interop.dll                 — .NET Framework (exe через ps2exe = PowerShell 5.1)
#   core\win-x64\System.Data.SQLite.dll + core\win-x64\SQLite.Interop.dll — .NET Core (pwsh 7)
#
# Каждый файл упаковывается gzip+base64 и вставляется между маркерами в теле backup-1c-gui.ps1.
# Приложение выбирает сборку по своей редакции и распаковывает её в
# %LOCALAPPDATA%\T-REX-Backup1C\sqlite-x64-netfx или sqlite-x64-netcore.
#
# Запуск: pwsh -File .\make_embedded_sqlite.ps1
#         powershell -ExecutionPolicy Bypass -File .\make_embedded_sqlite.ps1

param(
    [string]$ModuleDir = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\PSSQLite\1.1.0"
)

$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetPs1 = Join-Path $dir 'backup-1c-gui.ps1'

$sources = @(
    @{ Var = 'embeddedSqliteManagedFx';  File = Join-Path $ModuleDir 'x64\System.Data.SQLite.dll' },
    @{ Var = 'embeddedSqliteInteropFx';  File = Join-Path $ModuleDir 'x64\SQLite.Interop.dll' },
    @{ Var = 'embeddedSqliteManagedCore'; File = Join-Path $ModuleDir 'core\win-x64\System.Data.SQLite.dll' },
    @{ Var = 'embeddedSqliteInteropCore'; File = Join-Path $ModuleDir 'core\win-x64\SQLite.Interop.dll' }
)
foreach ($s in $sources) {
    if (-not (Test-Path -LiteralPath $s.File)) {
        throw "Не найден $($s.File) — укажите -ModuleDir или установите PSSQLite (Install-Module PSSQLite -Scope CurrentUser)."
    }
}

function Convert-ToGzipB64([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $ms = [IO.MemoryStream]::new()
    $gz = [IO.Compression.GZipStream]::new($ms, [IO.Compression.CompressionLevel]::Optimal)
    $gz.Write($bytes, 0, $bytes.Length)
    $gz.Dispose()
    # строки по 200 символов, чтобы here-string не был одной мегабайтной строкой
    $b64 = [Convert]::ToBase64String($ms.ToArray())
    ($b64 -replace '(.{200})', "`$1`n")
}

$parts = [System.Collections.Generic.List[string]]::new()
$summary = [System.Collections.Generic.List[string]]::new()
foreach ($s in $sources) {
    $b64 = Convert-ToGzipB64 $s.File
    $parts.Add("`$$($s.Var) = @'")
    $parts.Add($b64)
    $parts.Add("'@")
    $summary.Add("$($s.Var)=$($b64.Length) симв.")
}

$block = "# --- ВСТРОЕННЫЙ SQLITE-ДРАЙВЕР (сгенерировано make_embedded_sqlite.ps1, не редактировать) ---`r`n" +
         ($parts -join "`r`n") +
         "`r`n# --- КОНЕЦ ВСТРОЕННОГО SQLITE-ДРАЙВЕРА ---"

$text = [IO.File]::ReadAllText($targetPs1)
$pattern = '(?s)# --- ВСТРОЕННЫЙ SQLITE-ДРАЙВЕР.*?# --- КОНЕЦ ВСТРОЕННОГО SQLITE-ДРАЙВЕРА ---'
if ($text -match $pattern) {
    $text = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block })
}
else {
    $anchor = '$encUtf8 = New-Object System.Text.UTF8Encoding($false)'
    if (-not $text.Contains($anchor)) { throw 'Не найдена точка вставки в backup-1c-gui.ps1' }
    $text = $text.Replace($anchor, $anchor + "`r`n" + $block)
}
# UTF-8 С BOM: иначе Windows PowerShell 5.1 (в т.ч. в exe от ps2exe) прочитает кириллицу как ANSI
[IO.File]::WriteAllText($targetPs1, $text, (New-Object System.Text.UTF8Encoding($true)))

Write-Output ("embedded OK: " + ($summary -join '; ') + "; итоговый размер скрипта: $((Get-Item $targetPs1).Length) байт")
