[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Project,
    [string]$Model = 'gemini-3.1-flash-image',
    [string]$ApiKey = '',
    [string]$KeyFile = "$env:USERPROFILE\.config\opencode\gemini.key",
    [string]$AspectRatio = '9:16',
    [int]$DelaySeconds = 4,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/common.ps1"

$projPath = (Resolve-Path -LiteralPath $Project).Path
$dir = Split-Path -Parent $projPath
$proj = Read-JsonFile -Path $projPath
$ffmpeg = Resolve-Tool -Name 'ffmpeg'

$key = $ApiKey
if ([string]::IsNullOrWhiteSpace($key)) { $key = $env:GEMINI_API_KEY }
if ([string]::IsNullOrWhiteSpace($key)) { $key = $env:GOOGLE_API_KEY }
if ([string]::IsNullOrWhiteSpace($key)) { $key = $env:GOOGLE_GENERATIVE_AI_API_KEY }
if ([string]::IsNullOrWhiteSpace($key) -and (Test-Path -LiteralPath $KeyFile)) {
    $key = (Get-Content -LiteralPath $KeyFile -Raw).Trim()
}
if ([string]::IsNullOrWhiteSpace($key)) {
    throw "Falta la API key de Gemini. Define `$env:GEMINI_API_KEY o guarda la key en '$KeyFile'."
}

$models = @($Model) + @(
    'gemini-3.1-flash-image',
    'gemini-3-pro-image',
    'gemini-2.5-flash-image',
    'gemini-3.1-flash-image-preview',
    'gemini-3-pro-image-preview'
) | Select-Object -Unique

$imgDir = Join-Path $dir 'assets/images'
New-Item -ItemType Directory -Force -Path $imgDir | Out-Null
$tmpDir = Join-Path $dir 'build/gemini-tmp'
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

function Invoke-GeminiImage {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$ModelName,
        [switch]$NoImageConfig
    )

    $generationConfig = @{
        responseModalities = @('TEXT', 'IMAGE')
    }
    if (-not $NoImageConfig) {
        $generationConfig.imageConfig = @{ aspectRatio = $AspectRatio }
    }

    $bodyObj = @{
        contents         = @(@{ parts = @(@{ text = $Prompt }) })
        generationConfig = $generationConfig
    }
    $body = ConvertTo-Json -InputObject $bodyObj -Depth 12 -Compress
    $uri = "https://generativelanguage.googleapis.com/v1beta/models/${ModelName}:generateContent?key=$key"

    $resp = Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json' -Body $body -TimeoutSec 180

    if ($resp.promptFeedback -and $resp.promptFeedback.blockReason) {
        throw "Prompt bloqueado: $($resp.promptFeedback.blockReason)"
    }
    if (-not $resp.candidates -or $resp.candidates.Count -eq 0) {
        throw "Respuesta sin candidatos"
    }

    $parts = @($resp.candidates[0].content.parts)
    foreach ($part in $parts) {
        if ($part.inlineData -and $part.inlineData.data) {
            return [pscustomobject]@{
                Base64   = [string]$part.inlineData.data
                MimeType = [string]$part.inlineData.mimeType
            }
        }
    }
    throw "La respuesta no contiene imagen (inlineData)"
}

$index = 0
$okCount = 0
foreach ($scene in @($proj.scenes)) {
    $index++
    $id = [string]$scene.id
    if ([string]::IsNullOrWhiteSpace($id)) { throw "Escena sin id en project.json" }

    if ($scene.image_path) {
        $own = Join-Path $dir $scene.image_path
        if (Test-Path -LiteralPath $own) {
            Write-Host "Escena ${id}: usa image_path ($($scene.image_path))"
            continue
        }
        Write-Warning "Escena ${id}: image_path no existe, se genera con Gemini."
    }

    if ([string]::IsNullOrWhiteSpace($scene.image_prompt)) {
        Write-Warning "Escena ${id}: sin image_prompt, se omite."
        continue
    }

    $out = Join-Path $imgDir ("scene-{0}.jpg" -f $id)
    if ((Test-Path -LiteralPath $out) -and -not $Force) {
        Write-Host "Escena ${id}: ya existe $out (usa -Force para regenerar)"
        continue
    }

    $prompt = "$($scene.image_prompt). Vertical 9:16 composition, cinematic lighting, high detail, no text, no letters, no watermark, no logo"
    $tmpPng = Join-Path $tmpDir ("scene-{0}.png" -f $id)
    $done = $false

    foreach ($modelName in $models) {
        if ($done) { break }
        $noImageConfig = $false
        for ($attempt = 1; $attempt -le 3 -and -not $done; $attempt++) {
            try {
                $img = Invoke-GeminiImage -Prompt $prompt -ModelName $modelName -NoImageConfig:$noImageConfig
                $bytes = [Convert]::FromBase64String($img.Base64)
                if ($bytes.Length -lt 2000) { throw "imagen demasiado pequena" }
                [IO.File]::WriteAllBytes($tmpPng, $bytes)

                & $ffmpeg -y -i $tmpPng -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920" -q:v 2 $out 2>$null
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out)) {
                    throw "ffmpeg no pudo convertir la imagen"
                }

                Set-Content -LiteralPath (Join-Path $imgDir ("scene-{0}.prompt.txt" -f $id)) -Value $prompt -Encoding utf8
                Write-Host "Escena ${id}: OK con $modelName -> $out"
                $done = $true
                $okCount++
            }
            catch {
                $status = $null
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    $status = [int]$_.Exception.Response.StatusCode
                }
                $detail = $_.ErrorDetails.Message
                if ([string]::IsNullOrWhiteSpace($detail)) { $detail = $_.Exception.Message }
                Write-Warning "Escena ${id} / ${modelName} / intento ${attempt}: $status $detail"

                if ($status -eq 400 -and -not $noImageConfig) {
                    $noImageConfig = $true
                    Write-Warning "Reintento sin imageConfig (aspect ratio por prompt)."
                    continue
                }
                if ($status -eq 401 -or $status -eq 403) {
                    throw "API key de Gemini rechazada o sin permiso (HTTP $status)."
                }
                if ($status -eq 429) { Start-Sleep -Seconds (15 * $attempt) }
                elseif ($status -eq 404) { break }
                else { Start-Sleep -Seconds (5 * $attempt) }
            }
        }
    }

    if (-not $done) {
        throw "No pude generar la imagen de la escena $id con Gemini. Revisa key, cuota o modelo."
    }

    if (Test-Path -LiteralPath $tmpPng) { Remove-Item -LiteralPath $tmpPng -Force }
    if ($DelaySeconds -gt 0) { Start-Sleep -Seconds $DelaySeconds }
}

Write-Host ""
Write-Host "Imagenes Gemini en $imgDir ($okCount generadas)"
Write-Host "Siguiente: pwsh -File `"$PSScriptRoot\tts.ps1`" -Project `"$projPath`""
