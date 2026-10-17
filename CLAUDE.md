# divasclub reel factory — instructions for Claude

This repo makes "Types of …" paper-doll fashion reels for **divasclub** (Instagram, Indian women ~30–45).
One illustrated model stands centre; garment cut-outs fly on and off her; ends in confusion → a prime line that
leads into the owner's CTA (they stitch the CTA themselves).

## Make a new reel
1. `mkdir reels/<name>` and copy `reels/_template/reel.yaml` (or the closest existing reel's yaml) into it.
2. Fill in: title, items (id, LABEL, prompt — 10 items, first = base look, last = finale), finale desc + name_words,
   voice.lines (line 0 = hook "Types of … every woman should know!", then one line per item, the finale line starts
   "And the … one... the <NAME>!"), ending (pivot_word + prime_rows + ending_text), layout (start from the closest reel).
3. Show the user the item list + script before spending credits.
4. `python make_reel.py reels/<name> new` → check the images (contact sheet of img/), the pieces, the hem values and the
   stills. Fix anything, then `python make_reel.py reels/<name> build`. Output: `reels/<name>/out/<name>.mp4`.
5. Check the build log: "frames where graphics touched a face" must be 0. Transcribe the final video with whisper
   (`reelgen.voice.transcribe`) and compare with the script. Send the MP4 to the user (and a push notification if asked).
6. Commit the reel folder (reel.yaml, img/, pieces/, voice/ — never out/) and push.

## Non-negotiables (the owner asked for these)
- **Nothing on her face, ever.** Every graphic goes on the overlay; the face guard clears faces each frame. Text sits
  above her head; boards/labels never cross the face. If the log shows overlaps, move the graphic (e.g. raise
  `layout.outfit_top` so landing pieces stop below the chin) and re-render — don't rely on the guard's knock-out.
- **No bindi.** Prompts say "No bindi on her forehead"; `debindi` stage removes any that appears anyway.
- **Model:** default is the 38-year-old North Indian apple-shaped woman (`assets/models/apple_38_north_indian.png`) —
  realistic, relatable, body-positive. Same model across a reel; only the garment changes.
- **Modest, family-appropriate looks.** High/round necklines on blouses; if an image comes back revealing, regenerate.
- **Simple English** in the script, Indian English female voice (Gemini TTS voice "Sulafat"), ~45–55 s total.
- **Watermark** "divasclub", mid-frame, hops sides. **Loudness** about -9 LUFS, peaks ≤ -1.5 dBFS (lower `audio.limit`
  if a track peaks higher after AAC).
- Always send a push notification when a long job finishes if the user asked for it.

## Gotchas learned the hard way
- Kie key: env var `KIE_API_KEY` (or `kieapikey`). Credits: `python -c "from reelgen import kie; print(kie.credits())"`.
  1K GPT Image 2 ≈ 6 credits; a full reel ≈ 120–135 credits. Image-to-video is expensive (Kling 1080p 5 s = 112 credits) — avoid.
- GPT Image 2 content filter sometimes blocks harmless sarees/blouses → reword modestly ("traditional", "worn at family
  functions", "elbow sleeves") and rerun `images --only <id>`.
- Never put `<long pause>` tags in TTS ending text — the voice reads them aloud. `voice` records 3 ending takes and keeps
  the one both whisper models hear as the script ("To know…", not "Do you know…").
- Whisper spells Indian words oddly (saadhi, Chudidhar) — that's the transcriber, not the voice.
- Hem auto-measure fails on white/black/navy garments (they blend with paper/jeans) — set those `hem` values by hand.
- Wide pieces (tops) need bigger `hook_spacing` (580) and smaller `side_h`/`orbit_h`.
- The cloud VM is temporary: commit and push reel folders as soon as they're good.
