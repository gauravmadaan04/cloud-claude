#!/usr/bin/env python3
"""Builds the website's other pages (compare, pricing, FAQ, download, thanks, privacy, terms).

Their words live in this file; the header, footer and icons are copied from index.html, so a change there reaches
every page. Run from the repository root:  python3 scripts/website_pages.py website
"""
import re
import sys
from pathlib import Path

SITE = Path(sys.argv[1])
index = (SITE / "index.html").read_text()

sprite = index[index.index('<svg width="0" height="0"'):index.index("</svg>", index.index('<svg width="0" height="0"')) + 6]
header = index[index.index('<header class="gnav"'):index.index("</header>") + 9]
footer = index[index.index('<footer class="foot">'):index.index("</footer>") + 9]
buybar = '<div class="buybar" id="buybar"><span data-away="<b>$49 once</b> · install on your Mac later"><b>Haven</b> · $49 once · 30-day guarantee</span><a class="btn btn-sm" href="pricing.html#plans">Buy</a></div>\n'
PROVIDER = "Dodo Payments"  # the merchant of record; also set checkout.provider in assets/config.js
toast = '<div class="toast" id="toast" role="status" aria-live="polite"></div>\n'


def head(title, desc, og, robots=""):
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{title}</title>
<meta name="claude:viewport-fit-sides" content="cover">
<meta name="description" content="{desc}">{robots}
<meta property="og:type" content="website">
<meta property="og:title" content="{og}">
<meta property="og:description" content="{desc}">
<meta property="og:image" content="assets/img/og.png">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" type="image/png" href="assets/img/icon-64.png">
<link rel="apple-touch-icon" href="assets/img/apple-touch-icon.png">
<link rel="stylesheet" href="assets/site.css">
</head>
<body>
"""


def page(name, title, desc, og, body, current=None, sales=True, index=True):
    h = header
    if current:
        h = h.replace(f'<li><a href="{current}">', f'<li><a href="{current}" aria-current="page">', 1)
    out = head(title, desc, og, "" if index else '\n<meta name="robots" content="noindex">') + sprite + "\n\n" + h + "\n\n<main>\n" + body.strip("\n") + "\n</main>\n\n" + footer + "\n\n"
    out += (buybar if sales else "") + toast
    out += '\n<script src="assets/config.js"></script>\n<script src="assets/site.js"></script>\n</body>\n</html>\n'
    (SITE / name).write_text(out)
    print("wrote", name, len(out))


CHECK = '<svg aria-hidden="true"><use href="#i-check"/></svg>'

PLANS = f"""
      <div class="plans">
        <div class="plan">
          <div><h3>1 Mac</h3><p class="who">For your own Mac.</p></div>
          <div class="price"><b>$49</b><span>one time</span></div>
          <p class="per">Everything, on one Mac.</p>
          <a class="btn-quiet" href="pricing.html#plans" data-buy="one">Buy for 1 Mac</a>
          <ul>
            <li>{CHECK}Every feature and all 27 tools</li>
            <li>{CHECK}Free updates for version 1</li>
            <li>{CHECK}Move it to a new Mac any time</li>
          </ul>
        </div>
        <div class="plan pick">
          <span class="flag">Best for most people</span>
          <div><h3>3 Macs</h3><p class="who">Your desktop, your laptop, one more.</p></div>
          <div class="price"><b>$79</b><span>one time</span></div>
          <p class="per">$26.33 a Mac · <strong>save $68</strong></p>
          <a class="btn btn-glow" href="pricing.html#plans" data-buy="three">Buy for 3 Macs</a>
          <ul>
            <li>{CHECK}Every feature and all 27 tools</li>
            <li>{CHECK}Free updates for version 1</li>
            <li>{CHECK}Share with people you live with</li>
          </ul>
        </div>
        <div class="plan">
          <div><h3>5 Macs</h3><p class="who">For a family or a small team.</p></div>
          <div class="price"><b>$99</b><span>one time</span></div>
          <p class="per">$19.80 a Mac · <strong>save $146</strong></p>
          <a class="btn-quiet" href="pricing.html#plans" data-buy="five">Buy for 5 Macs</a>
          <ul>
            <li>{CHECK}Every feature and all 27 tools</li>
            <li>{CHECK}Free updates for version 1</li>
            <li>{CHECK}One license key for everyone</li>
          </ul>
        </div>
      </div>
      <p class="launch" data-launch hidden style="max-width:640px;margin:22px auto 0"><svg aria-hidden="true"><use href="#i-sparkle"/></svg><span><b>Launch offer:</b> every plan includes Haven 2 free when it comes<span data-launch-until></span>.</span></p>
      <p class="send-row away-only">On your phone? Buy now. Your license key and download link arrive by email, ready for your Mac. <button class="link-btn" type="button" data-send>Send this page to your Mac</button></p>
      <div class="guarantee">
        <span class="seal-sm"><svg aria-hidden="true"><use href="#i-shield"/></svg></span>
        <div><b>The 30-Day “Find It or It's Free” Guarantee</b><p>Use every feature from day one. If Haven isn't right for you within 30 days of buying, write to us and we'll refund every cent. No forms, no questions.</p></div>
      </div>
"""

CTA = """
  <section class="night close" aria-labelledby="cta-title">
    <div class="aurora soft" aria-hidden="true"><i></i><i></i></div>
    <div class="wrap close-in">
      <img class="close-icon" src="assets/img/icon-256.png" alt="" width="132" height="132">
      <h2 class="h1" id="cta-title">Stop searching. <em class="serif glowtext">Start finding.</em></h2>
      <div class="cta-row"><a class="btn btn-glow btn-lg" href="pricing.html#plans">Get Haven for $49</a></div>
      <ul class="assure">
        <li><svg aria-hidden="true"><use href="#i-check"/></svg>One-time payment</li>
        <li><svg aria-hidden="true"><use href="#i-check"/></svg>30-day money-back guarantee</li>
        <li><svg aria-hidden="true"><use href="#i-check"/></svg><span data-away="Buy now, install on your Mac later">Instant download</span></li>
      </ul>
    </div>
  </section>
