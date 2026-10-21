// Shared behaviour for every page: the phone menu, Buy and Download buttons, the toast, the phone buy bar,
// the launch offer and "buy now, install on your Mac later" for people who aren't on a Mac.
(function () {
  "use strict";
  var cfg = window.HAVEN || {};

  // Toast
  var toastEl = document.getElementById("toast");
  var toastTimer;
  window.havenToast = function (html, ms) {
    if (!toastEl) return;
    toastEl.innerHTML = html;
    toastEl.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toastEl.classList.remove("show"); }, ms || 4200);
  };

  // Phone menu
  var nav = document.querySelector(".gnav");
  var menuBtn = nav && nav.querySelector(".menu-btn");
  if (menuBtn) {
    menuBtn.addEventListener("click", function () {
      var open = !nav.hasAttribute("data-open");
      nav.toggleAttribute("data-open", open);
      menuBtn.setAttribute("aria-expanded", String(open));
      document.documentElement.style.overflow = open ? "hidden" : "";
    });
    nav.querySelectorAll(".menu-sheet a").forEach(function (a) {
      a.addEventListener("click", function () {
        nav.removeAttribute("data-open");
        menuBtn.setAttribute("aria-expanded", "false");
        document.documentElement.style.overflow = "";
      });
    });
  }

  // Not on a Mac (a phone, a tablet, a PC at work): "buy now, install on your Mac later" replaces Mac-only wording.
  var ua = navigator.userAgent || "";
  var iPadAsMac = /Macintosh/.test(ua) && navigator.maxTouchPoints > 1;
  var onMac = /Macintosh/.test(ua) && !iPadAsMac;
  var root = document.documentElement;
  if (!onMac) root.classList.add("away");
  if (iPadAsMac || /iPhone|iPad|iPod|Android|Mobile/.test(ua)) root.classList.add("phone");
  if (!onMac) {
    document.querySelectorAll("[data-away]").forEach(function (el) { el.innerHTML = el.getAttribute("data-away"); });
  }

  // "Send to my Mac": the share sheet (AirDrop, Messages, Mail to yourself), or the link copied.
  document.querySelectorAll("[data-send]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var url = new URL(btn.getAttribute("data-send") || location.pathname, location.href).href.split("#")[0];
      var share = { title: "Haven for Mac", text: "Haven: find any file on your Mac by describing it.", url: url };
      if (navigator.share) {
        navigator.share(share).catch(function () {});
        return;
      }
      var copied = function () { window.havenToast("Link copied. Open it on your Mac, or send it there with AirDrop or Messages."); };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(url).then(copied, function () { window.havenToast("Open this address on your Mac: <code>" + url + "</code>", 8000); });
      } else {
        window.havenToast("Open this address on your Mac: <code>" + url + "</code>", 8000);
      }
    });
  });

  // How checkout works, in the provider's own terms.
  var co = cfg.checkout || {};
  if (co.provider) {
    var line = "Secure checkout by " + co.provider + (co.payWith ? " · " + co.payWith : "") +
      (co.localCurrency ? " · pay in your own currency" : " · prices in US dollars") + " · tax handled for you";
    document.querySelectorAll("[data-payline]").forEach(function (el) { el.textContent = line; });
    document.querySelectorAll("[data-provider]").forEach(function (el) { el.textContent = co.provider; });
  }

  // The launch offer shows only while it's on (and until its last day, if it has one).
  var launch = cfg.launch || {};
  var endsOn = launch.endsOn ? new Date(launch.endsOn + "T23:59:59") : null;
  if (launch.on && (!endsOn || isNaN(endsOn) || endsOn >= new Date())) {
    document.querySelectorAll("[data-launch]").forEach(function (el) { el.hidden = false; });
    if (endsOn && !isNaN(endsOn)) {
      var day = endsOn.toLocaleDateString("en-US", { month: "long", day: "numeric" });
      document.querySelectorAll("[data-launch-until]").forEach(function (el) { el.textContent = ", if you buy by " + day; });
    }
  }

  // Buy buttons go straight to checkout when a plan's link is set.
  var planNames = { one: "1 Mac", three: "3 Macs", five: "5 Macs" };
  document.querySelectorAll("[data-buy]").forEach(function (a) {
    var plan = a.getAttribute("data-buy");
    var url = co[plan];
    if (url) {
      a.href = url;
      return;
    }
    a.addEventListener("click", function (e) {
      e.preventDefault();
      window.havenToast("Checkout for " + planNames[plan] + " isn't connected yet. Add its checkout link in <code>assets/config.js</code>.");
    });
  });

  // The download button on the download page uses the DMG link when it is set.
  document.querySelectorAll("[data-dmg]").forEach(function (a) {
    if (cfg.downloadURL) {
      a.href = cfg.downloadURL;
      return;
    }
    a.addEventListener("click", function (e) {
      e.preventDefault();
      window.havenToast("The download link isn't set yet. Add the DMG's address in <code>assets/config.js</code>.");
    });
  });

  // Support addresses, shown as text (with a copy button) because mail links don't open everywhere.
  document.querySelectorAll("[data-email]").forEach(function (el) {
    var which = el.getAttribute("data-email");
    var address = which === "privacy" ? cfg.privacyEmail : cfg.supportEmail;
    if (address) el.textContent = address;
  });
  document.querySelectorAll("[data-copy-email]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var target = document.getElementById(btn.getAttribute("data-copy-email"));
      var text = target ? target.textContent : "";
      var done = function () { btn.textContent = "Copied"; setTimeout(function () { btn.textContent = "Copy"; }, 1600); };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () { selectText(target); });
      } else {
        selectText(target);
      }
    });
  });
  function selectText(el) {
    if (!el) return;
    var r = document.createRange();
    r.selectNodeContents(el);
    var sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(r);
  }

  // Phone buy bar: appears once the first call to action has scrolled away.
  var bar = document.getElementById("buybar");
  var firstCta = document.querySelector(".cta-row, .plans, .dl, .page-hero");
  if (bar && firstCta && "IntersectionObserver" in window) {
    var footer = document.querySelector(".foot");
    var pastCta = false, atFooter = false, quiet = 0;
    var update = function () { bar.classList.toggle("show", pastCta && !atFooter && !quiet); };
    // Sections marked data-nobar keep the bar out of the way (the twelve-apps total sits at the bottom).
    document.querySelectorAll("[data-nobar]").forEach(function (zone) {
      var inZone = false;
      new IntersectionObserver(function (entries) {
        var now = entries[0].isIntersecting;
        if (now !== inZone) { quiet += now ? 1 : -1; inZone = now; update(); }
      }).observe(zone);
    });
    new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.target === firstCta) pastCta = !en.isIntersecting && en.boundingClientRect.top < 0;
        if (en.target === footer) atFooter = en.isIntersecting;
      });
      update();
    }).observe(firstCta);
    if (footer) {
      new IntersectionObserver(function (entries) {
        atFooter = entries[0].isIntersecting;
        update();
      }).observe(footer);
    }
  }

  // The header turns dark while it sits over a night section.
  var nights = Array.prototype.slice.call(document.querySelectorAll(".night"));
  if (nav && nights.length) {
    var navTicking = false;
    var checkNight = function () {
      navTicking = false;
      var y = nav.getBoundingClientRect().bottom;
      var over = nights.some(function (s) { var r = s.getBoundingClientRect(); return r.top <= y + 2 && r.bottom >= y; });
      nav.classList.toggle("on-night", over);
    };
    window.addEventListener("scroll", function () { if (!navTicking) { navTicking = true; requestAnimationFrame(checkNight); } }, { passive: true });
    checkNight();
  }

  // Marker highlights draw themselves when they come into view.
  var marks = document.querySelectorAll(".mark");
  if (marks.length && "IntersectionObserver" in window && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    document.documentElement.classList.add("marks-ready");
    var mio = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add("in"); mio.unobserve(e.target); } });
    }, { threshold: 0.8 });
    marks.forEach(function (m) { mio.observe(m); });
  }

  // Open the FAQ answer named in the address (faq.html#licenses).
  var openFromHash = function () {
    var id = location.hash.slice(1);
    if (!id) return;
    var el = document.getElementById(id);
    if (el && el.tagName === "DETAILS") el.open = true;
  };
  openFromHash();
  window.addEventListener("hashchange", openFromHash);
})();
