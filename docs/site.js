(function () {
  "use strict";

  document.querySelectorAll("[data-copy]").forEach(function (button) {
    button.addEventListener("click", function () {
      var target = document.getElementById(button.getAttribute("data-copy"));
      if (!target || !navigator.clipboard) return;
      navigator.clipboard.writeText(target.textContent.trim()).then(function () {
        var original = button.textContent;
        button.textContent = button.getAttribute("data-copied-label") || "Copied";
        window.setTimeout(function () { button.textContent = original; }, 1600);
      });
    });
  });
}());
