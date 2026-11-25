---
name: Reels Factory
description: Convierte un tema, nicho, historia o brief de investigacion en un reel original para TikTok, Instagram Reels y YouTube Shorts con concepto, hooks, guion cronometrado, shot list, imagenes IA, voz, subtitulos quemados, mezcla de musica y MP4 vertical 1080x1920 renderizado con ffmpeg. Usala para crear, replicar o producir un reel de principio a fin.
---

# Reels Factory

## Cuando usarla

- El usuario quiere crear un reel/short desde un tema, nicho, historia o producto.
- Ya existe un benchmark y hay que producir el video.
- Hay que replicar la estructura de un reel viral sin copiar su contenido.

Si aun no hay investigacion, ejecuta primero `reels-viral-research`.

## Prerrequisitos

Comprueba con:

```powershell
ffmpeg -version; ffprobe -version; npx --version
```

- `ffmpeg`/`ffprobe` (instalados via winget).
- `npx` (Node) para Edge-TTS.
- Imagenes IA recomendadas con Gemini: `$env:GEMINI_API_KEY` o clave en `~/.config/opencode/gemini.key`.
- Imagenes IA alternativas con Pollinations: `$env:POLLINATIONS_API_KEY` para FLUX 1080x1920 sin logo. Sin key: imagenes anonimas 576x1024, con marca de agua y 1 cada ~45 s.
- Opcional: `yt-dlp` para research y referencia.
- Musica con licencia en `assets/music/` (o deja que el usuario la aporte).

Las rutas de `scripts/`, `references/` y `templates/` son relativas al directorio de esta skill. Ejecuta los scripts con ruta absoluta y desde el directorio de trabajo del usuario (donde quieres que se cree `reels/`).

## Flujo

### 1. Brief

Confirma en una sola ronda: tema, audiencia, plataformas, objetivo, duracion, cara/no cara, voz, CTA y restricciones. Si hay `research/<slug>/replication-brief.md`, usalo como base.

### 2. Concepto y hooks

- Propone 3 conceptos: 1 seguro, 1 hibrido, 1 apuesta.
- Escribe 5 hooks de 0-3 s por concepto (ver `references/script-frameworks.md`).
- Puntua: curiosidad, claridad, especificidad, facilidad de produccion.
- Elige uno y muestra el guion antes de renderizar si el usuario esta presente.

### 3. Guion

- Duracion objetivo 20-45 s (maximo 60 s salvo que el tema lo justifique).
- 5-8 escenas; una idea por escena.
- 140-170 palabras/min: ~25-35 palabras por cada 10 s.
- Cada escena: `voiceover`, `caption` (3-6 palabras), `image_prompt`, `motion`.
- Escribe en `script.md` y traslada las escenas a `project.json`.

### 4. Scaffold

```powershell
pwsh -File scripts/new-reel.ps1 -Slug "mi-tema" -Voice es-MX-DaliaNeural
```

Crea `reels/mi-tema/` con `project.json`, `script.md`, `captions.md`, `assets/` y `out/`.

### 5. Assets

Imágenes IA con Gemini desde OpenCode o Antigravity:

```powershell
pwsh -File scripts/gen-images-gemini.ps1 -Project reels/mi-tema/project.json -AspectRatio 9:16
```

- Configura `$env:GEMINI_API_KEY`, o guarda la clave sin secretos en `~/.config/opencode/gemini.key`.
- Alternativa compatible: `GOOGLE_API_KEY` o `GOOGLE_GENERATIVE_AI_API_KEY`.
- El script prueba modelos disponibles y adapta el formato a 1080x1920.
- Pollinations sigue disponible como fallback:

```powershell
pwsh -File scripts/gen-images.ps1 -Project reels/mi-tema/project.json
```

- Con key Pollinations: FLUX 1080x1920, sin logo.
- Sin key Pollinations: 576x1024, marca de agua y espera entre imágenes.
- Para usar fotos/video propios: coloca el archivo y define `image_path` o `video_path` en la escena.
- Stock libre: descarga manual desde Pexels/Pixabay y anota la licencia en `assets/LICENSES.md`.

Voz:

```powershell
pwsh -File scripts/tts.ps1 -Project reels/mi-tema/project.json -Voice es-MX-DaliaNeural -Rate +8%
```

- Genera `assets/vo/scene-XX.mp3` + `.srt` y `assets/vo/timings.json`.
- Si Edge-TTS falla, usa SAPI local (voz de Windows) como respaldo.
- Voces utiles: `es-MX-DaliaNeural`, `es-MX-JorgeNeural`, `es-ES-ElviraNeural`, `es-ES-AlvaroNeural`, `es-CO-SalomeNeural`, `es-AR-ElenaNeural`.

### 6. Render

```powershell
pwsh -File scripts/render-reel.ps1 -Project reels/mi-tema/project.json
```

- 1080x1920, 30 fps, H.264, AAC 192 kbps, -14 LUFS, subtitulos quemados.
- Movimiento Ken Burns (`zoom-in`, `zoom-out`, `static`), cortes secos.
- Musica opcional con ducking: `-Music assets/music/track.mp3 -MusicVolume 0.12`.
- Salida: `out/reel-<slug>.mp4` + `out/cover.jpg`.

### 7. QA

```powershell
pwsh -File scripts/qa-reel.ps1 -Project reels/mi-tema/project.json
```

Verifica resolucion, fps, duracion, audio, loudness, codec y tamano. Corrige lo que marque FAIL antes de publicar.

### 8. Metadatos y publicacion

Completa `captions.md`: caption, hashtags, texto de cover, variante A/B y notas de publicacion. Exporta el mismo master para las tres plataformas; adapta caption y hashtags.

## Contrato de salida

```
reels/<slug>/
├── project.json
├── script.md
├── captions.md
├── assets/
│   ├── images/scene-XX.jpg
│   ├── vo/scene-XX.mp3 + .srt + timings.json
│   ├── music/
│   └── LICENSES.md
├── build/            (intermedios, opcional)
└── out/
    ├── reel-<slug>.mp4
    └── cover.jpg
```

## Calidad minima

- Hook legible sin audio en menos de 1.5 s.
- Cambio visual o de texto cada 2-4 s.
- Subtitulos de 3-6 palabras por linea, dentro de zona segura.
- Voz clara; musica al 8-15 % con ducking; -14 LUFS.
- Sin marcas de agua, logos ni audio con copyright.
- Duración normal 20-45 s. Duraciones hasta 60 s son válidas cuando el brief lo exige; ajustar pausas sin cambiar el guion ni acelerar excesivamente.

## Reglas

- Originalidad: replica estructura, jamas guion, audio, video o imagenes de terceros.
- Licencias: registra la fuente de cada asset en `assets/LICENSES.md`.
- IA: etiqueta contenido sintetico cuando la plataforma lo requiera; no clonar voces ni rostros sin consentimiento.
- Claims: nada de promesas medicas, financieras o resultados garantizados.
- Privacidad: no uses datos personales de terceros sin permiso.
- Si el usuario pide copiar un reel exacto, explica el riesgo y ofrece una version con estructura similar y contenido propio.

## Recursos

- `references/script-frameworks.md`: estructuras, hooks y guion modelo.
- `references/render-pipeline.md`: comandos ffmpeg, subtitulos, audio y problemas.
- `references/free-assets-and-licenses.md`: herramientas libres, limites y licencias.
- `templates/project.json`, `templates/script.md`, `templates/captions.md`.
- `scripts/new-reel.ps1`, `gen-images-gemini.ps1`, `gen-images.ps1`, `tts.ps1`, `render-reel.ps1`, `qa-reel.ps1`.
