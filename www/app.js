// The server switches page or shows the results, and the new HTML arrives a
// moment later. Wait until the target element exists, then scroll to it.
function scrollWhenReady(selector, highlight) {
  var tries = 0;
  var timer = setInterval(function () {
    var el = document.querySelector(selector);
    if (el || ++tries > 20) {
      clearInterval(timer);
      if (!el) return;
      el.scrollIntoView({ behavior: "smooth", block: highlight ? "center" : "start" });
      if (highlight) {
        el.classList.add("is-highlighted");
        setTimeout(function () { el.classList.remove("is-highlighted"); }, 1500);
      }
    }
  }, 50);
}

Shiny.addCustomMessageHandler("scroll-to-question", function (number) {
  scrollWhenReady("#question-" + number, true);
});

Shiny.addCustomMessageHandler("scroll-to", function (selector) {
  scrollWhenReady(selector, false);
});
