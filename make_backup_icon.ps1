# make_backup_icon.ps1 — иконка приложения бэкапа: чиби-динозаврик тащит значок 1С (BMP-кадры 16/32/48/256)
Add-Type -AssemblyName System.Drawing

$Script:Scale = 1.0
function S([int]$v) { [int][Math]::Round($v * $Script:Scale) }

function To-Points([int[]]$raw) {
    $pts = New-Object 'System.Drawing.PointF[]' ($raw.Count / 2)
    for ($i = 0; $i -lt $pts.Count; $i++) {
        $pts[$i] = New-Object System.Drawing.PointF((S $raw[$i * 2]), (S $raw[$i * 2 + 1]))
    }
    return , $pts
}

function New-RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x, $y, $r, $r, 180, 90); $p.AddArc(($x + $w - $r), $y, $r, $r, 270, 90)
    $p.AddArc(($x + $w - $r), ($y + $h - $r), $r, $r, 0, 90); $p.AddArc($x, ($y + $h - $r), $r, $r, 90, 90)
    $p.CloseFigure()
    return $p
}

function Draw-Icon([int]$px) {
    $Script:Scale = $px / 256.0
    $bmp = New-Object System.Drawing.Bitmap($px, $px)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([System.Drawing.Color]::Transparent)

    $cTile   = [System.Drawing.Color]::FromArgb(255, 32, 32, 40)    # тёмная плитка фона
    $cLine   = [System.Drawing.Color]::FromArgb(255, 122, 78, 50)   # мягкий коричневый контур
    $cBody   = [System.Drawing.Color]::FromArgb(255, 242, 174, 132) # персиковое тело
    $cBelly  = [System.Drawing.Color]::FromArgb(255, 251, 227, 200) # светлое брюшко
    $cSpike  = [System.Drawing.Color]::FromArgb(255, 222, 138, 84)  # гребешки
    $cBlush  = [System.Drawing.Color]::FromArgb(255, 240, 153, 110) # румянец
    $cEye    = [System.Drawing.Color]::FromArgb(255, 58, 42, 34)    # глаза
    $cMouth  = [System.Drawing.Color]::FromArgb(255, 92, 54, 38)    # открытая пасть
    $cTeeth  = [System.Drawing.Color]::FromArgb(255, 255, 246, 236) # зубки
    $c1cBg   = [System.Drawing.Color]::FromArgb(255, 247, 200, 28)  # жёлтый значок 1С
    $c1cTx   = [System.Drawing.Color]::FromArgb(255, 194, 30, 38)   # надпись 1С

    $penLine = New-Object System.Drawing.Pen($cLine, [Math]::Max(2, (S 6)))
    $penLine.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $bBody  = New-Object System.Drawing.SolidBrush($cBody)
    $bSpike = New-Object System.Drawing.SolidBrush($cSpike)

    # тёмная скруглённая плитка
    $g.FillPath((New-Object System.Drawing.SolidBrush($cTile)), (New-RoundRect (S 8) (S 8) (S 240) (S 240) (S 48)))

    # хвост: изогнутый, сужающийся к кончику, задран вверх (основание спрятано под телом)
    $tail = New-Object System.Drawing.Drawing2D.GraphicsPath
    $tail.StartFigure()
    $tail.AddBezier((S 84), (S 180), (S 58), (S 172), (S 36), (S 152), (S 20), (S 150))
    $tail.AddBezier((S 20), (S 150), (S 36), (S 160), (S 60), (S 188), (S 84), (S 202))
    $tail.CloseFigure()
    $g.FillPath($bBody, $tail); $g.DrawPath($penLine, $tail)

    # лапки-стоялки, разнесены шире
    foreach ($lx in @(72, 122)) {
        $leg = New-RoundRect (S $lx) (S 202) (S 24) (S 36) (S 11)
        $g.FillPath($bBody, $leg); $g.DrawPath($penLine, $leg)
    }

    # тело (высокое перекрытие под голову — чистый стык) + брюшко
    $g.FillEllipse($bBody, (S 70), (S 126), (S 80), (S 90))
    $g.DrawEllipse($penLine, (S 70), (S 126), (S 80), (S 90))
    $g.FillEllipse((New-Object System.Drawing.SolidBrush($cBelly)), (S 91), (S 158), (S 38), (S 40))

    # гребешки на макушке (рисуются до головы: основания спрячутся под ней), зеркально x=107
    foreach ($spk in @(
        , @(64, 66, 84, 46, 48, 28)
        , @(88, 44, 107, 12, 126, 44)
        , @(130, 46, 150, 66, 166, 28)
    )) {
        $tp = New-Object System.Drawing.Drawing2D.GraphicsPath
        $tp.AddPolygon((To-Points $spk))
        $g.FillPath($bSpike, $tp); $g.DrawPath($penLine, $tp)
    }

    # крупная голова + светлая морда (нос и рот живут на ней)
    $g.FillEllipse($bBody, (S 48), (S 40), (S 118), (S 100))
    $g.DrawEllipse($penLine, (S 48), (S 40), (S 118), (S 100))
    $g.FillEllipse((New-Object System.Drawing.SolidBrush($cBelly)), (S 56), (S 84), (S 102), (S 52))

    # румянец на щеках (симметрично центру головы x=107)
    foreach ($bx in @(61, 140)) {
        $g.FillEllipse((New-Object System.Drawing.SolidBrush($cBlush)), (S $bx), (S 99), (S 13), (S 8))
    }

    # ноздри на морде, на одной высоте
    $nh = [Math]::Max(1.5, (S 2.5))
    $g.FillEllipse((New-Object System.Drawing.SolidBrush($cEye)), (S 124), (S 92), $nh, $nh)
    $g.FillEllipse((New-Object System.Drawing.SolidBrush($cEye)), (S 134), (S 92), $nh, $nh)

    # открытая улыбка по центру морды: тёмная чаша + белые зубчики сверху
    $mouth = New-Object System.Drawing.Drawing2D.GraphicsPath
    $mouth.AddArc((S 76), (S 94), (S 62), (S 38), 0, 180)
    $mouth.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush($cMouth)), $mouth)
    $bTeeth = New-Object System.Drawing.SolidBrush($cTeeth)
    for ($i = 0; $i -lt 4; $i++) {
        $x0 = 77 + $i * 15
        $tooth = New-Object System.Drawing.Drawing2D.GraphicsPath
        $tooth.AddPolygon((To-Points @([int]$x0, 113, [int]($x0 + 15), 113, [int]($x0 + 7.5), 120)))
        $g.FillPath($bTeeth, $tooth)
    }
    $g.DrawPath($penLine, $mouth)

    # глаза с бликами: центры (81,70) и (133,70) — симметричны относительно x=107
    $eyeW = [Math]::Max(2, (S 22))
    $hlW  = [Math]::Max(1.5, (S 7))
    foreach ($ex in @(81, 133)) {
        $g.FillEllipse((New-Object System.Drawing.SolidBrush($cEye)), (S ($ex - 11)), (S 59), $eyeW, $eyeW)
        $g.FillEllipse($bTeeth, (S ($ex - 7)), (S 62), $hlW, $hlW)
    }

    # лапа тянет значок: почти горизонтальная, вниз — динозавр тащит, а не несёт
    $capRound = [System.Drawing.Drawing2D.LineCap]::Round
    $penArmDark = New-Object System.Drawing.Pen($cLine, [Math]::Max(3, (S 15)))
    $penArm     = New-Object System.Drawing.Pen($cBody, [Math]::Max(2, (S 9)))
    $penArmDark.StartCap = $capRound; $penArmDark.EndCap = $capRound
    $penArm.StartCap = $capRound; $penArm.EndCap = $capRound
    $g.DrawLine($penArmDark, (S 110), (S 170), (S 146), (S 171))
    $g.DrawLine($penArm, (S 110), (S 170), (S 146), (S 171))

    # значок 1С: жёлтый скруглённый квадрат с надписью, низко у земли
    $badge = New-RoundRect (S 152) (S 150) (S 84) (S 84) (S 16)
    $g.FillPath((New-Object System.Drawing.SolidBrush($c1cBg)), $badge)
    $g.DrawPath($penLine, $badge)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $font1c = New-Object System.Drawing.Font('Arial', [float](S 38), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $g.DrawString('1С', $font1c, (New-Object System.Drawing.SolidBrush($c1cTx)), (New-Object System.Drawing.RectangleF((S 152), (S 148), (S 84), (S 88))), $fmt)
    $font1c.Dispose()

    # кольцо-ручка на левом ребре значка (полный эллипс, кисть закроет левую половину)
    $penHandleDark = New-Object System.Drawing.Pen($cLine, [Math]::Max(3, (S 11)))
    $penHandle     = New-Object System.Drawing.Pen($c1cBg, [Math]::Max(2, (S 6)))
    $penHandleDark.StartCap = $capRound; $penHandleDark.EndCap = $capRound
    $penHandle.StartCap = $capRound; $penHandle.EndCap = $capRound
    $g.DrawArc($penHandleDark, (S 148), (S 158), (S 26), (S 26), 0, 360)
    $g.DrawArc($penHandle, (S 148), (S 158), (S 26), (S 26), 0, 360)

    # кисть сжимает кольцо
    $handPx = [Math]::Max(3, (S 19))
    $g.FillEllipse($bBody, (S 141), (S 163), $handPx, $handPx)
    $g.DrawEllipse($penLine, (S 141), (S 163), $handPx, $handPx)

    $g.Dispose()
    return $bmp
}