"""


def faq(items):
    out = []
    for q, a, *rest in items:
        ident = f' id="{rest[0]}"' if rest else ""
        paras = "".join(p if p.startswith("<") else f"<p>{p}</p>" for p in a)
        out.append(f'        <details{ident}>\n          <summary>{q}</summary>\n          <div class="a">{paras}</div>\n        </details>')
    return '      <div class="faq">\n' + "\n".join(out) + "\n      </div>\n"


def H2(text, ident=None):
    i = f' id="{ident}"' if ident else ""
    return f'<h2 class="h3" style="font-size:clamp(1.75rem,1.3rem + 1.6vw,2.5rem)"{i}>{text}</h2>'


# ------------------------------------------------------------------ Compare
def row(label, theirs, ours, kind="part", ours_kind="yes"):
    t = f'<span class="{kind}">{theirs}</span>' if kind else theirs
    o = f'<span class="{ours_kind}">{ours}</span>' if ours_kind else ours
    return f'          <tr><th scope="row">{label}</th><td>{t}</td><td class="us">{o}</td></tr>'


finder_rows = "\n".join([
    row("Search the way you'd say it, like “pdfs from last week”", "Some phrases work", "Dates, sizes, kinds, sources and folders, shown as chips you can remove"),
    row("Find text inside screenshots and photos", "Yes, as whole words, once Spotlight has read them in the background", "Yes, newest first, and “wifi” finds “Wi-Fi”", "yes"),
    row("Find a recording by what was said in it", "Only recordings made in Voice Memos or Notes", "Any recording or video, once it's transcribed"),
    row("Find a file by how it reached you, like “emailed”", "Only through a hidden “Where from” search attribute", "Type “emailed” or “from WhatsApp”: 30 sources"),
    row("See where each download came from", "One file at a time, in Get Info", "Grouped by 30 sources, with a From filter on every list"),
    row("Find duplicates and look-alike photos", "Photos library only", "Any folder, with the best copy picked to keep"),
    row("Clear out old installers and forgotten downloads", "Storage settings lists big files", "Grouped, reviewed first, moved to the Trash, with Undo"),
    row("See the size of every folder", "“Calculate all sizes”, slow on big folders", "All at once, in a fraction of a second"),
    row("Rename many files using dates and the title inside them", "Text and counters only", "Dates, titles from the text, sources and counters, with Undo"),
    row("Compress video, merge or sign PDFs, cut out a subject", "Some, spread across Preview and Quick Actions", "27 tools in one right-click menu, with progress and Undo"),
    row("Turn a recording into text or subtitles", "Only in Voice Memos and Notes, for their own recordings", "Any recording or video, with Whisper, in 20+ languages"),
    row("Search from any app", "⌘Space", "⇧⌘Space, with plain English and Show in Finder", "yes"),
    row("Price", "Included with macOS", "$49 once", None, None),
])

online_rows = "\n".join([
    row("Where your file goes", "Uploaded to someone else's server", "Stays on your Mac", "no"),
    row("Big files", "Free plans usually cap the size", "As big as your disk allows"),
    row("Many files at once", "Often a paid extra", "Included"),
    row("Waiting", "Upload, process, download again", "No transfers; it runs on your Mac"),
    row("Works without internet", "No", "Yes, once a speech model is downloaded for transcription", "no"),
    row("Sign-ups, ads and watermarks", "Common", "None"),
    row("Price", "Free with limits, or monthly plans", "$49 once", None, None),
])

cost = [
    ("Merge, split, organize and sign PDFs", "PDF Expert", "$139.99 lifetime", "PDF tools"),
    ("Clean up disk space", "CleanMyMac", "$119.95 once, or $39.95 a year", "Clean Up"),
    ("Transcribe recordings", "MacWhisper Pro", "€59 (about $69)", "Transcribe"),
    ("Find duplicates", "Gemini 2", "$44.95 once, or $19.95 a year", "Duplicates"),
    ("Rules that tidy folders for you", "Hazel", "$42", "Rules"),
    ("Jump to folders in Open and Save dialogs", "Default Folder X", "$39.95", "Dialog Jump"),
    ("Advanced file search", "HoudahSpot", "$34", "Search"),
    ("Rename many files at once", "Better Rename", "$19.99", "Smart Rename"),
    ("Convert and compress video and audio", "Permute", "$14.99", "Video and Audio tools"),
    ("See what fills your disk", "DaisyDisk", "$9.99", "Space"),
    ("A shelf for dragging files between apps", "Yoink", "$8.99", "Drop Shelf"),
]
cost_rows = "\n".join(f'          <tr><th scope="row">{a}</th><td>{b}</td><td class="num">{c}</td><td class="us">{d}</td></tr>' for a, b, c, d in cost)

compare = f"""
  <section class="night page-hero center">
    <div class="aurora soft" aria-hidden="true"><i></i><i></i></div>
    <div class="wrap">
      <p class="eyebrow">Compare</p>
      <h1 class="h1">How Haven <em class="serif glowtext">compares.</em></h1>
      <p class="lead">Haven works next to Finder, does the jobs of a dozen single-purpose apps, and keeps your files off other people's servers. Here's an honest look at each.</p>
    </div>
  </section>
  <div class="wrap" style="padding-block:clamp(56px,7vw,96px) clamp(80px,9vw,120px)">
    <nav class="cnav" aria-label="Comparisons"><a href="#finder">Haven and Finder</a><a href="#online">Haven and online tools</a><a href="#cost">Haven and separate apps</a></nav>

    <section class="csec" id="finder" aria-labelledby="finder-title">
      <div class="sec-head">
        {H2("Haven and Finder", "finder-title")}
        <p class="copy">Finder and Spotlight come with every Mac and do plenty well. Haven doesn't replace them. It reads the same folders and adds what they leave out.</p>
      </div>
      <div class="ctable-wrap"><table class="ctable">
        <thead><tr><th scope="col">What you want to do</th><th scope="col">Finder and Spotlight</th><th scope="col" class="us">Haven</th></tr></thead>
        <tbody>
{finder_rows}
        </tbody>
      </table></div>
      <div class="legend"><span class="yes">Yes</span><span class="part">Partly, or with limits</span><span class="no">No</span></div>
      <p class="fine" style="margin-top:14px">Checked against Apple's Mac User Guide for macOS 26 and 27 in October 2026. On macOS 27 you can also pass a question from Spotlight to Siri (beta, English only, on Macs with Apple Intelligence). Apple doesn't say how well it finds files, so it isn't in this table.</p>
    </section>

    <section class="csec" id="online" aria-labelledby="online-title">
      <div class="sec-head">
        {H2("Haven and online tools", "online-title")}
        <p class="copy">Free converter sites are handy until the file is a passport scan, a signed contract or a family video. Haven does the same jobs without the upload.</p>
      </div>
      <div class="ctable-wrap"><table class="ctable">
        <thead><tr><th scope="col">&nbsp;</th><th scope="col">Online converter sites</th><th scope="col" class="us">Haven</th></tr></thead>
        <tbody>
{online_rows}
        </tbody>
      </table></div>
    </section>

    <section class="csec" id="cost" aria-labelledby="cost-title">
      <div class="sec-head">
        {H2("Haven and separate apps", "cost-title")}
        <p class="copy">These are well-made apps, and several go further in their own area than Haven does. If you edit the text inside PDFs or fill in forms every day, a dedicated PDF editor is still worth having. If you need each of these jobs now and then, Haven covers them in one place, for one price.</p>
      </div>
      <div class="ctable-wrap"><table class="ctable cost">
        <thead><tr><th scope="col">Job</th><th scope="col">A popular app for it</th><th scope="col" class="num">Price</th><th scope="col" class="us">In Haven</th></tr></thead>
        <tbody>
{cost_rows}
        </tbody>
        <tfoot><tr><th scope="row">Bought one at a time</th><td></td><td class="num">about $540</td><td class="us">$49 for all of it</td></tr></tfoot>
      </table></div>
      <p class="fine" style="margin-top:14px">List prices for one Mac from each developer or major retailers, checked in October 2026, using the one-time price where there is one. Prices change and several apps also sell yearly plans, so check before you buy. MacWhisper is priced in euros. App names are trademarks of their owners and appear here only for comparison.</p>
    </section>
  </div>
{CTA}"""

# ------------------------------------------------------------------ Pricing
includes = [
    ("i-infinity", "Yours to keep", "Pay once. No subscription, no renewals."),
    ("i-refresh", "Free version 1 updates", "Every 1.x update, delivered in the app. Bought during the launch? Haven 2 too."),
    ("i-sparkle", "Everything included", "Search, Clean Up, Rename, Rules and all 27 tools."),
    ("i-shield", "30-day refund", "Full refund within 30 days, for any reason."),
    ("i-lock", "No account", "A license key is all you need. Your files stay on your Mac."),
    ("i-help", "Real support", "Questions go to the people who make Haven."),
]
inc_html = "\n".join(f'        <div><svg aria-hidden="true"><use href="#{i}"/></svg><b>{t}</b><p>{d}</p></div>' for i, t, d in includes)

pricing_faq = faq([
    ("Is there a free trial?", ["No, and we think you'll like the alternative better. You get the full app from day one, and you have 30 days to decide. If Haven isn't for you, write to us and we'll refund every cent."]),
    ("How do licenses work?", ["Your license key unlocks Haven on as many Macs as your plan covers: 1, 3 or 5 at the same time. Getting a new Mac? Deactivate the old one in Haven's Settings, then enter your key on the new one."]),
    ("Can I add more Macs later?", ["Yes. Write to us with your license key and you'll pay only the difference between your plan and the bigger one."]),
    ("Is this a subscription?", ["No. You pay once. Every update to version 1 is free, and if there's ever a Haven 2, the version you have keeps working."]),
    ("What happens when Haven 2 comes out?", ["Every update to version 1 is free. <span data-launch hidden>Buy during the launch offer and Haven 2 is included too, at no extra cost. </span>Otherwise Haven 2 may be a paid upgrade, and the version you have keeps working."]),
    ("How do I pay?", [f"Checkout is run by {PROVIDER}, our reseller. Pay with Apple Pay or a credit or debit card, in your own currency. Haven never sees your card details."]),
    ("Can I buy on my phone and install later?", ["Yes. Buy on any device. Your license key and the download link arrive by email, so you can install Haven on your Mac whenever you're ready."]),
    ("When do I get my license key?", ["Right after you pay. It's in the email with your receipt, and the thank-you page tells you how to install."]),
    ("What about tax?", [f"Prices are in US dollars. {PROVIDER} works out any sales tax, VAT or GST for where you live and shows it at checkout before you pay. Your receipt comes from {PROVIDER}."]),
    ("What if Haven isn't right for me?", ["Write to us within 30 days of buying and we'll refund every cent. No forms, no questions. That's the 30-Day “Find It or It's Free” Guarantee. <a href=\"terms.html#refunds\">Refund policy</a>"]),
    ("Do you have team pricing for more than 5 Macs?", ["Yes. Write to us with how many Macs you need and we'll send a quote."]),
])

pricing = f"""
  <section class="night page-hero center">
    <div class="aurora soft" aria-hidden="true"><i></i><i></i></div>
    <div class="wrap">
      <p class="eyebrow">Pricing</p>
      <h1 class="h1">Pay once. <em class="serif glowtext">Keep it.</em></h1>
      <p class="lead">Every plan has every feature. Just pick how many Macs. One payment, free updates for all of version 1, and 30 days to change your mind.</p>
    </div>
  </section>
  <section id="plans" aria-label="Plans" style="padding-block:clamp(64px,8vw,104px)">
    <div class="wrap-wide">
{PLANS}
      <p class="fine" style="text-align:center;margin-top:24px"><span data-payline>Secure checkout · tax handled for you</span>. Prices in US dollars; checkout can show yours in your own currency.</p>
    </div>
  </section>
  <section class="sec band" aria-labelledby="inc-title">
    <div class="wrap-wide">
      <div class="sec-head center" style="margin-bottom:0">
        <h2 class="h2" id="inc-title">Every license includes</h2>
      </div>
      <div class="includes">
{inc_html}
      </div>
    </div>
  </section>
  <section class="sec" aria-labelledby="pfaq-title">
    <div class="wrap-text">
      <div class="sec-head"><h2 class="h2" id="pfaq-title">Buying questions.</h2></div>
{pricing_faq}
      <p style="margin-top:28px"><a class="more" href="faq.html">All questions</a></p>
    </div>
  </section>
