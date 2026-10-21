# Haven website

The sales site for Haven: a static site with no build step and no third-party requests.

| Page | What it's for |
|---|---|
| `index.html` | Home: hero search demo, Search, File Tools (6 working demos + all 27 tools), Clean Up, Smart Rename, Quick Search, looks, privacy, speed, value, pricing, FAQ |
| `compare.html` | Haven and Finder/Spotlight, Haven and online converter sites, Haven and separate apps (with prices) |
| `pricing.html` | Plans ($49 / $79 / $99), what every license includes, buying questions |
| `faq.html` | Full FAQ, including `#licenses` and `#contact` |
| `download.html` | Download button, install steps (`#install`), requirements |
| `privacy.html`, `terms.html` | Privacy policy; terms of sale, license agreement and refund policy (`#refunds`) |

`assets/site.css` holds every style (light and dark), `assets/site.js` the shared behaviour (menu, Buy and
Download buttons, toast), `assets/demos.js` the home page demos. The demos run on sample data in the browser.

## Before launch

1. **`assets/config.js`**: the three Stripe Payment Links, the DMG's address and the support and privacy email
   addresses. Until a link is set, its button explains that it isn't connected yet.
2. **Legal placeholders** (highlighted in yellow on `privacy.html` and `terms.html`): company legal name,
   registered address, governing law, server-log retention, and your licensing, email and hosting providers.
   Have a lawyer read both pages.
3. **The app** must match what the site promises: a 14-day trial, license keys for 1, 3 or 5 Macs with
   deactivation in Settings › License, update checks, and a Developer ID signed, notarized DMG.
4. Prices on the compare page were checked in October 2026; check them again before launch and now and then after.

## Hosting

Upload the folder to any static host (Cloudflare Pages, Netlify, Vercel, GitHub Pages, S3). There is nothing
to build. The header and footer are repeated in every page, so change all seven when you change one.

## Sources for claims

- Speed figures: the `bench.log` from the macOS CI run on 300,000 generated files (slowest of 10 searches 85 ms,
  folder sizes 136 ms, rename preview for 5,000 files 116 ms), October 2026.
- Screenshots in `assets/img/look-*.webp`: the app's UI tests with a sample library.
- Caveat font (handwriting in the demos): SIL Open Font License, self-hosted in `assets/fonts`.
