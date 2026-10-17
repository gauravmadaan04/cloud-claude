# divasclub reel factory

Paper-doll "Types of …" reels: an illustrated model, garment cut-outs flying on and off, Indian English voiceover,
desi-fusion music, a confusion → "To know what suits you…" ending ready for your CTA, divasclub watermark,
and a face detector that keeps every graphic off her face.

## Reels in this repo
| Reel | Folder | Model |
|---|---|---|
| Types of Skirts | `reels/skirts` | slim, young |
| Types of Suits | `reels/suits` | 38, North Indian, apple shape |
| Types of Kurtis | `reels/kurtis` | 38, North Indian, apple shape |
| Types of Saree Drapes | `reels/saree-drapes` | 38, North Indian, apple shape |
| Types of Necklines | `reels/necklines` | 38, North Indian, apple shape |

Each folder has `reel.yaml` (all settings, script, prompts), `img/` (the model in each look), `pieces/` (cut-outs)
and `voice/` (final voiceover + timings). Re-rendering any of them costs no credits.

## Everyday use (just ask Claude in a session with this repo)
- "Make a Types of Jackets reel" → Claude proposes items + script, then runs it.
- "Change the Kurtis title / re-render the Suits reel" → edit `reel.yaml`, `python make_reel.py reels/kurtis build`.

## Commands
```bash
python make_reel.py reels/<name> new      # images, cut-outs, voice, preview stills (spends Kie credits)
python make_reel.py reels/<name> build    # render + sound + final MP4 → reels/<name>/out/<name>.mp4 (free)
python make_reel.py reels/<name> stills --stills 2 10 40   # quick preview frames
```

## One-time setup
1. **Cloud environment setup script:** paste the contents of `setup.sh` into your environment's *Setup script*
   (cloud environment menu → Edit). New sessions then start with everything installed.
2. **Kie API key:** set `KIE_API_KEY` in the environment (or keep the existing `kieapikey`).