"""

# ------------------------------------------------------------------ FAQ
groups = [
    ("Getting started", "start", [
        ("What is Haven?", ["Haven is a Mac app for finding, cleaning up and working on your files. It searches in plain English and reads the text inside images and documents, finds duplicates and clutter, and puts 27 tools for images, PDFs, video, audio and on-device AI one right-click away."]),
        ("Doesn't Spotlight already do this?", ["Partly. Spotlight finds words in names and text, and since macOS Ventura it reads text in images too. It doesn't hear recordings, understand “emailed” or “older than a year” in plain words, or find duplicate files outside Photos. <a href=\"compare.html#finder\">The full comparison</a>"]),
        ("Does Haven replace Finder?", ["No, it works alongside Finder. Your files stay in the folders they're already in. Haven indexes them so you can find them, clean up and work on them faster, and any file is one shortcut away from Finder."]),
        ("Which folders does Haven look at?", ["The ones you pick when you first open it, usually Desktop, Documents and Downloads, plus any you add later in Settings. macOS asks for your permission before Haven can read each one."]),
        ("Which Macs does it run on?", ["Any Mac with macOS 14 Sonoma or later, with Apple silicon or Intel. Translate needs macOS 15 or later, and Summarize needs a Mac with Apple Intelligence on macOS 26."]),
        ("How much space does Haven use?", ["Very little. Its search index for a library of 300,000 files is about 18 MB. If you use Transcribe, the Whisper speech model takes 190 MB, or 574 MB for the Best Quality model."]),
    ]),
    ("Features", "features", [
        ("How does plain-English search work?", ["Type what you remember, like “screenshots over 5 MB” or “photos from whatsapp last month”. Haven picks out the kind of file, the dates, sizes, sources and folders, and shows each one as a chip. Remove a chip to widen the search. Anything left over is matched against file names and the text inside files."]),
        ("Can Haven really read the text in my screenshots?", ["Yes. Haven uses Apple's on-device text recognition to read screenshots, photos and scanned PDFs in the background, newest first. The first pass takes a little while after you install Haven; after that, new files are read as they arrive."]),
        ("How does transcription work?", ["Haven runs Whisper, an open-source speech recognition model, on your Mac. The first time you transcribe, you choose Faster (190 MB) or Best Quality (574 MB, recommended on Apple silicon), and Haven downloads it once. It can detect the language or you can pick one of 20+, and it can translate the speech into English. You get a text file, subtitles (.srt), or both."]),
        ("Do the file tools change my originals?", ["Never. Every tool makes a new file next to the original, with a clear name like “Team call (720p).mp4” or “Lease agreement (signed).pdf”. Undo moves what a tool made to the Trash."]),
        ("What is Dialog Jump?", ["When an Open or Save dialog is on screen in any app, Haven can send it to the folder you're looking at in Haven, so you don't click through folders again. It needs Accessibility permission, because it types the folder's path into the dialog for you."]),
        ("Does it work with iCloud Drive?", ["Yes, add your iCloud Drive folders like any others. Files that are only in iCloud and not downloaded to this Mac are skipped when Haven looks for duplicates."]),
    ]),
    ("Privacy and safety", "privacy", [
        ("Are my files uploaded anywhere?", ["No. Search, text recognition, transcription, background removal and every file tool run on your Mac. Haven goes online only to download a speech model if you ask for transcription, check for updates and activate your license. <a href=\"privacy.html\">Privacy policy</a>"]),
        ("Does Haven collect analytics?", ["No. The app has no analytics, tracking or ads, and no account."]),
        ("Could Haven delete something I need?", ["Haven never deletes anything outright. Clean Up and Duplicates always show you the files first. When you confirm, they go to the Trash, and Undo or the Activity page puts them back. Rules are off until you turn them on, and they never touch files inside your project folders."]),
        ("What permissions does Haven ask for?", ["Access to the folders you choose. If you use Dialog Jump, it also asks for Accessibility. Nothing else."]),
    ]),
    ("Licenses and payment", "licenses", [
        ("Is there a free trial?", ["No. Instead you get the full app from day one and 30 days to decide. If it isn't for you, write to us and we'll refund every cent."]),
        ("Is Haven a subscription?", ["No. You pay once and keep it. Every update to version 1 is free."]),
        ("What happens when Haven 2 comes out?", ["Every update to version 1 is free. <span data-launch hidden>Buy during the launch offer and Haven 2 is included too, at no extra cost. </span>Otherwise Haven 2 may be a paid upgrade, and the version you have keeps working."]),
        ("Can I buy on my phone and install later?", ["Yes. Buy on any device. Your license key and the download link arrive by email, so you can install Haven on your Mac whenever you're ready."]),
        ("Why does my receipt say " + PROVIDER + "?", [f"{PROVIDER} is our reseller. It runs checkout, works out tax for where you live, and sends your receipt and license key. Refunds still come from us: just write to us."]),
        ("How many Macs can I use it on?", ["1, 3 or 5 at the same time, depending on your plan. The 3 and 5 Mac plans can be shared with people in your household, or with a small team."]),
        ("I got a new Mac. How do I move my license?", ["Deactivate it on the old Mac in Haven's Settings, then enter your key on the new one. If the old Mac is gone, write to us and we'll reset it."]),
        ("Can I add more Macs later?", ["Yes. Write to us with your license key and you'll pay only the difference."]),
        ("What's your refund policy?", ["Within 30 days of buying, for any reason, write to us and we'll refund you in full. <a href=\"terms.html#refunds\">Refund policy</a>"]),
        ("I lost my license key.", ["Write to us from the email you bought with and we'll send it again."]),
    ]),
    ("Troubleshooting", "help", [
        ("Haven doesn't find the text in an image.", ["Text reading happens in the background, newest files first, so give it a few minutes after you first install Haven. Very small, blurry or handwritten text may not be read."]),
        ("A folder is missing from Haven.", ["Open Settings › Folders and check that it's listed. If macOS asked for permission and you said no, allow it in System Settings › Privacy &amp; Security › Files and Folders."]),
        ("How do I uninstall Haven?", ["Quit Haven and drag it from Applications to the Trash. To remove its index, settings and speech models too, delete the Haven folder in ~/Library/Application Support."]),
    ]),
]
faq_html = ""
for title, ident, items in groups:
    faq_html += f'      <div class="faq-group">\n        <h2 id="{ident}">{title}</h2>\n{faq(items)}      </div>\n'

faqpage = f"""
  <section class="night page-hero center">
    <div class="aurora soft" aria-hidden="true"><i></i><i></i></div>
    <div class="wrap">
      <p class="eyebrow">FAQ</p>
      <h1 class="h1">Questions, <em class="serif glowtext">answered.</em></h1>
      <p class="lead">Everything people ask before and after they buy. Can't find yours? Write to us at the bottom of the page.</p>
    </div>
  </section>
  <section style="padding-block:clamp(56px,7vw,96px) clamp(64px,8vw,104px)">
    <div class="wrap-text">
{faq_html}
      <div class="guarantee" id="contact" style="margin-top:64px">
        <span class="seal-sm" style="background:var(--accent-soft);color:var(--accent)"><svg aria-hidden="true"><use href="#i-help"/></svg></span>
        <div><b>Still have a question?</b><p>Write to <strong id="support-email" data-email="support">support@yourdomain.com</strong> <button class="btn-line btn-sm" type="button" data-copy-email="support-email" style="margin-left:6px">Copy</button><br>We usually reply within one working day.</p></div>
      </div>
    </div>
  </section>
