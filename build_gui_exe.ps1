# Сборка t-rex_backup1C.exe из backup-1c-gui.ps1 (иконка: чиби-динозаврик тащит значок «1С»)
$ErrorActionPreference = 'Stop'
. "$env:USERPROFILE\Documents\PowerShell\Modules\ps2exe\1.0.18\ps2exe.ps1"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$outExe = Join-Path $dir 't-rex_backup1C.exe'
invoke-ps2exe -inputFile (Join-Path $dir 'backup-1c-gui.ps1') `
              -outputFile $outExe `
              -iconFile (Join-Path $dir 'T-REX-backup.ico') `
              -title 'T-REX бэкап файловых баз 1С' `
              -description 'T-REX бэкап файловых баз 1С v1.5 — GUI бэкапа файловых баз 1С (автор Валентин Суровцев, 2026)' `
              -product 'T-REX бэкап файловых баз 1С' `
              -sta -noConsole
Write-Output ("built: " + (Get-Item $outExe).Length + " bytes")
