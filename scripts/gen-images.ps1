[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Project,
    [string]$Model = 'flux',
    [int]$Width = 0,
    [int]$Height = 0,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/common.ps1"

$projPath = (Resolve-Path -LiteralPath $Project).Path
$dir = Split-Path -Parent $projPath
$proj = Read-JsonFile -Path $projPath
$key = $env:POLLINATIONS_API_KEY
$anonymous = [string]::IsNullOrWhiteSpace($key)

if ($anonymous) {
    $Width = 576
    $Height = 1024
    Write-Warning "Sin POLLINATIONS_API_KEY: 576x1024, marca de agua y 1 imagen cada ~45 s."
}
else {
    if ($Width -le 0) { $Width = 1080 }
    if ($Height -le 0) { $Height = 1920 }
}

$imgDir = Join-Path $dir 'assets/images'
New-Item -ItemType Directory -Force -Path $imgDir | Out-Null

$index = 0
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
        Write-Warning "Escena ${id}: image_path no existe, se genera con IA."
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
    $encoded = [uri]::EscapeDataString($prompt)
    $seed = if ($null -ne $scene.seed) { [int]$scene.seed } else { 100 + $index }

    $ok = $false
    for ($attempt = 1; $attempt -le 4 -and -not $ok; $attempt++) {
        try {
            if ($anonymous) {
                $url = "https://image.pollinations.ai/prompt/$encoded?width=$Width&height=$Height&seed=$seed&nologo=true"
                $headers = @{}
            }
            else {
                $url = "https://gen.pollinations.ai/image/$encoded?model=$Model&width=$Width&height=$Height&seed=$seed&nologo=true"
                $headers = @{ Authorization = "Bearer $key" }
            }

            Invoke-WebRequest -Uri $url -Headers $headers -OutFile $out -TimeoutSec 150 -UseBasicParsing

            $bytes = [IO.File]::ReadAllBytes($out)
            $isJpeg = ($bytes.Length -gt 1000 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8)
            $isPng = ($bytes.Length -gt 1000 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50)
            if (-not ($isJpeg -or $isPng)) { throw "la respuesta no es una imagen valida" }
            $ok = $true
        }
        catch {
            $status = $null
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $status = [int]$_.Exception.Response.StatusCode
            }
            Write-Warning "Escena ${id}, intento ${attempt}: $($_.Exception.Message)"
            if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }

            if (-not $anonymous -and ($status -eq 401 -or $status -eq 402)) {
                Write-Warning "Key rechazada o sin pollen. Paso a modo anonimo (576x1024, marca de agua)."
                $anonymous = $true
                $Width = 576
                $Height = 1024
                continue
            }
            Start-Sleep -Seconds (12 * $attempt)
        }
    }

    if (-not $ok) { throw "No pude generar la imagen de la escena $id. Revisa red/key o usa una imagen propia." }

    Write-Host "Escena ${id}: OK -> $out"
    if ($anonymous) { Start-Sleep -Seconds 46 }
}

Write-Host "Imagenes en $imgDir"
