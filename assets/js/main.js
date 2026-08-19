// GenWave landing page — no framework, no build step, no analytics, no external
// requests. Two small progressive-enhancement jobs: (1) load install.sh live from
// this same origin so the displayed script can never drift from what's actually
// served, and (2) a copy-to-clipboard convenience on the one-liner. Neither is
// required for the page's content to be readable without JavaScript.
(function () {
  "use strict";

  function loadScriptPreview() {
    var loading = document.getElementById("script-loading");
    var body = document.getElementById("script-body");
    var fallback = document.getElementById("script-fallback");
    if (!loading || !body || !fallback) return;

    loading.hidden = false;

    fetch("/install.sh", { credentials: "omit" })
      .then(function (response) {
        if (!response.ok) throw new Error("HTTP " + response.status);
        return response.text();
      })
      .then(function (text) {
        body.textContent = text;
        body.hidden = false;
        loading.hidden = true;
      })
      .catch(function () {
        loading.hidden = true;
        fallback.hidden = false;
      });
  }

  function wireCopyButton() {
    var btn = document.querySelector(".copy-btn");
    if (!btn) return;

    btn.addEventListener("click", function () {
      var targetId = btn.getAttribute("data-copy-target");
      var target = targetId ? document.getElementById(targetId) : null;
      if (!target || !navigator.clipboard) return;

      navigator.clipboard.writeText(target.textContent.trim()).then(function () {
        var original = btn.textContent;
        btn.textContent = "Copied";
        setTimeout(function () {
          btn.textContent = original;
        }, 1500);
      }).catch(function () {
        // Clipboard access denied or unavailable — the command is still plain
        // selectable text in the block above, so this is a silent no-op.
      });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    loadScriptPreview();
    wireCopyButton();
  });
})();
