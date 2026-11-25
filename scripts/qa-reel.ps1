[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Project,
    [string]$File = ''
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/common.ps1"

$projPath = (Resolve-Path -LiteralPath $Project).Path
$dir = Split-Path -Parent $projPath
$proj = Read-JsonFile -Path $projPath

if ([string]::IsNullOrWhiteSpace($File)) {
    $slug = if ($proj.slug) { $proj.slug } else { 'reel' }
    $File = Join-Path $dir ("out/reel-{0}.mp4" -f $slug)
}
elseif (-not [IO.Path]::IsPathRooted($File)) {
    $File = Join-Path $dir $File
}
if (-not (Test-Path -LiteralPath $File)) { throw "No existe el video: $File" }

$ffprobe = Resolve-Tool -Name 'ffprobe'
$ffmpeg = Resolve-Tool -Name 'ffmpeg'

$info = & $ffprobe -v error -print_format json -show_format -show_streams $File | ConvertFrom-Json
$video = @($info.streams) | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
$audio = @($info.streams) | Where-Object { $_.codec_type -eq 'audio' } | Select-Object -First 1

if (-not $video) { throw "El archivo no tiene stream de video" }

$width = [int]$video.width
$height = [int]$video.height
$codec = [string]$video.codec_name
$pixFmt = [string]$video.pix_fmt
$fpsParts = ([string]$video.r_frame_rate) -split '/'
$fpsValue = if ($fpsParts.Count -eq 2) { [double]$fpsParts[0] / [double]$fpsParts[1] } else { [double]$fpsParts[0] }
$duration = [double]$info.format.duration
$sizeMb = [math]::Round([double]$info.format.size / 1MB, 2)

$loudness = $null
$ebur = & $ffmpeg -hide_banner -nostats -i $File -af ebur128=peak=true -f null - 2>&1
$line = $ebur | Select-String -Pattern 'I:\s*(-?\d+(?:[.,]\d+)?)\s*LUFS' | Select-Object -Last 1
if ($line -and $line.Matches.Count -gt 0) {
    $loudness = [double]::Parse(($line.Matches[0].Groups[1].Value -replace ',', '.'), [Globalization.CultureInfo]::InvariantCulture)
}

$checks = @(
    [pscustomobject]@{
        Check  = 'Resolucion'
        Status = if ($width -eq 1080 -and $height -eq 1920) { 'PASS' } else { 'FAIL' }
        Detail = "${width}x${height} (esperado 1080x1920)"
    },
    [pscustomobject]@{
        Check  = 'FPS'
        Status = if ([math]::Abs($fpsValue - 30) -lt 0.1) { 'PASS' } else { 'WARN' }
        Detail = ('{0:N2}' -f $fpsValue)
    },
    [pscustomobject]@{
        Check  = 'Codec video'
        Status = if ($codec -eq 'h264') { 'PASS' } else { 'WARN' }
        Detail = "$codec / $pixFmt"
    },
    [pscustomobject]@{
        Check  = 'Duracion'
        Status = if ($duration -ge 15 -and $duration -le 90) { 'PASS' } else { 'WARN' }
        Detail = ('{0:N2}s (objetivo 20-45s)' -f $duration)
    },
    [pscustomobject]@{
        Check  = 'Audio'
        Status = if ($audio) { 'PASS' } else { 'FAIL' }
        Detail = if ($audio) { "$($audio.codec_name) / $($audio.sample_rate) Hz / $($audio.channels) ch" } else { 'sin audio' }
    },
    [pscustomobject]@{
        Check  = 'Loudness'
        Status = if ($null -ne $loudness -and $loudness -ge -16 -and $loudness -le -12) { 'PASS' } else { 'WARN' }
        Detail = if ($null -ne $loudness) { ('{0:N1} LUFS (objetivo -14)' -f $loudness) } else { 'sin dato' }
    },
    [pscustomobject]@{
        Check  = 'Peso'
        Status = if ($sizeMb -lt 100) { 'PASS' } else { 'WARN' }
        Detail = "$sizeMb MB"
    },
    [pscustomobject]@{
        Check  = 'Subtitulos'
        Status = if (Test-Path -LiteralPath (Join-Path $dir 'build/captions.ass')) { 'PASS' } else { 'WARN' }
        Detail = 'build/captions.ass'
    }
)

$checks | Format-Table -AutoSize
$fails = @($checks | Where-Object { $_.Status -eq 'FAIL' })
if ($fails.Count -gt 0) {
    Write-Warning "$($fails.Count) comprobacion(es) FAIL. Corrige antes de publicar."
    exit 1
}

Write-Host "QA OK: $File"
Write-Host "Revisa a ojo: hook en <1.5s, texto en zona segura y CTA claro."
