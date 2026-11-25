[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Project,
    [string]$Music = '',
    [double]$MusicVolume = -1,
    [string]$Font = '',
    [string]$OutFile = '',
    [int]$Crf = 19,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/common.ps1"

$inv = [Globalization.CultureInfo]::InvariantCulture
$projPath = (Resolve-Path -LiteralPath $Project).Path
$dir = Split-Path -Parent $projPath
$proj = Read-JsonFile -Path $projPath

$ffmpeg = Resolve-Tool -Name 'ffmpeg'
$ffprobe = Resolve-Tool -Name 'ffprobe'

$timingsPath = Join-Path $dir 'assets/vo/timings.json'
if (-not (Test-Path -LiteralPath $timingsPath)) {
    throw "Falta $timingsPath. Ejecuta primero scripts/tts.ps1."
}
$timings = Read-JsonFile -Path $timingsPath
$timingById = @{}
foreach ($t in @($timings.scenes)) { $timingById[[string]$t.id] = $t }

$fps = if ($proj.fps) { [int]$proj.fps } else { 30 }
$w = if ($proj.width) { [int]$proj.width } else { 1080 }
$h = if ($proj.height) { [int]$proj.height } else { 1920 }
$style = $proj.style
$fontName = if ($Font) { $Font } elseif ($style -and $style.font) { $style.font } else { 'Arial Black' }
$captionSize = if ($style -and $style.caption_size) { [int]$style.caption_size } else { 76 }
$marginV = if ($style -and $style.margin_v) { [int]$style.margin_v } else { 300 }
$primaryColor = if ($style -and $style.caption_color) { $style.caption_color } else { '&H00FFFFFF' }

$musicPath = if ($Music) { $Music } elseif ($proj.music) { $proj.music } else { '' }
if ($musicPath -and -not [IO.Path]::IsPathRooted($musicPath)) {
    $candidate = Join-Path $dir $musicPath
    if (Test-Path -LiteralPath $candidate) { $musicPath = $candidate }
}
if ($musicPath -and -not (Test-Path -LiteralPath $musicPath)) {
    Write-Warning "No encuentro la musica '$musicPath'; se renderiza sin musica."
    $musicPath = ''
}
$volume = if ($MusicVolume -ge 0) { $MusicVolume } elseif ($proj.music_volume) { [double]$proj.music_volume } else { 0.12 }
$volumeStr = $volume.ToString('0.###', $inv)

$build = Join-Path $dir 'build'
$outDir = Join-Path $dir 'out'
New-Item -ItemType Directory -Force -Path $build | Out-Null
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if ([string]::IsNullOrWhiteSpace($OutFile)) {
    $slug = if ($proj.slug) { $proj.slug } else { 'reel' }
    $OutFile = Join-Path $outDir ("reel-{0}.mp4" -f $slug)
}
elseif (-not [IO.Path]::IsPathRooted($OutFile)) {
    $OutFile = Join-Path $dir $OutFile
}

$sceneFiles = @()
$sceneIndex = 0

foreach ($scene in @($proj.scenes)) {
    $sceneIndex++
    $id = [string]$scene.id
    if ([string]::IsNullOrWhiteSpace($id)) { throw "Escena sin id en project.json" }
    if (-not $timingById.ContainsKey($id)) {
        throw "Falta la duracion de la escena $id. Ejecuta scripts/tts.ps1."
    }

    $t = $timingById[$id]
    $dur = [double]$t.duration
    if ($dur -le 0.2) { throw "Duracion invalida en escena $id" }
    $durStr = $dur.ToString('0.###', $inv)

    $audioPath = [IO.Path]::GetFullPath((Join-Path $dir $t.audio))
    if (-not (Test-Path -LiteralPath $audioPath)) { throw "Falta el audio $audioPath" }

    $videoPath = ''
    if ($scene.video_path) {
        $candidate = [IO.Path]::GetFullPath((Join-Path $dir $scene.video_path))
        if (Test-Path -LiteralPath $candidate) { $videoPath = $candidate }
        else { Write-Warning "Escena ${id}: video_path no existe; se usa imagen." }
    }
    if (-not $videoPath) {
        $vbase = Join-Path $dir ("assets/videos/scene-{0}" -f $id)
        foreach ($ext in @('.mp4', '.mov', '.webm', '.mkv')) {
            if (Test-Path -LiteralPath ($vbase + $ext)) { $videoPath = $vbase + $ext; break }
        }
    }

    $imagePath = ''
    if (-not $videoPath) {
        if ($scene.image_path) { $imagePath = [IO.Path]::GetFullPath((Join-Path $dir $scene.image_path)) }
        else {
            $imgDir = Join-Path $dir 'assets/images'
            $exact = Join-Path $imgDir ("scene-{0}.jpg" -f $id)
            if (Test-Path -LiteralPath $exact) {
                $imagePath = $exact
            }
            else {
                $pattern = '^scene-' + [regex]::Escape($id) + '(?![0-9])'
                $candidate = Get-ChildItem -LiteralPath $imgDir -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.BaseName -match $pattern -and $_.Extension -match '^\.(jpg|jpeg|png|webp)$' } |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1
                if ($candidate) { $imagePath = $candidate.FullName }
                else { $imagePath = $exact }
            }
        }
        if (-not (Test-Path -LiteralPath $imagePath)) {
            throw "Falta la imagen de la escena $id ($imagePath). Ejecuta gen-images.ps1 o define image_path."
        }
    }

    $sceneOut = Join-Path $build ("scene-{0}.mp4" -f $id)
    $sceneFiles += $sceneOut

    if ($videoPath) {
        $vf = "scale=${w}:${h}:force_original_aspect_ratio=increase,crop=${w}:${h},fps=${fps},format=yuv420p"
        & $ffmpeg -y -stream_loop -1 -i $videoPath -i $audioPath -t $durStr -vf $vf `
            -map 0:v:0 -map 1:a:0 `
            -af "apad=whole_dur=$durStr" -c:v libx264 -preset medium -crf 18 `
            -c:a aac -b:a 192k -ar 48000 -ac 2 -shortest $sceneOut
    }
    else {
        $motion = if ($scene.motion) { [string]$scene.motion } else { 'zoom-in' }
        switch ($motion) {
            'zoom-out' { $z = "max(1.14-0.0012*on,1.0)" }
            'static' { $z = "1.06" }
            default { $z = "min(1.0+0.0012*on,1.14)" }
        }
        $vf = "scale=${w}:${h}:force_original_aspect_ratio=increase,crop=${w}:${h},zoompan=z='$z':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=${w}x${h}:fps=${fps},format=yuv420p"
        & $ffmpeg -y -loop 1 -framerate $fps -t $durStr -i $imagePath -i $audioPath -vf $vf `
            -map 0:v:0 -map 1:a:0 `
            -af "apad=whole_dur=$durStr" -t $durStr -c:v libx264 -preset medium -crf 18 `
            -c:a aac -b:a 192k -ar 48000 -ac 2 -shortest $sceneOut
    }

    if ($LASTEXITCODE -ne 0) { throw "ffmpeg fallo al construir la escena $id" }
    Write-Host ("Escena {0}: {1:N2}s OK" -f $id, $dur)
}

