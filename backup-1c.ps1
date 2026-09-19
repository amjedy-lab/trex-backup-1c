#requires -Version 5.1
<#
    Бэкап файловых баз 1С.

    Читает config.json (список баз: путь до 1Cv8.1CD + имя для архива),
    копирует каждую базу в %TEMP%, упаковывает через 7-Zip в архив
    с именем <Имя>_<дата>_<время>.7z, переносит в каталог назначения
    и удаляет временные файлы. Оригиналы не трогаются.

    Ротация: параметр КоличествоДнейАктуальности в config.json - сколько дней
    хранить архивы. Если параметра нет - спрашивается в начале выполнения
    (при неинтерактивном запуске ротация пропускается с WARN в логе).
    После успешного выполнения (все базы без ошибок) удаляются архивы
    <Имя>_ГГГГ-ММ-ДД_*.7z старше текущей даты минус это число дней.
    Если бэкап хоть одной базы упал - ротация пропускается.

    SQLite-лог: результат каждого запуска пишется в БД (config.LogDb,
    по умолчанию <Destination>\backup_log.db). Требуется System.Data.SQLite.dll
    рядом со скриптом или модуль PSSQLite; если не найдено - запись в БД
    отключается (WARN в логе), бэкап выполняется как обычно.

    Запуск: powershell -ExecutionPolicy Bypass -File .\backup-1c.ps1 [-Config path]
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = ''
)

if (-not $ConfigPath) {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $ConfigPath = Join-Path $scriptDir 'config.json'
}

$ErrorActionPreference = 'Stop'

# кириллица в консоли
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

Write-Host ''
Write-Host '=========================================================='
Write-Host '  ВНИМАНИЕ: чтобы прервать выполнение скрипта, нажмите'
Write-Host '  комбинацию Ctrl+C (временные файлы будут удалены)'
Write-Host '=========================================================='
Write-Host ''

# --- Проверка конфига / интерактивное создание -------------------------------

$enc = New-Object System.Text.UTF8Encoding($false)

# безопасное чтение строки: конец ввода (Ctrl+C / закрытый поток) завершает мастер
function Read-Trimmed {
    param([string]$Prompt)
    $v = Read-Host $Prompt
    if ($null -eq $v) {
        Write-Host ''
        Write-Host 'Ввод не получен (прервано). Настройка отменена.' -ForegroundColor Red
        exit 1
    }
    return $v.Trim()
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "Конфиг не найден: $ConfigPath"
    Write-Host 'Запустим настройку - ответьте на несколько вопросов.'
    Write-Host ''

    # каталог назначения
    do {
        $destInput = [Environment]::ExpandEnvironmentVariables((Read-Trimmed 'Папка для архивов (например E:\1C_backup)'))
        if (-not $destInput) {
            Write-Host 'Путь не может быть пустым.' -ForegroundColor Red
            continue
        }
        if (-not (Test-Path -LiteralPath $destInput -PathType Container)) {
            $make = Read-Host "Папка '$destInput' не существует. Создать? (y/n)"
            if ($make -match '^[дy]') {
                try {
                    New-Item -ItemType Directory -Path $destInput -Force | Out-Null
                }
                catch {
                    Write-Host "Не удалось создать: $($_.Exception.Message)" -ForegroundColor Red
                    $destInput = ''
                }
            }
            else { $destInput = '' }
        }
    } while (-not $destInput)

    # базы
    $bases = @()
    while ($true) {
        Write-Host ''
        Write-Host ("База #{0}:" -f ($bases.Count + 1))
        $basePath = ''
        do {
            $basePath = Read-Trimmed '  Путь к базе (каталог или полный путь к 1Cv8.1CD), пустой ввод - закончить'
            if (-not $basePath) { break }
            $basePath = [Environment]::ExpandEnvironmentVariables($basePath)
            if (Test-Path -LiteralPath $basePath -PathType Leaf) {
                if ((Split-Path $basePath -Leaf) -ne '1Cv8.1CD') {
                    Write-Host '  Файл должен называться 1Cv8.1CD.' -ForegroundColor Red
                    $basePath = ''
                }
            }
            elseif (-not (Test-Path -LiteralPath $basePath -PathType Container)) {
                Write-Host '  Путь не найден.' -ForegroundColor Red
                $basePath = ''
            }
        } while (-not $basePath)
        if (-not $basePath) { break }

        $baseName = ''
        do {
            $baseName = Read-Trimmed '  Имя для архива'
            if (-not $baseName) { Write-Host '  Имя не может быть пустым.' -ForegroundColor Red }
            elseif ($baseName -match '[\\/:\*\?"<>\|]') {
                Write-Host '  Имя содержит недопустимые для имени файла символы.' -ForegroundColor Red
                $baseName = ''
            }
        } while (-not $baseName)

        $bases += [pscustomobject]@{ Name = $baseName; Path = $basePath }
    }

    if ($bases.Count -eq 0) {
        Write-Error 'Не указано ни одной базы. Конфиг не создан.'
        exit 1
    }

    # сколько дней хранить архивы
    $keepDays = $null
    do {
        $daysInput = Read-Trimmed 'Сколько дней хранить архивы (Enter = 30, 0 = не удалять)'
        if ($daysInput -eq '') { $keepDays = 30 }
        elseif ($daysInput -match '^\d+$') { $keepDays = [int]$daysInput }
        else { Write-Host '  Нужно целое число.' -ForegroundColor Red }
    } while ($null -eq $keepDays)

    $config = [pscustomobject]@{
        Destination = $destInput
        КоличествоДнейАктуальности = $keepDays
        Bases       = $bases
    }

    $json = $config | ConvertTo-Json -Depth 4
    try {
        [IO.File]::WriteAllText($ConfigPath, $json, $enc)
        Write-Host ''
        Write-Host "Конфиг создан: $ConfigPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Не удалось записать конфиг: $($_.Exception.Message)"
        exit 1
    }
}
else {
    $raw = [System.IO.File]::ReadAllText($ConfigPath, $enc)
    try {
        $config = $raw | ConvertFrom-Json
    }
    catch {
        Write-Error "Ошибка разбора config.json: $($_.Exception.Message)"
        exit 1
    }
}

