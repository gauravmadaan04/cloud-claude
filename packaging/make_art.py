"""Draws the DMG window background (1x and 2x) and writes "Read Me First.pdf".

python3 packaging/make_art.py
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 740, 560
# Everything is laid out on a 720×520 grid, offset so Finder has breathing room (no scrollbars).
OX, OY = 10, 14
INTER = "/usr/share/fonts/opentype/inter/Inter-{}.otf"


def font(weight, size):
    return ImageFont.truetype(INTER.format(weight), size)


def hexrgb(h, a=255):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255, a)


def background(scale):
    full = gradient(W * scale, H * scale)
    layer = content(scale)
    full.paste(layer, (OX * scale, OY * scale), layer)
    return full.convert("RGB")


def gradient(w, h):
    img = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    px = img.load()
    c1, c2, c3 = (250, 246, 255), (255, 244, 248), (243, 249, 255)
    for y in range(h):
        for x in range(w):
            t = (x / w * 0.6 + y / h * 0.4)
            if t < 0.5:
                u = t / 0.5
                c = tuple(int(c1[i] + (c2[i] - c1[i]) * u) for i in range(3))
            else:
                u = (t - 0.5) / 0.5
                c = tuple(int(c2[i] + (c3[i] - c2[i]) * u) for i in range(3))
            px[x, y] = c + (255,)
    return img


def content(scale):
    w, h = 720 * scale, 520 * scale
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = scale

    # Title
    title = "Install Haven"
    f = font("Bold", 30 * s)
    tw = d.textlength(title, font=f)
    d.text(((w - tw) / 2, 30 * s), title, font=f, fill=hexrgb(0x241C3D))
    sub = "Your files, beautifully organised. Everything stays on your Mac."
    f2 = font("Regular", 13 * s)
    sw = d.textlength(sub, font=f2)
    d.text(((w - sw) / 2, 70 * s), sub, font=f2, fill=hexrgb(0x6E6880))

    # Arrow from the app (x=190) to Applications (x=530) at y=178 (icons are 100 pt).
    y = 178 * s
    x0, x1 = 266 * s, 454 * s
    for i in range(int(x0), int(x1 - 26 * s), int(14 * s)):
        d.rounded_rectangle([i, y - 3 * s, i + 8 * s, y + 3 * s], radius=3 * s, fill=hexrgb(0x8E7BFF))
    d.polygon([(x1 - 26 * s, y - 13 * s), (x1, y), (x1 - 26 * s, y + 13 * s)], fill=hexrgb(0x6B4EFF))
    lab = "drag"
    fl = font("SemiBold", 12 * s)
    lw = d.textlength(lab, font=fl)
    d.text(((x0 + x1) / 2 - lw / 2, y - 30 * s), lab, font=fl, fill=hexrgb(0x6B4EFF))

    # One card: the steps on the left, the guide (Finder draws its icon at 587, 396) on the right.
    card = [24 * s, 296 * s, 696 * s, 492 * s]
    divider = 478 * s
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([card[0], card[1] + 4 * s, card[2], card[3] + 4 * s], radius=18 * s, fill=(60, 40, 120, 34))
    shadow = shadow.filter(ImageFilter.GaussianBlur(8 * s))
    img = Image.alpha_composite(img, shadow)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(card, radius=18 * s, fill=(255, 255, 255, 240), outline=hexrgb(0xE6E0F5), width=max(1, s))
    d.line([(divider, 320 * s), (divider, 468 * s)], fill=hexrgb(0xECE7F7), width=max(1, s))

    steps = [
        ("1", "Drag Haven onto Applications.", None),
        ("2", "Open Haven from Applications.", None),
        ("3", "First time only: if macOS can't verify Haven,",
         "choose System Settings › Privacy & Security › Open Anyway."),
    ]
    sy = 335 * s
    fb = font("SemiBold", 14 * s)
    fr = font("Regular", 12.5 * s)
    fn = font("Bold", 12 * s)
    for num, line, extra in steps:
        cx, cy, r = 52 * s, sy + 10 * s, 11 * s
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=hexrgb(0x6B4EFF))
        nw = d.textlength(num, font=fn)
        d.text((cx - nw / 2, cy - 8 * s), num, font=fn, fill=(255, 255, 255, 255))
        d.text((74 * s, sy), line, font=fb, fill=hexrgb(0x241C3D))
        assert 74 * s + d.textlength(line, font=fb) < divider - 12 * s, line
        if extra:
            d.text((74 * s, sy + 21 * s), extra, font=fr, fill=hexrgb(0x5A5470))
            assert 74 * s + d.textlength(extra, font=fr) < divider - 12 * s, extra
            sy += 21 * s
        sy += 40 * s

    # Caption over the guide's icon.
    cx = (divider + card[2]) / 2
    a, b = "New here? ", "Read this first"
    fa, fb2 = font("SemiBold", 12 * s), font("Regular", 12 * s)
    total = d.textlength(a, font=fa) + d.textlength(b, font=fb2)
    left = cx - total / 2
    d.text((left, 318 * s), a, font=fa, fill=hexrgb(0x6B4EFF))
    d.text((left + d.textlength(a, font=fa), 318 * s), b, font=fb2, fill=hexrgb(0x6E6880))
    return img


def readme_pdf(path):
    from reportlab.lib.colors import HexColor
    from reportlab.lib.pagesizes import A4
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.pdfgen import canvas

    pdfmetrics.registerFont(TTFont("DV", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"))
    pdfmetrics.registerFont(TTFont("DVB", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"))
    pdfmetrics.registerFont(TTFont("DVM", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"))
    ink, soft, accent = HexColor("#241C3D"), HexColor("#5A5470"), HexColor("#6B4EFF")
    pw, ph = A4
    c = canvas.Canvas(path, pagesize=A4)
    c.setTitle("Haven: Read Me First")
    c.setAuthor("Haven")
    icon = os.path.join(os.path.dirname(HERE), "scripts", "icon-1024.png")

    def wrap(text, fontname, size, width):
        words, lines, cur = text.split(), [], ""
        for w in words:
            trial = (cur + " " + w).strip()
            if pdfmetrics.stringWidth(trial, fontname, size) > width and cur:
                lines.append(cur)
                cur = w
            else:
                cur = trial
        if cur:
            lines.append(cur)
        return lines

    def para(text, x, y, width, size=11, fontname="DV", color=soft, leading=1.45):
        c.setFont(fontname, size)
        c.setFillColor(color)
        for line in wrap(text, fontname, size, width):
            c.drawString(x, y, line)
            y -= size * leading
        return y

    def header(title, subtitle):
        c.setFillColor(HexColor("#F6F2FF"))
        c.rect(0, ph - 150, pw, 150, stroke=0, fill=1)
        if os.path.exists(icon):
            c.drawImage(icon, 48, ph - 128, 96, 96, mask="auto")
        c.setFillColor(ink)
        c.setFont("DVB", 26)
        c.drawString(160, ph - 78, title)
        c.setFont("DV", 12)
        c.setFillColor(soft)
        c.drawString(160, ph - 100, subtitle)

    def step(n, title, body, y):
        c.setFillColor(accent)
        c.circle(62, y + 4, 12, stroke=0, fill=1)
        c.setFillColor(HexColor("#FFFFFF"))
        c.setFont("DVB", 12)
        c.drawCentredString(62, y, str(n))
        c.setFillColor(ink)
        c.setFont("DVB", 14)
        c.drawString(86, y, title)
        y -= 20
        for b in body:
            if b.startswith("$ "):
                c.setFillColor(HexColor("#F1EEF8"))
                c.roundRect(86, y - 6, pw - 140, 20, 4, stroke=0, fill=1)
                c.setFillColor(ink)
                c.setFont("DVM", 10)
                c.drawString(94, y, b[2:])
                y -= 26
            else:
                y = para(b, 86, y, pw - 140) - 4
        return y - 14

    # Page 1: install
    header("Welcome to Haven", "Read me first: installing takes about a minute.")
    y = ph - 190
    y = step(1, "Drag Haven into Applications", ["In the window that opened, drag the Haven icon onto the Applications folder."], y)
    y = step(2, "Open Haven", ["Open your Applications folder (Finder › Go › Applications, or ⇧⌘A) and double-click Haven."], y)
    y = step(3, "First time only: tell macOS you trust Haven", [
        "Haven was built just for you, so it isn't notarized by Apple. The first time you open it, macOS may say "
        "“Apple could not verify Haven is free of malware”. That's expected. Click Done, then:",
        "• macOS 15 Sequoia or later: open System Settings › Privacy & Security, scroll down to Security and click "
        "“Open Anyway” next to Haven. Confirm with your password, then click Open Anyway again.",
        "• macOS 14 Sonoma: right-click (or Control-click) Haven in Applications, choose Open, then click Open.",
        "Prefer Terminal? This does the same in one line:",
        "$ xattr -dr com.apple.quarantine /Applications/Haven.app",
        "You only do this once. After that Haven opens like any other app.",
    ], y)
    y = step(4, "Take the one-minute tour", [
        "Haven opens with a short welcome tour. When it asks about folders, click Allow for Desktop, Documents and "
        "Downloads, and click OK when macOS asks. Haven only reads them to show and search your files.",
        "You'll pick a look (Playful or Minimal), try a plain-English search, and test Quick Search (⇧⌘Space).",
    ], y)
    c.setFillColor(HexColor("#F6F2FF"))
    c.roundRect(48, 48, pw - 96, 64, 10, stroke=0, fill=1)
    para("Private by design: no account, no uploads, no internet use at all. Reading text in images and finding "
         "duplicates happen on your Mac. Haven never deletes files; they only go to the Trash, and you can undo.",
         64, 92, pw - 128, size=10, color=ink)
    c.showPage()

    # Page 2: everyday use
    header("Everyday Haven", "The things you'll use most, and their shortcuts.")
    y = ph - 185
    items = [
        ("Search like you talk (⌘F)", "Type “pdfs from last week”, “screenshots over 5 MB”, “photos from whatsapp” or "
         "“big videos older than a year”. Haven shows how it read your words as chips; click × on a chip to drop it. "
         "Matches names, tags, folders and the text inside screenshots, photos and PDFs."),
        ("Quick Search from any app (⇧⌘Space)", "A Spotlight-style panel. ↩ opens the file, ⌘↩ shows it in Haven, "
         "⌥↩ shows it in Finder, ⌘C copies it. Change the shortcut in Settings › Quick Search."),
        ("Copy text from images (⇧⌘C)", "Hover a screenshot or PDF and click the Copy Text button, or open the big "
         "preview (double-click) and select text right in the picture."),
        ("Downloaded From (⇧⌘J)", "Downloads grouped by Gmail, Google Drive, ChatGPT, Canva, WhatsApp, Slack, GitHub, "
         "AirDrop or any website. Every list also has a “From” filter."),
        ("Duplicates (⇧⌘D) and Clean Up (⇧⌘K)", "Finds identical files and look-alike photos, old installers, "
         "forgotten downloads, old screenshots, big old videos, unused apps and zips you already unzipped. You review "
         "everything first; files go to the Trash and Undo puts them back. See Activity for a full history."),
        ("Menu bar", "The ten newest downloads with thumbnails. Drag them straight into Mail, Slack or Figma."),
        ("Saved searches & rules", "Save any search to the sidebar; it updates by itself. Optional rules (off by "
         "default) can trash old installers or file screenshots into monthly folders."),
        ("Shortcuts & Siri", "Use “Find Files”, “Get Latest Download” and “Search in Haven” in the Shortcuts app."),
    ]
    for title, body in items:
        c.setFillColor(accent)
        c.circle(56, y + 4, 3.5, stroke=0, fill=1)
        c.setFillColor(ink)
        c.setFont("DVB", 12.5)
        c.drawString(68, y, title)
        y = para(body, 68, y - 17, pw - 120, size=10.5) - 10
    c.setFillColor(ink)
    c.setFont("DVB", 12.5)
    c.drawString(48, y - 4, "More shortcuts")
    y -= 24
    keys = [("Space", "Quick Look"), ("⌘I", "Inspector"), ("⌘1 / ⌘2", "Grid / List"), ("⌘+ / ⌘−", "Card size"),
            ("⌃⌘T", "Switch look"), ("⌘⌫", "Move to Trash"), ("⌘Z", "Undo"), ("⌘/", "All shortcuts")]
    col_x = [48, 300]
    for i, (k, v) in enumerate(keys):
        x = col_x[i % 2]
        yy = y - (i // 2) * 20
        c.setFont("DVB", 10.5)
        c.setFillColor(accent)
        c.drawString(x, yy, k)
        c.setFont("DV", 10.5)
        c.setFillColor(soft)
        c.drawString(x + 80, yy, v)
    y -= 4 * 20 + 30
    para("To remove Haven: quit it, drag it from Applications to the Trash, and delete the folder "
         "~/Library/Application Support/Haven. Replay the tour any time from Help › Welcome Tour.",
         48, max(y, 70), pw - 96, size=9.5)
    c.showPage()

    # Page 3: getting more done
    header("Getting more done", "Tools for the chores Finder makes slow.")
    y = ph - 185
    more = [
        ("Smart rename (⌘R)", "Rename one file or hundreds: add dates, numbers, find & replace, or name screenshots and "
         "PDFs by what's written in them (“2026-10-12 Boarding Pass.png”). You see every new name first; ⌘Z undoes it."),
        ("Space", "See which folders and files take the most room, by kind, by where they came from and by when you "
         "last used them. Click a folder to look inside; folder sizes also show in list view."),
        ("Your own rules", "On Clean Up: “PDFs from Gmail with ‘invoice’ in them → Documents/Invoices”, “WhatsApp "
         "photos → Pictures/WhatsApp”, or name screenshots by their text. Start from an idea, see what a rule would do "
         "before turning it on, and undo anything it did from Activity."),
        ("Make Shareable", "Right-click: Save as JPEG (for HEIC photos), Make a Smaller Image, Make a Smaller PDF, or "
         "Compress as ZIP. Copies go next to the originals, which never change."),
        ("The Shelf (⌥⌘S)", "A small window that floats over every app. Drop files on it from anywhere, then drag "
         "them all into Mail, Slack or a folder at once."),
        ("Collections", "Like playlists for files: one file can be in many collections and stays where it is. Drop "
         "files onto a collection in the sidebar, or right-click › Add to Collection."),
        ("Text in more files", "Haven also reads Word, Excel, PowerPoint, OpenDocument and EPUB files, the first page "
         "of Pages, Numbers and Keynote files, and web pages, with its own index (it doesn't rely on Spotlight)."),
        ("Copy List and Open/Save jump", "Copy List above any list copies names, paths or a table for Numbers or "
         "Excel. In an app's Open or Save dialog, open Quick Search, pick a folder and press ⌃↩ to jump there."),
    ]
    for title, body in more:
        c.setFillColor(accent)
        c.circle(56, y + 4, 3.5, stroke=0, fill=1)
        c.setFillColor(ink)
        c.setFont("DVB", 12.5)
        c.drawString(68, y, title)
        y = para(body, 68, y - 17, pw - 120, size=10.5) - 10
    c.showPage()
    c.save()


def main():
    background(1).save(os.path.join(HERE, "dmg-background.png"))
    background(2).save(os.path.join(HERE, "dmg-background@2x.png"))
    readme_pdf(os.path.join(HERE, "Read Me First.pdf"))
    print("ok")


if __name__ == "__main__":
    main()
