// Shared behaviour for every page: the phone menu, Buy and Download buttons, the toast and the phone buy bar.
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

  // Buy buttons go straight to Stripe when a Payment Link is set.
  var planNames = { one: "1 Mac", three: "3 Macs", five: "5 Macs" };
  document.querySelectorAll("[data-buy]").forEach(function (a) {
    var plan = a.getAttribute("data-buy");
    var url = cfg.checkout && cfg.checkout[plan];
    if (url) {
      a.href = url;
      return;
    }
    a.addEventListener("click", function (e) {
      e.preventDefault();
      window.havenToast("Checkout for " + planNames[plan] + " isn't connected yet. Add its Stripe Payment Link in <code>assets/config.js</code>.");
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