if (-not $config.Destination -or -not $config.Bases -or $config.Bases.Count -eq 0) {
    Write-Error "В config.json должны быть заполнены Destination и непустой массив Bases."
    exit 1
}

# --- Проверка каталога назначения -------------------------------------------

$destination = [Environment]::ExpandEnvironmentVariables($config.Destination)

if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
    Write-Error "Каталог назначения недоступен или не существует: $destination"
    exit 1
}

# проверка, что каталог реально доступен на запись
$probe = Join-Path $destination ("~write-probe-" + [Guid]::NewGuid().ToString('N'))
try {
    [IO.File]::WriteAllText($probe, '')
    Remove-Item -LiteralPath $probe -Force
}
catch {
    Write-Error "Каталог назначения недоступен для записи: $destination ($($_.Exception.Message))"
    exit 1
}

# --- Поиск 7-Zip -------------------------------------------------------------

function Find-SevenZip {
    if ($config.SevenZipPath -and (Test-Path -LiteralPath $config.SevenZipPath)) {
        return $config.SevenZipPath
    }
    $candidates = @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    $fromPath = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }
    return $null
}

$sevenZip = Find-SevenZip
if (-not $sevenZip) {
    Write-Error "7-Zip не найден. Укажите путь в config.json (SevenZipPath) или установите 7-Zip."
    exit 1
}

# --- Лог ----------------------------------------------------------------------

$logName = 'backup_{0:yyyy-MM-dd_HH-mm-ss}.log' -f (Get-Date)
$logPath = Join-Path $destination $logName

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO')
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    Write-Host $line
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

Write-Log "Старт бэкапа. Конфиг: $ConfigPath"
Write-Log "Назначение: $destination"
Write-Log "7-Zip: $sevenZip"

# --- КоличествоДнейАктуальности ------------------------------------------------

$keepDays = $null

if ($null -ne $config.КоличествоДнейАктуальности) {
    $rawDays = "$($config.КоличествоДнейАктуальности)".Trim()
    if ($rawDays -match '^\d+$') {
        $keepDays = [int]$rawDays
    }
    else {
        Write-Log "Некорректное значение КоличествоДнейАктуальности в конфиге: '$rawDays'" WARN
    }
}

if ($null -eq $keepDays) {
    if ([Console]::IsInputRedirected) {
        Write-Log 'КоличествоДнейАктуальности не задан в конфиге, запуск неинтерактивный - ротация ПРОПУЩЕНА.' WARN
    }
    else {
        while ($null -eq $keepDays) {
            $daysInput = Read-Trimmed 'Сколько дней хранить архивы (Enter = 30, 0 = не удалять)'
            if ($daysInput -eq '') { $keepDays = 30 }
            elseif ($daysInput -match '^\d+$') { $keepDays = [int]$daysInput }
            else { Write-Host '  Нужно целое число.' -ForegroundColor Red }
        }
    }
}

