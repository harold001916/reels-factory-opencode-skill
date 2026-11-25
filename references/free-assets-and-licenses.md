# Herramientas libres y licencias

## Stack recomendado para este equipo

GPU: Intel Iris Xe (sin CUDA), 16 GB RAM, i9-13900H. Conclusion: no correr modelos de video locales pesados; usar nube gratuita para imagen y ffmpeg local para montaje.

| Funcion | Herramienta | Costo | Limite | Licencia/nota |
|---|---|---|---|---|
| Imagen IA | Pollinations (FLUX) | Gratis con key | ~1 pollen por request; key gratis por quests | Modelos abiertos; revisa terminos |
| Imagen IA anonima | Pollinations legacy (Sana) | Gratis | 1 imagen/45 s, 576x1024, marca de agua | Solo prototipos |
| Imagen/video stock | Pexels, Pixabay, Unsplash | Gratis | API con key o descarga manual | Revisa licencia por asset |
| Video IA | Wan 2.2, LTX-Video, HunyuanVideo | Gratis (pesos) | Requiere GPU NVIDIA >=12 GB | No viable en Iris Xe |
| Voz | Edge-TTS (Microsoft) | Gratis | Sin key; requiere red | Voces neurales; revisa terminos de uso comercial |
| Voz local | Kokoro-82M (Apache 2.0) | Gratis | CPU/GPU; ~300 MB | Espanol limitado; alternativa offline |
| Voz offline | Windows SAPI | Gratis | Voces instaladas | Respaldo si falla Edge-TTS |
| Musica/SFX | Pixabay, Free Music Archive, Uppbeat | Gratis | Segun pista | Verifica CC/atribucion |
| Edicion | ffmpeg | Gratis | — | GPL/LGPL segun build |
| Subtitulos | edge-tts SRT + ASS | Gratis | — | Generado localmente |
| Research | yt-dlp + websearch | Gratis | — | Respeta ToS y copyright |

## Variables de entorno

```powershell
# Imagenes FLUX 1080x1920 sin logo (recomendado)
$env:POLLINATIONS_API_KEY = "sk_..."

# Opcional: stock
$env:PEXELS_API_KEY = "..."
$env:PIXABAY_API_KEY = "..."
```

Persistir (usuario):

```powershell
[Environment]::SetEnvironmentVariable('POLLINATIONS_API_KEY','sk_...','User')
```

No escribas keys en `project.json`, scripts ni repositorios.

## Licencias: checklist

- [ ] Imagenes: Pollinations/stock con licencia comercial o propias.
- [ ] Video: propio o stock libre; nada descargado de otro creador.
- [ ] Musica: licencia comercial; guarda captura o URL en `assets/LICENSES.md`.
- [ ] SFX: libres o generados.
- [ ] Fuentes: OFL/Apache (Montserrat, Anton, Bebas Neue) o Arial Black del sistema.
- [ ] Voz: Edge-TTS/SAPI/Kokoro segun terminos; sin clonar voces reales.
- [ ] Contenido: sin marcas, logos, rostros reconocibles ni datos privados.
- [ ] IA: etiqueta cuando la plataforma lo exija.

## Registro de assets

`assets/LICENSES.md`:

```markdown
| Asset | Fuente/URL | Autor | Licencia | Fecha | Uso comercial |
|---|---|---|---|---|---|
| scene-01.jpg | Pollinations FLUX | generado | Terminos Pollinations | 2026-11-18 | Revisar |
| track.mp3 | Pixabay | autor | Pixabay License | 2026-11-18 | Si |
```

## Alternativas de imagen

- **Pollinations con key**: mejor calidad/costo, FLUX, 1080x1920, sin logo.
- **Pollinations anonimo**: cero setup, pero lento y con marca.
- **Pexels/Pixabay**: fotos reales; mejor para estilo documental.
- **Capturas propias**: pantallas, producto, manos, escritorio; suelen convertir mejor que IA generica.
- **ComfyUI local**: posible en CPU pero lento (minutos por imagen); no recomendado aqui.

## Alternativas de voz

- **Edge-TTS**: mejor calidad/precio para espanol; requiere internet.
- **Kokoro-82M**: Apache 2.0, local, voces es limitadas; util sin internet.
- **Piper**: CPU, muchas voces; licencia GPL del motor y por voz.
- **SAPI**: siempre disponible en Windows; calidad inferior.

## Video IA (si cambias de equipo)

- Wan 2.2 / LTX-Video / HunyuanVideo: pesos abiertos, requieren GPU NVIDIA con 12-24 GB VRAM.
- Para clips cortos de b-roll puede valer la pena, pero el costo/tiempo supera a imagen + movimiento para reels faceless.
- Si usas un servicio con API, revisa licencia comercial y limites.

## Reglas de derechos

- La estructura, el ritmo y las ideas no son copyright; el guion literal, el video, la musica y las imagenes si.
- No re-subas contenido ajeno ni lo uses como b-roll.
- Tendencias musicales: solo si la plataforma cubre tu tipo de cuenta.
- Guarda evidencia de licencia; las reclamaciones llegan meses despues.