"""

# ------------------------------------------------------------------ Download
download = f"""
  <section class="night page-hero center" aria-labelledby="dl-title">
    <div class="aurora soft" aria-hidden="true"><i></i><i></i></div>
    <div class="wrap">
      <img class="dl-icon" src="assets/img/icon-256.png" width="128" height="128" alt="Haven app icon" style="margin-inline:auto">
      <h1 class="h1" id="dl-title">Download Haven.</h1>
      <p class="lead">For customers. Your license key is in the email you got when you bought Haven.</p>
      <div class="cta-row"><a class="btn btn-glow btn-lg" href="#install" data-dmg>Download for Mac</a></div>
      <p class="fine">Version 1.0 · 11.2 MB · macOS 14 Sonoma or later · Apple silicon and Intel</p>
      <p class="fine">Don't have Haven yet? <a href="pricing.html">Get it for $49</a>, with a 30-day money-back guarantee.</p>
      <div class="away-note away-only">
        <b>You're not on a Mac right now.</b>
        <p>Haven installs on a Mac. Open the email with your license key on your Mac (it has this link), or send this page there now.</p>
        <button class="btn btn-sm" type="button" data-send>Send this page to my Mac</button>
      </div>
    </div>
  </section>

  <section class="sec band" id="install" aria-labelledby="install-title">
    <div class="wrap">
      <div class="sec-head"><h2 class="h2" id="install-title">Install it in a minute.</h2></div>
      <div class="steps">
        <div class="step"><b>Open the download</b><p>Double-click Haven-1.0.0.dmg in your Downloads folder.</p></div>
        <div class="step"><b>Drag Haven to Applications</b><p>The window that opens shows Haven next to your Applications folder. Drag one onto the other.</p></div>
        <div class="step"><b>Open Haven</b><p>Pick the folders Haven should look after. macOS asks your permission for each one, and Haven starts reading them in the background.</p></div>
      </div>
      <p class="copy" style="margin-top:28px">Then open Haven, choose Settings › License and paste the key from your purchase email.</p>
    </div>
  </section>

  <section class="sec" aria-labelledby="req-title">
    <div class="wrap">
      <div class="sec-head"><h2 class="h3" style="font-size:clamp(1.75rem,1.3rem + 1.6vw,2.5rem)" id="req-title">What you need</h2></div>
      <div class="reqs">
        <div><b>macOS 14 Sonoma or later</b><span>Translate needs macOS 15. Summarize needs Apple Intelligence on macOS 26.</span></div>
        <div><b>Apple silicon or Intel</b><span>One app for both. Transcription is fastest on Apple silicon.</span></div>
        <div><b>About 100 MB of space</b><span>Plus 190 MB or 574 MB for a speech model, only if you transcribe.</span></div>
        <div><b>Internet, now and then</b><span>To download a speech model, check for updates and activate your license.</span></div>
      </div>
      <p class="fine" style="margin-top:32px">To uninstall, quit Haven and drag it to the Trash. To remove its index and settings too, delete the Haven folder in ~/Library/Application Support.</p>
    </div>
  </section>
