// The working demos on the home page. Everything here is sample data drawn in the browser; nothing is uploaded.
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

  function fileCard(f, terms) {
    var hit = "";
    if (terms.length) {
      var inName = terms.every(function (t) { return norm(f.n).indexOf(t) >= 0; });
      if (!inName && f.said && terms.some(function (t) { return norm(f.said).indexOf(t) >= 0; })) {
        hit = '<div class="hit"><b>Said at ' + f.saidAt + ":</b> " + snippet(f.said, terms) + "</div>";
      } else if (!inName && f.text) {
        var sn = snippet(f.text, terms);
        if (sn) hit = '<div class="hit"><b>' + (f.k === "photo" || f.k === "shot" || f.k === "image" ? "In the picture" : "In the text") + ":</b> " + sn + "</div>";
      }
    }
    return '<div class="file">' + thumb(f) + '<div class="nm" title="' + esc(f.n) + '">' + esc(f.n) + '</div><div class="mt">' + size(f.mb) + " · " + when(f.d) + "</div>" + hit + "</div>";
  }

  function heroSearch() {
    var input = $("hero-q"), readas = $("hero-readas"), results = $("hero-results"), count = $("hero-count");
    if (!input) return;
    var tryBtns = Array.prototype.slice.call(document.querySelectorAll("#hero-try button"));
    var maxCards = function () {
      var w = results.clientWidth || 600;
      var cols = window.innerWidth < 560 ? 2 : Math.max(2, Math.floor((w + 14) / (150 + 14)));
      return cols * 2;
    };

    function render() {
      var q = input.value.trim();
      tryBtns.forEach(function (b) { b.setAttribute("aria-pressed", String(b.textContent === q)); });
      if (!q) {
        readas.innerHTML = "<span>Type what you remember: a kind of file, when, how big, where it came from, or words inside it.</span>";
        count.textContent = "";
        results.innerHTML = FILES.slice().sort(function (a, b) { return a.d - b.d; }).slice(0, maxCards()).map(function (f) { return fileCard(f, []); }).join("");
        return;
      }
      var r = search(q);
      readas.innerHTML = (r.parts.length ? "<span>Haven read this as</span>" : "") + r.parts.map(function (p, i) {
        return '<span class="chip k-' + p.type + '">' + esc(p.label) + '<button type="button" aria-label="Remove ' + esc(p.label) + '" data-i="' + i + '">×</button></span>';
      }).join("");
      readas.querySelectorAll("button").forEach(function (b) {
        b.addEventListener("click", function () {
          stopAuto();
          var p = r.parts[+b.getAttribute("data-i")];
          var idx = input.value.toLowerCase().indexOf(p.raw);
          if (idx >= 0) input.value = (input.value.slice(0, idx) + input.value.slice(idx + p.raw.length)).replace(/\s+/g, " ").trim();
          render();
        });
      });
      var total = r.list.reduce(function (s, f) { return s + f.mb; }, 0);
      count.textContent = r.list.length ? r.list.length + (r.list.length === 1 ? " item · " : " items · ") + size(total) : "";
      var terms = r.parts.filter(function (p) { return p.type === "text"; }).map(function (p) { return p.term; });
      results.innerHTML = r.list.length
        ? r.list.slice(0, maxCards()).map(function (f) { return fileCard(f, terms); }).join("")
        : '<div class="empty" style="grid-column:1/-1"><b>Nothing matches “' + esc(q) + '” in this sample library.</b><br>Try “screenshots over 5 MB” or “videos from zoom”.</div>';
    }

    var debounce;
    input.addEventListener("input", function () { stopAuto(); clearTimeout(debounce); debounce = setTimeout(render, 140); });
    input.addEventListener("focus", stopAuto);
    tryBtns.forEach(function (b) {
      b.addEventListener("click", function () { stopAuto(); input.value = b.textContent; render(); });
    });
    render();

    // Types the example searches one after another until someone interacts.
    var auto = !reduce, visible = false, queue = tryBtns.map(function (b) { return b.textContent; }), qi = 0, busy = false;
    function stopAuto() { auto = false; }
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (es) { visible = es[0].isIntersecting; }, { threshold: 0.4 }).observe($("hero-mac"));
    }
    async function loop() {
      await wait(3600);
      while (auto) {
        if (!visible || document.hidden || busy) { await wait(800); continue; }
        busy = true;
        qi = (qi + 1) % queue.length;
        var text = queue[qi];
        input.value = "";
        for (var i = 1; i <= text.length && auto; i++) {
          input.value = text.slice(0, i);
          await wait(38 + Math.random() * 40);
        }
        if (!auto) break;
        render();
        busy = false;
        await wait(3800);
      }
    }
    if (auto) loop();
    var lastMax = maxCards();
    window.addEventListener("resize", function () {
      var m = maxCards();
      if (m !== lastMax && !busy) { lastMax = m; render(); }
    });
  }

  // ---------------------------------------------------------------- Search lenses
  var CUES = [
    ["00:04:01,200", "Morning, everyone. Let's start with the launch."],
    ["00:04:06,800", "Beta invites go out on Monday."],
    ["00:04:12,400", "We need to move the budget review to Thursday."],
    ["00:04:17,900", "Priya will send the final pricing by Friday."],
    ["00:04:23,300", "And the onboarding video is ready for review."],
    ["00:04:28,600", "Great. Same time next week."],
  ];
  var SOURCES = [
    { n: "WhatsApp", c: "#25a35a", ct: 1038, files: [["Beach day.jpg", "3 days ago"], ["Dinner.jpg", "5 days ago"], ["IMG_2207.HEIC", "8 days ago"], ["Voice message 14.opus", "2 weeks ago"]] },
    { n: "Gmail", c: "#d93025", ct: 214, files: [["Budget 2026.xlsx", "7 days ago"], ["Q3 report.pdf", "8 days ago"], ["Invoice 4821.pdf", "9 days ago"], ["Resume.docx", "2 months ago"]] },
    { n: "Slack", c: "#7a2f7f", ct: 342, files: [["Pitch deck.key", "11 days ago"], ["Product demo.mp4", "3 weeks ago"], ["Brand assets.zip", "a month ago"], ["Roadmap.pdf", "2 months ago"]] },
    { n: "ChatGPT", c: "#10a37f", ct: 61, files: [["ChatGPT Image.png", "7 days ago"], ["sales-by-region.csv", "2 weeks ago"], ["Itinerary.docx", "a month ago"], ["Cover letter.pdf", "3 months ago"]] },
    { n: "AirDrop", c: "#1e88e5", ct: 127, files: [["IMG_4021.HEIC", "yesterday"], ["IMG_3988.MOV", "6 days ago"], ["Mountains.heic", "7 months ago"], ["Contacts.vcf", "8 months ago"]] },
    { n: "Google Drive", c: "#1a73e8", ct: 89, files: [["Lease agreement.pdf", "6 weeks ago"], ["Wedding highlights.mp4", "a year ago"], ["Tax return 2025.pdf", "6 months ago"], ["Floor plan.png", "8 months ago"]] },
    { n: "Zoom", c: "#2d8cff", ct: 23, files: [["Team call.mov", "3 days ago"], ["Client kickoff.m4a", "3 weeks ago"], ["All hands.mp4", "2 months ago"], ["Interview.mp4", "4 months ago"]] },
    { n: "Figma", c: "#a259ff", ct: 47, files: [["Logo concepts.png", "6 days ago"], ["Onboarding flow.pdf", "4 weeks ago"], ["Icons.svg", "2 months ago"], ["Figma installer.dmg", "4 months ago"]] },
    { n: "Any website", c: "#6b6878", ct: 2310, files: [["Figma installer.dmg", "4 months ago"], ["Podcast episode 12.m4a", "2 weeks ago"], ["Recipe.pdf", "a month ago"], ["Font pack.zip", "5 months ago"]] },
  ];

  function lenses() {
    var tabs = Array.prototype.slice.call(document.querySelectorAll("#lens-tabs [role=tab]"));
    if (!tabs.length) return;
    var cueBox = $("speech-cues");
    cueBox.innerHTML = CUES.map(function (c, i) {
      return '<div class="cue' + (i === 2 ? " on" : "") + '"><time>' + c[0].slice(3, 8) + "</time><span>" + esc(c[1]).replace("budget", "<mark>budget</mark>") + "</span></div>";
    }).join("");

    var srcs = $("srcs"), list = $("src-list");
    srcs.innerHTML = SOURCES.map(function (s, i) {
      return '<button class="src" type="button" aria-pressed="' + (i === 0) + '" data-i="' + i + '"><span class="dot" style="background:' + s.c + '">' + s.n[0] + "</span>" + s.n + ' <span class="n">' + s.ct.toLocaleString("en-US") + "</span></button>";
    }).join("");
    var showSource = function (i) {
      srcs.querySelectorAll(".src").forEach(function (b) { b.setAttribute("aria-pressed", String(+b.getAttribute("data-i") === i)); });
      list.innerHTML = SOURCES[i].files.map(function (f, j) { return '<li style="animation-delay:' + j * 40 + 'ms"><span>' + esc(f[0]) + "</span><span>" + f[1] + "</span></li>"; }).join("");
    };
    srcs.addEventListener("click", function (e) { var b = e.target.closest(".src"); if (b) showSource(+b.getAttribute("data-i")); });
    showSource(0);

    async function typeInto(el, text) {
      if (reduce) { el.textContent = text; return; }
      el.textContent = "";
      for (var i = 1; i <= text.length; i++) { el.textContent = text.slice(0, i); await wait(55); }
    }
    var token = 0;
    async function play(id) {
      var my = ++token;
      if (id === "lens-image") {
        var hit = $("wb-hit");
        hit.classList.remove("hl");
        await typeInto($("lq-image"), "launch plan");
        if (my === token) { await wait(150); hit.classList.add("hl"); }
      } else if (id === "lens-speech") {
        var cues = cueBox.querySelectorAll(".cue");
        cues.forEach(function (c) { c.classList.remove("on"); });
        await typeInto($("lq-speech"), "budget");
        if (my === token) { await wait(150); cues[2].classList.add("on"); }
      }
    }
    tabs.forEach(function (t, i) {
      t.addEventListener("click", function () { select(i); });
      t.addEventListener("keydown", function (e) {
        if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
          var n = (i + (e.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length;
          tabs[n].focus();
          select(n);
        }
      });
    });
    function select(i) {
      tabs.forEach(function (t, j) {
        t.setAttribute("aria-selected", String(i === j));
        t.tabIndex = i === j ? 0 : -1;
        $(t.getAttribute("aria-controls")).hidden = i !== j;
      });
      play(tabs[i].getAttribute("aria-controls"));
    }
    tabs.forEach(function (t, j) { t.tabIndex = j === 0 ? 0 : -1; });
  }

  // ---------------------------------------------------------------- File Tools
  function shell(title, path, body) {
    return '<div class="mac"><div class="mac-main"><div class="mac-bar"><div class="lights" aria-hidden="true"><i></i><i></i><i></i></div><span class="mac-title">' + title + '</span></div><div class="mac-body"><div class="ctx" aria-label="Chosen from the right-click menu">' +
      path.map(function (p, i) { return (i ? "<i>›</i>" : "") + "<span>" + esc(p) + "</span>"; }).join("") + "</div>" + body + "</div></div></div>";
  }
  function made(name, detail) {
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

  function tools() {
    var pick = $("tool-pick"), stage = $("tool-stage");
    if (!pick) return;
    var btns = Array.prototype.slice.call(pick.querySelectorAll("button"));
    function select(btn) {
      btns.forEach(function (b) { b.setAttribute("aria-selected", String(b === btn)); b.tabIndex = b === btn ? 0 : -1; });
      TOOLS[btn.getAttribute("data-tool")](stage);
    }
    btns.forEach(function (b, i) {
      b.addEventListener("click", function () { select(b); });
      b.addEventListener("keydown", function (e) {
        var k = e.key, n = null;
        if (k === "ArrowDown" || k === "ArrowRight") n = btns[(i + 1) % btns.length];
        if (k === "ArrowUp" || k === "ArrowLeft") n = btns[(i + btns.length - 1) % btns.length];
        if (n) { e.preventDefault(); n.focus(); select(n); }
      });
    });
    select(btns[0]);
  }

  // ---------------------------------------------------------------- Clean Up
  function cleanup() {
    var cardsEl = $("clean-cards");
    if (!cardsEl) return;
    var TOTAL = 494.4, USED = 431.2;
    var groups = [
      { id: "videos", n: "Big Old Videos", gb: 18.4, items: 6, c: "#df5a90", icon: "i-film", note: "Unopened for a year", on: false },
      { id: "downloads", n: "Forgotten Downloads", gb: 7.9, items: 142, c: "#3b82d6", icon: "i-download", note: "Unopened, 90+ days", on: true },
      { id: "installers", n: "Old Installers", gb: 4.6, items: 23, c: "#e39a2d", icon: "i-box", note: "Apps stay installed", on: true },
      { id: "dups", n: "Duplicates", gb: 3.2, items: 61, c: "#6a4df2", icon: "i-dup", note: "Best copy kept", on: false },
      { id: "zips", n: "Already Unzipped", gb: 2.7, items: 9, c: "#2f9e6b", icon: "i-archive", note: "Already extracted", on: true },
      { id: "shots", n: "Old Screenshots", gb: 1.3, items: 288, c: "#8b8898", icon: "i-shot", note: "Over 30 days old", on: false },
    ];
    var trashed = [];
    var go = $("clean-go"), sum = $("clean-sum"), bar = $("disk-bar"), legend = $("disk-legend"), free = $("disk-free");
    var toast = $("clean-toast"), toastMsg = $("clean-toast-msg"), toastTimer;

    function draw() {
      cardsEl.innerHTML = groups.map(function (g) {
        var done = trashed.indexOf(g.id) >= 0;
        return '<button type="button" class="ccard' + (done ? " done" : "") + '" style="--c:' + g.c + '" aria-pressed="' + (g.on && !done) + '" data-id="' + g.id + '"><span class="ic"><svg aria-hidden="true"><use href="#' + g.icon + '"/></svg></span><span><b>' + g.n + "</b><small>" + (done ? "In the Trash" : g.items + " items · " + g.note) + '</small></span><span><span class="sz">' + g.gb.toFixed(1) + ' GB</span><span class="ck"></span></span></button>';
      }).join("");
      var sel = groups.filter(function (g) { return g.on && trashed.indexOf(g.id) < 0; });
      var selGB = sel.reduce(function (s, g) { return s + g.gb; }, 0);
      var inTrash = groups.filter(function (g) { return trashed.indexOf(g.id) >= 0; }).reduce(function (s, g) { return s + g.gb; }, 0);
      var pct = function (gb) { return (gb / TOTAL * 100).toFixed(2) + "%"; };
      bar.innerHTML = '<i style="width:' + pct(USED - selGB - inTrash) + ';background:var(--win-ink-2);opacity:.55"></i><i style="width:' + pct(selGB) + ';background:var(--accent)"></i><i style="width:' + pct(inTrash) + ';background:repeating-linear-gradient(45deg,var(--ok) 0 4px,color-mix(in srgb,var(--ok) 55%,transparent) 4px 8px)"></i>';
      legend.innerHTML = '<span style="--c:var(--win-ink-2)">Used</span>' + (selGB ? '<span style="--c:var(--accent)">Selected ' + selGB.toFixed(1) + " GB</span>" : "") + (inTrash ? '<span style="--c:var(--ok)">In the Trash ' + inTrash.toFixed(1) + " GB</span>" : "") + '<span style="--c:var(--win-field)">Free</span>';
      free.textContent = (TOTAL - USED).toFixed(1) + " GB free";
      go.disabled = !sel.length;
      go.textContent = sel.length ? "Move " + sel.length + (sel.length === 1 ? " group" : " groups") + " to Trash" : "Move to Trash";
      sum.textContent = sel.length ? selGB.toFixed(1) + " GB selected · you'll review each file first" : (trashed.length ? inTrash.toFixed(1) + " GB is in the Trash, ready to empty" : "Pick what to clear");
    }
    cardsEl.addEventListener("click", function (e) {
      var b = e.target.closest(".ccard"); if (!b) return;
      var g = groups.filter(function (x) { return x.id === b.getAttribute("data-id"); })[0];
      g.on = !g.on; draw();
    });
    var last = [];
    go.addEventListener("click", function () {
      var sel = groups.filter(function (g) { return g.on && trashed.indexOf(g.id) < 0; });
      if (!sel.length) return;
      last = sel.map(function (g) { return g.id; });
      trashed = trashed.concat(last);
      var items = sel.reduce(function (s, g) { return s + g.items; }, 0);
      draw();
      toastMsg.textContent = "Moved " + items + " items to the Trash";
      toast.classList.add("show");
      clearTimeout(toastTimer);
      toastTimer = setTimeout(function () { toast.classList.remove("show"); }, 6000);
    });
    $("clean-undo").addEventListener("click", function () {
      trashed = trashed.filter(function (id) { return last.indexOf(id) < 0; });
      last = [];
      toast.classList.remove("show");
      draw();
    });
    draw();
  }

  // ---------------------------------------------------------------- Smart Rename
  function rename() {
    var input = $("rn-input"), list = $("rn-list");
    if (!input) return;
    var FILESR = [
      { name: "scan0003", ext: "pdf", title: "Invoice 4821", d: 9, src: "Gmail", kind: "PDF" },
      { name: "scan0004", ext: "pdf", title: "Lease Agreement", d: 41, src: "Google Drive", kind: "PDF" },
      { name: "IMG_4021", ext: "HEIC", title: null, d: 1, src: "AirDrop", kind: "Photo" },
      { name: "Screenshot " + ymd(ago(4)) + " at 09.41.22", ext: "png", title: "Wi-Fi Password", d: 4, src: "", kind: "Screenshot" },
      { name: "Document (2)", ext: "docx", title: "Quarterly Plan", d: 16, src: "Gmail", kind: "Document" },
    ];
    function apply(pattern) {
      var seen = {};
      return FILESR.map(function (f, i) {
        var base = pattern.replace(/\{(\w+)(?::(\d+))?\}/g, function (m, tok, width) {
          switch (tok) {
            case "date": return ymd(ago(f.d));
            case "time": return "14.05";
            case "name": return f.name;
            case "title": return f.title || f.name;
            case "n": { var s = String(i + 1); while (width && s.length < +width) s = "0" + s; return s; }
            case "source": return f.src || "";
            case "kind": return f.kind;
            case "folder": return "Downloads";
            default: return m;
          }
        }).replace(/[\/:]/g, "-").replace(/\s+/g, " ").replace(/^[\s–-]+|[\s–-]+$/g, "").trim();
        if (!base) base = f.name;
        var full = base + "." + f.ext, k = full.toLowerCase(), n = 2;
        while (seen[k]) { full = base + " " + n + "." + f.ext; k = full.toLowerCase(); n++; }
        seen[k] = true;
        return [f.name + "." + f.ext, full];
      });
    }
    function draw() {
      list.innerHTML = apply(input.value).map(function (r) {
        return '<li><span class="old" title="' + esc(r[0]) + '">' + esc(r[0]) + '</span><span class="arrow" aria-hidden="true">→</span><span class="new" title="' + esc(r[1]) + '">' + esc(r[1]) + "</span></li>";
      }).join("");
      document.querySelectorAll("#rn-presets .opt").forEach(function (b) { b.setAttribute("aria-pressed", String(b.getAttribute("data-p") === input.value)); });
    }
    input.addEventListener("input", draw);
    $("rn-presets").addEventListener("click", function (e) {
      var b = e.target.closest(".opt"); if (!b) return;
      input.value = b.getAttribute("data-p"); draw();
    });
    $("rn-tokens").addEventListener("click", function (e) {
      var b = e.target.closest("button"); if (!b) return;
      var s = input.selectionStart == null ? input.value.length : input.selectionStart, t = input.selectionEnd == null ? s : input.selectionEnd;
      var token = b.textContent, before = input.value.slice(0, s), after = input.value.slice(t);
      var sep = before && !/\s$/.test(before) ? " " : "";
      input.value = before + sep + token + after;
      var pos = (before + sep + token).length;
      input.focus(); input.setSelectionRange(pos, pos);
      draw();
    });
    draw();
  }

  // ---------------------------------------------------------------- Quick Search
  function quickSearch() {
    var openBtn = $("qs-open");
    if (!openBtn) return;
    var scrim = null, lastFocus = null;
    function open() {
      if (scrim) return;
      lastFocus = document.activeElement;
      scrim = document.createElement("div");
      scrim.className = "qs-scrim";
      scrim.innerHTML = '<div class="qs" role="dialog" aria-modal="true" aria-label="Quick Search"><label class="qs-field"><svg aria-hidden="true"><use href="#i-search"/></svg><span class="sr">Search</span><input id="qs-input" type="text" autocomplete="off" spellcheck="false" placeholder="Search your Mac"></label><ul class="qs-list" id="qs-list" role="listbox"></ul><div class="qs-foot"><span><kbd>↩</kbd> Open</span><span><kbd>⌘</kbd><kbd>↩</kbd> Show in Haven</span><span><kbd>⌥</kbd><kbd>↩</kbd> Show in Finder</span><span><kbd>esc</kbd> Close</span></div></div>';
      document.body.appendChild(scrim);
      var input = scrim.querySelector("input"), list = scrim.querySelector("#qs-list"), sel = 0, rows = [];
      function draw() {
        var q = input.value.trim();
        rows = q ? search(q).list.slice(0, 7) : FILES.slice().sort(function (a, b) { return a.d - b.d; }).slice(0, 6);
        sel = Math.min(sel, Math.max(0, rows.length - 1));
        list.innerHTML = rows.length ? rows.map(function (f, i) {
          return '<li role="option" aria-selected="' + (i === sel) + '" data-i="' + i + '"><span class="mini">' + thumb(f, true) + "</span><span><b>" + esc(f.n) + "</b><small>" + (f.src ? "From " + esc(f.src) + " · " : "") + when(f.d) + "</small></span><small>" + size(f.mb) + "</small></li>";
        }).join("") : '<li aria-disabled="true"><span></span><span><b>No matches</b><small>Try “invoice” or “videos from zoom”</small></span></li>';
      }
      function choose(how) {
        var f = rows[sel]; if (!f) return;
        var verb = how === "finder" ? "shows it in Finder" : how === "haven" ? "shows it in Haven" : "opens it";
        window.havenToast("In Haven, this " + verb + ": “" + esc(f.n) + "”");
        close();
      }
      input.addEventListener("input", function () { sel = 0; draw(); });
      input.addEventListener("keydown", function (e) {
        if (e.key === "ArrowDown") { sel = Math.min(rows.length - 1, sel + 1); draw(); e.preventDefault(); }
        else if (e.key === "ArrowUp") { sel = Math.max(0, sel - 1); draw(); e.preventDefault(); }
        else if (e.key === "Enter") { choose(e.metaKey ? "haven" : e.altKey ? "finder" : "open"); e.preventDefault(); }
        else if (e.key === "Tab") { e.preventDefault(); }
      });
      list.addEventListener("click", function (e) { var li = e.target.closest("li[data-i]"); if (li) { sel = +li.getAttribute("data-i"); choose("open"); } });
      scrim.addEventListener("mousedown", function (e) { if (e.target === scrim) close(); });
      draw();
      input.focus();
    }
    function close() {
      if (!scrim) return;
      scrim.remove(); scrim = null;
      if (lastFocus && lastFocus.focus) lastFocus.focus();
    }
    openBtn.addEventListener("click", open);
    document.addEventListener("keydown", function (e) {
      if ((e.metaKey || e.ctrlKey) && e.shiftKey && (e.code === "Space" || e.key === " ")) { e.preventDefault(); scrim ? close() : open(); }
      else if (e.key === "Escape" && scrim) close();
    });
  }

  // ---------------------------------------------------------------- Looks
  function looks() {
    var img = $("look-img");
    if (!img) return;
    var state = { style: "playful", mode: "light" };
    ["look-style", "look-mode"].forEach(function (id) {
      var group = $(id), key = id === "look-style" ? "style" : "mode";
      group.addEventListener("click", function (e) {
        var b = e.target.closest("button"); if (!b) return;
        state[key] = b.getAttribute("data-v");
        group.querySelectorAll("button").forEach(function (x) { x.setAttribute("aria-checked", String(x === b)); });
        img.src = "assets/img/look-" + state.style + "-" + state.mode + ".webp";
        img.alt = "Haven's Home screen in the " + (state.style === "playful" ? "Playful" : "Minimal") + " look, " + state.mode + " appearance";
      });
    });
    // Load the other three so switching is instant.
    ["playful-dark", "minimal-light", "minimal-dark"].forEach(function (n) { var i = new Image(); i.src = "assets/img/look-" + n + ".webp"; });
  }

  heroSearch();
  lenses();
  tools();
  cleanup();
  rename();
  quickSearch();
  looks();
})();
