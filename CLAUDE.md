# divasclub reel studio: instructions for Claude

Short vertical reels (1080×1920, 30 fps, ~30–55 s) for **divasclub** (Instagram, Indian women ~30–45), made only from
AI stills (Kie GPT Image 2), an Indian English voiceover (Kie Gemini TTS), music and code-drawn motion graphics.
The owner brainstorms many kinds of reels, so the repo is split into reusable parts:

```
studio/      shared toolkit (images, voice, timing, music, graphics components, face guard, sfx, mix, qa)
formats/     video styles: paperdoll ("Types of…" cut-outs), story (narrated photo story); add more as needed
projects/    one folder per reel: project.yaml (everything editable) + img/ + voice/ (+ pieces/, masks/, custom.py)
docs/        FORMATS.md (what exists, how to add a format), IDEAS.md (idea bank)
make.py      python make.py projects/<name> <stages…>   |   python make.py --list
```

## From idea to reel
1. **Fit the idea to a format** (docs/FORMATS.md). If none fits, propose a new format: a short sketch of the look,
   which `studio/` pieces it reuses and what is new, then build it as `formats/<name>/` (see "Adding a format").
   Don't twist an idea to fit an old format, and don't copy-paste a format to make a variant: add options instead.
2. **Write the project**: copy the closest `projects/*/project.yaml` (or a `projects/_template*`), then write the
   script (`voice.lines`), image prompts and timings. **Show the user the script + image list before spending credits**
   and give the credit estimate (`python -c "from studio import kie; print(kie.credits())"`).
3. `python make.py projects/<name> new` → look at the images and stills (open them!), fix prompts/times/layout.
4. `python make.py projects/<name> build` → `projects/<name>/out/<name>.mp4`, plus `qa` (loudness, face log,
   contact sheet). Run `qa --deep` once to compare the transcript with the script. Look at out/contact.jpg.
5. Send the MP4 to the user (and a push notification if they asked). Commit the project folder (never `out/`) and push.
6. Add the idea to docs/IDEAS.md "Made so far".

## Non-negotiables (the owner asked for these)
- **Nothing on anyone's face, ever.** Graphics go on the overlay; FaceGuard clears faces each frame and logs overlaps.
  qa must show 0 overlaps: if not, move the graphic and re-render; don't rely on the guard's knock-out.
- **No bindi** on the illustrated model: prompts say "No bindi on her forehead"; the `debindi` stage removes leftovers.
- **Model:** for fashion reels the default is the 38-year-old North Indian apple-shaped woman
  (`assets/models/apple_38_north_indian.png`), realistic and relatable. Keep one model per reel.
- **Modest, family-appropriate looks.** If an image comes back revealing, regenerate it.
- **Simple English**, Indian English female voice (Gemini TTS "Sulafat").
- **CTA:** the owner stitches their own CTA. Endings prime it ("To know what suits you…"). No "comment below" asks,
  no recap grid of all items.
- **Watermark** "divasclub" on brand reels, hard to crop (mid-frame). **Loudness** about -9 LUFS, peak ≤ -1 dBFS.
- Images at 1K unless asked otherwise. Avoid image-to-video (expensive, and the owner prefers stills + motion graphics).

## Gotchas learned the hard way
- Kie key: env var `KIE_API_KEY` (or `kieapikey`). 1K image ≈ 6 credits, 2K ≈ 10, a voice take ≈ 0.5.
- The GPT Image 2 content filter sometimes blocks harmless sarees/blouses: reword modestly and rerun `images --only <id>`.
- Never put `<long pause>`-style tags in a TTS *ending* text; the voice may read them aloud. Endings are recorded 3×
  and the take both whisper models hear as the script wins. Tags between main narration lines are fine.
- Whisper spells Indian words oddly (saadhi, Chudidhar); that's the transcriber, not the voice.
- Every timing should hang off a word/line/beat (`studio/timeline.py` expressions), so a new voice take re-times it all.
- `music.analyse` beat grids are reliable; its `drops` are candidates that can be a beat early: pin exact track times.
- Paperdoll: hem auto-measure fails on white/black/navy garments, so set those by hand. Wide pieces (tops) need
  `hook_spacing` ~580 and smaller `side_h`/`orbit_h`.
- The cloud VM is temporary: commit and push project folders as soon as they're good.