"""

# ------------------------------------------------------------------ Privacy
privacy = """
  <section class="doc-head">
    <div class="wrap-text">
      <p class="eyebrow">Legal</p>
      <h1 class="h2">Privacy Policy</h1>
      <p class="fine">Effective October 21, 2026</p>
    </div>
  </section>
  <article class="wrap-text prose">
    <div class="summary">
      <strong>The short version</strong>
      <ul>
        <li>Haven works on your Mac. Your files, your search index and everything Haven reads from your files stay there.</li>
        <li>The app has no account, no analytics, no ads and no tracking.</li>
        <li>When you buy, our reseller, """ + PROVIDER + """, handles your payment and tax. We get your name, email and what you bought, never your card number.</li>
        <li>We never sell your information.</li>
      </ul>
    </div>
    <div class="toc"><ol>
      <li><a href="#who">Who we are</a></li>
      <li><a href="#app">What the app does with your files</a></li>
      <li><a href="#online">When the app goes online</a></li>
      <li><a href="#buying">When you buy a license</a></li>
      <li><a href="#site">This website</a></li>
      <li><a href="#support">When you write to us</a></li>
      <li><a href="#share">Who we share information with</a></li>
      <li><a href="#keep">How long we keep it</a></li>
      <li><a href="#rights">Your rights</a></li>
      <li><a href="#children">Children</a></li>
      <li><a href="#changes">Changes to this policy</a></li>
      <li><a href="#contact">Contact</a></li>
    </ol></div>

    <h2 id="who">1. Who we are</h2>
    <p>Haven is made by <span class="fill">Company legal name</span>, <span class="fill">registered address</span> (“we”, “us”). We are responsible for the personal information described in this policy.</p>

    <h2 id="app">2. What the app does with your files</h2>
    <p>Haven reads the folders you choose so it can search, sort and clean them up. To do that it keeps an index on your Mac with file names, sizes, dates, where downloads came from, and text it reads from your files (for example, words in screenshots, PDFs and transcribed recordings).</p>
    <ul>
      <li>The index is stored in ~/Library/Application Support/Haven on your Mac. It is never sent to us or anyone else.</li>
      <li>Text recognition, background removal, transcription, translation and summaries run on your Mac using Apple's frameworks and the Whisper model. Your files are not uploaded to do any of this.</li>
      <li>File tools write new files next to your originals. Files Haven moves go to the Trash, where you can restore them.</li>
      <li>The app contains no analytics, crash-reporting service, advertising or tracking code.</li>
    </ul>
    <p>You can delete the index at any time by deleting the Haven folder in ~/Library/Application Support.</p>

    <h2 id="online">3. When the app goes online</h2>
    <p>Haven connects to the internet only for these things:</p>
    <ul>
      <li><strong>Speech models.</strong> If you use Transcribe, Haven downloads the Whisper model you choose from Hugging Face (huggingface.co), which hosts the open-source whisper.cpp models. Hugging Face receives the request, including your IP address, as any website would. Nothing about your files is sent.</li>
      <li><strong>Updates.</strong> Haven checks our update server for new versions. The request includes the app version and your macOS version, and our server sees your IP address.</li>
      <li><strong>Translation languages.</strong> The first time you translate into a language, macOS downloads that language from Apple. The text you translate is processed on your Mac.</li>
      <li><strong>License activation.</strong> When you enter a license key, Haven sends the key and a random identifier for this Mac to our licensing service so we can count activations. It does not send your name, files or anything about them.</li>
    </ul>
    <p>Nothing else. Haven never sends files, file names, search terms or usage data.</p>

    <h2 id="buying">4. When you buy a license</h2>
    <p>Licenses are sold through """ + PROVIDER + """, our reseller and merchant of record. It collects your payment details directly, works out and collects tax, and handles them under its own privacy policy. We receive your name, email address, billing country, the plan you bought, the price and tax, and a record of the payment. We never see or store your full card number.</p>
    <p>We use this to deliver and manage your license, send your receipt and important notices about your purchase, handle refunds and meet our tax and accounting obligations. We do not send marketing email unless you ask for it.</p>

    <h2 id="site">5. This website</h2>
    <p>This website does not use cookies, analytics or advertising trackers, and it loads no fonts or scripts from other companies. Our hosting provider keeps standard server logs (IP address, pages requested, browser type) for security and reliability, for no longer than <span class="fill">30 days</span>.</p>

    <h2 id="support">6. When you write to us</h2>
    <p>If you email us, we keep your message and our reply so we can help you and follow up. Please don't send files you'd rather keep private; we'll never need them to help with your license.</p>

    <h2 id="share">7. Who we share information with</h2>
    <p>We share personal information only with service providers who help us run Haven, under contracts that limit what they can do with it:</p>
    <ul>
      <li>""" + PROVIDER + """, our reseller, for payments, receipts, tax, license keys and activations.</li>
      <li><span class="fill">Email provider</span>, for receipts and support email.</li>
      <li><span class="fill">Hosting provider</span>, for this website, downloads and update checks.</li>
    </ul>
    <p>We may also disclose information if the law requires it. We never sell or rent personal information, and we don't share it for advertising.</p>

    <h2 id="keep">8. How long we keep it</h2>
    <p>We keep purchase records for as long as tax and accounting law requires (typically up to 7 years), license records for as long as your license is active, and support email for up to 3 years after your last message. Then we delete it.</p>

    <h2 id="rights">9. Your rights</h2>
    <p>Depending on where you live, including the EU, UK and California, you can ask to see the personal information we hold about you, correct it, delete it, receive a copy, or object to how we use it. Write to us at the address below and we'll answer within 30 days. You can also complain to your local data protection authority.</p>
    <p>Where the GDPR applies, we rely on performing our contract with you (to sell and support your license), our legal obligations (tax records) and our legitimate interest in keeping our services secure.</p>
    <p>Some of our providers are in the United States. Where information leaves the EU or UK, it is protected by safeguards such as the European Commission's Standard Contractual Clauses.</p>

    <h2 id="children">10. Children</h2>
    <p>Haven is not directed at children under 13 (or 16 in the EU), and we don't knowingly collect their personal information.</p>

    <h2 id="changes">11. Changes to this policy</h2>
    <p>If we change this policy, we'll update the date at the top. If a change matters, for example a new kind of information we collect, we'll say so on this page and, if you've bought Haven, by email, before it takes effect.</p>

    <h2 id="contact">12. Contact</h2>
    <p>Questions or requests about privacy: <strong id="privacy-email" data-email="privacy">privacy@yourdomain.com</strong> <button class="btn-line btn-sm" type="button" data-copy-email="privacy-email">Copy</button></p>
    <p><span class="fill">Company legal name</span><br><span class="fill">Registered address</span></p>
  </article>
