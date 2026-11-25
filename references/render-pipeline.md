# Pipeline de render (ffmpeg)

## Estructura del proyecto

```
reels/<slug>/
├── project.json
├── assets/
│   ├── images/scene-01.jpg ...
│   ├── vo/scene-01.mp3, scene-01.srt, timings.json
│   └── music/track.mp3
├── build/
└── out/reel-<slug>.mp4, cover.jpg
```

`project.json` define escenas, voz, estilo y musica. `timings.json` lo genera `tts.ps1` con la duracion real de cada audio; el render usa esas duraciones.

## Escena con imagen (Ken Burns)

```powershell
ffmpeg -y -loop 1 -framerate 30 -t 4.2 -i assets/images/scene-01.jpg `
  -i assets/vo/scene-01.mp3 `
  -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,zoompan=z='min(1.0+0.0012*on,1.14)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1080x1920:fps=30,format=yuv420p" `
  -af "apad=whole_dur=4.2" -t 4.2 `
  -c:v libx264 -preset medium -crf 18 -c:a aac -b:a 192k -ar 48000 -ac 2 -shortest `
  build/scene-01.mp4
```

- `zoom-in`: `z='min(1.0+0.0012*on,1.14)'`.
- `zoom-out`: `z='max(1.14-0.0012*on,1.0)'`.
- `static`: `z='1.06'` (ligero zoom fijo evita bordes).
- Ajusta `0.0012` si el movimiento es muy rapido (menos) o muy lento (mas).

## Escena con video propio

```powershell
ffmpeg -y -stream_loop -1 -i assets/video/clip.mp4 -i assets/vo/scene-01.mp3 -t 4.2 `
  -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,fps=30,format=yuv420p" `
  -af "apad=whole_dur=4.2" -c:v libx264 -preset medium -crf 18 `
  -c:a aac -b:a 192k -ar 48000 -ac 2 -shortest build/scene-01.mp4
```

## Concatenar

```powershell
# build/concat.txt
# file 'build/scene-01.mp4'
# file 'build/scene-02.mp4'
ffmpeg -y -f concat -safe 0 -i build/concat.txt -c copy build/video.mp4
```

Todas las escenas deben tener mismo codec, resolucion, fps y audio.

## Subtitulos ASS (1080x1920)

```ass
[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial Black,76,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,7,2,2,90,90,300,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,0:00:03.00,Default,,0,0,0,,NADIE TE DICE ESTO
```

- `Alignment=2` = abajo centro; `MarginV=300` respeta la UI inferior.
- `Outline=7`, `Shadow=2` para legibilidad.
- 3-6 palabras por linea; usa `\N` para salto manual.
- Fuentes: Arial Black siempre existe; Montserrat/Anton/Bebas Neue requieren instalacion y nombre exacto.

## Audio final con musica y ducking

`build/filter.txt`:

```
[0:v]ass=build/captions.ass[vout];
[0:a]aformat=sample_rates=48000:channel_layouts=stereo,asplit=2[vo1][vo2];
[1:a]aformat=sample_rates=48000:channel_layouts=stereo,volume=0.12,aloop=loop=-1:size=2147483647[m];
[m][vo1]sidechaincompress=threshold=0.03:ratio=8:attack=5:release=250[duck];
[vo2][duck]amix=inputs=2:duration=first:dropout_transition=0,alimiter=limit=0.95,loudnorm=I=-14:TP=-1.5:LRA=11[aout]
```

```powershell
ffmpeg -y -i build/video.mp4 -i assets/music/track.mp3 `
  -filter_complex_script build/filter.txt -map "[vout]" -map "[aout]" `
  -c:v libx264 -preset slow -crf 19 -profile:v high -level 4.0 -r 30 -g 60 `
  -pix_fmt yuv420p -c:a aac -b:a 192k -ar 48000 -movflags +faststart `
  out/reel-mi-tema.mp4
```

Sin musica:

```
[0:v]ass=build/captions.ass[vout];
[0:a]loudnorm=I=-14:TP=-1.5:LRA=11[aout]
```

## Cover

```powershell
ffmpeg -y -ss 0.6 -i out/reel-mi-tema.mp4 -frames:v 1 -q:v 2 out/cover.jpg
```

Elige un frame con texto legible y sujeto centrado; si no, genera un cover aparte en 1080x1920.

## Verificacion

```powershell
ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,sample_rate,channels -show_entries format=duration,size -of json out/reel-mi-tema.mp4
ffmpeg -hide_banner -i out/reel-mi-tema.mp4 -af ebur128=peak=true -f null -
```

Objetivo: H.264, 1080x1920, 30 fps, AAC 48 kHz estereo, -14 LUFS, faststart.

## Problemas comunes

| Sintoma | Causa | Solucion |
|---|---|---|
| Video borroso | imagen 576x1024 estirada | usa key de Pollinations (1080x1920) o sube resolucion |
| Zoom tiembla | `zoompan` con imagen pequena | escala antes a 1080x1920 y usa `d=1` |
| Subtitulos no aparecen | ruta con `:` o fuente inexistente | ejecuta desde la carpeta del proyecto y usa `ass=build/captions.ass` |
| Audio desincronizado | duraciones de timings.json desactualizadas | vuelve a ejecutar `tts.ps1 -Force` y renderiza |
| Volumen bajo | loudnorm mal aplicado | normaliza solo en el render final |
| ffmpeg no encontrado | PATH sin refrescar | abre shell nueva o usa el script (resuelve winget) |
| Edge-TTS falla | red/proxy | el script cae a SAPI; o usa `npx -y @andresaya/edge-tts` manualmente |
| Pollinations 402 | limite anonimo | espera 45 s o configura `POLLINATIONS_API_KEY` |

## Rendimiento

- i9 + Iris Xe: 30-60 s de reel en ~1-3 min con preset medium.
- `-preset slow` solo en el render final.
- No reescales a 4K: las plataformas recomprimen.
- Borra `build/` si no necesitas depurar (`-Clean`).