if ($null -ne $keepDays) {
    if ($keepDays -eq 0) {
        Write-Log 'Ротация отключена (КоличествоДнейАктуальности = 0).'
    }
    else {
        $cutoffDate = (Get-Date).Date.AddDays(-$keepDays)
        Write-Log ("Ротация: будут удалены архивы с датой в имени раньше {0:dd.MM.yyyy}." -f $cutoffDate)
    }
}

# --- SQLite-лог ----------------------------------------------------------------

$dbConn = $null
$runId = $null

# dll рядом со скриптом (или в lib\) либо модуль PSSQLite (положит сборку в GAC процесса)
function Find-SqliteDll {
    if ($PSScriptRoot) {
        foreach ($p in @(
            (Join-Path $PSScriptRoot 'System.Data.SQLite.dll'),
            (Join-Path $PSScriptRoot 'lib\System.Data.SQLite.dll')
        )) {
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    try {
        Import-Module PSSQLite -ErrorAction Stop
        if ('System.Data.SQLite.SQLiteConnection' -as [type]) { return 'module' }
    } catch { }
    return $null
}

function Invoke-Db {
    param([string]$Sql, [hashtable]$Params = @{})
    if (-not $dbConn) { return $null }
    $cmd = $dbConn.CreateCommand()
    try {
        $cmd.CommandText = $Sql
        foreach ($k in $Params.Keys) {
            [void]$cmd.Parameters.AddWithValue("@$k", $Params[$k])
        }
        return $cmd.ExecuteScalar()
    }
    finally { $cmd.Dispose() }
}

$dbPath = if ($config.LogDb) { [Environment]::ExpandEnvironmentVariables($config.LogDb) }
          else { Join-Path $destination 'backup_log.db' }

$sqliteDll = Find-SqliteDll
if (-not $sqliteDll) {
    Write-Log 'SQLite: System.Data.SQLite.dll не найден (положите рядом со скриптом или установите модуль PSSQLite) - запись в БД отключена.' WARN
}
else {
    try {
        if ($sqliteDll -ne 'module') { Add-Type -Path $sqliteDll -ErrorAction Stop }
        $dbConn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=`"$dbPath`";Version=3;")
        $dbConn.Open()

        # WAL не блокирует чтение во время записи (удобно для внешних просмотров)
        [void](Invoke-Db 'PRAGMA journal_mode=WAL;')

        Invoke-Db 'CREATE TABLE IF NOT EXISTS bases (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, path TEXT NOT NULL, is_active INTEGER NOT NULL DEFAULT 1);'
        Invoke-Db 'CREATE TABLE IF NOT EXISTS runs (id INTEGER PRIMARY KEY, started_at TEXT NOT NULL, finished_at TEXT, config_path TEXT, destination TEXT, keep_days INTEGER, status TEXT NOT NULL DEFAULT ''running'', ok_count INTEGER NOT NULL DEFAULT 0, failed_count INTEGER NOT NULL DEFAULT 0, exit_code INTEGER, log_file TEXT);'
        Invoke-Db 'CREATE TABLE IF NOT EXISTS run_results (id INTEGER PRIMARY KEY, run_id INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE, base_id INTEGER REFERENCES bases(id), base_name TEXT NOT NULL, status TEXT NOT NULL, archive_name TEXT, archive_size_mb REAL, duration_sec REAL, error_text TEXT);'
        Invoke-Db 'CREATE TABLE IF NOT EXISTS rotation_events (id INTEGER PRIMARY KEY, run_id INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE, action TEXT NOT NULL, archive_name TEXT, cutoff_date TEXT, detail TEXT);'
        Invoke-Db 'CREATE INDEX IF NOT EXISTS idx_results_run ON run_results(run_id);'
        Invoke-Db 'CREATE INDEX IF NOT EXISTS idx_results_base ON run_results(base_id);'
        Invoke-Db 'CREATE INDEX IF NOT EXISTS idx_rotation_run ON rotation_events(run_id);'
        Invoke-Db 'CREATE INDEX IF NOT EXISTS idx_runs_started ON runs(started_at);'

        $runId = Invoke-Db "INSERT INTO runs (started_at, config_path, destination, keep_days, status, log_file)
                            VALUES (datetime('now','localtime'), @cfg, @dst, @kd, 'running', @log);
                            SELECT last_insert_rowid();" @{
            cfg = $ConfigPath; dst = $destination
            kd  = $keepDays;   log = $logPath
        }
        Write-Log "SQLite: лог пишется в $dbPath (run_id=$runId)"
    }
    catch {
        Write-Log "SQLite: не удалось инициализировать БД ($dbPath): $($_.Exception.Message) - запись в БД отключена." WARN
        if ($dbConn) { try { $dbConn.Close() } catch { } }
        $dbConn = $null; $runId = $null
    }
}