$concat = Join-Path $build 'concat.txt'
$concatLines = foreach ($file in $sceneFiles) { "file '" + ($file -replace '\\', '/') + "'" }
Set-Content -LiteralPath $concat -Value $concatLines -Encoding ascii

$videoFile = Join-Path $build 'video.mp4'
& $ffmpeg -y -f concat -safe 0 -i $concat -c copy $videoFile
if ($LASTEXITCODE -ne 0) { throw "ffmpeg fallo al concatenar las escenas" }

$assPath = Join-Path $build 'captions.ass'
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('[Script Info]')
[void]$sb.AppendLine('ScriptType: v4.00+')
[void]$sb.AppendLine("PlayResX: $w")
[void]$sb.AppendLine("PlayResY: $h")
[void]$sb.AppendLine('WrapStyle: 0')
[void]$sb.AppendLine('ScaledBorderAndShadow: yes')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('[V4+ Styles]')
[void]$sb.AppendLine('Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding')
$safeFont = $fontName.Replace(',', ' ')
[void]$sb.AppendLine("Style: Default,$safeFont,$captionSize,$primaryColor,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,7,2,2,90,90,$marginV,1")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('[Events]')
[void]$sb.AppendLine('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text')

foreach ($scene in @($proj.scenes)) {
    $id = [string]$scene.id
    $t = $timingById[$id]
    $caption = [string]$scene.caption
    if ([string]::IsNullOrWhiteSpace($caption)) {
        $words = ([string]$scene.voiceover) -split '\s+'
        $caption = ($words | Select-Object -First 6) -join ' '
    }
    if ([string]::IsNullOrWhiteSpace($caption)) { continue }

    $text = Wrap-Caption -Text $caption.ToUpperInvariant()
    $startS = [double]$t.start
    $endS = $startS + [double]$t.duration
    [void]$sb.AppendLine("Dialogue: 0,$(Format-AssTime -Seconds $startS),$(Format-AssTime -Seconds $endS),Default,,0,0,0,,$text")
}
Set-Content -LiteralPath $assPath -Value $sb.ToString() -Encoding utf8