"""

# ------------------------------------------------------------------ Terms
terms = """
  <section class="doc-head">
    <div class="wrap-text">
      <p class="eyebrow">Legal</p>
      <h1 class="h2">Terms of Sale and License Agreement</h1>
      <p class="fine">Effective October 21, 2026</p>
    </div>
  </section>
  <article class="wrap-text prose">
    <div class="summary">
      <strong>The short version</strong>
      <ul>
        <li>You buy a license to use Haven on 1, 3 or 5 Macs, depending on your plan. You pay once.</li>
        <li>Updates to version 1 are free. Bought during the launch offer? Version 2 is included. Otherwise a future major version may be a paid upgrade, and the version you have keeps working.</li>
        <li>Changed your mind? Full refund within 30 days of buying.</li>
        <li>Haven moves files to the Trash rather than deleting them, but please keep backups of anything important.</li>
      </ul>
    </div>
    <div class="toc"><ol>
      <li><a href="#agreement">This agreement</a></li>
      <li><a href="#license">Your license</a></li>
      <li><a href="#buying">Buying and payment</a></li>
      <li><a href="#refunds">Refunds</a></li>
      <li><a href="#updates">Updates</a></li>
      <li><a href="#rules">What you may not do</a></li>
      <li><a href="#files">Your files and backups</a></li>
      <li><a href="#third">Third-party parts</a></li>
      <li><a href="#warranty">Warranty</a></li>
      <li><a href="#liability">Limits of liability</a></li>
      <li><a href="#ending">Ending the license</a></li>
      <li><a href="#law">Governing law</a></li>
      <li><a href="#changes">Changes</a></li>
      <li><a href="#contact">Contact</a></li>
    </ol></div>

    <h2 id="agreement">1. This agreement</h2>
    <p>These terms are an agreement between you and <span class="fill">Company legal name</span>, <span class="fill">registered address</span> (“we”, “us”), the maker of Haven. They cover buying a Haven license and using the app. By installing Haven or buying a license, you agree to them. If you're buying for a business, you confirm you can accept these terms for it.</p>
    <p>If you are a consumer, you also have rights under the law where you live. Nothing in these terms takes those rights away.</p>

    <h2 id="license">2. Your license</h2>
    <p>Haven is licensed, not sold. When you buy, we give you a non-exclusive, non-transferable license to install and use Haven on the number of Macs your plan covers at the same time:</p>
    <ul>
      <li><strong>1 Mac:</strong> one Mac that you own or control.</li>
      <li><strong>3 Macs:</strong> up to three Macs used by you or people in your household.</li>
      <li><strong>5 Macs:</strong> up to five Macs used by you, your household, or a business with up to five users.</li>
    </ul>
    <p>You can move a license to another Mac by deactivating it on the old one. You can add Macs later by paying the difference between plans.</p>

    <h2 id="buying">3. Buying and payment</h2>
    <p>Our order process is run by our online reseller, """ + PROVIDER + """, which is the merchant of record for your purchase: it takes your payment, works out and collects any sales tax, VAT or GST, and sends your receipt. Its own terms apply to the payment; these terms cover your license and the app.</p>
    <p>Prices are shown in US dollars on our website, and checkout may show and charge the price in your own currency. Your license key is emailed to you with your receipt, so you can buy on any device and install on your Mac later. We may change prices for future purchases; that never affects a license you've already bought.</p>

    <h2 id="refunds">4. Refunds</h2>
    <p>If Haven isn't right for you, email us within 30 days of your purchase from the address you bought with, or include your order number, and we'll refund the full price, including tax, to your original payment method through """ + PROVIDER + """. You don't need to give a reason. Once refunded, the license key stops working.</p>
    <p>If you live in the EU or UK, you have a legal right to withdraw from a purchase of digital content within 14 days. By starting to use your license key right away, you agree that it is supplied immediately. Our 30-day refund applies to you in any case.</p>

    <h2 id="updates">5. Updates</h2>
    <p>Every update to version 1 of Haven is free for license holders. Licenses bought while our launch offer was shown on our website also include version 2 at no extra cost. Otherwise, we may release a new major version with new features as a paid upgrade. If you don't upgrade, the version you have keeps working under these terms. We aim to keep Haven working with new versions of macOS, but we can't promise every version of Haven will run on every future version of macOS.</p>

    <h2 id="rules">6. What you may not do</h2>
    <p>You may not: share your license key publicly or with people your plan doesn't cover; sell, rent or sublicense Haven; get around the license checks; or reverse engineer, decompile or modify the app, except where the law allows it despite this restriction. You agree to use Haven only with files you have the right to work with.</p>

    <h2 id="files">7. Your files and backups</h2>
    <p>Haven is designed to be careful: it shows you files before moving them, sends them to the Trash rather than deleting them, and never changes your originals when it makes new files. Even so, computers fail and mistakes happen. Keep backups of files that matter, for example with Time Machine. Emptying the Trash is your decision and can't be undone by Haven.</p>

    <h2 id="third">8. Third-party parts</h2>
    <p>Haven includes open-source software, including whisper.cpp and Whisper models, which are MIT licensed. Their notices are in Haven › Settings › Acknowledgements. Some features use Apple frameworks and services, such as Apple Intelligence and Translation, which are provided by Apple under Apple's terms. Apple is not a party to this agreement and is not responsible for Haven.</p>

    <h2 id="warranty">9. Warranty</h2>
    <p>We work hard to make Haven reliable, and we'll fix problems you report. Apart from that, and to the extent the law allows, Haven is provided “as is”, without warranties of any kind, including fitness for a particular purpose and non-infringement. Results from transcription, translation, text recognition, summaries and background removal are produced automatically and may contain mistakes; check them before relying on them.</p>

    <h2 id="liability">10. Limits of liability</h2>
    <p>To the extent the law allows, we are not liable for indirect, incidental or consequential losses, or for loss of data, profits or business, arising from your use of Haven. Our total liability for any claim about Haven is limited to the amount you paid for your license. These limits don't apply where the law doesn't allow them, such as for death or personal injury caused by negligence, or fraud.</p>

    <h2 id="ending">11. Ending the license</h2>
    <p>You can stop using Haven at any time. If you break these terms in a serious way and don't fix it after we tell you, we may end your license. If we do, you must stop using Haven and delete it.</p>

    <h2 id="law">12. Governing law</h2>
    <p>These terms are governed by the laws of <span class="fill">jurisdiction</span>, and disputes will be handled by the courts of <span class="fill">jurisdiction</span>. If you're a consumer, you can also bring a claim where you live, and you keep the protection of your local consumer laws.</p>

    <h2 id="changes">13. Changes</h2>
    <p>We may update these terms for new purchases. The terms you agreed to when you bought continue to apply to that license unless you agree to new ones. We'll update the date at the top whenever these terms change.</p>

    <h2 id="contact">14. Contact</h2>
    <p>Questions about these terms, refunds or your license: <strong id="support-email" data-email="support">support@yourdomain.com</strong> <button class="btn-line btn-sm" type="button" data-copy-email="support-email">Copy</button></p>
    <p><span class="fill">Company legal name</span><br><span class="fill">Registered address</span></p>
  </article>