function Frame-Bytes([System.Drawing.Bitmap]$bmp) {
    $w = $bmp.Width; $h = $bmp.Height
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $stride = $data.Stride
    $raw = [byte[]]::new($stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $raw, 0, $raw.Length)
    $bmp.UnlockBits($data)

    $andRow = [Math]::Floor(($w + 31) / 32) * 4
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([uint32]40); $bw.Write([int32]$w); $bw.Write([int32]($h * 2))
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]0)
    $bw.Write([uint32]($h * $andRow))
    $bw.Write([int32]0); $bw.Write([int32]0); $bw.Write([uint32]0); $bw.Write([uint32]0)
    for ($yy = $h - 1; $yy -ge 0; $yy--) {
        for ($xx = 0; $xx -lt $w; $xx++) {
            $o = $yy * $stride + $xx * 4
            $bw.Write($raw[$o]); $bw.Write($raw[$o + 1]); $bw.Write($raw[$o + 2]); $bw.Write($raw[$o + 3])
        }
    }
    $zeros = [byte[]]::new($andRow * $h)
    $bw.Write($zeros)
    $bw.Flush()
    return , ($ms.ToArray())
}

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sizes = @(16, 32, 48, 256)
$frames = @()
foreach ($s in $sizes) {
    $bytes = Frame-Bytes (Draw-Icon $s)
    $frames += , @{ W = $s; Data = $bytes }
}

$out = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($out)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$frames.Count)
$offset = 6 + 16 * $frames.Count
for ($i = 0; $i -lt $frames.Count; $i++) {
    $f = $frames[$i]
    $dim = if ($f.W -ge 256) { 0 } else { $f.W }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$f.Data.Length); $bw.Write([uint32]$offset)
    $offset += $f.Data.Length
}
foreach ($f in $frames) { $bw.Write($f.Data) }

$bw.Flush()
[IO.File]::WriteAllBytes((Join-Path $dir 'T-REX-backup.ico'), $out.ToArray())
$preview = Draw-Icon 256
$preview.Save((Join-Path $dir 'T-REX-backup-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$preview.Dispose()
Write-Output ("ico: " + (Get-Item (Join-Path $dir 'T-REX-backup.ico')).Length + " bytes")
