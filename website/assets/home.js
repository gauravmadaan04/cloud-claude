// The home page demos. Everything is sample data drawn in the browser; nothing is uploaded or sent anywhere.
(function () {
  "use strict";

  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var DAY = 86400000;
  var now = new Date();
  var $ = function (id) { return document.getElementById(id); };

  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; });
  }
  function pad(n) { return n < 10 ? "0" + n : "" + n; }
  function ago(d) { return new Date(now.getTime() - d * DAY); }
  function ymd(date) { return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate()); }
  function size(mb) {
    if (mb >= 1000) return (mb / 1000).toFixed(mb >= 10000 ? 0 : 1) + " GB";
    if (mb >= 1) return (mb >= 100 ? Math.round(mb) : mb.toFixed(1).replace(/\.0$/, "")) + " MB";
    return Math.max(1, Math.round(mb * 1000)) + " KB";
  }
  function when(d) {
    if (d < 1) return "Today";
    if (d < 2) return "Yesterday";
    var date = ago(d);
    var opts = d < 300 ? { month: "short", day: "numeric" } : { month: "short", day: "numeric", year: "numeric" };
    return date.toLocaleDateString("en-US", opts);
  }
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  // ---------------------------------------------------------------- Sample library
  var PH = {
    sunset: "radial-gradient(circle at 68% 56%, #fff0c2 0 7%, transparent 7.5%), linear-gradient(172deg, transparent 63%, #3b2550 63.5%), linear-gradient(180deg, #ffb36b, #f2706d 52%, #8a4a8f)",
    beach: "radial-gradient(ellipse at 50% 125%, #f3dfb5 0 40%, transparent 40.5%), linear-gradient(180deg, #8fd3f4 0 46%, #2d9cc4 46% 64%, #f3dfb5 64%)",
    dinner: "radial-gradient(circle at 50% 58%, #c0502d 0 13%, #e7a23b 13.5% 17%, transparent 17.5%), radial-gradient(circle at 50% 58%, #f6efe6 0 29%, #d8c9b8 29.5% 32%, transparent 32.5%), linear-gradient(135deg, #3a2a22, #6b4632)",
    mount: "linear-gradient(148deg, transparent 56%, #5b6f8a 56.5%), linear-gradient(212deg, transparent 52%, #3e5170 52.5%), linear-gradient(180deg, #c8dcf0, #eef4fb)",
    logo: "radial-gradient(circle at 38% 50%, #6a4df2 0 17%, transparent 17.5%), radial-gradient(circle at 62% 50%, rgba(223, 90, 144, 0.9) 0 17%, transparent 17.5%), linear-gradient(#f4f1fb, #f4f1fb)",
    gen: "conic-gradient(from 210deg at 50% 55%, #7dd3c0, #6a8cf2, #c58af0, #f29ab8, #7dd3c0)",
    wb: "linear-gradient(170deg, #fbfbf8, #e3e2dc)",
    deck: "linear-gradient(180deg, #ff9f43 0 30%, #fff 30%)",
    call: "radial-gradient(circle at 26% 42%, #d9a27a 0 10%, transparent 10.5%), radial-gradient(circle at 74% 42%, #8a6a52 0 10%, transparent 10.5%), radial-gradient(ellipse at 26% 92%, #4a5d8a 0 25%, transparent 25.5%), radial-gradient(ellipse at 74% 92%, #7a4a5a 0 25%, transparent 25.5%), linear-gradient(90deg, #2a3142 0 49.5%, #111 49.5% 50.5%, #262a3a 50.5%)",
    wedding: "radial-gradient(circle at 70% 30%, rgba(255, 255, 255, 0.7) 0 8%, transparent 9%), linear-gradient(135deg, #f3d9c9, #c99a8a 60%, #8e6a6a)",
    screen: "linear-gradient(180deg, #e9e9ef 0 12%, #fff 12% 100%)",
    cake: "radial-gradient(circle at 50% 30%, #ffd166 0 3%, transparent 3.5%), linear-gradient(180deg, transparent 0 34%, #f7e3ea 34% 58%, #e98fae 58% 64%, #f7e3ea 64% 82%, transparent 82%), linear-gradient(135deg, #59406e, #2d2440)",
    park: "radial-gradient(ellipse at 30% 40%, #5cae5a 0 22%, transparent 22.5%), radial-gradient(ellipse at 72% 36%, #4a9a4f 0 20%, transparent 20.5%), linear-gradient(180deg, #a8d8f0 0 45%, #7fbf6a 45%)",
    market: "radial-gradient(circle at 22% 70%, #e2533a 0 8%, transparent 8.5%), radial-gradient(circle at 40% 72%, #f2a33a 0 8%, transparent 8.5%), radial-gradient(circle at 58% 70%, #8bbf3f 0 8%, transparent 8.5%), radial-gradient(circle at 76% 72%, #d94a6a 0 8%, transparent 8.5%), linear-gradient(180deg, #f3efe6 0 30%, #b1835a 30% 50%, #8a5c38 50%)",
    grad: "radial-gradient(circle at 50% 38%, #1d1d24 0 12%, transparent 12.5%), linear-gradient(180deg, #8fb9e8, #d8e7f6 60%, #6f9a5b 60%)",
    holiday: "radial-gradient(circle at 75% 25%, #fff6c9 0 7%, transparent 7.5%), linear-gradient(180deg, #4fb3d9 0 55%, #f0d8a8 55%)",
    demo: "radial-gradient(circle at 30% 70%, rgba(255, 255, 255, 0.25) 0 18%, transparent 19%), linear-gradient(135deg, #4b3bd6, #9a5ae8)",
  };

  var FILES = [
    { n: "Q3 report.pdf", k: "pdf", mb: 1.2, d: 8, src: "Gmail", dir: "Downloads", text: "Q3 report. Revenue up 18%. Marketing budget for Q4 needs sign-off." },
    { n: "Invoice 4821.pdf", k: "pdf", mb: 0.22, d: 9, src: "Gmail", dir: "Downloads", text: "Invoice 4821. Amount due $1,240.00 by November 15." },
    { n: "Boarding pass.pdf", k: "pdf", mb: 0.18, d: 2, src: "Mail", dir: "Downloads", text: "Boarding pass SFO to JFK, gate 22, seat 14A." },
    { n: "Tax receipt.pdf", k: "pdf", mb: 0.31, d: 10, src: "Gmail", dir: "Downloads", text: "Receipt for estimated tax payment, Q3." },
    { n: "Train tickets.pdf", k: "pdf", mb: 0.42, d: 13, src: "Mail", dir: "Downloads", text: "Two tickets, Lisbon to Porto, coach 4." },
    { n: "Insurance renewal.pdf", k: "pdf", mb: 0.95, d: 12, src: "Gmail", dir: "Downloads", text: "Home insurance renewal. Policy HX-20931." },
    { n: "Meeting agenda.pdf", k: "pdf", mb: 0.11, d: 7, src: "Outlook", dir: "Downloads", text: "Agenda: launch, budget review, hiring." },
    { n: "Lease agreement.pdf", k: "pdf", mb: 3.4, d: 41, src: "Google Drive", dir: "Documents", text: "Residential lease agreement for 14 Alder Street." },
    { n: "Services agreement (signed).pdf", k: "pdf", mb: 0.64, d: 11, src: "Outlook", dir: "Downloads", text: "Services agreement. Signed by both parties." },
    { n: "Screenshot " + ymd(ago(4)) + " at 09.41.22.png", k: "shot", mb: 6.4, d: 4, dir: "Desktop", text: "Wi-Fi password: blue-otter-42 on network Studio 5G" },
    { n: "Screenshot " + ymd(ago(12)) + " at 18.02.10.png", k: "shot", mb: 7.9, d: 12, dir: "Desktop", text: "Flight confirmation ABC123, Lisbon, seat 21C" },
    { n: "Screenshot " + ymd(ago(52)) + " at 11.15.48.png", k: "shot", mb: 1.1, d: 52, dir: "Desktop", text: "Meeting notes: budget review moved, hiring plan" },
    { n: "Screenshot " + ymd(ago(2)) + " at 20.17.03.png", k: "shot", mb: 8.3, d: 2, dir: "Desktop", text: "Order #88214 has shipped. Arrives Thursday." },
    { n: "Screenshot " + ymd(ago(19)) + " at 07.58.40.png", k: "shot", mb: 5.6, d: 19, dir: "Desktop", text: "Your disk is almost full." },
    { n: "Screenshot " + ymd(ago(26)) + " at 13.30.12.png", k: "shot", mb: 6.1, d: 26, dir: "Desktop", text: "Recipe: lemon pasta, serves four" },
    { n: "IMG_4021.HEIC", k: "photo", mb: 3.1, d: 1, src: "AirDrop", dir: "Pictures", ph: "sunset" },
    { n: "Beach day.jpg", k: "photo", mb: 2.4, d: 3, src: "WhatsApp", dir: "Downloads", ph: "beach" },
    { n: "Dinner.jpg", k: "photo", mb: 1.8, d: 5, src: "WhatsApp", dir: "Downloads", ph: "dinner" },
    { n: "IMG_2207.HEIC", k: "photo", mb: 2.2, d: 8, src: "WhatsApp", dir: "Downloads", ph: "wb", text: "Q4 roadmap. Launch plan: Oct 28. Beta invites Mon. Pricing page. Budget review moved to Thu." },
    { n: "Birthday cake.jpg", k: "photo", mb: 2.1, d: 6, src: "WhatsApp", dir: "Downloads", ph: "cake" },
    { n: "At the park.jpg", k: "photo", mb: 2.9, d: 9, src: "WhatsApp", dir: "Downloads", ph: "park" },
    { n: "Sunday market.jpg", k: "photo", mb: 3.3, d: 13, src: "WhatsApp", dir: "Downloads", ph: "market" },
    { n: "Mountains.heic", k: "photo", mb: 4.5, d: 220, src: "AirDrop", dir: "Pictures", ph: "mount" },
    { n: "Logo concepts.png", k: "image", mb: 2.8, d: 6, src: "Figma", dir: "Downloads", ph: "logo" },
    { n: "ChatGPT Image.png", k: "image", mb: 1.6, d: 7, src: "ChatGPT", dir: "Downloads", ph: "gen" },
    { n: "Team call.mov", k: "video", mb: 412, d: 3, src: "Zoom", dir: "Movies", ph: "call", dur: "32:14", said: "We need to move the budget review to Thursday.", saidAt: "04:12" },
    { n: "Wedding highlights.mp4", k: "video", mb: 2150, d: 410, src: "Google Drive", dir: "Movies", ph: "wedding", dur: "8:41" },
    { n: "Graduation.mov", k: "video", mb: 1400, d: 540, src: "AirDrop", dir: "Movies", ph: "grad", dur: "21:37" },
    { n: "Holiday 2024.mp4", k: "video", mb: 3200, d: 480, dir: "Movies", ph: "holiday", dur: "12:05" },
    { n: "Screen recording.mov", k: "video", mb: 860, d: 396, dir: "Desktop", ph: "screen", dur: "14:02" },
    { n: "Product demo.mp4", k: "video", mb: 96, d: 20, src: "Slack", dir: "Downloads", ph: "demo", dur: "2:36", said: "Drag any file onto the shelf, then drop it into the email.", saidAt: "01:08" },
    { n: "Podcast episode 12.m4a", k: "audio", mb: 54, d: 15, dir: "Music" },
    { n: "Brand assets.zip", k: "zip", mb: 380, d: 30, src: "Slack", dir: "Downloads" },
    { n: "Figma installer.dmg", k: "dmg", mb: 210, d: 120, src: "figma.com", dir: "Downloads" },
    { n: "Budget 2026.xlsx", k: "sheet", mb: 0.088, d: 7, src: "Gmail", dir: "Documents", text: "Budget 2026: marketing, travel, hiring" },
    { n: "Pitch deck.key", k: "deck", mb: 24, d: 11, src: "Slack", dir: "Documents", ph: "deck", text: "Pitch deck. Seed round." },
    { n: "Resume.docx", k: "doc", mb: 0.12, d: 60, src: "Gmail", dir: "Documents", text: "Resume. Product designer, 8 years." },
  ];

  function thumb(f, bare) {
    var badge = f.src && !bare ? '<span class="src-badge">' + esc(f.src) + "</span>" : "";
    var lines = function (n) { var s = ""; for (var i = 0; i < n; i++) s += "<i></i>"; return s; };
    switch (f.k) {
      case "pdf": return '<div class="th th-pdf"><div class="page"><b></b>' + lines(7) + "</div>" + badge + "</div>";
      case "doc": return '<div class="th th-doc"><div class="page blue"><b></b>' + lines(7) + "</div>" + badge + "</div>";
      case "sheet": return '<div class="th th-doc"><div class="page green">' + lines(20) + "</div>" + badge + "</div>";
      case "shot": return '<div class="th th-shot"><div class="scr"><span></span><span></span><span></span><span></span></div>' + badge + "</div>";
      case "video":
        return '<div class="th th-video" style="--ph:' + PH[f.ph] + '"><span class="play"></span>' + (bare ? "" : '<span class="dur">' + f.dur + "</span>") + badge + "</div>";
      case "audio": {
        var bars = "", hs = [30, 52, 38, 66, 44, 72, 50, 34, 58, 40, 26];
        hs.forEach(function (h) { bars += '<i style="height:' + h + '%"></i>'; });
        return '<div class="th th-audio">' + bars + badge + "</div>";
      }
      case "zip": return '<div class="th th-box"><svg style="color:#c98a2b"><use href="#i-archive"/></svg>' + badge + "</div>";
      case "dmg": return '<div class="th th-box"><svg style="color:#6b6878"><use href="#i-box"/></svg>' + badge + "</div>";
      default: {
        var extra = f.ph === "wb" ? '<span class="wbmini">Launch plan:<br>Oct 28</span>' : f.ph === "deck" ? '<span class="deckmini">Pitch</span>' : "";
        return '<div class="th th-photo" style="--ph:' + PH[f.ph] + '">' + extra + badge + "</div>";
      }
    }
  }

  // ---------------------------------------------------------------- Plain-English search
  var KINDS = [
    { re: /\b(?:screenshots?|screen ?shots?)\b/, label: "Screenshots", kinds: ["shot"] },
    { re: /\b(?:screen recordings?|videos?|movies?|clips?|recordings?)\b/, label: "Videos", kinds: ["video"] },
    { re: /\bpdfs?\b/, label: "PDFs", kinds: ["pdf"] },
    { re: /\b(?:photos?|pictures?|pics?)\b/, label: "Photos", kinds: ["photo", "image"] },
    { re: /\bimages?\b/, label: "Images", kinds: ["photo", "image", "shot"] },
    { re: /\b(?:music|audio|songs?|podcasts?)\b/, label: "Audio", kinds: ["audio"] },
    { re: /\b(?:spreadsheets?|excel|sheets?)\b/, label: "Spreadsheets", kinds: ["sheet"] },
    { re: /\b(?:presentations?|decks?|slides?|keynotes?)\b/, label: "Presentations", kinds: ["deck"] },
    { re: /\b(?:documents?|docs?)\b/, label: "Documents", kinds: ["pdf", "doc", "sheet", "deck"] },
    { re: /\b(?:zips?|archives?)\b/, label: "Archives", kinds: ["zip"] },
    { re: /\b(?:installers?|dmgs?|disk images?)\b/, label: "Installers", kinds: ["dmg"] },
  ];
  var UNIT_DAYS = { day: 1, week: 7, month: 30, year: 365 };
  var DATES = [
    { re: /\b(?:older than|over|more than) (?:a|one|1) years?(?: old)?\b/, label: function () { return "Older than a year"; }, test: function () { return function (d) { return d >= 365; }; } },
    { re: /\bolder than (\d+) (day|week|month|year)s?\b/, label: function (m) { return "Older than " + m[1] + " " + m[2] + (m[1] === "1" ? "" : "s"); }, test: function (m) { var n = +m[1] * UNIT_DAYS[m[2]]; return function (d) { return d >= n; }; } },
    { re: /\b(?:in the )?(?:last|past) (\d+) (day|week|month)s?\b/, label: function (m) { return "Last " + m[1] + " " + m[2] + (m[1] === "1" ? "" : "s"); }, test: function (m) { var n = +m[1] * UNIT_DAYS[m[2]]; return function (d) { return d < n; }; } },
    { re: /\btoday\b/, label: function () { return "Today"; }, test: function () { return function (d) { return d < 1; }; } },
    { re: /\byesterday\b/, label: function () { return "Yesterday"; }, test: function () { return function (d) { return d >= 1 && d < 2; }; } },
    { re: /\b(?:this week|recent|recently|new)\b/, label: function () { return "This week"; }, test: function () { return function (d) { return d < 7; }; } },
    { re: /\blast week\b/, label: function () { return "Last week"; }, test: function () { return function (d) { return d >= 7 && d < 14; }; } },
    { re: /\bthis month\b/, label: function () { return "This month"; }, test: function () { return function (d) { return d < 30; }; } },
    { re: /\blast month\b/, label: function () { return "Last month"; }, test: function () { return function (d) { return d >= 30 && d < 60; }; } },
    { re: /\bthis year\b/, label: function () { return "This year"; }, test: function () { return function (d) { return d < 365; }; } },
    { re: /\blast year\b/, label: function () { return "Last year"; }, test: function () { return function (d) { return d >= 365 && d < 730; }; } },
    { re: /\bold\b/, label: function () { return "Older than 6 months"; }, test: function () { return function (d) { return d >= 180; }; } },
  ];
  var MB = { kb: 0.001, mb: 1, gb: 1000 };
  var SIZES = [
    { re: /\b(?:over|bigger than|larger than|more than|above|at least) ?(\d+(?:\.\d+)?) ?(kb|mb|gb)\b/, label: function (m) { return "Over " + m[1] + " " + m[2].toUpperCase(); }, test: function (m) { var n = +m[1] * MB[m[2]]; return function (mb) { return mb > n; }; } },
    { re: /\b(?:under|smaller than|less than|below|at most) ?(\d+(?:\.\d+)?) ?(kb|mb|gb)\b/, label: function (m) { return "Under " + m[1] + " " + m[2].toUpperCase(); }, test: function (m) { var n = +m[1] * MB[m[2]]; return function (mb) { return mb < n; }; } },
    { re: /\b(?:big|large|huge|largest|biggest)\b/, label: function () { return "Over 100 MB"; }, test: function () { return function (mb) { return mb >= 100; }; } },
    { re: /\b(?:small|tiny)\b/, label: function () { return "Under 1 MB"; }, test: function () { return function (mb) { return mb < 1; }; } },
  ];
  var SOURCE_NAMES = { gmail: "Gmail", whatsapp: "WhatsApp", slack: "Slack", zoom: "Zoom", airdrop: "AirDrop", "google drive": "Google Drive", drive: "Google Drive", chatgpt: "ChatGPT", figma: "Figma", outlook: "Outlook", mail: "Mail", telegram: "Telegram" };
  var SOURCE_RE = /\b(?:(?:from|via|on|in) )?(gmail|whatsapp|slack|zoom|airdrop|google drive|drive|chatgpt|figma|outlook|mail|telegram)\b/;
  var FOLDER_RE = /\b(?:in|on) (?:my |the )?(downloads|desktop|documents|pictures|movies|music)\b/;
  var STOP = "a an and the my me of in on at to for from with that which show find all any files file stuff things i got sent some about named called containing contains where".split(" ");

  function parse(raw) {
    var q = " " + raw.toLowerCase().replace(/[“”"]/g, " ").replace(/\s+/g, " ").trim() + " ";
    var parts = [];
    var take = function (re, make) {
      var m = q.match(re);
      if (!m) return null;
      q = q.slice(0, m.index) + " ".repeat(m[0].length) + q.slice(m.index + m[0].length);
      var part = make(m);
      part.raw = m[0].trim();
      parts.push(part);
      return part;
    };
    take(FOLDER_RE, function (m) { var dir = m[1][0].toUpperCase() + m[1].slice(1); return { type: "folder", label: "In " + dir, test: function (f) { return f.dir === dir; } }; });
    SIZES.forEach(function (s) { take(s.re, function (m) { var t = s.test(m); return { type: "size", label: s.label(m), test: function (f) { return t(f.mb); } }; }); });
    DATES.forEach(function (s) { take(s.re, function (m) { var t = s.test(m); return { type: "date", label: s.label(m), test: function (f) { return t(f.d); } }; }); });
    take(SOURCE_RE, function (m) { var name = SOURCE_NAMES[m[1]]; return { type: "from", label: "From " + name, test: function (f) { return f.src === name; } }; });
    var kindPart = null;
    KINDS.some(function (k) {
      kindPart = take(k.re, function () { return { type: "kind", label: k.label, test: function (f) { return k.kinds.indexOf(f.k) >= 0; } }; });
      return !!kindPart;
    });
    var words = q.split(/\s+/).filter(function (w) { return w && STOP.indexOf(w) < 0 && w.replace(/[^a-z0-9]/g, "").length > 1; });
    words.forEach(function (w) {
      var norm = w.replace(/[^a-z0-9]/g, "");
      parts.push({ type: "text", label: "“" + w + "”", raw: w, term: norm, test: function (f) { return hay(f).indexOf(norm) >= 0; } });
    });
    // Show the parts in the order they were typed.
    var lower = raw.toLowerCase();
    parts.sort(function (a, b) { return lower.indexOf(a.raw) - lower.indexOf(b.raw); });
    return parts;
  }
  function norm(s) { return String(s || "").toLowerCase().replace(/[^a-z0-9]/g, ""); }
  function hay(f) {
    if (!f._hay) f._hay = norm(f.n) + "|" + norm(f.text) + "|" + norm(f.said) + "|" + norm(f.src);
    return f._hay;
  }
  function termRegex(term) {
    var chars = term.split("").map(function (c) { return c.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); });
    return new RegExp(chars.join("[^a-z0-9]?"), "i");
  }
  function snippet(text, terms) {
    var first = -1, len = 0;
    terms.forEach(function (t) {
      var m = text.match(termRegex(t));
      if (m && (first < 0 || m.index < first)) { first = m.index; len = m[0].length; }
    });
    if (first < 0) return null;
    var start = Math.max(0, first - 22);
    var out = (start > 0 ? "…" : "") + text.slice(start);
    var html = esc(out);
    terms.forEach(function (t) {
      html = html.replace(new RegExp(termRegex(t).source, "ig"), function (s) { return "<mark>" + s + "</mark>"; });
    });
    return html;
  }
  function search(raw) {
    var parts = parse(raw);
    var list = FILES.filter(function (f) { return parts.every(function (p) { return p.test(f); }); });
    list.sort(function (a, b) { return a.d - b.d; });
    return { parts: parts, list: list };
  }


  // The meeting that the Transcribe demo listens to.
  var CUES = [
    ["00:04:01,200", "Morning, everyone. Let's start with the launch."],
    ["00:04:06,800", "Beta invites go out on Monday."],
    ["00:04:12,400", "We need to move the budget review to Thursday."],
    ["00:04:17,900", "Priya will send the final pricing by Friday."],
    ["00:04:23,300", "And the onboarding video is ready for review."],
    ["00:04:28,600", "Great. Same time next week."],
  ];

  // ---------------------------------------------------------------- Tool windows
  function shell(title, path, body) {
    return '<div class="mac"><div class="mac-main"><div class="mac-bar"><div class="lights" aria-hidden="true"><i></i><i></i><i></i></div><span class="mac-title">' + title + '</span></div><div class="mac-body"><div class="ctx" aria-label="Chosen from the right-click menu">' +
      path.map(function (p, i) { return (i ? "<i>›</i>" : "") + "<span>" + esc(p) + "</span>"; }).join("") + "</div>" + body + "</div></div></div>";
  }
  function made(name, detail) {
    if (onMade) { var cb = onMade; setTimeout(function () { cb(name); }, 0); }
    return '<div class="made"><span class="fi"><svg aria-hidden="true"><use href="#i-check"/></svg></span><span><b>' + esc(name) + "</b><small>" + esc(detail) + "</small></span></div>";
  }
  function progress(bar, ms) {
    return new Promise(function (resolve) {
      var start = performance.now();
      var step = function (t) {
        var p = Math.min(1, (t - start) / ms);
        bar.style.width = Math.round(p * 100) + "%";
        if (p < 1) requestAnimationFrame(step); else resolve();
      };
      requestAnimationFrame(step);
    });
  }

  var TOOLS = {
    sign: function (stage) {
      var today = now.toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" });
      stage.innerHTML = shell("Sign “Lease agreement.pdf”", ["Lease agreement.pdf", "Tools", "Sign PDF…"],
        '<div class="sign-wrap"><div class="paper"><h5>Residential Lease Agreement</h5><p>This agreement is made between the Landlord and the Tenant for the home at 14 Alder Street, Unit 3.</p><p>The lease begins on November 1, 2026 and runs for twelve months. Rent is due on the first day of each month.</p><p>The Tenant has read and accepts the terms above.</p>' +
        '<div class="sigline"><span class="sigslot" id="sigslot"></span><span>Tenant signature</span><span>' + today + "</span></div></div>" +
        '<div class="pad"><canvas id="sigpad" aria-label="Signature pad. Draw with your mouse, trackpad or finger."></canvas><span class="hint">Draw your signature here, or use a sample.</span><div class="tool-row"><button class="wbtn ghost" type="button" id="sig-sample">Use a sample</button><button class="wbtn ghost" type="button" id="sig-clear">Clear</button><button class="wbtn" type="button" id="sig-place" disabled>Place signature</button></div></div></div><div id="sig-made" aria-live="polite"></div>');
      var canvas = $("sigpad"), ctx = canvas.getContext("2d"), dpr = Math.min(2, window.devicePixelRatio || 1);
      var w = canvas.clientWidth, h = canvas.clientHeight;
      canvas.width = w * dpr; canvas.height = h * dpr;
      ctx.scale(dpr, dpr);
      ctx.lineCap = "round"; ctx.lineJoin = "round"; ctx.lineWidth = 2.4; ctx.strokeStyle = "#1f3a93";
      var drawn = false, drawing = false, last = null, mid = null, animating = 0;
      var placeBtn = $("sig-place");
      var mark = function () { drawn = true; placeBtn.disabled = false; };
      var pt = function (e) { var r = canvas.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
      canvas.addEventListener("pointerdown", function (e) { animating++; drawing = true; last = pt(e); mid = last; canvas.setPointerCapture(e.pointerId); });
      canvas.addEventListener("pointermove", function (e) {
        if (!drawing) return;
        var p = pt(e), m = [(last[0] + p[0]) / 2, (last[1] + p[1]) / 2];
        ctx.beginPath(); ctx.moveTo(mid[0], mid[1]); ctx.quadraticCurveTo(last[0], last[1], m[0], m[1]); ctx.stroke();
        last = p; mid = m; mark();
      });
      var end = function () { drawing = false; };
      canvas.addEventListener("pointerup", end);
      canvas.addEventListener("pointercancel", end);
      var clear = function () { animating++; ctx.clearRect(0, 0, w, h); drawn = false; placeBtn.disabled = true; };
      $("sig-clear").addEventListener("click", clear);
      $("sig-sample").addEventListener("click", async function () {
        clear();
        var my = animating;
        var strokes = sampleSignature(w, h);
        for (var s = 0; s < strokes.length; s++) {
          var pts = strokes[s];
          for (var i = 1; i < pts.length; i++) {
            if (my !== animating) return;
            ctx.beginPath(); ctx.moveTo(pts[i - 1][0], pts[i - 1][1]); ctx.lineTo(pts[i][0], pts[i][1]); ctx.stroke();
            if (!reduce && i % 6 === 0) await wait(8);
          }
        }
        mark();
      });
      placeBtn.addEventListener("click", function () {
        if (!drawn) return;
        $("sigslot").innerHTML = '<img alt="Your signature" src="' + trimCanvas(canvas) + '">';
        $("sig-made").innerHTML = made("Lease agreement (signed).pdf", "Saved next to the original · 1 page");
      });
    },

    cutout: function (stage) {
      stage.innerHTML = shell("Remove Background", ["Product shot.heic", "Tools", "Remove Background"],
        '<div class="ba" id="ba" style="--cut:46%"><svg class="before" viewBox="0 0 400 300" aria-hidden="true">' + SCENE + '<use href="#plant"/></svg><svg class="after" viewBox="0 0 400 300" aria-hidden="true"><rect width="400" height="300" fill="url(#checker)"/><use href="#plant"/></svg>' +
        '<span class="tag l">Original</span><span class="tag r">Cut out</span><div class="handle"><button class="knob" type="button" role="slider" aria-label="Compare original and cut out" aria-valuemin="0" aria-valuemax="100" aria-valuenow="46"><svg><use href="#i-lr"/></svg></button></div></div>' +
        '<div class="tool-row" style="justify-content:space-between">' + made("Product shot (cut out).png", "Transparent background · made in under a second") + '<span class="mac-sub">Drag the handle to compare.</span></div>');
      var ba = $("ba"), knob = ba.querySelector(".knob");
      var set = function (v) {
        v = Math.max(0, Math.min(100, v));
        ba.style.setProperty("--cut", v + "%");
        knob.setAttribute("aria-valuenow", String(Math.round(v)));
      };
      var dragging = false;
      var move = function (e) { var r = ba.getBoundingClientRect(); set(((e.clientX - r.left) / r.width) * 100); };
      ba.addEventListener("pointerdown", function (e) { dragging = true; ba.setPointerCapture(e.pointerId); move(e); });
      ba.addEventListener("pointermove", function (e) { if (dragging) move(e); });
      ba.addEventListener("pointerup", function () { dragging = false; });
      ba.addEventListener("pointercancel", function () { dragging = false; });
      knob.addEventListener("keydown", function (e) {
        var v = +knob.getAttribute("aria-valuenow");
        if (e.key === "ArrowLeft") { set(v - 5); e.preventDefault(); }
        if (e.key === "ArrowRight") { set(v + 5); e.preventDefault(); }
      });
      if (!reduce) {
        // A short sweep so it's obvious the picture can be compared.
        var t0 = performance.now();
        var sweep = function (t) {
          var p = Math.min(1, (t - t0) / 1400);
          set(46 + Math.sin(p * Math.PI * 2) * 22 * (1 - p));
          if (p < 1 && !dragging) requestAnimationFrame(sweep);
        };
        requestAnimationFrame(sweep);
      }
    },

    compress: function (stage) {
      var sizes = { "1080p": 171, "720p": 74, "540p": 43 };
      var pick = "720p";
      stage.innerHTML = shell("Compress Video", ["Team call.mov", "Tools", "Compress Video", "Smaller (720p)"],
        '<div class="vid-row"><div class="th th-video" style="--ph:' + PH.call + '"><span class="play"></span><span class="dur">32:14</span></div><div><b>Team call.mov</b><div class="mac-sub">412 MB · 1920 × 1080 · 32 minutes</div></div></div>' +
        '<div class="optrow" role="radiogroup" aria-label="Size" id="cmp-opts"><button class="opt" type="button" data-v="1080p" aria-pressed="false">High Quality (1080p)</button><button class="opt" type="button" data-v="720p" aria-pressed="true">Smaller (720p)</button><button class="opt" type="button" data-v="540p" aria-pressed="false">Smallest (540p)</button></div>' +
        '<div class="sizes"><div class="sizebar"><span>Before</span><span class="track"><span class="fill" style="width:100%;display:block"></span></span><span>412 MB</span></div><div class="sizebar new"><span>After</span><span class="track"><span class="fill" id="cmp-fill" style="width:0;display:block"></span></span><span id="cmp-after">–</span></div></div>' +
        '<div class="tool-row"><button class="wbtn" type="button" id="cmp-go">Compress</button><div class="bar" style="flex:1;min-width:120px" hidden id="cmp-bar"><i></i></div></div><div id="cmp-out" aria-live="polite"></div>');
      var opts = $("cmp-opts"), go = $("cmp-go");
      opts.addEventListener("click", function (e) {
        var b = e.target.closest(".opt"); if (!b) return;
        pick = b.getAttribute("data-v");
        opts.querySelectorAll(".opt").forEach(function (o) { o.setAttribute("aria-pressed", String(o === b)); });
        stage.querySelector(".ctx span:last-child").textContent = b.textContent;
        $("cmp-fill").style.width = "0"; $("cmp-after").textContent = "–"; $("cmp-out").innerHTML = "";
      });
      go.addEventListener("click", async function () {
        go.disabled = true;
        var bar = $("cmp-bar"); bar.hidden = false;
        await progress(bar.firstElementChild, reduce ? 10 : 1500);
        bar.hidden = true; go.disabled = false;
        var after = sizes[pick];
        $("cmp-fill").style.width = (after / 412 * 100).toFixed(1) + "%";
        $("cmp-after").textContent = after + " MB";
        var pct = Math.round((1 - after / 412) * 100);
        $("cmp-out").innerHTML = '<div class="tool-row" style="justify-content:space-between"><div><div class="saved">' + pct + '% smaller</div><div class="mac-sub">' + (412 - after) + " MB saved · example video</div></div>" + made("Team call (" + pick + ").mp4", after + " MB · next to the original") + "</div>";
      });
    },

    transcribe: function (stage) {
      stage.innerHTML = shell("Transcribe “Team call.mov”", ["Team call.mov", "Tools", "Transcribe…"],
        '<div class="vid-row"><div class="th th-video" style="--ph:' + PH.call + '"><span class="play"></span><span class="dur">32:14</span></div><div><b>Team call.mov</b><div class="mac-sub">Whisper large-v3 turbo · runs on your Mac</div></div></div>' +
        '<div class="optrow"><span class="opt static">Language: Detect automatically</span><span class="opt static on">✓ Text (.txt)</span><span class="opt static on">✓ Subtitles (.srt)</span></div>' +
        '<div class="tool-row"><button class="wbtn" type="button" id="tr-go">Transcribe</button><div class="bar" style="flex:1;min-width:120px" hidden id="tr-bar"><i></i></div></div>' +
        '<div class="tr-out" id="tr-out"><div class="wait">Press Transcribe to see the words appear, with their times.</div></div><div class="tool-row" id="tr-made" aria-live="polite"></div>');
      var go = $("tr-go");
      go.addEventListener("click", async function () {
        go.disabled = true;
        var out = $("tr-out"), bar = $("tr-bar");
        out.innerHTML = ""; $("tr-made").innerHTML = ""; bar.hidden = false;
        for (var i = 0; i < CUES.length; i++) {
          bar.firstElementChild.style.width = Math.round(((i + 1) / CUES.length) * 100) + "%";
          out.insertAdjacentHTML("beforeend", '<div class="cue"><time>' + CUES[i][0] + "</time><span>" + esc(CUES[i][1]) + "</span></div>");
          out.scrollTop = out.scrollHeight;
          await wait(reduce ? 0 : 420);
        }
        bar.hidden = true; go.disabled = false;
        $("tr-made").innerHTML = made("Team call.txt", "Plain text, next to the video") + made("Team call.srt", "Subtitles for any player");
      });
    },

    merge: function (stage) {
      var docs = [["Brief.pdf", 4], ["Budget.pdf", 3], ["Contract.pdf", 7]];
      stage.innerHTML = shell("Merge PDFs", ["3 PDFs", "Tools", "Merge PDFs…"],
        '<p class="mac-sub" style="margin:0">Put them in order with the arrows, then merge.</p><div class="docs" id="docs"></div><div class="tool-row"><button class="wbtn" type="button" id="mg-go">Merge 3 PDFs</button><button class="wbtn ghost" type="button" id="mg-again" hidden>Start over</button></div><div id="mg-out" aria-live="polite"></div>');
      var box = $("docs");
      var pages = function (n) { var s = ""; for (var i = 0; i < Math.min(n, 3); i++) s += '<div class="page"><b></b><i></i><i></i><i></i><i></i><i></i></div>'; return s; };
      function draw() {
        box.classList.remove("merging");
        box.innerHTML = docs.map(function (d, i) {
          return '<div class="doc"><span class="order">' + (i + 1) + '</span><div class="pg">' + pages(d[1]) + "</div><b>" + esc(d[0]) + "</b><small>" + d[1] + ' pages</small><span class="tool-row" style="gap:4px"><button class="wbtn ghost" type="button" style="height:24px;padding:0 8px" aria-label="Move ' + esc(d[0]) + ' earlier" data-mv="' + i + ':-1"' + (i === 0 ? " disabled" : "") + '>‹</button><button class="wbtn ghost" type="button" style="height:24px;padding:0 8px" aria-label="Move ' + esc(d[0]) + ' later" data-mv="' + i + ':1"' + (i === docs.length - 1 ? " disabled" : "") + ">›</button></span></div>";
        }).join("");
      }
      box.addEventListener("click", function (e) {
        var b = e.target.closest("[data-mv]"); if (!b) return;
        var parts = b.getAttribute("data-mv").split(":"), i = +parts[0], j = i + +parts[1];
        var t = docs[i]; docs[i] = docs[j]; docs[j] = t;
        draw();
      });
      draw();
      $("mg-go").addEventListener("click", async function () {
        var total = docs.reduce(function (s, d) { return s + d[1]; }, 0);
        box.classList.add("merging");
        await wait(reduce ? 0 : 420);
        var name = docs[0][0].replace(/\.pdf$/, "") + " (merged).pdf";
        box.classList.remove("merging");
        box.innerHTML = '<div class="merged"><div class="doc" style="cursor:default"><div class="pg">' + pages(3) + "</div></div>" + made(name, total + " pages, in the order you chose") + "</div>";
        $("mg-go").hidden = true; $("mg-again").hidden = false;
      });
      $("mg-again").addEventListener("click", function () { $("mg-go").hidden = false; $("mg-again").hidden = true; draw(); });
    },

    clean: function (stage) {
      var rows = [["Location", "38.7139° N, 9.1394° W (Lisbon)"], ["Camera", "Apple iPhone 16 Pro"], ["Lens", "24 mm ƒ/1.78"], ["Taken", "Saturday, 18:42"], ["Software", "iOS 26.0"], ["Orientation", "Portrait"]];
      stage.innerHTML = shell("Remove Private Details", ["IMG_4021.HEIC", "Tools", "Remove Private Details"],
        '<div class="meta-card"><div class="th th-photo" style="--ph:' + PH.sunset + '"></div><div><table class="meta"><tbody id="meta-rows">' +
        rows.map(function (r) { return "<tr><th>" + r[0] + "</th><td>" + r[1] + "</td></tr>"; }).join("") +
        '</tbody></table><div class="tool-row" style="margin-top:14px"><button class="wbtn" type="button" id="pd-go">Remove details</button><span class="mac-sub">Anyone you send the photo to can read these.</span></div></div></div><div id="pd-out" aria-live="polite"></div>');
      $("pd-go").addEventListener("click", async function () {
        var trs = $("meta-rows").querySelectorAll("tr");
        $("pd-go").disabled = true;
        for (var i = 0; i < trs.length; i++) {
          trs[i].classList.add(i === trs.length - 1 ? "kept" : "gone");
          await wait(reduce ? 0 : 140);
        }
        $("pd-out").innerHTML = made("IMG_4021 (clean).HEIC", "Same picture, nothing re-compressed · the photo stays upright");
      });
    },
  };

  // A signature made of loops, drawn as if by hand.
  function sampleSignature(w, h) {
    var cap = [], word = [], line = [], t;
    // A tall capital with a curl at the bottom.
    for (t = 0; t <= 1; t += 0.01) {
      var a = t * Math.PI * 1.6;
      cap.push([w * (0.1 + 0.05 * Math.sin(a) + 0.07 * t), h * (0.5 - 0.38 * Math.sin(t * Math.PI) + 0.22 * t * t)]);
    }
    // Joined lowercase letters: loops of uneven size and spacing.
    for (t = 0; t <= 1; t += 0.0025) {
      var ang = 2 * Math.PI * (5.2 * t + 0.25 * Math.sin(t * 7));
      var amp = h * (0.13 + 0.07 * Math.sin(t * 5.3) + 0.04 * Math.sin(t * 13.1)) * (t > 0.55 && t < 0.63 ? 1.9 : 1);
      word.push([w * (0.2 + 0.6 * t) - w * 0.022 * Math.cos(ang), h * 0.6 - amp * Math.sin(ang) * (Math.sin(ang) < 0 && t > 0.55 && t < 0.63 ? -0.9 : 1)]);
    }
    // A quick underline.
    for (t = 0; t <= 1; t += 0.01) line.push([w * (0.3 + 0.58 * t), h * (0.84 - 0.1 * t * t) + 2 * Math.sin(t * 6)]);
    return [cap, word, line];
  }
  function trimCanvas(canvas) {
    var ctx = canvas.getContext("2d"), W = canvas.width, H = canvas.height;
    var data = ctx.getImageData(0, 0, W, H).data, x0 = W, y0 = H, x1 = 0, y1 = 0;
    for (var y = 0; y < H; y += 2) for (var x = 0; x < W; x += 2) {
      if (data[(y * W + x) * 4 + 3] > 10) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    }
    if (x1 <= x0 || y1 <= y0) return canvas.toDataURL();
    var out = document.createElement("canvas"), padPx = 6;
    out.width = x1 - x0 + padPx * 2; out.height = y1 - y0 + padPx * 2;
    out.getContext("2d").drawImage(canvas, x0 - padPx, y0 - padPx, out.width, out.height, 0, 0, out.width, out.height);
    return out.toDataURL("image/png");
  }

  // The photo behind the plant, for Remove Background.
  var SCENE =
    '<defs>' +
    '<linearGradient id="wall" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ecdfcf"/><stop offset="1" stop-color="#d6c2aa"/></linearGradient>' +
    '<linearGradient id="table" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b98458"/><stop offset="1" stop-color="#7d5133"/></linearGradient>' +
    '<radialGradient id="light" cx="0.18" cy="0.2" r="0.6"><stop offset="0" stop-color="#fffaf0" stop-opacity="0.95"/><stop offset="1" stop-color="#fffaf0" stop-opacity="0"/></radialGradient>' +
    '<linearGradient id="pot" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#9c4526"/><stop offset="0.35" stop-color="#d7774c"/><stop offset="0.6" stop-color="#c2603a"/><stop offset="1" stop-color="#7f361d"/></linearGradient>' +
    '<linearGradient id="rim" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#a94e2c"/><stop offset="0.4" stop-color="#e38a5f"/><stop offset="1" stop-color="#8a3d21"/></linearGradient>' +
    '<linearGradient id="leaf" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#1f5a33"/><stop offset="0.5" stop-color="#3f8c4f"/><stop offset="1" stop-color="#245f37"/></linearGradient>' +
    '<linearGradient id="leaf2" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#2b6d3d"/><stop offset="0.5" stop-color="#5aa864"/><stop offset="1" stop-color="#2b6d3d"/></linearGradient>' +
    '<pattern id="checker" width="20" height="20" patternUnits="userSpaceOnUse"><rect width="20" height="20" fill="#ffffff"/><rect width="10" height="10" fill="#e6e6ea"/><rect x="10" y="10" width="10" height="10" fill="#e6e6ea"/></pattern>' +
    '<filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="5"/></filter>' +
    '<filter id="softer" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="2.4"/></filter>' +
    '<g id="plant">' +
    '<path d="M171 214 C 162 160 160 98 178 46 C 188 98 190 158 189 214 Z" fill="url(#leaf)" stroke="#c9c46a" stroke-width="2"/>' +
    '<path d="M194 214 C 190 150 192 84 207 26 C 216 86 216 150 210 214 Z" fill="url(#leaf2)" stroke="#d2cc72" stroke-width="2"/>' +
    '<path d="M206 214 C 212 160 224 110 246 66 C 244 120 234 168 224 214 Z" fill="url(#leaf)" stroke="#c9c46a" stroke-width="2"/>' +
    '<path d="M180 214 C 168 176 152 140 128 106 C 150 128 172 160 194 214 Z" fill="url(#leaf2)" stroke="#d2cc72" stroke-width="2"/>' +
    '<path d="M214 214 C 228 180 248 150 274 124 C 258 156 242 186 230 214 Z" fill="url(#leaf2)" stroke="#d2cc72" stroke-width="2"/>' +
    '<path d="M186 214 C 184 172 186 128 196 92 C 204 130 204 172 202 214 Z" fill="url(#leaf)" stroke="#c9c46a" stroke-width="1.6"/>' +
    '<path d="M150 214 L 250 214 L 240 280 Q 238 288 228 288 L 172 288 Q 162 288 160 280 Z" fill="url(#pot)"/>' +
    '<rect x="144" y="204" width="112" height="16" rx="3" fill="url(#rim)"/>' +
    '<path d="M150 220 L 250 220 L 249 226 L 151 226 Z" fill="#000" opacity="0.12"/>' +
    "</g>" +
    "</defs>" +
    '<rect width="400" height="300" fill="url(#wall)"/>' +
    '<rect width="400" height="300" fill="url(#light)"/>' +
    '<g filter="url(#soft)" opacity="0.85"><rect x="292" y="40" width="74" height="96" rx="3" fill="#8d7c6a"/><rect x="299" y="47" width="60" height="82" fill="#c9b49b"/><circle cx="330" cy="82" r="16" fill="#e7a86a"/><rect x="34" y="120" width="10" height="110" fill="#5b4a3d"/><path d="M14 120 h50 l-10 -34 h-30 z" fill="#f3e7d4"/></g>' +
    '<rect y="268" width="400" height="32" fill="url(#table)"/>' +
    '<rect y="266" width="400" height="4" fill="#caa078" opacity="0.7"/>' +
    '<g filter="url(#soft)"><rect x="310" y="236" width="56" height="34" rx="3" fill="#6f8aa6"/><rect x="314" y="226" width="48" height="12" rx="2" fill="#a96f5b"/></g>' +
    '<ellipse cx="200" cy="288" rx="66" ry="6" fill="#3a2414" opacity="0.45" filter="url(#softer)"/>';


  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
  function ease(t) { return 1 - Math.pow(1 - t, 3); }
  function rng(seed) {
    return function () {
      seed = (seed + 0x6d2b79f5) | 0;
      var t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  function onView(el, fn, threshold) {
    if (!el) return;
    if (!("IntersectionObserver" in window)) { fn(); return; }
    var io = new IntersectionObserver(function (es) {
      if (es[0].isIntersecting) { io.disconnect(); fn(); }
    }, { threshold: threshold || 0.35 });
    io.observe(el);
  }
  function whereFound(f, terms) {
    if (!terms.length) return "";
    var inName = terms.every(function (t) { return norm(f.n).indexOf(t) >= 0; });
    if (inName) return "";
    if (f.said && terms.some(function (t) { return norm(f.said).indexOf(t) >= 0; })) return "Said at " + f.saidAt + ": " + snippet(f.said, terms);
    if (f.text) {
      var sn = snippet(f.text, terms);
      if (sn) return (f.k === "photo" || f.k === "shot" || f.k === "image" ? "In the picture: " : "Inside: ") + sn;
    }
    return "";
  }

  // ---------------------------------------------------------------- Hero: a pile of files, searched
  function pile() {
    var stage = $("pile-stage"), input = $("pile-q"), readas = $("pile-readas"), count = $("pile-count");
    if (!stage) return;
    var hero = stage.closest(".hero");
    var tryBtns = Array.prototype.slice.call(document.querySelectorAll("#pile-try button"));
    var R = rng(11);
    var order = FILES.map(function (f, i) { return i; });
    for (var i = order.length - 1; i > 0; i--) { var j = Math.floor(R() * (i + 1)); var t = order[i]; order[i] = order[j]; order[j] = t; }
    var cards = order.map(function (fi) {
      var f = FILES[fi], el = document.createElement("div");
      el.className = "pf";
      el.innerHTML = '<div class="pf-in">' + thumb(f, true) + '<div class="lbl">' + esc(f.n) + '</div><div class="snip"></div></div>';
      stage.appendChild(el);
      return { f: f, el: el, snip: el.querySelector(".snip"), rot: (R() - 0.5) * 30, sc: 0.84 + R() * 0.28, d: 3 + R() * 14, jx: R(), jy: R() };
    });

    var W = 0, H = 0, cw = 100, home = [], hits = null, terms = [];
    function layout() {
      W = stage.clientWidth; H = stage.clientHeight;
      cw = W > 1000 ? 104 : W > 700 ? 88 : 64;
      var ch = cw * 0.75 + 34, n = cards.length;
      var cols = Math.max(4, Math.round(Math.sqrt((n * W) / H)));
      var rows = Math.ceil(n / cols), cellW = W / cols, cellH = (H - 60) / rows;
      home = cards.map(function (c, k) {
        var col = k % cols, row = Math.floor(k / cols);
        var x = col * cellW + (cellW - cw) * c.jx + (c.jy - 0.5) * cellW * 0.55;
        var y = row * cellH + Math.max(0, cellH - ch) * c.jy + (c.jx - 0.5) * cellH * 0.45;
        return { x: clamp(x, -cw * 0.1, W - cw * 0.9), y: clamp(y, 0, H - ch - 30), r: c.rot, s: c.sc };
      });
      cards.forEach(function (c) { c.el.style.setProperty("--w", cw + "px"); c.el.style.setProperty("--d", c.d.toFixed(1)); });
    }
    function slots(n) {
      var big = W < 560 ? 1.22 : W < 900 ? 1.35 : 1.5, perRow = W < 560 ? 3 : 6;
      var w = cw * big, gap = W < 560 ? 10 : 30, rowsN = Math.ceil(n / perRow), out = [];
      for (var i = 0; i < n; i++) {
        var row = Math.floor(i / perRow), inRow = Math.min(perRow, n - row * perRow), col = i % perRow;
        var totalW = inRow * w + (inRow - 1) * gap;
        out.push({ x: (W - totalW) / 2 + col * (w + gap) + (w - cw) / 2, y: H * (rowsN > 1 ? 0.1 : 0.24) + row * (cw * 0.75 + 78) * big, s: big });
      }
      return out;
    }
    function place() {
      var found = hits ? hits.slice(0, 6) : [], sl = slots(found.length);
      cards.forEach(function (c, k) {
        var h = home[k], idx = found.indexOf(c.f), x, y, r, s, z;
        if (idx >= 0) {
          x = sl[idx].x; y = sl[idx].y; r = 0; s = sl[idx].s; z = 200 + idx;
          c.el.classList.add("hit"); c.el.classList.remove("dim");
          c.el.style.transitionDelay = idx * 70 + "ms";
          c.snip.innerHTML = whereFound(c.f, terms);
        } else {
          x = h.x; y = h.y; r = h.r; s = h.s; z = Math.round(s * 60);
          if (hits) {
            var dx = x + cw / 2 - W / 2;
            x += Math.sign(dx) * Math.min(90, Math.abs(dx) * 0.2);
            y += y > H * 0.3 ? 26 : -12;
            s *= 0.86;
          }
          c.el.classList.toggle("dim", !!hits);
          c.el.classList.remove("hit");
          c.el.style.transitionDelay = "0ms";
        }
        c.el.style.zIndex = z;
        c.el.style.opacity = "";
        c.el.style.transform = "translate3d(" + x.toFixed(1) + "px," + y.toFixed(1) + "px,0) rotate(" + r.toFixed(1) + "deg) scale(" + s.toFixed(3) + ")";
      });
    }
    function run(q) {
      q = q.trim();
      tryBtns.forEach(function (b) { b.setAttribute("aria-pressed", String(b.textContent === q)); });
      if (!q) {
        hits = null; terms = []; readas.innerHTML = ""; count.textContent = FILES.length + " files";
        place();
        return;
      }
      var r = search(q);
      hits = r.list;
      terms = r.parts.filter(function (p) { return p.type === "text"; }).map(function (p) { return p.term; });
      readas.innerHTML = (r.parts.length ? "<span>Haven read this as</span>" : "") + r.parts.map(function (p, i) {
        return '<span class="chip k-' + p.type + '">' + esc(p.label) + '<button type="button" aria-label="Remove ' + esc(p.label) + '" data-i="' + i + '">×</button></span>';
      }).join("");
      readas.querySelectorAll("button").forEach(function (b) {
        b.addEventListener("click", function () {
          stopAuto();
          var p = r.parts[+b.getAttribute("data-i")], at = input.value.toLowerCase().indexOf(p.raw);
          if (at >= 0) input.value = (input.value.slice(0, at) + input.value.slice(at + p.raw.length)).replace(/\s+/g, " ").trim();
          run(input.value);
        });
      });
      count.textContent = r.list.length ? r.list.length + " of " + FILES.length : "No match";
      place();
    }

    layout();
    // The pile spills out of the middle on load.
    cards.forEach(function (c, k) {
      c.el.style.transition = "none";
      c.el.style.opacity = "0";
      c.el.style.transform = "translate3d(" + (W / 2 - cw / 2) + "px," + H * 0.3 + "px,0) rotate(" + c.rot * 2 + "deg) scale(0.5)";
    });
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        cards.forEach(function (c, k) { c.el.style.transition = ""; c.el.style.transitionDelay = (reduce ? 0 : k * 14) + "ms"; });
        place();
      });
    });

    var debounce;
    input.addEventListener("input", function () { stopAuto(); clearTimeout(debounce); debounce = setTimeout(function () { run(input.value); }, 160); });
    input.addEventListener("focus", stopAuto);
    tryBtns.forEach(function (b) { b.addEventListener("click", function () { stopAuto(); input.value = b.textContent; run(b.textContent); }); });

    var rt;
    window.addEventListener("resize", function () {
      clearTimeout(rt);
      rt = setTimeout(function () { var w = stage.clientWidth; if (Math.abs(w - W) > 8) { layout(); place(); } }, 150);
    });

    // Depth: the pile leans a little toward the pointer.
    if (!reduce && window.matchMedia("(pointer: fine)").matches) {
      hero.addEventListener("pointermove", function (e) {
        stage.style.setProperty("--px", ((e.clientX / window.innerWidth - 0.5) * 2).toFixed(3));
        stage.style.setProperty("--py", ((e.clientY / window.innerHeight - 0.5) * 2).toFixed(3));
      });
    }

    // Types the example searches one after another until someone takes over.
    var auto = !reduce, visible = true, qi = -1;
    function stopAuto() { auto = false; }
    if ("IntersectionObserver" in window) new IntersectionObserver(function (es) { visible = es[0].isIntersecting; }, { threshold: 0.3 }).observe(stage);
    async function loop() {
      await wait(1700);
      while (auto) {
        if (!visible || document.hidden) { await wait(700); continue; }
        qi = (qi + 1) % tryBtns.length;
        var text = tryBtns[qi].textContent;
        input.value = "";
        for (var i = 1; i <= text.length && auto; i++) { input.value = text.slice(0, i); await wait(34 + Math.random() * 46); }
        if (!auto) break;
        run(text);
        await wait(4600);
        if (!auto) break;
        input.value = ""; run("");
        await wait(1400);
      }
    }
    if (auto) loop(); else run("the invoice from gmail last week");
  }

  // ---------------------------------------------------------------- Story: the clock runs late as you read
  function storyClock() {
    var sec = document.querySelector(".story"), h = $("clock-h"), m = $("clock-m"), box = $("clock"), note = $("clock-note");
    if (!sec || !box) return;
    var notes = { 58: "Two minutes to go", 59: "One minute to go", 60: "Still searching", 61: "Still searching", 62: "Still searching", 63: "Late", 64: "Late", 65: "Late", 66: "Late, with the wrong version" };
    var last = -1, ticking = false;
    function update() {
      ticking = false;
      var r = sec.getBoundingClientRect();
      var p = clamp((window.innerHeight * 0.6 - r.top) / (r.height * 0.9), 0, 1);
      var mins = 58 + Math.round(p * 8);
      if (mins === last) return;
      last = mins;
      h.textContent = mins >= 60 ? "10" : "9";
      m.textContent = pad(mins % 60);
      box.classList.toggle("late", mins >= 63);
      note.textContent = notes[mins];
    }
    window.addEventListener("scroll", function () { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
    update();
  }

  // ---------------------------------------------------------------- The Recall Index: 300,000 files as dots
  function recallField() {
    var canvas = $("field");
    if (!canvas) return;
    var FW = 750, FH = 400, N = FW * FH, S = 2, W2 = FW * S;
    canvas.width = FW * S; canvas.height = FH * S;
    var ctx = canvas.getContext("2d");
    var img = ctx.createImageData(FW * S, FH * S), px = img.data;
    var kind = new Uint8Array(N), days = new Uint16Array(N), src = new Uint8Array(N), flag = new Uint8Array(N), lum = new Uint8Array(N);
    var R = rng(42), i, x, y;
    // Kinds cluster into soft regions, so the field reads like a map of a library rather than static.
    for (i = 0; i < N; i++) {
      x = i % FW; y = (i / FW) | 0;
      var n = (Math.sin(x * 0.011 + Math.sin(y * 0.021) * 1.6) + Math.sin(y * 0.017 + x * 0.006) + Math.sin((x + y) * 0.0072)) / 3;
      var v = clamp(n * 0.5 + 0.5 + (R() - 0.5) * 0.42, 0, 0.9999);
      kind[i] = Math.floor(v * 7);
      days[i] = Math.min(4000, Math.floor(-Math.log(1 - R()) * 220));
      var u = R();
      src[i] = u < 0.08 ? 1 : u < 0.22 ? 2 : u < 0.28 ? 3 : u < 0.5 ? 4 : 0;
      if ((kind[i] === 0 || kind[i] === 2 || kind[i] === 4) && R() < 0.004) flag[i] |= 1;
      if ((kind[i] === 3 || kind[i] === 5) && R() < 0.012) flag[i] |= 2;
      var sp = R();
      lum[i] = 95 + ((sp * sp * 160) | 0);
    }
    var TX = Math.floor(FW * 0.64), TY = Math.floor(FH * 0.68), T = TY * FW + TX;
    for (i = 0; i < N; i++) if (kind[i] === 0 && days[i] >= 7 && days[i] < 14 && src[i] === 1) flag[i] &= ~1;
    kind[T] = 0; days[T] = 9; src[T] = 1; flag[T] = 1; lum[T] = 255;

    var COL = [[255, 140, 178], [178, 160, 255], [135, 185, 255], [255, 196, 130], [140, 225, 210], [150, 230, 170], [210, 204, 236]];
    var TESTS = {
      kind: function (i) { return kind[i] === 0; },
      when: function (i) { return days[i] >= 7 && days[i] < 14; },
      from: function (i) { return src[i] === 1; },
      text: function (i) { return (flag[i] & 1) === 1; },
      said: function (i) { return (flag[i] & 2) === 2; },
    };
    var WORDS = { kind: "pdf", from: "from gmail", when: "last week", text: "invoice", said: "said “budget”" };
    var ORDER = ["kind", "from", "when", "text", "said"];
    var on = new Uint8Array(N).fill(1), prev = new Uint8Array(N).fill(1), active = {}, shown = N;
    var nEl = $("field-n"), labelEl = $("field-label"), qEl = $("field-q"), hit = $("field-hit");
    var cueBtns = Array.prototype.slice.call(document.querySelectorAll("#cues button"));

    function compute() {
      var keys = ORDER.filter(function (k) { return active[k]; }), total = 0;
      prev.set(on);
      for (var i = 0; i < N; i++) {
        var ok = 1;
        for (var j = 0; j < keys.length; j++) if (!TESTS[keys[j]](i)) { ok = 0; break; }
        on[i] = ok; total += ok;
      }
      return total;
    }
    // Each file is one dot with a gap around it. With no cue every dot is faint; with cues, matches brighten and
    // the rest fade almost to black, and the last few get a glow so they can be seen.
    for (i = 0; i < px.length; i += 4) px[i + 3] = 255;
    var hadCues = false, hasCues = false;
    function paint(t, total) {
      var a, b, f, c, o;
      for (var i = 0; i < N; i++) {
        a = hadCues ? (prev[i] ? 1.35 : 0.06) : 0.95;
        b = hasCues ? (on[i] ? 1.35 : 0.06) : 0.95;
        f = ((a + (b - a) * t) * lum[i]) / 255;
        c = COL[kind[i]];
        o = (((i / FW) | 0) * S * W2 + (i % FW) * S) * 4;
        px[o] = c[0] * f; px[o + 1] = c[1] * f; px[o + 2] = c[2] * f;
      }
      ctx.putImageData(img, 0, 0);
      if (hasCues && total <= 3000 && t > 0.3) {
        ctx.globalCompositeOperation = "lighter";
        var alpha = Math.min(1, (t - 0.3) / 0.7), few = total < 200;
        for (var k = 0; k < N; k++) {
          if (!on[k]) continue;
          var c2 = COL[kind[k]], cx = (k % FW) * S + 0.5, cy = ((k / FW) | 0) * S + 0.5;
          ctx.fillStyle = "rgba(" + c2[0] + "," + c2[1] + "," + c2[2] + "," + (few ? 0.35 : 0.2) * alpha + ")";
          ctx.beginPath(); ctx.arc(cx, cy, few ? 10 : 4.5, 0, 6.283); ctx.fill();
          ctx.fillStyle = "rgba(255,255,255," + 0.95 * alpha + ")";
          ctx.beginPath(); ctx.arc(cx, cy, few ? 2.4 : 1.3, 0, 6.283); ctx.fill();
        }
        ctx.globalCompositeOperation = "source-over";
      }
    }
    var animId = 0;
    function update() {
      var keys = ORDER.filter(function (k) { return active[k]; });
      hadCues = hasCues; hasCues = keys.length > 0;
      var total = compute(), from = shown, my = ++animId, start = performance.now(), dur = reduce ? 1 : 700;
      qEl.textContent = keys.length ? "Haven: “" + keys.map(function (k) { return WORDS[k]; }).join(" ") + "”" : "Every dot is a file. Turn on a cue.";
      hit.hidden = true;
      (function frame(now) {
        if (my !== animId) return;
        var t = clamp((now - start) / dur, 0, 1), e = ease(t);
        paint(e, total);
        nEl.textContent = Math.round(from + (total - from) * e).toLocaleString("en-US");
        if (t < 1) { requestAnimationFrame(frame); return; }
        shown = total;
        labelEl.textContent = total === 1 ? "file" : total === 0 ? "files. No PDF has ever said “budget”." : "files";
        if (total === 1 && on[T]) {
          hit.style.setProperty("--x", ((TX + 0.5) / FW) * 100 + "%");
          hit.style.setProperty("--y", ((TY + 0.5) / FH) * 100 + "%");
          hit.classList.toggle("left", TX > FW * 0.55);
          hit.hidden = false;
        }
      })(performance.now());
    }
    function set(key, val) {
      active[key] = val;
      cueBtns.forEach(function (b) { b.setAttribute("aria-pressed", String(!!active[b.getAttribute("data-cue")])); });
      update();
    }
    var playing = 0;
    cueBtns.forEach(function (b) {
      b.addEventListener("click", function () { playing++; var k = b.getAttribute("data-cue"); set(k, !active[k]); });
    });
    async function play() {
      var my = ++playing;
      active = {}; set("kind", false);
      var seq = ["kind", "when", "from", "text"];
      for (var s = 0; s < seq.length; s++) {
        await wait(reduce ? 0 : 1400);
        if (my !== playing) return;
        set(seq[s], true);
      }
    }
    prev.fill(1); paint(1, N);
    $("field-play").addEventListener("click", play);
    onView(canvas, play, 0.45);
  }

  // ---------------------------------------------------------------- A desktop with a right-click menu
  var onMade = null;
  function desk() {
    var deskEl = $("desk");
    if (!deskEl) return;
    var iconsEl = $("desk-icons"), menu = $("cmenu"), sub = $("cmenu-sub"), win = $("desk-win"), hint = $("desk-hint");
    PH.product = "radial-gradient(ellipse at 50% 88%, #c2603a 0 17%, transparent 17.5%), radial-gradient(ellipse at 50% 46%, #3f8c4f 0 20%, transparent 20.5%), radial-gradient(ellipse at 40% 40%, #5aa864 0 12%, transparent 12.5%), linear-gradient(180deg, #ecdfcf, #d6c2aa)";
    PH.cut = "radial-gradient(ellipse at 50% 88%, #c2603a 0 17%, transparent 17.5%), radial-gradient(ellipse at 50% 46%, #3f8c4f 0 20%, transparent 20.5%), radial-gradient(ellipse at 40% 40%, #5aa864 0 12%, transparent 12.5%), repeating-conic-gradient(#e6e6ea 0 25%, #fff 0 50%) 0 0 / 10px 10px";
    var items = [
      { id: "lease", name: "Lease agreement.pdf", f: { k: "pdf" }, tools: [["Sign PDF…", "sign"], ["Add Password…", " (locked).pdf"], ["Split PDF", " (pages)"], ["Extract Pages…", " (pages 2-3).pdf"], ["Organize Pages…", " (edited).pdf"], ["PDF to Images", " (images)"], null, ["Summarize", " (summary).txt"], ["Translate…", " (Spanish).txt"]] },
      { id: "shot", name: "Product shot.heic", f: { k: "photo", ph: "product" }, tools: [["Remove Background", "cutout"], ["Convert to PNG", ".png"], ["Resize Images", " (1600 px).heic"], ["Rotate Images", " (rotated).heic"], ["Remove Private Details", " (clean).heic"], ["Images to PDF", ".pdf"]] },
      { id: "call", name: "Team call.mov", f: { k: "video", ph: "call", dur: "32:14" }, tools: [["Compress Video", "compress"], ["Transcribe…", "transcribe"], ["Trim Video…", " (trimmed).mov"], ["Make a GIF", ".gif"], ["Extract Audio", ".m4a"], ["Mute Video", " (muted).mov"], ["Change Speed", " (2x).mov"]] },
      { id: "img", name: "IMG_4021.HEIC", f: { k: "photo", ph: "sunset" }, tools: [["Remove Private Details", "clean"], ["Remove Background", " (cut out).png"], ["Convert to JPEG", ".jpg"], ["Resize Images", " (1600 px).HEIC"], ["Rotate Images", " (rotated).HEIC"]] },
      { id: "pdfs", name: "Brief, Budget, Contract", stack: true, tools: [["Merge PDFs…", "merge"], ["Add Password…", " (locked)"], ["PDF to Images", " (images)"]] },
    ];
    var made_n = 0;
    function iconHTML(it, isNew) {
      var th = it.stack ? '<div class="th pile3"><span class="sheet"></span><span class="sheet"></span><span class="sheet">PDF</span></div>' : thumb(it.f, true);
      return '<button type="button" class="dicon' + (isNew ? " new" : "") + '" data-id="' + it.id + '" aria-haspopup="menu">' + th + '<span class="nm">' + esc(it.name) + "</span></button>";
    }
    iconsEl.innerHTML = items.map(function (it) { return iconHTML(it); }).join("");
    function find(id) { return items.filter(function (it) { return it.id === id; })[0]; }
    function select(id) { iconsEl.querySelectorAll(".dicon").forEach(function (b) { b.classList.toggle("sel", b.getAttribute("data-id") === id); }); }
    function closeMenus() { menu.hidden = true; sub.hidden = true; }
    function closeWin() { win.hidden = true; win.innerHTML = ""; onMade = null; }
    closeDeskWindow = closeWin;
    function deskPoint(clientX, clientY) { var r = deskEl.getBoundingClientRect(); return [clientX - r.left, clientY - r.top]; }

    var current = null;
    function ci(label, attrs, extra) { return '<button type="button" class="ci" role="menuitem" ' + (attrs || "") + ">" + label + (extra || "") + "</button>"; }
    function openMenu(it, x, y) {
      current = it;
      select(it.id);
      hint.classList.add("gone");
      var label = it.stack ? "3 items" : "“" + esc(it.name) + "”";
      menu.innerHTML = ci("Open", 'data-act="other"') + ci("Open With", 'data-act="other"', '<span class="ar">›</span>') + ci("Quick Look " + label, 'data-act="other"') + "<hr>" +
        ci('<svg aria-hidden="true"><use href="#i-tools"/></svg>Tools', 'data-act="tools" aria-haspopup="menu"', '<span class="ar">›</span>') +
        ci("Make Shareable", 'data-act="other"', '<span class="ar">›</span>') + "<hr>" + ci("Copy", 'data-act="other"', '<span class="kb">⌘C</span>') + ci("Share…", 'data-act="other"');
      menu.hidden = false;
      var dw = deskEl.clientWidth, dh = deskEl.clientHeight, mw = menu.offsetWidth, mh = menu.offsetHeight;
      menu.style.left = clamp(x, 8, dw - mw - 8) + "px";
      menu.style.top = clamp(y, 34, dh - mh - 8) + "px";
      sub.hidden = true;
    }
    function openSub(focusFirst) {
      if (!current) return;
      var toolsBtn = menu.querySelector('[data-act="tools"]');
      sub.innerHTML = current.tools.map(function (t, i) {
        if (!t) return "<hr>";
        var feat = TOOLS[t[1]] ? " feat" : "";
        return '<button type="button" class="ci' + feat + '" role="menuitem" data-tool="' + i + '">' + t[0] + "</button>";
      }).join("");
      sub.hidden = false;
      var dw = deskEl.clientWidth, dh = deskEl.clientHeight;
      var mx = menu.offsetLeft, mw = menu.offsetWidth, sw = sub.offsetWidth, sh = sub.offsetHeight, ty = menu.offsetTop + toolsBtn.offsetTop - 5;
      var left = mx + mw - 4;
      if (left + sw > dw - 8) left = mx - sw + 4;
      if (left < 8) { left = clamp(mx + 16, 8, dw - sw - 8); ty = menu.offsetTop + toolsBtn.offsetTop + toolsBtn.offsetHeight; }
      sub.style.left = left + "px";
      sub.style.top = clamp(ty, 34, dh - sh - 8) + "px";
      toolsBtn.classList.add("on");
      if (focusFirst) { var f = sub.querySelector(".ci"); if (f) f.focus(); }
    }
    function addIcon(name, from) {
      var ext = (name.split(".").pop() || "").toLowerCase();
      var f = ext === "pdf" ? { k: "pdf" } : ext === "png" || ext === "heic" || ext === "jpg" ? { k: "photo", ph: /cut out/.test(name) ? "cut" : from.f && from.f.ph || "sunset" } : ext === "mp4" || ext === "mov" ? { k: "video", ph: "call", dur: "32:14" } : ext === "gif" ? { k: "photo", ph: "call" } : ext === "m4a" ? { k: "audio" } : ext === "txt" || ext === "srt" ? { k: "doc" } : { k: "zip" };
      var it = { id: "n" + ++made_n, name: name, f: f, tools: from.tools, stack: false };
      items.push(it);
      iconsEl.insertAdjacentHTML("beforeend", iconHTML(it, true));
      var extra = iconsEl.querySelectorAll(".dicon");
      if (extra.length > 12) { var old = extra[5]; items = items.filter(function (x) { return x.id !== old.getAttribute("data-id"); }); old.remove(); }
    }
    function runTool(it, t) {
      closeMenus();
      win.hidden = false;
      onMade = function (name) { if (!win.hidden) addIcon(name, it); };
      if (TOOLS[t[1]]) TOOLS[t[1]](win);
      else generic(it, t);
      var lights = win.querySelector(".lights");
      if (lights) {
        lights.removeAttribute("aria-hidden");
        lights.innerHTML = '<button type="button" aria-label="Close window"></button><i></i><i></i>';
        lights.querySelector("button").addEventListener("click", closeWin);
      }
    }
    function generic(it, t) {
      var base = it.stack ? "Brief" : it.name.replace(/\.[^.]+$/, ""), out = /^\./.test(t[1]) ? base + t[1] : base + t[1];
      win.innerHTML = shell(t[0].replace("…", ""), [it.stack ? "3 PDFs" : it.name, "Tools", t[0]], '<div class="tool-row"><div class="bar" style="flex:1;min-width:140px"><i></i></div></div><div id="gen-out" aria-live="polite"></div>');
      progress(win.querySelector(".bar i"), reduce ? 10 : 900).then(function () {
        var o = $("gen-out");
        if (o) o.innerHTML = made(out, "Made next to the original. The original is untouched.");
      });
    }

    deskEl.addEventListener("contextmenu", function (e) {
      var b = e.target.closest(".dicon");
      if (!b) { e.preventDefault(); closeMenus(); return; }
      e.preventDefault();
      autoShown = false;
      var p = deskPoint(e.clientX, e.clientY);
      openMenu(find(b.getAttribute("data-id")), p[0], p[1]);
    });
    iconsEl.addEventListener("click", function (e) {
      var b = e.target.closest(".dicon");
      if (!b) return;
      autoShown = false;
      var r = b.getBoundingClientRect(), p = deskPoint(r.left + r.width * 0.3, r.top + r.height * 0.7);
      openMenu(find(b.getAttribute("data-id")), p[0], p[1]);
    });
    menu.addEventListener("click", function (e) {
      var b = e.target.closest(".ci");
      if (!b) return;
      if (b.getAttribute("data-act") === "tools") { openSub(true); return; }
      closeMenus();
      window.havenToast("Those work just like Finder. Open <b>Tools</b> to see Haven's part.");
    });
    menu.addEventListener("mouseover", function (e) {
      var b = e.target.closest(".ci");
      if (!b) return;
      if (b.getAttribute("data-act") === "tools") openSub(false);
      else { sub.hidden = true; var tb = menu.querySelector('[data-act="tools"]'); if (tb) tb.classList.remove("on"); }
    });
    menu.addEventListener("keydown", function (e) {
      var b = e.target.closest(".ci");
      if (b && b.getAttribute("data-act") === "tools" && (e.key === "ArrowRight" || e.key === "Enter")) { e.preventDefault(); openSub(true); }
    });
    sub.addEventListener("click", function (e) {
      var b = e.target.closest("[data-tool]");
      if (!b || !current) return;
      runTool(current, current.tools[+b.getAttribute("data-tool")]);
    });
    sub.addEventListener("keydown", function (e) {
      if (e.key === "ArrowLeft") { var tb = menu.querySelector('[data-act="tools"]'); sub.hidden = true; if (tb) tb.focus(); }
    });
    [menu, sub].forEach(function (m) {
      m.addEventListener("keydown", function (e) {
        if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
        e.preventDefault();
        var list = Array.prototype.slice.call(m.querySelectorAll(".ci")), at = list.indexOf(document.activeElement);
        var next = list[(at + (e.key === "ArrowDown" ? 1 : list.length - 1)) % list.length];
        if (next) next.focus();
      });
    });
    document.addEventListener("pointerdown", function (e) {
      if (!menu.hidden && !menu.contains(e.target) && !sub.contains(e.target) && !e.target.closest(".dicon")) closeMenus();
    });
    document.addEventListener("keydown", function (e) {
      if (e.key !== "Escape") return;
      if (!menu.hidden) closeMenus(); else if (!win.hidden) closeWin();
    });

    // Shows the way once: the menu opens on the lease with Tools and Sign PDF highlighted.
    var autoShown = false;
    onView(deskEl, function () {
      setTimeout(function () {
        if (!menu.hidden || !win.hidden) return;
        var b = iconsEl.querySelector(".dicon");
        var r = b.getBoundingClientRect(), p = deskPoint(r.left + r.width * 0.35, r.top + r.height * 0.75);
        openMenu(items[0], p[0], p[1]);
        openSub(false);
        var first = sub.querySelector(".ci.feat");
        if (first) first.classList.add("on");
        autoShown = true;
      }, reduce ? 0 : 900);
    }, 0.5);
  }

  // ---------------------------------------------------------------- Clean Up: a ring, a dock and a Trash
  function cleanup() {
    var groupsEl = $("cgroups");
    if (!groupsEl) return;
    var CLUTTER = 38.1, C = 2 * Math.PI * 80;
    var groups = [
      { id: "videos", n: "Big Old Videos", gb: 18.4, items: 6, c: "#df5a90", icon: "i-film", note: "Unopened for a year", on: false },
      { id: "downloads", n: "Forgotten Downloads", gb: 7.9, items: 142, c: "#3b82d6", icon: "i-download", note: "Never opened, 90+ days", on: true },
      { id: "installers", n: "Old Installers", gb: 4.6, items: 23, c: "#e39a2d", icon: "i-box", note: "The apps stay installed", on: true },
      { id: "dups", n: "Duplicates", gb: 3.2, items: 61, c: "#6a4df2", icon: "i-dup", note: "Best copy kept", on: false },
      { id: "zips", n: "Already Unzipped", gb: 2.7, items: 9, c: "#2f9e6b", icon: "i-archive", note: "Contents are next to them", on: true },
      { id: "shots", n: "Old Screenshots", gb: 1.3, items: 288, c: "#8b8898", icon: "i-shot", note: "Over 30 days old", on: false },
    ];
    var trashed = [], last = [];
    var ring = $("ring"), big = $("ring-big"), small = $("ring-small"), go = $("clean-go"), sum = $("clean-sum"), trash = $("trash"), cwin = $("cwin");
    var toast = $("ctoast"), toastMsg = $("ctoast-msg"), toastTimer;
    ring.innerHTML = '<circle cx="100" cy="100" r="80" style="stroke:var(--win-field)"/>' + groups.map(function (g) { return '<circle data-g="' + g.id + '" cx="100" cy="100" r="80"/>'; }).join("");
    function arcs(trashedNow) {
      var start = 0;
      groups.forEach(function (g) {
        var el = ring.querySelector('[data-g="' + g.id + '"]'), len = (g.gb / CLUTTER) * C, gone = trashedNow.indexOf(g.id) >= 0;
        el.style.strokeDasharray = Math.max(0, len - 3).toFixed(2) + " " + C.toFixed(2);
        el.style.strokeDashoffset = (-start).toFixed(2);
        el.style.stroke = gone ? "#16995b" : g.c;
        el.style.opacity = gone ? "1" : g.on ? "1" : "0.28";
        start += len;
      });
    }
    function draw() {
      groupsEl.innerHTML = groups.map(function (g) {
        var done = trashed.indexOf(g.id) >= 0;
        return '<button type="button" class="cg' + (done ? " done" : "") + '" style="--c:' + g.c + '" aria-pressed="' + (g.on && !done) + '" data-id="' + g.id + '"><span class="ic"><svg aria-hidden="true"><use href="#' + g.icon + '"/></svg></span><span><b>' + g.n + "</b><small>" + (done ? "In the Trash" : g.items + " items · " + g.note) + '</small></span><span class="sz">' + g.gb.toFixed(1) + ' GB</span><span class="ck"></span></button>';
      }).join("");
      var sel = groups.filter(function (g) { return g.on && trashed.indexOf(g.id) < 0; });
      var selGB = sel.reduce(function (s, g) { return s + g.gb; }, 0);
      var inTrash = groups.filter(function (g) { return trashed.indexOf(g.id) >= 0; }).reduce(function (s, g) { return s + g.gb; }, 0);
      arcs(trashed);
      if (inTrash) { big.textContent = inTrash.toFixed(1) + " GB"; small.textContent = "in the Trash, ready to empty"; }
      else { big.textContent = selGB.toFixed(1) + " GB"; small.textContent = "selected of " + CLUTTER.toFixed(1) + " GB found"; }
      go.disabled = !sel.length;
      go.textContent = sel.length ? "Move " + selGB.toFixed(1) + " GB to Trash" : "Move to Trash";
      sum.textContent = sel.length ? sel.length + (sel.length === 1 ? " group" : " groups") + " selected · you review every file first" : "Pick what to clear";
    }
    function fly(fromEl, toEl, color, delay) {
      if (!fromEl || !toEl || reduce || !Element.prototype.animate) return Promise.resolve();
      var base = cwin.getBoundingClientRect(), a = fromEl.getBoundingClientRect(), b = toEl.getBoundingClientRect();
      var x0 = a.left - base.left + a.width * (0.3 + Math.random() * 0.5), y0 = a.top - base.top + a.height / 2;
      var x1 = b.left - base.left + b.width / 2 - 7, y1 = b.top - base.top + b.height / 2 - 7;
      var mx = (x0 + x1) / 2 + (Math.random() - 0.5) * 80, my = Math.min(y0, y1) - 60 - Math.random() * 60;
      var d = document.createElement("span");
      d.className = "flyer"; d.style.setProperty("--c", color); d.style.left = "0"; d.style.top = "0";
      cwin.appendChild(d);
      var anim = d.animate([
        { transform: "translate(" + x0 + "px," + y0 + "px) scale(1)", opacity: 1 },
        { transform: "translate(" + mx + "px," + my + "px) scale(1.15) rotate(90deg)", opacity: 1, offset: 0.45 },
        { transform: "translate(" + x1 + "px," + y1 + "px) scale(0.35) rotate(200deg)", opacity: 0.4 },
      ], { duration: 760 + Math.random() * 200, delay: delay, easing: "cubic-bezier(.45,.05,.4,1)", fill: "forwards" });
      return anim.finished.then(function () { d.remove(); });
    }
    groupsEl.addEventListener("click", function (e) {
      var b = e.target.closest(".cg"); if (!b) return;
      var g = groups.filter(function (x) { return x.id === b.getAttribute("data-id"); })[0];
      g.on = !g.on; draw();
    });
    go.addEventListener("click", function () {
      var sel = groups.filter(function (g) { return g.on && trashed.indexOf(g.id) < 0; });
      if (!sel.length) return;
      var flights = [];
      sel.forEach(function (g, gi) {
        var card = groupsEl.querySelector('[data-id="' + g.id + '"]');
        for (var k = 0; k < 5; k++) flights.push(fly(card, trash, g.c, gi * 90 + k * 60));
      });
      last = sel.map(function (g) { return g.id; });
      trashed = trashed.concat(last);
      var items = sel.reduce(function (s, g) { return s + g.items; }, 0);
      Promise.all(flights).then(function () {
        trash.classList.add("full"); trash.classList.remove("bump"); void trash.offsetWidth; trash.classList.add("bump");
      });
      setTimeout(draw, reduce ? 0 : 500);
      toastMsg.textContent = "Moved " + items + " items to the Trash";
      toast.classList.add("show");
      clearTimeout(toastTimer);
      toastTimer = setTimeout(function () { toast.classList.remove("show"); }, 6500);
    });
    $("ctoast-undo").addEventListener("click", function () {
      var back = last.slice();
      trashed = trashed.filter(function (id) { return back.indexOf(id) < 0; });
      last = [];
      toast.classList.remove("show");
      draw();
      back.forEach(function (id, gi) {
        var g = groups.filter(function (x) { return x.id === id; })[0], card = groupsEl.querySelector('[data-id="' + id + '"]');
        for (var k = 0; k < 4; k++) fly(trash, card, g.c, gi * 80 + k * 50);
      });
      if (!trashed.length) trash.classList.remove("full");
    });
    draw();
  }

  // ---------------------------------------------------------------- Twelve apps fold into one as you scroll
  function stack() {
    var sec = $("stack"), tilesEl = $("tiles"), core = $("stack-core"), total = $("stack-total"), label = document.querySelector(".tot-label");
    if (!sec || reduce) return;
    var inner = sec.querySelector(".stack-in"), tiles = Array.prototype.slice.call(tilesEl.children), offs = [];
    function measure() {
      tiles.forEach(function (t) { t.style.transform = ""; });
      var sr = tilesEl.getBoundingClientRect(), cx = sr.left + sr.width / 2, cy = sr.top + sr.height / 2;
      offs = tiles.map(function (t) { var r = t.getBoundingClientRect(); return [cx - (r.left + r.width / 2), cy - (r.top + r.height / 2)]; });
    }
    var ticking = false;
    function update() {
      ticking = false;
      var r = sec.getBoundingClientRect(), span = r.height - inner.offsetHeight;
      var p = clamp(-r.top / (span || 1), 0, 1);
      tiles.forEach(function (t, i) {
        var e = ease(clamp((p - 0.08 - i * 0.022) / 0.42, 0, 1));
        t.style.transform = "translate(" + (offs[i][0] * e).toFixed(1) + "px," + (offs[i][1] * e).toFixed(1) + "px) scale(" + (1 - 0.72 * e).toFixed(3) + ") rotate(" + ((i % 2 ? -1 : 1) * e * 10).toFixed(1) + "deg)";
        t.style.opacity = (1 - e * e).toFixed(3);
      });
      var c = ease(clamp((p - 0.5) / 0.28, 0, 1));
      core.style.opacity = c.toFixed(3);
      core.style.transform = "translate(-50%,-50%) scale(" + (0.6 + 0.4 * c).toFixed(3) + ")";
      var m = clamp((p - 0.1) / 0.62, 0, 1), v = 543.8 - (543.8 - 49) * ease(m);
      total.textContent = "$" + v.toFixed(2);
      total.classList.toggle("cheap", m >= 1);
      label.textContent = m >= 1 ? "With Haven" : "Bought separately";
    }
    measure(); update();
    window.addEventListener("scroll", function () { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
    window.addEventListener("resize", function () { measure(); update(); });
  }

  // ---------------------------------------------------------------- Pull the plug
  function plug() {
    var wifi = $("wifi"), qEl = $("plug-q"), steps = $("plug-steps"), plugEl = $("plug");
    if (!wifi) return;
    var title = plugEl.querySelector(".plug-bar b");
    var STEPS = [
      ["i-search", "Found “Passport scan.jpg”", "Matched the word PASSPORT inside the picture"],
      ["i-locoff", "Removed private details", "Location and camera gone · Passport scan (clean).jpg"],
      ["i-compress", "Made a smaller copy for email", "4.2 MB → 640 KB, next to the original"],
      ["i-sign", "Signed “Visa application.pdf”", "Visa application (signed).pdf"],
    ];
    var run = 0;
    async function play(offline) {
      var my = ++run;
      steps.innerHTML = "";
      title.innerHTML = offline ? 'Haven <span class="offline-badge">Offline</span>' : "Haven";
      var text = "passport";
      if (reduce) qEl.textContent = text;
      else { qEl.textContent = ""; for (var i = 1; i <= text.length; i++) { if (my !== run) return; qEl.textContent = text.slice(0, i); await wait(70); } }
      for (var s = 0; s < STEPS.length; s++) {
        await wait(reduce ? 0 : 520);
        if (my !== run) return;
        steps.insertAdjacentHTML("beforeend", '<div class="pstep"><span class="ic"><svg aria-hidden="true"><use href="#' + STEPS[s][0] + '"/></svg></span><span><b>' + STEPS[s][1] + "</b><small>" + STEPS[s][2] + '</small></span><span class="ok">Done</span></div>');
      }
      if (offline) {
        await wait(reduce ? 0 : 400);
        if (my === run) steps.insertAdjacentHTML("beforeend", '<div class="pstep"><span class="ic"><svg aria-hidden="true"><use href="#i-shield"/></svg></span><span><b>Still working, with Wi-Fi off</b><small>Nothing here needed the internet</small></span><span class="ok">✓</span></div>');
      }
    }
    wifi.addEventListener("click", function () {
      var on = wifi.getAttribute("aria-checked") !== "true";
      wifi.setAttribute("aria-checked", String(on));
      $("wifi-label").textContent = on ? "Wi-Fi on" : "Wi-Fi off";
      play(!on);
    });
    qEl.textContent = "passport";
    steps.innerHTML = STEPS.map(function (st) { return '<div class="pstep"><span class="ic"><svg aria-hidden="true"><use href="#' + st[0] + '"/></svg></span><span><b>' + st[1] + "</b><small>" + st[2] + '</small></span><span class="ok">Done</span></div>'; }).join("");
    onView(plugEl, function () { if (!reduce) play(false); }, 0.5);
  }

  // ---------------------------------------------------------------- Before and after
  function flips() {
    var box = $("flips");
    if (!box) return;
    var btns = Array.prototype.slice.call(document.querySelectorAll(".flip-switch button"));
    function side(s) {
      box.setAttribute("data-side", s);
      btns.forEach(function (b) { b.setAttribute("aria-checked", String(b.getAttribute("data-side") === s)); });
    }
    btns.forEach(function (b) { b.addEventListener("click", function () { side(b.getAttribute("data-side")); }); });
    if ("IntersectionObserver" in window && !reduce) {
      side("before");
      onView(box, function () { setTimeout(function () { side("after"); }, 900); }, 0.6);
    }
  }

  // ---------------------------------------------------------------- The receipt prints itself
  function receipt() {
    var r = $("receipt");
    if (!r || reduce || !("IntersectionObserver" in window)) return;
    var lines = r.querySelectorAll(".r-lines li");
    lines.forEach(function (li, i) { li.style.transitionDelay = i * 90 + "ms"; });
    r.classList.add("printing");
    onView(r, function () { r.classList.remove("printing"); }, 0.3);
  }

  // ---------------------------------------------------------------- Tool studio: every one of the 27 tools, working
  var closeDeskWindow = null;
  function studio() {
    var root = $("studio");
    if (!root) return;
    var catsEl = $("studio-cats"), chipsEl = $("studio-chips"), stage = $("studio-stage");
    var CATS = [
      { id: "images", name: "Images", icon: "i-photo", tools: [["Convert Images", "convertImg"], ["Resize Images", "resizeImg"], ["Rotate Images", "rotateImg"], ["Remove Private Details", "clean"], ["Remove Background", "cutout"]] },
      { id: "pdf", name: "PDF", icon: "i-doc", tools: [["Merge PDFs", "merge"], ["Split PDF", "split"], ["Organize Pages", "organize"], ["Extract Pages", "extract"], ["Images to PDF", "img2pdf"], ["PDF to Images", "pdf2img"], ["Add Password", "lock"], ["Remove Password", "unlock"], ["Sign PDF", "sign"]] },
      { id: "video", name: "Video", icon: "i-film", tools: [["Compress Video", "compress"], ["Convert Video", "convertVid"], ["Trim Video", "trimVid"], ["Make a GIF", "gif"], ["Extract Audio", "extractAudio"], ["Mute Video", "mute"], ["Merge Videos", "mergeVid"], ["Change Speed", "speed"]] },
      { id: "audio", name: "Audio", icon: "i-wave", tools: [["Convert Audio", "convertAud"], ["Trim Audio", "trimAud"]] },
      { id: "ai", name: "On-device AI", icon: "i-sparkle", tools: [["Transcribe", "transcribe"], ["Translate", "translate"], ["Summarize", "summarize"]] },
    ];
    var timers = [];
    function later(fn, ms) { var t = setInterval(fn, ms); timers.push(t); return t; }
    function cleanup() { timers.forEach(clearInterval); timers = []; }

    // ---- small builders
    function chipMade(name, detail) {
      return '<div class="made"><span class="fi"><svg aria-hidden="true"><use href="#i-check"/></svg></span><span><b>' + esc(name) + "</b><small>" + esc(detail) + "</small></span></div>";
    }
    function goRow(label, extra) {
      return '<div class="tool-row"><button class="wbtn" type="button" data-go>' + label + "</button>" + (extra || "") + '<div class="bar sbar" hidden style="flex:1;min-width:120px"><i></i></div></div>';
    }
    function seg(name, opts, pick) {
      return '<div class="optrow" data-seg="' + name + '">' + opts.map(function (o) {
        var v = Array.isArray(o) ? o[0] : o, label = Array.isArray(o) ? o[1] : o;
        return '<button class="opt" type="button" data-v="' + esc(v) + '" aria-pressed="' + (v === pick) + '">' + label + "</button>";
      }).join("") + "</div>";
    }
    function body(title, path, vis, ctl, note) {
      return shell(title, path, '<div class="sv">' + vis + '</div><div class="sctl">' + ctl + "</div>" + (note ? '<p class="snote">' + note + "</p>" : "") + '<div class="sout" aria-live="polite"></div>');
    }
    function wireSeg(st, name, fn) {
      var box = st.querySelector('[data-seg="' + name + '"]');
      box.addEventListener("click", function (e) {
        var b = e.target.closest(".opt");
        if (!b || b.disabled) return;
        box.querySelectorAll(".opt").forEach(function (o) { o.setAttribute("aria-pressed", String(o === b)); });
        fn(b.getAttribute("data-v"));
      });
    }
    function go(st, fn) {
      var b = st.querySelector("[data-go]");
      b.addEventListener("click", async function () {
        if (b.disabled) return;
        b.disabled = true;
        try { await fn(b); } finally { b.disabled = false; }
      });
      return b;
    }
    function bar(st, ms) {
      var el = st.querySelector(".sbar");
      el.hidden = false;
      el.firstElementChild.style.width = "0";
      return progress(el.firstElementChild, reduce ? 10 : ms).then(function () { el.hidden = true; });
    }
    function out(st, html) { st.querySelector(".sout").innerHTML = html; }
    function photo(ph, extra) { return '<div class="th th-photo" style="--ph:' + PH[ph] + '">' + (extra || "") + "</div>"; }
    function card(th, name, meta, cls) { return '<div class="fcard ' + (cls || "") + '">' + th + "<b>" + esc(name) + "</b><small>" + meta + "</small></div>"; }
    function fmt(label, color) { return '<span class="fmt" style="--c:' + color + '">' + label + "</span>"; }
    var ARROW = '<svg class="toarrow" aria-hidden="true"><use href="#i-chev"/></svg>';
    var HUES = [262, 340, 205, 28, 150, 300, 190, 45];
    function pageHTML(n, opts) {
      opts = opts || {};
      var hue = HUES[(n - 1) % HUES.length];
      return '<div class="spage' + (opts.cls ? " " + opts.cls : "") + '" style="--hue:' + hue + (opts.rot ? ";--r:" + opts.rot + "deg" : "") + '"><b></b><i></i><i></i><i></i><i></i><span>' + n + "</span></div>";
    }
    function docStack(n, name, meta, cls) {
      var pages = "";
      for (var i = Math.min(n, 3); i >= 1; i--) pages += pageHTML(i, { cls: "st" + i });
      return '<div class="fcard ' + (cls || "") + '"><div class="dstack">' + pages + "</div><b>" + esc(name) + "</b><small>" + meta + "</small></div>";
    }
    function waveHTML(n, seed, cls) {
      var R = rng(seed || 3), s = "";
      for (var i = 0; i < n; i++) {
        var h = 18 + Math.abs(Math.sin(i * 0.37) * 50 + Math.sin(i * 0.11) * 20) + R() * 18;
        s += '<i style="--h:' + Math.min(100, h).toFixed(0) + '%;--d:' + (R() * 0.6).toFixed(2) + 's"></i>';
      }
      return '<div class="wv ' + (cls || "") + '">' + s + "</div>";
    }
    var FRAMES = ["demo", "call", "wedding", "holiday", "beach", "sunset", "park", "grad", "mount", "market"];
    function stripHTML(n, list) {
      var s = "";
      for (var i = 0; i < n; i++) s += '<span class="fr" style="--ph:' + PH[(list || FRAMES)[i % (list || FRAMES).length]] + '"></span>';
      return s;
    }
    function mmss(sec) { sec = Math.max(0, Math.round(sec)); return Math.floor(sec / 60) + ":" + pad(sec % 60); }

    // A range picker with two handles over a strip (frames or a waveform).
    function rangePicker(track, a, b, onChange) {
      var hA = track.querySelector(".hdl.a"), hB = track.querySelector(".hdl.b"), sel = track.querySelector(".rsel");
      function draw() {
        hA.style.left = a * 100 + "%"; hB.style.left = b * 100 + "%";
        track.style.setProperty("--a", a); track.style.setProperty("--b", b);
        sel.style.left = a * 100 + "%"; sel.style.width = (b - a) * 100 + "%";
        hA.setAttribute("aria-valuenow", Math.round(a * 100)); hB.setAttribute("aria-valuenow", Math.round(b * 100));
        onChange(a, b);
      }
      [hA, hB].forEach(function (h) {
        var isA = h === hA, dragging = false;
        h.addEventListener("pointerdown", function (e) { dragging = true; h.setPointerCapture(e.pointerId); e.preventDefault(); });
        h.addEventListener("pointermove", function (e) {
          if (!dragging) return;
          var r = track.getBoundingClientRect(), v = clamp((e.clientX - r.left) / r.width, 0, 1);
          if (isA) a = Math.min(v, b - 0.05); else b = Math.max(v, a + 0.05);
          draw();
        });
        h.addEventListener("pointerup", function () { dragging = false; });
        h.addEventListener("keydown", function (e) {
          var d = e.key === "ArrowLeft" ? -0.02 : e.key === "ArrowRight" ? 0.02 : 0;
          if (!d) return;
          e.preventDefault();
          if (isA) a = clamp(a + d, 0, b - 0.05); else b = clamp(b + d, a + 0.05, 1);
          draw();
        });
      });
      draw();
      return function () { return [a, b]; };
    }
    function rangeTrack(inner, label) {
      return '<div class="rtrack">' + inner + '<span class="rsel"></span><button class="hdl a" type="button" role="slider" aria-label="' + label + ' start" aria-valuemin="0" aria-valuemax="100"></button><button class="hdl b" type="button" role="slider" aria-label="' + label + ' end" aria-valuemin="0" aria-valuemax="100"></button></div>';
    }

    var DEMOS = {
      // ---------------- Images
      convertImg: function (st) {
        var F = { JPEG: [2.2, "#e2453c", "jpg", "Opens everywhere, small enough to email"], PNG: [9.8, "#2f80ed", "png", "Lossless, every pixel kept"], WebP: [1.4, "#2f9e6b", "webp", "The smallest, made for the web"], TIFF: [24.1, "#8a63e8", "tiff", "For print and archives"] }, pick = "JPEG";
        st.innerHTML = body("Convert Images", ["IMG_4021.HEIC", "Tools", "Convert Images"],
          card(photo("sunset", fmt("HEIC", "#6c6a75")), "IMG_4021.HEIC", "3.1 MB · from your iPhone", "src") + ARROW + '<div class="fcard ghost" id="s-out"><div class="th"></div><b>Pick a format</b><small>&nbsp;</small></div>',
          seg("f", ["JPEG", "PNG", "TIFF"], pick) + goRow("Convert"), "Works on one photo or a thousand at once.");
        var outEl = st.querySelector("#s-out");
        wireSeg(st, "f", function (v) { pick = v; outEl.className = "fcard ghost"; outEl.innerHTML = '<div class="th"></div><b>IMG_4021.' + F[v][2] + "</b><small>Press Convert</small>"; out(st, ""); });
        go(st, async function () {
          await bar(st, 900);
          var f = F[pick];
          outEl.className = "fcard pop";
          outEl.innerHTML = photo("sunset", fmt(pick.toUpperCase(), f[1])) + "<b>IMG_4021." + f[2] + "</b><small>" + f[0] + " MB · " + f[3] + "</small>";
          out(st, chipMade("IMG_4021." + f[2], "Made next to the original"));
        });
      },
      resizeImg: function (st) {
        var v = 1600;
        st.innerHTML = body("Resize Images", ["IMG_4021.HEIC", "Tools", "Resize Images"],
          '<div class="rs-wrap"><div class="rs-full"><span>4032 × 3024</span></div><div class="rs-frame" id="s-frame">' + photo("sunset") + '</div></div><div class="rs-read"><b id="s-dim"></b><small id="s-size"></small></div>',
          '<div class="tool-row"><label class="srange"><span>Long edge</span><input id="s-r" type="range" min="400" max="4032" step="16" value="1600"></label>' + seg("p", [["800", "800"], ["1280", "1280"], ["1600", "1600"], ["2048", "2048"]], "1600") + "</div>" + goRow("Resize"), "The shape stays the same. Big photos become email-friendly in a click.");
        var frame = st.querySelector("#s-frame"), dim = st.querySelector("#s-dim"), size = st.querySelector("#s-size"), range = st.querySelector("#s-r");
        function draw() {
          frame.style.width = (24 + 76 * (v / 4032)).toFixed(1) + "%";
          dim.textContent = v + " × " + Math.round(v * 0.75) + " px";
          var mb = Math.max(0.08, 3.1 * Math.pow(v / 4032, 2));
          size.textContent = "3.1 MB → " + (mb < 1 ? Math.round(mb * 1000) + " KB" : mb.toFixed(1) + " MB");
          st.querySelectorAll('[data-seg="p"] .opt').forEach(function (o) { o.setAttribute("aria-pressed", String(+o.getAttribute("data-v") === v)); });
        }
        range.addEventListener("input", function () { v = +range.value; draw(); out(st, ""); });
        wireSeg(st, "p", function (x) { v = +x; range.value = v; draw(); out(st, ""); });
        draw();
        go(st, async function () { await bar(st, 700); out(st, chipMade("IMG_4021 (" + v + "px).HEIC", size.textContent + " · next to the original")); });
      },
      rotateImg: function (st) {
        var pics = [["beach", 90], ["mount", 0], ["park", 270], ["cake", 180]];
        st.innerHTML = body("Rotate Images", ["4 photos", "Tools", "Rotate Images"],
          '<div class="rot-row">' + pics.map(function (p, i) { return '<button type="button" class="rot" data-i="' + i + '" aria-pressed="' + (p[1] !== 0) + '" style="--r:' + p[1] + 'deg">' + photo(p[0]) + "</button>"; }).join("") + "</div>",
          '<div class="tool-row"><button class="wbtn ghost" type="button" data-turn="-90">⟲ Turn left</button><button class="wbtn ghost" type="button" data-turn="90">⟳ Turn right</button><span class="mac-sub" id="s-st"></span></div>', "Click photos to pick them, then turn them. Every pick turns together.");
        var stat = st.querySelector("#s-st");
        function status() {
          var off = pics.filter(function (p) { return ((p[1] % 360) + 360) % 360 !== 0; }).length;
          stat.textContent = off ? off + (off === 1 ? " photo is" : " photos are") + " sideways" : "All upright";
          if (!off) out(st, chipMade("3 photos rotated", "Saved as new copies, originals untouched"));
        }
        st.querySelector(".rot-row").addEventListener("click", function (e) {
          var b = e.target.closest(".rot"); if (!b) return;
          b.setAttribute("aria-pressed", String(b.getAttribute("aria-pressed") !== "true"));
        });
        st.querySelectorAll("[data-turn]").forEach(function (btn) {
          btn.addEventListener("click", function () {
            var d = +btn.getAttribute("data-turn");
            st.querySelectorAll(".rot").forEach(function (b) {
              if (b.getAttribute("aria-pressed") !== "true") return;
              var p = pics[+b.getAttribute("data-i")];
              p[1] -= d;
              b.style.setProperty("--r", p[1] + "deg");
              if (((p[1] % 360) + 360) % 360 === 0) b.setAttribute("aria-pressed", "false");
            });
            status();
          });
        });
        status();
      },

      // ---------------- PDF
      split: function (st) {
        st.innerHTML = body("Split PDF", ["Report.pdf", "Tools", "Split PDF"],
          '<div class="split-stage" id="s-split">' + docStack(5, "Report.pdf", "5 pages") + "</div>", goRow("Split into 5 files"), "One file per page, numbered so they sort in order.");
        var box = st.querySelector("#s-split");
        go(st, async function () {
          await bar(st, 700);
          var s = "";
          for (var i = 1; i <= 5; i++) s += '<div class="fcard pop" style="animation-delay:' + i * 70 + 'ms"><div class="dstack one">' + pageHTML(i) + "</div><b>Report - page 0" + i + ".pdf</b><small>1 page</small></div>";
          box.innerHTML = s;
          out(st, chipMade("Report (pages)", "A folder with 5 PDFs: Report - page 01.pdf to page 05.pdf"));
        });
      },
      organize: function (st) {
        var pages = [1, 2, 3, 4, 5, 6].map(function (n) { return { n: n, r: n === 4 ? 90 : 0 }; });
        st.innerHTML = body("Organize Pages", ["Report.pdf", "Tools", "Organize Pages…"],
          '<div class="og-grid" id="s-og"></div>', goRow("Save"), "Move pages with the arrows, turn the sideways one, delete the ones you don't need.");
        var grid = st.querySelector("#s-og");
        function draw() {
          grid.innerHTML = pages.map(function (p, i) {
            return '<div class="og">' + pageHTML(p.n, { rot: p.r }) + '<div class="og-tools"><button type="button" aria-label="Move page ' + p.n + ' earlier" data-a="l" data-i="' + i + '"' + (i === 0 ? " disabled" : "") + '>‹</button><button type="button" aria-label="Turn page ' + p.n + '" data-a="r" data-i="' + i + '">⟳</button><button type="button" aria-label="Delete page ' + p.n + '" data-a="x" data-i="' + i + '">✕</button><button type="button" aria-label="Move page ' + p.n + ' later" data-a="n" data-i="' + i + '"' + (i === pages.length - 1 ? " disabled" : "") + ">›</button></div></div>";
          }).join("");
        }
        grid.addEventListener("click", function (e) {
          var b = e.target.closest("button"); if (!b) return;
          var i = +b.getAttribute("data-i"), a = b.getAttribute("data-a"), t;
          if (a === "l") { t = pages[i - 1]; pages[i - 1] = pages[i]; pages[i] = t; }
          if (a === "n") { t = pages[i + 1]; pages[i + 1] = pages[i]; pages[i] = t; }
          if (a === "r") pages[i].r = (pages[i].r + 90) % 360;
          if (a === "x" && pages.length > 1) pages.splice(i, 1);
          draw(); out(st, "");
        });
        draw();
        go(st, async function () { await bar(st, 600); out(st, chipMade("Report (edited).pdf", pages.length + " pages, in your order: " + pages.map(function (p) { return p.n; }).join(", "))); });
      },
      extract: function (st) {
        var picked = { 2: 1, 3: 1, 6: 1 };
        st.innerHTML = body("Extract Pages", ["Report.pdf", "Tools", "Extract Pages…"],
          '<div class="ex-grid" id="s-ex"></div>',
          '<div class="tool-row"><label class="sfield"><span>Pages</span><input id="s-pages" type="text" value="2-3, 6" autocomplete="off" spellcheck="false"></label></div>' + goRow("Extract"), "Type pages and ranges, or click the pages themselves.");
        var grid = st.querySelector("#s-ex"), input = st.querySelector("#s-pages"), btn = st.querySelector("[data-go]");
        function toText() {
          var ns = Object.keys(picked).map(Number).sort(function (a, b) { return a - b; }), parts = [], i = 0;
          while (i < ns.length) { var j = i; while (j + 1 < ns.length && ns[j + 1] === ns[j] + 1) j++; parts.push(i === j ? "" + ns[i] : ns[i] + "-" + ns[j]); i = j + 1; }
          return parts.join(", ");
        }
        function fromText(t) {
          picked = {};
          t.split(",").forEach(function (part) {
            var m = part.trim().match(/^(\d+)(?:\s*-\s*(\d+))?$/);
            if (!m) return;
            for (var k = +m[1]; k <= +(m[2] || m[1]) && k <= 8; k++) if (k >= 1) picked[k] = 1;
          });
        }
        function draw() {
          var n = Object.keys(picked).length;
          grid.innerHTML = [1, 2, 3, 4, 5, 6, 7, 8].map(function (k) { return '<button type="button" class="ex' + (picked[k] ? " on" : "") + '" data-k="' + k + '" aria-pressed="' + !!picked[k] + '">' + pageHTML(k) + "</button>"; }).join("");
          btn.textContent = "Extract " + n + (n === 1 ? " page" : " pages");
          btn.disabled = !n;
        }
        grid.addEventListener("click", function (e) {
          var b = e.target.closest(".ex"); if (!b) return;
          var k = +b.getAttribute("data-k");
          if (picked[k]) delete picked[k]; else picked[k] = 1;
          input.value = toText(); draw(); out(st, "");
        });
        input.addEventListener("input", function () { fromText(input.value); draw(); out(st, ""); });
        draw();
        go(st, async function () { var n = Object.keys(picked).length; await bar(st, 600); out(st, chipMade("Report (" + (n === 1 ? "page " : "pages ") + toText() + ").pdf", "Pages " + toText() + " · the original keeps all 8")); });
      },
      img2pdf: function (st) {
        st.innerHTML = body("Images to PDF", ["4 photos", "Tools", "Images to PDF"],
          '<div class="i2p" id="s-i2p">' + [1, 2, 3, 4].map(function (k) { return '<div class="rcpt" style="--t:' + (k * 7 - 18) + 'deg"><b>RECEIPT</b><i></i><i></i><i></i><i></i><em>$' + [12.4, 38, 7.95, 64.2][k - 1].toFixed(2) + "</em></div>"; }).join("") + "</div>",
          goRow("Make one PDF"), "Photos of receipts, whiteboards or homework become a single document, in order.");
        var box = st.querySelector("#s-i2p");
        go(st, async function () {
          box.classList.add("gather");
          await bar(st, 800);
          box.classList.remove("gather");
          box.innerHTML = docStack(4, "Receipt 1 (4 pages).pdf", "4 pages · one file to send", "pop");
          out(st, chipMade("Receipt 1 (4 pages).pdf", "Made next to the photos"));
        });
      },
      pdf2img: function (st) {
        var pick = "PNG";
        st.innerHTML = body("PDF to Images", ["Slides.pdf", "Tools", "PDF to Images"],
          '<div class="split-stage" id="s-p2i">' + docStack(3, "Slides.pdf", "3 pages") + "</div>", seg("f", ["PNG", "JPEG"], pick) + goRow("Convert"), "Every page as a picture, ready for a chat, a slide or a post.");
        var box = st.querySelector("#s-p2i");
        wireSeg(st, "f", function (v) { pick = v; });
        go(st, async function () {
          await bar(st, 700);
          var ext = pick === "PNG" ? "png" : "jpg", s = "";
          for (var i = 1; i <= 3; i++) s += '<div class="fcard pop" style="animation-delay:' + i * 80 + 'ms"><div class="th th-photo slide' + i + '">' + fmt(pick, pick === "PNG" ? "#2f80ed" : "#e2453c") + "</div><b>Slides - page " + i + "." + ext + "</b><small>1920 × 1080</small></div>";
          box.innerHTML = s;
          out(st, chipMade("Slides (images)", "A folder with 3 " + pick + " images"));
        });
      },
      lock: function (st) {
        st.innerHTML = body("Add Password", ["Contract.pdf", "Tools", "Add Password…"],
          '<div class="lk-stage">' + docStack(1, "Contract.pdf", "Anyone can open it", "lk-doc") + '<div class="pw-prompt" hidden id="s-prompt"><b>“Contract (locked).pdf” is protected</b><small>Enter the password to open it.</small><input type="password" id="s-try" placeholder="Password" autocomplete="off"><div class="tool-row"><button class="wbtn ghost" type="button" id="s-cancel">Cancel</button><button class="wbtn" type="button" id="s-open">Open</button></div></div></div>',
          '<div class="tool-row"><label class="sfield"><span>Password</span><input id="s-pw" type="password" placeholder="Choose a password" autocomplete="new-password"></label><span class="pw-meter"><i id="s-meter"></i></span></div>' + goRow("Add Password", '<button class="wbtn ghost" type="button" id="s-test" hidden>Try opening it</button>'), "The copy only opens with the password. Your original stays as it was.");
        var pw = st.querySelector("#s-pw"), meter = st.querySelector("#s-meter"), btn = st.querySelector("[data-go]"), prompt = st.querySelector("#s-prompt"), doc = st.querySelector(".lk-doc"), test = st.querySelector("#s-test"), secret = "";
        function strength() {
          var v = pw.value, s = Math.min(4, (v.length >= 6) + (v.length >= 10) + (/\d/.test(v)) + (/[^a-z0-9]/i.test(v)));
          meter.style.width = (v ? 15 + s * 21 : 0) + "%";
          meter.style.background = s < 2 ? "var(--bad)" : s < 3 ? "#e39a2d" : "var(--ok)";
          btn.disabled = v.length < 4;
        }
        pw.addEventListener("input", strength); strength();
        go(st, async function () {
          secret = pw.value;
          await bar(st, 700);
          doc.classList.add("locked");
          doc.querySelector(":scope > b").textContent = "Contract (locked).pdf";
          doc.querySelector(":scope > small").textContent = "Needs the password";
          test.hidden = false;
          out(st, chipMade("Contract (locked).pdf", "Only people with the password can open it"));
        });
        test.addEventListener("click", function () { prompt.hidden = false; st.querySelector("#s-try").value = ""; st.querySelector("#s-try").focus(); });
        st.querySelector("#s-cancel").addEventListener("click", function () { prompt.hidden = true; });
        st.querySelector("#s-open").addEventListener("click", function () {
          var tryEl = st.querySelector("#s-try");
          if (tryEl.value === secret) { prompt.hidden = true; doc.classList.remove("locked"); doc.classList.add("opened"); doc.querySelector(":scope > small").textContent = "Opened with the right password"; }
          else { prompt.classList.remove("shake"); void prompt.offsetWidth; prompt.classList.add("shake"); }
        });
      },
      unlock: function (st) {
        st.innerHTML = body("Remove Password", ["Bank statement.pdf", "Tools", "Remove Password…"],
          '<div class="lk-stage">' + docStack(1, "Bank statement.pdf", "Asks for a password every time", "lk-doc locked") + "</div>",
          '<div class="tool-row"><label class="sfield"><span>Password</span><input id="s-pw" type="password" placeholder="The password you were given" autocomplete="off"></label><span class="mac-sub">For this example it\'s <b>haven</b></span></div>' + goRow("Remove Password"), "You need the password once. The copy opens without it from then on.");
        var pw = st.querySelector("#s-pw"), doc = st.querySelector(".lk-doc"), sv = st.querySelector(".sv");
        go(st, async function () {
          if (pw.value.trim().toLowerCase() !== "haven") { sv.classList.remove("shake"); void sv.offsetWidth; sv.classList.add("shake"); out(st, '<p class="mac-sub">That isn\'t the password. Try <b>haven</b>.</p>'); return; }
          await bar(st, 700);
          doc.classList.remove("locked"); doc.classList.add("opened");
          doc.querySelector(":scope > b").textContent = "Bank statement (unlocked).pdf";
          doc.querySelector(":scope > small").textContent = "Opens without a password";
          out(st, chipMade("Bank statement (unlocked).pdf", "A copy that opens without the password"));
        });
      },

      // ---------------- Video
      convertVid: function (st) {
        var pick = "MP4";
        st.innerHTML = body("Convert Video", ["Screen recording.mov", "Tools", "Convert Video"],
          card('<div class="th th-video" style="--ph:' + PH.screen + '"><span class="play"></span><span class="dur">14:02</span>' + fmt("MOV", "#6c6a75") + "</div>", "Screen recording.mov", "860 MB · QuickTime", "src") + ARROW + '<div class="fcard ghost" id="s-out"><div class="th"></div><b>Screen recording.mp4</b><small>Press Convert</small></div>',
          seg("f", [["MP4", "MP4, plays everywhere"], ["MOV", "MOV, for Apple apps"]], pick) + goRow("Convert"), "MP4 plays on Windows, Android and every website. No extra software to install.");
        var outEl = st.querySelector("#s-out");
        wireSeg(st, "f", function (v) { pick = v; outEl.className = "fcard ghost"; outEl.innerHTML = '<div class="th"></div><b>Screen recording' + (v === "MOV" ? " (converted).mov" : ".mp4") + "</b><small>Press Convert</small>"; out(st, ""); });
        go(st, async function () {
          await bar(st, 1100);
          var name = pick === "MP4" ? "Screen recording.mp4" : "Screen recording (converted).mov";
          outEl.className = "fcard pop";
          outEl.innerHTML = '<div class="th th-video" style="--ph:' + PH.screen + '"><span class="play"></span><span class="dur">14:02</span>' + fmt(pick, pick === "MP4" ? "#2f9e6b" : "#6a4df2") + "</div><b>" + name + "</b><small>Same length, plays everywhere</small>";
          out(st, chipMade(name, "Made next to the original"));
        });
      },
      trimVid: function (st) {
        var TOTAL = 32 * 60 + 14, cur = [0.18, 0.52];
        st.innerHTML = body("Trim Video", ["Team call.mov", "Tools", "Trim Video…"],
          '<div class="tv"><div class="tv-screen" style="--ph:' + PH.call + '"><span class="tv-time" id="s-time"></span></div>' + rangeTrack(stripHTML(12, ["call", "call", "demo", "call", "screen", "call", "call", "demo", "call", "screen", "call", "call"]), "Trim") + "</div>",
          '<div class="tool-row"><span class="mac-sub" id="s-sel"></span></div>' + goRow("Trim"), "Drag the yellow handles to keep just the part you want.");
        var time = st.querySelector("#s-time"), selEl = st.querySelector("#s-sel");
        rangePicker(st.querySelector(".rtrack"), cur[0], cur[1], function (a, b) {
          cur = [a, b];
          time.textContent = mmss(a * TOTAL) + " – " + mmss(b * TOTAL);
          selEl.textContent = "Keeping " + mmss((b - a) * TOTAL) + " of 32:14";
          out(st, "");
        });
        go(st, async function () { await bar(st, 700); out(st, chipMade("Team call (trimmed).mov", mmss((cur[1] - cur[0]) * TOTAL) + " long · next to the original")); });
      },
      gif: function (st) {
        var pick = "480", seq = ["demo", "holiday", "beach", "sunset", "wedding", "park"], fi = 0, playing = 0;
        st.innerHTML = body("Make a GIF", ["Product demo.mp4", "Tools", "Make a GIF"],
          '<div class="gif-stage"><div class="gif-view" id="s-gif" style="--ph:' + PH.demo + '"><span class="gif-badge">GIF</span></div><div class="gif-strip">' + stripHTML(6, seq) + "</div></div>",
          seg("s", [["320", "Small · 320 px"], ["480", "Medium · 480 px"], ["640", "Large · 640 px"]], pick) + goRow("Make GIF"), "A looping GIF to drop into Slack, a README or an email.");
        var view = st.querySelector("#s-gif");
        wireSeg(st, "s", function (v) { pick = v; view.style.width = v * 0.62 + "px"; });
        view.style.width = 480 * 0.62 + "px";
        go(st, async function () {
          await bar(st, 900);
          if (!playing) playing = later(function () { fi = (fi + 1) % seq.length; view.style.setProperty("--ph", PH[seq[fi]]); }, reduce ? 1000 : 260);
          view.classList.add("live");
          out(st, chipMade("Product demo.gif", { 320: "1.2 MB", 480: "2.6 MB", 640: "4.8 MB" }[pick] + " · loops forever"));
        });
      },
      extractAudio: function (st) {
        st.innerHTML = body("Extract Audio", ["Team call.mov", "Tools", "Extract Audio"],
          card('<div class="th th-video" style="--ph:' + PH.call + '"><span class="play"></span><span class="dur">32:14</span></div>', "Team call.mov", "412 MB · video and sound", "src") + ARROW + '<div class="fcard ghost" id="s-out"><div class="th"></div><b>Team call.m4a</b><small>Press Extract</small></div>',
          goRow("Extract"), "Keep just the soundtrack: a meeting for your commute, a song from a clip.");
        var outEl = st.querySelector("#s-out");
        go(st, async function () {
          await bar(st, 800);
          outEl.className = "fcard pop";
          outEl.innerHTML = '<div class="th th-audio-big">' + waveHTML(28, 7, "mini") + "</div><b>Team call.m4a</b><small>31 MB · just the sound</small>";
          out(st, chipMade("Team call.m4a", "The video is untouched"));
        });
      },
      mute: function (st) {
        st.innerHTML = body("Mute Video", ["Kids at the beach.mov", "Tools", "Mute Video"],
          '<div class="mute-stage"><div class="th th-video big" style="--ph:' + PH.beach + '"><span class="play"></span><span class="spk" id="s-spk"><svg aria-hidden="true"><use href="#i-wave"/></svg></span></div>' + waveHTML(48, 11, "live") + "</div>",
          goRow("Mute"), "Take out wind noise, background chatter or music you can't post.");
        var wv = st.querySelector(".wv"), spk = st.querySelector("#s-spk");
        go(st, async function () {
          await bar(st, 700);
          wv.classList.add("flat"); spk.classList.add("off");
          out(st, chipMade("Kids at the beach (muted).mov", "Same picture, no sound"));
        });
      },
      mergeVid: function (st) {
        var clips = [["Intro.mov", 24, "demo"], ["Interview.mov", 138, "call"], ["Outro.mov", 30, "wedding"]];
        st.innerHTML = body("Merge Videos", ["3 clips", "Tools", "Merge Videos…"],
          '<div class="mv-stage"><div class="mv-clips" id="s-clips"></div><div class="mv-line" id="s-line"></div></div>', goRow("Merge 3 clips"), "Clips are joined in the order you set.");
        var box = st.querySelector("#s-clips"), line = st.querySelector("#s-line");
        function draw() {
          box.innerHTML = clips.map(function (c, i) {
            return '<div class="mv"><span class="order">' + (i + 1) + '</span><div class="th th-video" style="--ph:' + PH[c[2]] + '"><span class="dur">' + mmss(c[1]) + "</span></div><b>" + c[0] + '</b><span class="tool-row" style="gap:4px;justify-content:center"><button class="wbtn ghost mini" type="button" data-mv="' + i + ':-1"' + (i ? "" : " disabled") + ' aria-label="Earlier">‹</button><button class="wbtn ghost mini" type="button" data-mv="' + i + ':1"' + (i < clips.length - 1 ? "" : " disabled") + ' aria-label="Later">›</button></span></div>';
          }).join("");
          var total = clips.reduce(function (s, c) { return s + c[1]; }, 0);
          line.className = "mv-line";
          line.innerHTML = clips.map(function (c) { return '<span style="flex:' + c[1] + ";--ph:" + PH[c[2]] + '"></span>'; }).join("");
          line.setAttribute("data-total", mmss(total));
        }
        box.addEventListener("click", function (e) {
          var b = e.target.closest("[data-mv]"); if (!b) return;
          var p = b.getAttribute("data-mv").split(":"), i = +p[0], j = i + +p[1], t = clips[i];
          clips[i] = clips[j]; clips[j] = t; draw(); out(st, "");
        });
        draw();
        go(st, async function () {
          await bar(st, 900);
          line.classList.add("joined");
          var total = clips.reduce(function (s, c) { return s + c[1]; }, 0);
          out(st, chipMade(clips[0][0].replace(".mov", "") + " (merged).mov", mmss(total) + " · " + clips.map(function (c) { return c[0].replace(".mov", ""); }).join(" → ")));
        });
      },
      speed: function (st) {
        var pick = "2";
        st.innerHTML = body("Change Speed", ["Lecture.mov", "Tools", "Change Speed"],
          '<div class="spd"><div class="spd-track"><span class="spd-dot" id="s-dot"></span></div><div class="spd-read"><b id="s-len">48:00 → 24:00</b><small>The voice keeps its pitch, so nobody sounds like a chipmunk.</small></div></div>',
          seg("x", [["0.5", "0.5×"], ["1.5", "1.5×"], ["2", "2×"], ["4", "4×"]], pick) + goRow("Make it"), "Watch a lecture in half the time, or slow down a tutorial.");
        var dot = st.querySelector("#s-dot"), len = st.querySelector("#s-len");
        function draw() { var x = +pick; dot.style.animationDuration = (2.4 / x).toFixed(2) + "s"; len.textContent = "48:00 → " + mmss((48 * 60) / x); }
        wireSeg(st, "x", function (v) { pick = v; draw(); out(st, ""); });
        draw();
        go(st, async function () { await bar(st, 900); out(st, chipMade("Lecture (" + pick + "×).mov", mmss((48 * 60) / +pick) + " long · same pitch")); });
      },

      // ---------------- Audio
      convertAud: function (st) {
        var F = { WAV: [465, "#2f80ed", "wav", "Uncompressed, for editing"], AIFF: [465, "#8a63e8", "aiff", "Uncompressed, the Mac way"], FLAC: [255, "#2f9e6b", "flac", "Lossless and about half the size"], M4A: [54, "#e39a2d", "m4a", "Small, for listening"] }, pick = "WAV";
        st.innerHTML = body("Convert Audio", ["Interview.m4a", "Tools", "Convert Audio"],
          card('<div class="th th-audio-big">' + waveHTML(26, 5, "mini") + fmt("M4A", "#6c6a75") + "</div>", "Interview.m4a", "54 MB · 46 minutes", "src") + ARROW + '<div class="fcard ghost" id="s-out"><div class="th"></div><b>Interview.wav</b><small>Press Convert</small></div>',
          seg("f", ["WAV", "AIFF", "FLAC"], pick) + goRow("Convert"), "Hand a file to an editor in the format they ask for.");
        var outEl = st.querySelector("#s-out");
        wireSeg(st, "f", function (v) { pick = v; outEl.className = "fcard ghost"; outEl.innerHTML = '<div class="th"></div><b>Interview.' + F[v][2] + "</b><small>Press Convert</small>"; out(st, ""); });
        go(st, async function () {
          await bar(st, 900);
          var f = F[pick];
          outEl.className = "fcard pop";
          outEl.innerHTML = '<div class="th th-audio-big">' + waveHTML(26, 5, "mini") + fmt(pick, f[1]) + "</div><b>Interview." + f[2] + "</b><small>" + f[0] + " MB · " + f[3] + "</small>";
          out(st, chipMade("Interview." + f[2], "Made next to the original"));
        });
      },
      trimAud: function (st) {
        var TOTAL = 46 * 60, cur = [0.3, 0.62], playT = 0;
        st.innerHTML = body("Trim Audio", ["Interview.m4a", "Tools", "Trim Audio…"],
          '<div class="ta">' + rangeTrack(waveHTML(90, 9, "track") + '<span class="playhead" id="s-ph"></span>', "Trim") + "</div>",
          '<div class="tool-row"><button class="wbtn ghost" type="button" id="s-play">▶ Play selection</button><span class="mac-sub" id="s-sel"></span></div>' + goRow("Trim"), "Cut a podcast down to the quote you need.");
        var selEl = st.querySelector("#s-sel"), ph = st.querySelector("#s-ph");
        rangePicker(st.querySelector(".rtrack"), cur[0], cur[1], function (a, b) { cur = [a, b]; selEl.textContent = mmss(a * TOTAL) + " – " + mmss(b * TOTAL) + " · " + mmss((b - a) * TOTAL); ph.style.left = a * 100 + "%"; out(st, ""); });
        st.querySelector("#s-play").addEventListener("click", function () {
          if (playT) { clearInterval(playT); playT = 0; }
          var t0 = performance.now();
          playT = later(function () {
            var p = (performance.now() - t0) / 3000;
            if (p >= 1) { clearInterval(playT); playT = 0; p = 1; }
            ph.style.left = (cur[0] + (cur[1] - cur[0]) * p) * 100 + "%";
          }, 30);
        });
        go(st, async function () { await bar(st, 600); out(st, chipMade("Interview (trimmed).m4a", mmss((cur[1] - cur[0]) * TOTAL) + " long")); });
      },

      // ---------------- On-device AI
      translate: function (st) {
        var EN = ["Welcome to the team!", "Your first day is Monday at 9 a.m.", "Please bring your ID and a signed copy of the contract."];
        var L = {
          Spanish: ["¡Bienvenido al equipo!", "Tu primer día es el lunes a las 9 a. m.", "Por favor, trae tu identificación y una copia firmada del contrato."],
          French: ["Bienvenue dans l'équipe !", "Votre premier jour est lundi à 9 h.", "Veuillez apporter votre pièce d'identité et un exemplaire signé du contrat."],
          German: ["Willkommen im Team!", "Dein erster Tag ist Montag um 9 Uhr.", "Bitte bring deinen Ausweis und eine unterschriebene Kopie des Vertrags mit."],
          Hindi: ["टीम में आपका स्वागत है!", "आपका पहला दिन सोमवार सुबह 9 बजे है।", "कृपया अपना पहचान पत्र और अनुबंध की हस्ताक्षरित प्रति साथ लाएँ।"],
          Japanese: ["チームへようこそ！", "初日は月曜日の午前9時です。", "身分証明書と署名済みの契約書を1部お持ちください。"],
        };
        var pick = "Spanish";
        st.innerHTML = body("Translate", ["Welcome letter.pdf", "Tools", "Translate…"],
          '<div class="tl"><div class="tl-doc"><small>English</small>' + EN.map(function (l) { return "<p>" + l + "</p>"; }).join("") + '</div>' + ARROW + '<div class="tl-doc out" id="s-tl"><small id="s-lang">Spanish</small>' + EN.map(function () { return '<p class="tl-blank"></p>'; }).join("") + "</div></div>",
          seg("l", ["Spanish", "French", "German", "Hindi", "Japanese"], pick) + goRow("Translate"), "Uses Apple's translation on your Mac, so the letter never leaves it. Needs macOS 15.");
        var outDoc = st.querySelector("#s-tl"), lang = st.querySelector("#s-lang");
        function blank() { lang.textContent = pick; outDoc.querySelectorAll("p").forEach(function (p) { p.className = "tl-blank"; p.textContent = ""; }); }
        wireSeg(st, "l", function (v) { pick = v; blank(); out(st, ""); });
        go(st, async function () {
          blank();
          var ps = outDoc.querySelectorAll("p");
          for (var i = 0; i < ps.length; i++) {
            await wait(reduce ? 0 : 380);
            ps[i].className = "tl-in"; ps[i].textContent = L[pick][i];
          }
          out(st, chipMade("Welcome letter (" + pick + ").txt", "Translated on your Mac, next to the PDF"));
        });
      },
      summarize: function (st) {
        var PARAS = [
          "Revenue for the third quarter reached $4.2 million, up 18% from the second quarter. Most of the growth came from the Pro plan, which now makes up 61% of new sign-ups.",
          "Costs rose 6%, mainly from two new support hires and higher hosting bills during the September launch. Gross margin held steady at 78%.",
          "Customer churn fell from 3.1% to 2.4% a month after the onboarding redesign. Average response time for support tickets dropped to under four hours.",
          "For the fourth quarter, the team plans to launch the Windows beta in November, raise the Pro price for new customers in January, and hire a second designer.",
          "Risks include a slower holiday season and a dependency on one payments provider. The board asked for a review of both by the end of December.",
        ];
        var SUM = ["Revenue up 18% to $4.2M, driven by the Pro plan.", "Churn fell to 2.4% a month after the onboarding redesign.", "Q4: Windows beta in November, Pro price rise in January."];
        st.innerHTML = body("Summarize", ["Q3 report.pdf", "Tools", "Summarize"],
          '<div class="sm"><div class="sm-doc">' + PARAS.map(function (p) { return "<p>" + p + "</p>"; }).join("") + '</div><div class="sm-out" id="s-sum"><small>Summary</small><ul></ul></div></div>',
          goRow("Summarize"), "Apple Intelligence reads the document on your Mac and gives you the gist. Needs a Mac with Apple Intelligence on macOS 26.");
        var ul = st.querySelector("#s-sum ul");
        go(st, async function () {
          ul.innerHTML = "";
          st.querySelector(".sm-doc").classList.add("reading");
          await bar(st, 1100);
          st.querySelector(".sm-doc").classList.remove("reading");
          for (var i = 0; i < SUM.length; i++) {
            var li = document.createElement("li");
            ul.appendChild(li);
            var t = SUM[i];
            if (reduce) li.textContent = t;
            else for (var k = 1; k <= t.length; k += 2) { li.textContent = t.slice(0, k); await wait(12); }
            li.textContent = t;
          }
          out(st, chipMade("Q3 report (summary).txt", "Next to the PDF"));
        });
      },
    };

    // The six tools that also live on the desktop above reuse those demos.
    ["clean", "cutout", "merge", "sign", "compress", "transcribe"].forEach(function (k) { DEMOS[k] = function (st) { if (closeDeskWindow) closeDeskWindow(); TOOLS[k](st); }; });

    var cat = CATS[0], toolId = cat.tools[0][1], touched = false;
    function drawCats() {
      catsEl.innerHTML = CATS.map(function (c) {
        return '<button type="button" class="cat" role="tab" aria-selected="' + (c === cat) + '" data-c="' + c.id + '"><svg aria-hidden="true"><use href="#' + c.icon + '"/></svg>' + c.name + '<span class="n">' + c.tools.length + "</span></button>";
      }).join("");
      chipsEl.innerHTML = cat.tools.map(function (t) {
        return '<button type="button" class="tchip" aria-pressed="' + (t[1] === toolId) + '" data-t="' + t[1] + '">' + t[0] + "</button>";
      }).join("");
    }
    function show(id) {
      cleanup();
      toolId = id;
      chipsEl.querySelectorAll(".tchip").forEach(function (b) { b.setAttribute("aria-pressed", String(b.getAttribute("data-t") === id)); });
      stage.classList.remove("swap"); void stage.offsetWidth; stage.classList.add("swap");
      DEMOS[id](stage);
    }
    catsEl.addEventListener("click", function (e) {
      var b = e.target.closest(".cat"); if (!b) return;
      touched = true;
      cat = CATS.filter(function (c) { return c.id === b.getAttribute("data-c"); })[0];
      toolId = cat.tools[0][1];
      drawCats(); show(toolId);
    });
    chipsEl.addEventListener("click", function (e) {
      var b = e.target.closest(".tchip"); if (!b) return;
      touched = true;
      show(b.getAttribute("data-t"));
    });
    stage.addEventListener("pointerdown", function () { touched = true; });
    drawCats();
    show(toolId);
    // When it first comes into view, the first tool runs on its own so it's obvious these are live.
    onView(stage, function () {
      setTimeout(function () {
        if (touched || toolId !== "convertImg") return;
        var b = stage.querySelector("[data-go]");
        if (b) b.click();
      }, reduce ? 0 : 700);
    }, 0.5);
  }

  pile();
  storyClock();
  recallField();
  desk();
  cleanup();
  stack();
  plug();
  flips();
  receipt();
  studio();
})();
