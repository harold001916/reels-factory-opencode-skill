# Reels Factory Skill

Skill de OpenCode/Antigravity para producir reels verticales originales de principio a fin: concepto, hooks, guion, voz Edge-TTS, imágenes Gemini/Pollinations, subtítulos, música con ducking y QA.

## Requisitos

- PowerShell 7
- ffmpeg y ffprobe
- Node.js y npx
- Gemini API key para imágenes Gemini, o Pollinations como alternativa

## Uso

Coloca esta carpeta como skill global de OpenCode o como skill compatible en tu entorno.

```powershell
pwsh -File scripts/new-reel.ps1 -Slug "mi-tema" -Voice es-MX-JorgeNeural
pwsh -File scripts/gen-images-gemini.ps1 -Project reels/mi-tema/project.json -AspectRatio 9:16
pwsh -File scripts/tts.ps1 -Project reels/mi-tema/project.json -Voice es-MX-JorgeNeural
pwsh -File scripts/render-reel.ps1 -Project reels/mi-tema/project.json
pwsh -File scripts/qa-reel.ps1 -Project reels/mi-tema/project.json
```

Configura Gemini mediante `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `GOOGLE_GENERATIVE_AI_API_KEY` o `~/.config/opencode/gemini.key`. No subas claves al repositorio.
