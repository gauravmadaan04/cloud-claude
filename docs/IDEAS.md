# Idea bank

Brainstorm here. For each idea, note which format makes it (✅ ready, 🔧 needs a small format change, 🆕 needs a
new format). Audience: Indian women ~30–45 (divasclub). The best ads make her ask "which one suits *me*?", which
is what the CTA answers.

## Made so far
| Reel | Format |
|---|---|
| Roshni at the airport (narrated story) | story |
| Types of Skirts / Suits / Kurtis / Saree Drapes / Necklines | paperdoll |

## Ready to make with existing formats
| Idea | Format | Notes |
|---|---|---|
| More "Types of…": sleeves, dupatta drapes, lehenga silhouettes, jeans fits, ethnic jackets, blouse backs | paperdoll ✅ | ~130 credits each |
| Same reel, other body shapes (pear, hourglass, rectangle, inverted triangle) for audience split tests | paperdoll ✅ | new `generation.model_image`, same script |
| Hinglish / Hindi voiceover of an existing reel | any ✅ | ~1.5 credits: edit `voice.lines`, `voice` + `timing` + `build` |
| Hook A/B variants ("Stop buying suits that don't suit you", "Are you an apple shape?") | any ✅ | new line 0, re-voice, rebuild |
| Short relatable stories: first day at a new job, first saree at a wedding, mom getting ready for a kitty party, "she finally found her colour" | story ✅ | 6–10 images; reuse boards/captions or switch boards off |
| Customer-style transformation stories ("Priya hated her photos… until…") | story ✅ | use a consistent character via `images.refs` |

## Needs a small change
| Idea | Change |
|---|---|
| 15-second cut-downs (hook + 3–4 items + CTA prime) | 🔧 paperdoll: `items` subset + shorter script works today; hook timing may need a `layout.hook_dur` |
| 4:5 and 1:1 feed versions | 🔧 `studio.common` W/H per project + layout scaling |
| Occasion-led ("Apple-shaped? What to wear to a shaadi / office / Karva Chauth") | 🔧 paperdoll with full-look items, or story with one shot per occasion |

## New formats worth building
| Idea | Sketch |
|---|---|
| **Right vs Wrong** (likely the best converter): "5 suit mistakes that make you look heavier" | 🆕 `versus`: split screen, same model in two looks, ✗ / ✓ stamps, one mistake per line, prime line at the end |
| "Which body shape are you?" | 🆕 `morph`: silhouettes cross-fade into each other with labels, quiz-style pause before the CTA |
| This-or-that / poll reels | 🆕 `versus` variant without verdicts: "comment A or B" is out (no comment CTAs), so end on the prime line |
| Myth vs fact | 🆕 text-led cards over a single look, flips from MYTH to FACT (reuse `Board`) |
| Countdown listicles ("3 colours every wheatish skin tone should own") | 🆕 or `story` with big numbers via `kinetic` |
