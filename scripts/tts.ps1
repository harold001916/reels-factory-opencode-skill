[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Project,
    [string]$Voice = '',
    [string]$Rate = '',
    [string]$Pitch = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/common.ps1"

$projPath = (Resolve-Path -LiteralPath $Project).Path
$dir = Split-Path -Parent $projPath
$proj = Read-JsonFile -Path $projPath

$voice = if ($Voice) { $Voice } elseif ($proj.voice) { $proj.voice } else { 'es-MX-DaliaNeural' }
$rate = if ($Rate) { $Rate } elseif ($proj.rate) { $proj.rate } else { '+8%' }
$pitch = if ($Pitch) { $Pitch } elseif ($proj.pitch) { $proj.pitch } else { '+0Hz' }

$voDir = Join-Path $dir 'assets/vo'
New-Item -ItemType Directory -Force -Path $voDir | Out-Null

$ffprobe = Resolve-Tool -Name 'ffprobe'
$npx = $null
try { $npx = Resolve-Tool -Name 'npx' } catch { Write-Warning "npx no encontrado; se usara SAPI local." }

$timings = @()
$start = 0.0

foreach ($scene in @($proj.scenes)) {
    $id = [string]$scene.id
    if ([string]::IsNullOrWhiteSpace($id)) { throw "Escena sin id en project.json" }
    $text = [string]$scene.voiceover
    if ([string]::IsNullOrWhiteSpace($text)) { throw "Escena $id sin voiceover" }

    $mp3 = Join-Path $voDir ("scene-{0}.mp3" -f $id)
    $wav = Join-Path $voDir ("scene-{0}.wav" -f $id)
    $srt = Join-Path $voDir ("scene-{0}.srt" -f $id)

    $audio = if (Test-Path -LiteralPath $mp3) { $mp3 } elseif (Test-Path -LiteralPath $wav) { $wav } else { $null }

    if (-not $audio -or $Force) {
        $done = $false
        if ($npx) {
            try {
                & $npx -y '@andresaya/edge-tts@1.9.1' synthesize -t $text -v $voice -r $rate -p $pitch `
                    -o $mp3 --subtitles $srt --format 'audio-24khz-96kbitrate-mono-mp3' 2>&1 | Out-Null
                if ((Test-Path -LiteralPath $mp3) -and (Get-Item -LiteralPath $mp3).Length -gt 1000) {
                    $audio = $mp3
                    $done = $true
                }
            }
            catch {
                Write-Warning "Edge-TTS fallo en escena ${id}: $($_.Exception.Message)"
            }
        }

        if (-not $done) {
            Write-Warning "Escena ${id}: usando SAPI local (calidad inferior)."
            Add-Type -AssemblyName System.Speech
            $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
            $spanish = $synth.GetInstalledVoices() |
                Where-Object { $_.VoiceInfo.Culture.Name -like 'es-*' } |
                Select-Object -First 1
            if ($spanish) { $synth.SelectVoice($spanish.VoiceInfo.Name) }
            else { Write-Warning "No hay voces es-* instaladas; se usara la voz por defecto." }
            $synth.SetOutputToWaveFile($wav)
            $synth.Speak($text)
            $synth.Dispose()
            $audio = $wav
        }
    }

    if (-not (Test-Path -LiteralPath $audio)) { throw "No se genero audio para la escena $id" }

    $duration = Get-MediaDuration -Path $audio -Ffprobe $ffprobe
    $timings += [pscustomobject]@{
        id       = $id
        audio    = [IO.Path]::GetRelativePath($dir, $audio)
        duration = [math]::Round($duration, 3)
        start    = [math]::Round($start, 3)
    }
    $start += $duration
    Write-Host ("Escena {0}: {1:N2}s ({2})" -f $id, $duration, (Split-Path $audio -Leaf))
}

$total = [math]::Round($start, 3)
$payload = [pscustomobject]@{
    voice     = $voice
    rate      = $rate
    pitch     = $pitch
    total     = $total
    generated = (Get-Date).ToString('s')
    scenes    = $timings
}
Write-JsonFile -Object $payload -Path (Join-Path $voDir 'timings.json')

Write-Host ""
Write-Host ("Voz lista: {0} escenas, {1:N2}s totales" -f $timings.Count, $total)
if ($total -gt 90) { Write-Warning "El reel dura mas de 90 s; considera acortar." }
Write-Host "Siguiente: pwsh -File `"$PSScriptRoot\render-reel.ps1`" -Project `"$projPath`""
