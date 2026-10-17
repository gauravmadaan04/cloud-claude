# divasclub reel studio

Instagram reels made from AI images, an Indian English voiceover, music and code-drawn motion graphics, all rebuilt
with one command. Different kinds of reels are different **formats**; each reel is a **project** folder.

## Reels in this repo
| Reel | Project | Format |
|---|---|---|
| Roshni at the airport | `projects/roshni-airport-story` | story |
| Types of Skirts | `projects/skirts` | paperdoll |
| Types of Suits | `projects/suits` | paperdoll |
| Types of Kurtis | `projects/kurtis` | paperdoll |
| Types of Saree Drapes | `projects/saree-drapes` | paperdoll |
| Types of Necklines | `projects/necklines` | paperdoll |

Re-rendering any of them costs no credits. Formats and how to add one: [docs/FORMATS.md](docs/FORMATS.md).
Ideas for next reels: [docs/IDEAS.md](docs/IDEAS.md).

## Everyday use (just ask Claude in a session with this repo)
- "Make a Types of Jackets reel" → a new paperdoll project.
- "Make a story reel about a mom's first solo trip" → a new story project.
- "New idea: right-vs-wrong reels with ✗ and ✓ stamps" → Claude sketches a new format, builds it, makes the first reel.
- "Make a Hinglish version of the Suits reel" → edit the script, re-voice, rebuild (~1.5 credits).

## Commands
```bash
python make.py --list                                  # formats, projects
python make.py projects/<name> new                     # first-time stages (images, voice, previews; spends credits)
python make.py projects/<name> build                   # render + sound + final MP4 + checks (free)
python make.py projects/<name> stills --stills 2 10 40 # quick preview frames
python make.py projects/<name> qa --deep               # loudness, face log, contact sheet, transcript vs script
```
Output: `projects/<name>/out/<name>.mp4`.

## One-time setup
1. **Cloud environment setup script:** paste the contents of `setup.sh` into your environment's *Setup script*
   (cloud environment menu → Edit). New sessions then start with everything installed.
2. **Kie API key:** set `KIE_API_KEY` in the environment (or keep the existing `kieapikey`).