function Get-BaseId {
    param([string]$Name, [string]$Path)
    if (-not $dbConn) { return $null }
    [void](Invoke-Db 'INSERT OR IGNORE INTO bases (name, path) VALUES (@n, @p);' @{ n = $Name; p = $Path })
    [void](Invoke-Db 'UPDATE bases SET path = @p, is_active = 1 WHERE name = @n;' @{ n = $Name; p = $Path })
    return Invoke-Db 'SELECT id FROM bases WHERE name = @n;' @{ n = $Name }
}

# --- Бэкап баз ----------------------------------------------------------------

$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("1c-backup-" + $stamp)
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

$ok = 0
$failed = 0

$completed = $false

try {
    foreach ($base in $config.Bases) {
    $name = $base.Name
    $source = [Environment]::ExpandEnvironmentVariables($base.Path)

    # если указан каталог базы - достраиваем имя файла
    if (Test-Path -LiteralPath $source -PathType Container) {
        $source = Join-Path $source '1Cv8.1CD'
    }

    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = [IO.Path]::GetFileNameWithoutExtension((Split-Path $source -Parent))
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        Write-Log "БАЗА НЕ НАЙДЕНА: $name -> $source" ERROR
        Invoke-Db "INSERT INTO run_results (run_id, base_id, base_name, status, duration_sec, error_text)
                   VALUES (@run, @bid, @name, 'not_found', @dur, @err)" @{
            run = $runId; bid = (Get-BaseId $name $base.Path)
            name = $name; dur = [math]::Round($sw.Elapsed.TotalSeconds, 1); err = "не найден: $source" }
        $failed++
        continue
    }

    $baseTempDir = Join-Path $tempRoot $name
    $tempCopy = Join-Path $baseTempDir '1Cv8.1CD'
    $archiveName = "{0}_{1}.7z" -f $name, $stamp
    $tempArchive = Join-Path $tempRoot $archiveName
    $finalArchive = Join-Path $destination $archiveName

    try {
        New-Item -ItemType Directory -Path $baseTempDir -Force | Out-Null
        Write-Log "Копирование: $source -> $tempCopy"
        Copy-Item -LiteralPath $source -Destination $tempCopy -Force

        Write-Log "Архивация: $tempArchive"
        # пакуем из папки базы, чтобы внутри архива файл звался 1Cv8.1CD
        Push-Location $baseTempDir
        try {
            & $sevenZip @('a', '-t7z', '-mx=5', '-y', $tempArchive, '1Cv8.1CD') | Out-Null
        }
        finally {
            Pop-Location
        }
        if ($LASTEXITCODE -ne 0) {
            throw "7-Zip завершился с кодом $LASTEXITCODE"
        }

        Write-Log "Перенос архива: $finalArchive"
        Move-Item -LiteralPath $tempArchive -Destination $finalArchive -Force

        $sizeMb = [math]::Round((Get-Item -LiteralPath $finalArchive).Length / 1MB, 2)
        Write-Log "OK: $name ($sizeMb МБ)"
        $ok++
        Invoke-Db "INSERT INTO run_results (run_id, base_id, base_name, status, archive_name, archive_size_mb, duration_sec)
                   VALUES (@run, @bid, @name, 'ok', @arch, @sz, @dur)" @{
            run = $runId; bid = (Get-BaseId $name $base.Path)
            name = $name; arch = $archiveName; sz = $sizeMb
            dur = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
    }
    catch {
        Write-Log "ОШИБКА для '$name': $($_.Exception.Message)" ERROR
        $failed++
        Invoke-Db "INSERT INTO run_results (run_id, base_id, base_name, status, duration_sec, error_text)
                   VALUES (@run, @bid, @name, 'error', @dur, @err)" @{
            run = $runId; bid = (Get-BaseId $name $base.Path)
            name = $name; dur = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            err = $_.Exception.Message }
        if (Test-Path -LiteralPath $tempArchive)  { Remove-Item -LiteralPath $tempArchive -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $finalArchive)  { Remove-Item -LiteralPath $finalArchive -Force -ErrorAction SilentlyContinue }
    }
}

    # --- Ротация (только при полном успехе и заданном КоличествоДнейАктуальности) --

    # базы, которых больше нет в конфиге, помечаем неактивными (историю не трогаем)
    if ($dbConn) {
        [void](Invoke-Db 'UPDATE bases SET is_active = 0;')
        foreach ($b in $config.Bases) {
            [void](Invoke-Db 'UPDATE bases SET is_active = 1 WHERE name = @n;' @{ n = $b.Name })
        }
    }

    if ($null -eq $keepDays -or $keepDays -eq 0) {
        # уже отражено в логе выше (WARN про пропуск или отключение)
        if ($null -eq $keepDays) {
            Invoke-Db "INSERT INTO rotation_events (run_id, action, detail)
                       VALUES (@run, 'skipped', @d)" @{ run = $runId; d = 'КоличествоДнейАктуальности не задан / неинтерактивный запуск' }
        }
        elseif ($keepDays -eq 0) {
            Invoke-Db "INSERT INTO rotation_events (run_id, action, detail)
                       VALUES (@run, 'disabled', @d)" @{ run = $runId; d = 'КоличествоДнейАктуальности = 0' }
        }
    }
    elseif ($failed -gt 0) {
        Write-Log "Ротация ПРОПУЩЕНА: бэкап завершился с ошибками (успешно: $ok, с ошибками: $failed) - старые архивы оставлены как страховка." WARN
        Invoke-Db "INSERT INTO rotation_events (run_id, action, detail)
                   VALUES (@run, 'skipped', @d)" @{ run = $runId; d = "бэкап с ошибками (ok=$ok, failed=$failed)" }
    }
    else {
        $deletedCount = 0
        # имена файлов вида <Имя>_<штамп>.7z; дата берём из имени, а не LastWriteTime
        $allArchives = Get-ChildItem -LiteralPath $destination -Filter '*.7z' -File
        foreach ($base in $config.Bases) {
            $pattern = '^' + [regex]::Escape($base.Name) + '_(\d{4})-(\d{2})-(\d{2})_\d{2}-\d{2}-\d{2}\.7z$'
            foreach ($arch in $allArchives) {
                $m = [regex]::Match($arch.Name, $pattern)
                if (-not $m.Success) { continue }
                $archDate = Get-Date -Year $m.Groups[1].Value -Month $m.Groups[2].Value -Day $m.Groups[3].Value -Hour 0 -Minute 0 -Second 0
                if ($archDate -lt $cutoffDate) {
                    try {
                        Remove-Item -LiteralPath $arch.FullName -Force
                        $deletedCount++
                        Write-Log "Ротация: удалён архив $($arch.Name)"
                        Invoke-Db "INSERT INTO rotation_events (run_id, action, archive_name, cutoff_date)
                                   VALUES (@run, 'deleted', @a, @c)" @{ run = $runId; a = $arch.Name; c = $cutoffDate.ToString('yyyy-MM-dd') }
                        # записи об этом архиве в БД больше не актуальны
                        Invoke-Db 'DELETE FROM run_results WHERE archive_name = @a;' @{ a = $arch.Name }
                    }
                    catch {
                        Write-Log "Ротация: не удалось удалить $($arch.Name): $($_.Exception.Message)" WARN
                        Invoke-Db "INSERT INTO rotation_events (run_id, action, archive_name, cutoff_date, detail)
                                   VALUES (@run, 'delete_failed', @a, @c, @d)" @{ run = $runId; a = $arch.Name; c = $cutoffDate.ToString('yyyy-MM-dd'); d = $_.Exception.Message }
                    }
                }
            }
        }
        Write-Log ("Ротация: удалено архивов - {0} (старше {1:dd.MM.yyyy})." -f $deletedCount, $cutoffDate)
    }

    $completed = $true
}
finally {
    # --- Очистка (выполняется и при нормальном завершении, и при Ctrl+C) ---

    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue

    if ($completed) {
        Write-Log "Готово. Успешно: $ok, с ошибками: $failed. Лог: $logPath"
        $exitCode = if ($failed -gt 0) { 2 } else { 0 }
        $status   = if ($failed -gt 0) { 'partial' } else { 'ok' }
    }
    else {
        Write-Log "ВЫПОЛНЕНИЕ ПРЕРВАНО: обработаны не все базы. Успешно: $ok, с ошибками: $failed. Временные файлы в $tempRoot удалены." ERROR
        $exitCode = 3
        $status   = 'aborted'
    }

    if ($dbConn) {
        try {
            Invoke-Db "UPDATE runs SET finished_at = datetime('now','localtime'), status = @st,
                       ok_count = @ok, failed_count = @f, exit_code = @ex WHERE id = @id" @{
                st = $status; ok = $ok; f = $failed; ex = $exitCode; id = $runId }
        }
        catch { Write-Host "SQLite: не удалось зафиксировать итог запуска: $($_.Exception.Message)" }
        try { $dbConn.Close() } catch { }
    }

    exit $exitCode
}
