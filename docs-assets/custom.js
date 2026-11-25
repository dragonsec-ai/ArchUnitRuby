(() => {
  // YARD also loads pages in a hidden iframe before swapping their content into #main.
  if (window !== window.top) return;
  const main = document.getElementById("main");
  if (!main) return;

  const narrow = window.matchMedia("(max-width: 920px)");
  function enhanceContents() {
    const toc = main.querySelector("div#toc");
    const list = toc?.querySelector("ol.top");
    if (!list) return;

    const disclosure = document.createElement("details");
    disclosure.id = toc.id;
    disclosure.open = !narrow.matches;

    const summary = document.createElement("summary");
    summary.className = "title";
    summary.textContent = "Table of Contents";
    disclosure.append(summary, list);
    toc.replaceWith(disclosure);
  }

  // Keep working when YARD replaces #main's contents during reference navigation.
  new MutationObserver(enhanceContents).observe(main, { childList: true, subtree: true });
  enhanceContents();
  narrow.addEventListener("change", () => {
    const toc = main.querySelector("details#toc");
    if (toc) toc.open = !narrow.matches;
  });
})();
