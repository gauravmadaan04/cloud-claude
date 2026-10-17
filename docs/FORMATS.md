# Formats

A **format** is a reusable video style. A **project** (`projects/<name>/project.yaml`) picks one with `format:` and
fills it with content. New idea that fits an existing format → new project only. New idea that doesn't → new format
(usually built from `studio/` pieces in an afternoon) and the idea becomes its first project.

| Format | What it looks like | Example projects | Credits for a new one |
|---|---|---|---|
| `paperdoll` | Illustrated model centre-frame; paper cut-outs of 10 items fly on/off her one per line; hook scrolls all items; confusion → prime line for a CTA stitch | skirts, suits, kurtis, saree-drapes, necklines | ~130 (10 looks + 10 cut-outs + voice) |
| `story` | Narrated photo story: stills with Ken Burns + 2.5D parallax, beat-snapped cuts, split-flap boards, word-by-word captions, kinetic finale words, optional bespoke end card | roshni-airport-story | ~60–110 (6–11 images + voice) |

## The toolkit every format uses (`studio/`)
| Module | Gives you |
|---|---|
| `kie.py` | Kie API: `upload`, `run_jobs` (parallel, polled), `credits`, Suno music |
| `imaging.py` | `generate` (GPT Image 2 from an `images:` block), `debindi` |
| `voice.py` | Gemini TTS narration (+ best-of-3 ending), whisper word timings, pause tightening |
| `timeline.py` | `Timeline`: word/line lookups and named **time expressions** (`{word: [3, light]}`, `{gap: [0, 1]}`, …) |
| `music.py` | beat grid + drop candidates for a track (cached `<track>.beats.json`), `snap` |
| `components.py` | `Board` (split-flap), `chip`, `Captions` (karaoke), `kinetic`, `punch`, `flash`, `fade_black` |
| `faceguard.py` | `FaceGuard`: detects faces each frame, keeps graphics off them, logs any overlap |
| `sfx.py` | synthesised sounds (swish, whoosh, tick, pop, fall, riser, impact, thud, bell, clatter, flyover) + `Track` |
| `mix.py` | voice clean-up, music ducking + dips, loud master (-9 LUFS), `mux` |
| `qa.py` | loudness, face log, contact sheet, transcript check |
| `video.py` | ffmpeg frame pipes (`encoder`, `frames`, `frame_at`, `filter_image`) |
| `common.py` | sizes (1080×1920 @ 30), config load/save, easing, fonts, `cover` (Ken Burns), `watermark` |

## Adding a format
```
formats/<name>/__init__.py   NEW = [...first-time stages...]; BUILD = ["render", "mix", "mux", "qa"]
                             STAGES = {"stills": fn(d, args), "render": fn, "mix": fn, ...}   # overrides shared stages
formats/<name>/render.py     a class that takes the project dir, computes timings from the narration, and renders
                             frame(t) = picture + overlay (graphics) -> FaceGuard -> out/graphics.mp4
```
Rules of thumb:
1. Every timing comes from a spoken word, a line gap or a beat (via `Timeline`), never a hard-coded second, so a
   new voice take re-times the whole video.
2. Every graphic goes on the overlay layer; run `FaceGuard.apply` on it each frame; `qa` must report 0 overlaps.
3. Everything a person might change (text, colours, positions, times, prompts) lives in project.yaml, not the code.
4. One-off flourishes for a single project go in `projects/<name>/custom.py` (the story format calls `setup`,
   `overlay`, `sfx`, `events` if present); promote them to `studio/components.py` once a second project wants them.
5. Write a `projects/_template_<format>/project.yaml` and add a row to the table above and to `docs/IDEAS.md`.
