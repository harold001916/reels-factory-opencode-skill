$ErrorActionPreference = 'Stop'

function Resolve-Tool {
    param([Parameter(Mandatory = $true)][string]$Name)

    $cmd = Get-Command -Name $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $links = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    foreach ($ext in @('.exe', '')) {
        $candidate = Join-Path $links ($Name + $ext)
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    $packages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $packages) {
        $hit = Get-ChildItem -LiteralPath $packages -Recurse -Filter "$Name.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }

    throw "No encuentro '$Name'. Instalalo con: winget install $Name"
}

function ConvertTo-Slug {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [int]$MaxLength = 48
    )

    $s = $Text.ToLowerInvariant()
    $s = [regex]::Replace($s, '[áàäâã]', 'a')
    $s = [regex]::Replace($s, '[éèëê]', 'e')
    $s = [regex]::Replace($s, '[íìïî]', 'i')
    $s = [regex]::Replace($s, '[óòöôõ]', 'o')
    $s = [regex]::Replace($s, '[úùüû]', 'u')
    $s = $s -replace 'ñ', 'n'
    $s = [regex]::Replace($s, '[^a-z0-9]+', '-').Trim('-')
    if ($s.Length -gt $MaxLength) { $s = $s.Substring(0, $MaxLength).Trim('-') }
    if ([string]::IsNullOrWhiteSpace($s)) { $s = 'reel' }
    return $s
}

function Get-MediaDuration {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Ffprobe
    )

    if (-not $Ffprobe) { $Ffprobe = Resolve-Tool -Name 'ffprobe' }
    $raw = & $Ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $Path
    if (-not $raw) { throw "No pude leer la duracion de $Path" }
    return [double]::Parse(($raw | Select-Object -First 1).Trim(), [Globalization.CultureInfo]::InvariantCulture)
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $Object | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Format-AssTime {
    param([Parameter(Mandatory = $true)][double]$Seconds)
    $ts = [TimeSpan]::FromSeconds($Seconds)
    return ('{0:00}:{1:00}:{2:00}.{3:00}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds, [int]($ts.Milliseconds / 10))
}

function Wrap-Caption {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [int]$MaxChars = 18,
        [int]$MaxLines = 2
    )

    $clean = ($Text -replace '\s+', ' ').Trim()
    $clean = $clean.Replace('{', '(').Replace('}', ')').Replace('\', '/')
    $words = $clean -split ' '
    $lines = @()
    $current = ''
    foreach ($word in $words) {
        $candidate = if ($current) { "$current $word" } else { $word }
        if ($candidate.Length -le $MaxChars -or -not $current) {
            $current = $candidate
        }
        else {
            $lines += $current
            $current = $word
        }
    }
    if ($current) { $lines += $current }
    if ($lines.Count -gt $MaxLines) { $lines = $lines[0..($MaxLines - 1)] }
    return ($lines -join '\N')
}