"""

thanks = f"""
  <section class="night page-hero center" aria-labelledby="ty-title">
    <div class="aurora soft" aria-hidden="true"><i></i><i></i></div>
    <div class="wrap">
      <img class="dl-icon" src="assets/img/icon-256.png" width="128" height="128" alt="Haven app icon" style="margin-inline:auto">
      <p class="eyebrow">Thank you</p>
      <h1 class="h1" id="ty-title">Haven is <em class="serif glowtext">yours.</em></h1>
      <p class="lead">Your license key is on its way to your inbox, with your receipt from {PROVIDER}. It usually arrives within a minute.</p>
      <div class="cta-row mac-only"><a class="btn btn-glow btn-lg" href="download.html#install" data-dmg>Download Haven</a></div>
      <div class="away-note away-only">
        <b>On your phone? Install on your Mac later.</b>
        <p>The email with your key has the download link: open it on your Mac when you're ready. Or send the download page to your Mac now.</p>
        <button class="btn btn-sm" type="button" data-send="download.html">Send it to my Mac</button>
      </div>
      <p class="launch" data-launch hidden style="max-width:560px;margin:22px auto 0;text-align:left"><svg aria-hidden="true"><use href="#i-sparkle"/></svg><span>You bought during the launch offer, so <b>Haven 2 is included</b> when it comes.</span></p>
    </div>
  </section>

  <section class="sec band" aria-labelledby="next-title">
    <div class="wrap">
      <div class="sec-head"><h2 class="h2" id="next-title">Three steps on your Mac.</h2></div>
      <div class="steps">
        <div class="step"><b>Download and install</b><p>Open Haven-1.0.0.dmg and drag Haven onto Applications. <a href="download.html#install">Install help</a></p></div>
        <div class="step"><b>Open Haven</b><p>Pick the folders it should look after. macOS asks your permission for each one.</p></div>
        <div class="step"><b>Enter your key</b><p>Choose Settings › License and paste the key from your email. It works on as many Macs as your plan covers.</p></div>
      </div>
      <p class="copy" style="margin-top:28px">No email after a few minutes? Check your spam folder, then write to <strong id="support-email" data-email="support">support@yourdomain.com</strong> <button class="btn-line btn-sm" type="button" data-copy-email="support-email">Copy</button> and we'll send your key again.</p>
    </div>
  </section>
