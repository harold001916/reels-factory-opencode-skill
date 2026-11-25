[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Slug,
    [string]$Root = 'reels',
    [string]$Voice = 'es-MX-DaliaNeural',
    [string]$Rate = '+8%',
    [string]$Pitch = '+0Hz',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/common.ps1"

$slug = ConvertTo-Slug -Text $Slug
$dir = Join-Path $Root $slug
$templateDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'templates'

if ((Test-Path -LiteralPath $dir) -and -not $Force) {
    throw "Ya existe '$dir'. Usa -Force para reemplazar las plantillas."
}

foreach ($sub in @('assets/images', 'assets/vo', 'assets/music', 'assets/sfx', 'build', 'out')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $dir $sub) | Out-Null
}

$replace = @{
    '{{SLUG}}'  = $slug
    '{{DATE}}'  = (Get-Date).ToString('yyyy-MM-dd')
    '{{VOICE}}' = $Voice
    '{{RATE}}'  = $Rate
    '{{PITCH}}' = $Pitch
}

foreach ($name in @('project.json', 'script.md', 'captions.md')) {
    $src = Join-Path $templateDir $name
    $dst = Join-Path $dir $name
    if (-not (Test-Path -LiteralPath $src)) { throw "Falta la plantilla $src" }
    $content = Get-Content -LiteralPath $src -Raw
    foreach ($k in $replace.Keys) { $content = $content.Replace($k, $replace[$k]) }
    Set-Content -LiteralPath $dst -Value $content -Encoding utf8
}

$license = Join-Path $dir 'assets/LICENSES.md'
if (-not (Test-Path -LiteralPath $license)) {
    @"
# Registro de licencias

| Asset | Fuente/URL | Autor | Licencia | Fecha | Uso comercial |
|---|---|---|---|---|---|
|  |  |  |  |  |  |
"@ | Set-Content -LiteralPath $license -Encoding utf8
}

$projPath = Join-Path $dir 'project.json'
Write-Host "Proyecto creado: $dir"
Write-Host ""
Write-Host "Siguiente:"
Write-Host "  1. Edita $projPath y script.md"
Write-Host "  2. pwsh -File `"$PSScriptRoot\gen-images.ps1`" -Project `"$projPath`""
Write-Host "  3. pwsh -File `"$PSScriptRoot\tts.ps1`" -Project `"$projPath`""
Write-Host "  4. pwsh -File `"$PSScriptRoot\render-reel.ps1`" -Project `"$projPath`""
Write-Host "  5. pwsh -File `"$PSScriptRoot\qa-reel.ps1`" -Project `"$projPath`""
