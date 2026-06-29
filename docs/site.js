(function () {
  "use strict";

  var DAY_S = 360;

  /* —— photoperiod readout (6-min sim day) —— */
  function tickPhotoperiod() {
    var el = document.getElementById("photoperiod");
    if (!el) return;
    var t = (Date.now() / 1000) % DAY_S;
    var daylight = 0.5 + 0.5 * Math.sin((t / DAY_S) * Math.PI * 2 - Math.PI / 2);
    var pct = Math.round(daylight * 100);
    var phase;
    if (daylight < 0.18) phase = "night";
    else if (daylight < 0.38) phase = "dawn";
    else if (daylight < 0.72) phase = "day";
    else if (daylight < 0.88) phase = "dusk";
    else phase = "night";
    el.textContent = phase + " · " + pct + "% daylight";
    el.dataset.phase = phase;
  }

  /* —— mobile nav —— */
  function initNav() {
    var toggle = document.querySelector(".nav-toggle");
    var panel = document.getElementById("site-nav-panel");
    if (!toggle || !panel) return;

    toggle.addEventListener("click", function () {
      var open = panel.classList.toggle("is-open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });

    panel.querySelectorAll("a").forEach(function (link) {
      link.addEventListener("click", function () {
        panel.classList.remove("is-open");
        toggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  /* —— scroll spy —— */
  function initScrollSpy() {
    var links = document.querySelectorAll(".site-links a[href^='#']");
    if (!links.length) return;
    var sections = [];
    links.forEach(function (link) {
      var id = link.getAttribute("href").slice(1);
      var sec = document.getElementById(id);
      if (sec) sections.push({ id: id, el: sec, link: link });
    });

    function update() {
      var y = window.scrollY + 120;
      var current = sections[0];
      sections.forEach(function (s) {
        if (s.el.offsetTop <= y) current = s;
      });
      sections.forEach(function (s) {
        s.link.classList.toggle("is-active", s === current);
      });
    }

    window.addEventListener("scroll", update, { passive: true });
    update();
  }

  /* —— reveal on scroll —— */
  function initReveal() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    var nodes = document.querySelectorAll(".reveal");
    if (!nodes.length || !("IntersectionObserver" in window)) return;
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) {
            e.target.classList.add("is-visible");
            io.unobserve(e.target);
          }
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 }
    );
    nodes.forEach(function (n) { io.observe(n); });
  }

  /* —— back to top —— */
  function initBackTop() {
    var btn = document.getElementById("back-top");
    if (!btn) return;
    window.addEventListener(
      "scroll",
      function () {
        btn.classList.toggle("is-shown", window.scrollY > 480);
      },
      { passive: true }
    );
    btn.addEventListener("click", function () {
      window.scrollTo({ top: 0, behavior: "smooth" });
    });
  }

  tickPhotoperiod();
  setInterval(tickPhotoperiod, 1000);
  initNav();
  initScrollSpy();
  initReveal();
  initBackTop();
})();