"""

page("compare.html", "Haven Compared", "How Haven compares with Finder and Spotlight, online converter sites, and buying a dozen single-purpose Mac apps.", "How Haven compares", compare, "compare.html")
page("pricing.html", "Haven Pricing", "Haven is $49 for one Mac, $79 for three and $99 for five. Pay once, free version 1 updates and a 30-day money-back guarantee.", "Haven pricing: pay once, keep it", pricing, "pricing.html")
page("faq.html", "Haven FAQ", "Answers about Haven for Mac: features, privacy, licenses, refunds and troubleshooting.", "Haven questions, answered", faqpage, "faq.html")
page("download.html", "Download Haven", "Download Haven for Mac (customers). macOS 14 Sonoma or later, Apple silicon and Intel.", "Download Haven for Mac", download)
page("privacy.html", "Haven Privacy Policy", "How Haven handles your information: files stay on your Mac, no analytics, and payments through our reseller.", "Haven privacy policy", privacy, sales=False)
page("thanks.html", "Thank You", "Thank you for buying Haven. Your license key is on its way.", "Thank you for buying Haven", thanks, sales=False, index=False)
page("terms.html", "Haven Terms of Sale", "Terms of sale and license agreement for Haven for Mac, including the 30-day refund policy.", "Haven terms of sale", terms, sales=False)
