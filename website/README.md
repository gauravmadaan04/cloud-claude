# Haven website

The sales site for Haven: a static site with no build step and no third-party requests.

| Page | What it's for |
|---|---|
| `index.html` | The sales page: searchable file pile, the Filename Trap, the Recall Index dot field, the film of the real app, Spotlight compared honestly, a right-click desktop and a studio with all 27 tools, Clean Up, twelve-apps-into-one, what goes online, before/after, receipt and plans, guarantee, FAQ, P.S. |
| `compare.html` | Haven and Finder/Spotlight, Haven and online converter sites, Haven and separate apps (with prices) |
| `pricing.html` | Plans ($49 / $79 / $99), the launch offer, what every license includes, buying questions |
| `faq.html` | Full FAQ, including `#licenses` and `#contact` |
| `download.html` | Download button, install steps (`#install`), requirements; a "send this page to my Mac" button for phones |
| `thanks.html` | Where checkout sends buyers: what happens next, download on a Mac, "install later" on a phone (not indexed) |
| `privacy.html`, `terms.html` | Privacy policy; terms of sale, license agreement and refund policy (`#refunds`) |

`COPY.md` is the copy deck the page was written from. `assets/site.css` holds every style (light and dark),
`assets/site.js` the shared behaviour (menu, Buy and Download buttons, toast, header colour, highlights, the launch
offer, the checkout line and the phone path) and `assets/home.js` the home page demos, which run on sample data
in the browser, plus the film player.

The pages other than `index.html` are built by `scripts/website_pages.py` (their words live in that file; the
header, footer and icons are copied from `index.html`). After changing either, run
`python3 scripts/website_pages.py website` from the repository root.

## Checkout

Haven is sold through a **merchant of record**: a reseller that takes the payment in the buyer's currency, works
out and pays sales tax, VAT and GST worldwide, sends the receipt and issues the license key. The pages are written
for **Dodo Payments**, which fits a seller in India, offers Apple Pay and local currencies, works with plain
checkout links (no scripts on the site) and has license keys with an activation limit the app can check without a
server of yours. Polar works the same way and is the fallback. If you pick another provider, change `PROVIDER` in
`scripts/website_pages.py` and `checkout.provider` / `checkout.payWith` in `assets/config.js`, rebuild, and have
the terms and privacy pages read again.

1. Create three one-time products: Haven for 1 Mac ($49), 3 Macs ($79) and 5 Macs ($99). Turn on license keys with
   an activation limit of 1, 3 and 5.
2. Copy each product's checkout link into `checkout.one`, `checkout.three` and `checkout.five` in
   `assets/config.js`, and set its return address to `https://yourdomain.com/thanks.html` (for Dodo, add
   `?redirect_url=https://yourdomain.com/thanks.html` to the link).
3. Put the download link (`downloadURL` in `assets/config.js`) in the email the provider sends with the key, so
   people who buy on a phone can install on their Mac later.
4. Decide whether you absorb the currency conversion fee, so buyers don't see a surcharge.
5. Before you commit, ask the provider whether you can sign up as an individual or need a company, and what
   payouts to an Indian bank cost.

## Launch offer

While `launch.on` is `true` in `assets/config.js`, the plans, FAQ and thank-you page say that Haven 2 is included
free. Set `launch.endsOn` to show the last day, and set `launch.on` to `false` when the launch ends. The terms
promise version 2 to everyone who bought while the offer was shown, so keep a note of when it ran.

## Before launch

1. **`assets/config.js`**: the three checkout links, the DMG's address and the support and privacy email
   addresses. Until a link is set, its button explains that it isn't connected yet.
2. **Legal placeholders** (highlighted in yellow on `privacy.html` and `terms.html`): company legal name,
   registered address, governing law, server-log retention, and your email and hosting providers. The pages name
   Dodo Payments as reseller. Have a lawyer read both pages.
3. **The app** must match what the site promises: license keys for 1, 3 or 5 Macs with deactivation in
   Settings › License, update checks that can be turned off, and a Developer ID signed, notarized DMG. Licensing
   must keep working offline once a Mac is activated ("Once Haven is set up, turn Wi-Fi off and it doesn't
   notice"). There is no free trial; the 30-day money-back guarantee replaces it.
4. Prices on the compare page were checked in October 2026; check them again before launch and now and then after.
5. The Spotlight comparison was checked against Apple's guides for macOS 26 and 27 in October 2026. Check it again
   when a new macOS comes out.

## The film

`assets/film/haven-film.mp4` is a recording of the real app, made by the **Haven film** workflow
(`.github/workflows/haven-film.yml`): it runs `HavenUITests.test90_Film` on the Debug build with sample files while
the screen is recorded, and logs every internet connection the Haven process opens. To make a new take, push to the
`haven-film` branch, download the `film` artifact, and cut it to the moments in `film-marks.json`. Chapter starts
and captions are at the top of the film code in `assets/home.js`.

## Hosting

Upload the folder to any static host (Cloudflare Pages, Netlify, Vercel, GitHub Pages, S3). There is nothing to
build. Serve `thanks.html` like any other page; it asks search engines not to index it.

## Sources for claims

- Speed figures: the `bench.log` from the macOS CI run on 300,000 generated files (slowest of 10 searches 85 ms,
  folder sizes 136 ms, rename preview for 5,000 files 116 ms), October 2026.
- Spotlight: Apple's Mac User Guide for macOS 26 and 27 (Spotlight search, Live Text in Spotlight since macOS
  Ventura, Voice Memos and Notes transcripts, Photos duplicates, Storage settings), October 2026; the
  `Spotlight check` workflow for what Spotlight's importers read from recordings.
- What goes online: `App/Tools/Transcriber.swift` (Whisper models from Hugging Face, checked by SHA-256), Apple's
  Translation framework, and the film workflow's network log.
- Fonts: Instrument Serif and Caveat, both SIL Open Font License, self-hosted in `assets/fonts`.