$hasMusic = -not [string]::IsNullOrWhiteSpace($musicPath)
if ($hasMusic) {
    $filter = "[0:v]ass=build/captions.ass,scale=out_range=tv,format=yuv420p[vout];" +
    "[0:a]aformat=sample_rates=48000:channel_layouts=stereo,asplit=2[vo1][vo2];" +
    "[1:a]aformat=sample_rates=48000:channel_layouts=stereo,volume=$volumeStr,aloop=loop=-1:size=2147483647[m];" +
    "[m][vo1]sidechaincompress=threshold=0.03:ratio=8:attack=5:release=250[duck];" +
    "[vo2][duck]amix=inputs=2:duration=first:dropout_transition=0,alimiter=limit=0.95,loudnorm=I=-14:TP=-1.5:LRA=11[aout]"
}
else {
    $filter = "[0:v]ass=build/captions.ass,scale=out_range=tv,format=yuv420p[vout];" +
    "[0:a]loudnorm=I=-14:TP=-1.5:LRA=11[aout]"
}

Push-Location $dir
try {
    $args = @('-y', '-i', 'build/video.mp4')
    if ($hasMusic) { $args += @('-i', $musicPath) }
    $args += @(
        '-filter_complex', $filter,
        '-map', '[vout]', '-map', '[aout]',
        '-c:v', 'libx264', '-preset', 'slow', '-crf', "$Crf",
        '-profile:v', 'high', '-level', '4.0', '-r', "$fps", '-g', "$($fps * 2)",
        '-pix_fmt', 'yuv420p', '-color_range', 'tv',
        '-c:a', 'aac', '-b:a', '192k', '-ar', '48000',
        '-movflags', '+faststart',
        $OutFile
    )
    & $ffmpeg @args
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg fallo en el render final" }
}
finally {
    Pop-Location
}

$cover = Join-Path $outDir 'cover.jpg'
& $ffmpeg -y -ss 0.6 -i $OutFile -frames:v 1 -update 1 -q:v 2 $cover | Out-Null

if ($Clean) { Remove-Item -LiteralPath $build -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "Reel: $OutFile"
Write-Host "Cover: $cover"
Write-Host "Siguiente: pwsh -File `"$PSScriptRoot\qa-reel.ps1`" -Project `"$projPath`""
