/**
 * Tables marked `gg-stack-table` turn into one card per row when their
 * wrapper (`gg-stack-wrap`) is too narrow for every column (main.css, fourth
 * scan 2026-11-01). Each cell then shows its column name, read from
 * data-label; this fills that in from the table's header so the tables
 * don't each have to repeat it. A cell that sets its own data-label keeps it.
 */
const STACK_SELECTOR = "table.gg-stack-table";

export function labelStackedTable(table) {
  const headers = [...table.querySelectorAll("thead th")].map((cell) => cell.textContent.trim());
  table.querySelectorAll("tbody tr").forEach((row) => {
    let column = 0;
    [...row.children].forEach((cell) => {
      const span = Number(cell.getAttribute("colspan")) || 1;
      if (span > 1) {
        // An empty-state row spanning the table reads as one line.
        cell.classList.add("gg-stack-full");
      } else if (!cell.hasAttribute("data-label")) {
        cell.setAttribute("data-label", headers[column] || "");
      }
      column += span;
    });
  });
}

export function watchStackedTables(root = typeof document === "undefined" ? null : document.body) {
  if (!root || typeof MutationObserver === "undefined") {
    return () => {};
  }
  const schedule = window.requestAnimationFrame
    ? (task) => window.requestAnimationFrame(task)
    : (task) => window.setTimeout(task, 16);
  let pending = false;
  const run = () => {
    pending = false;
    root.querySelectorAll(STACK_SELECTOR).forEach(labelStackedTable);
  };
  // Only added and removed nodes are watched, so setting data-label here
  // never triggers another pass.
  const observer = new MutationObserver(() => {
    if (!pending) {
      pending = true;
      schedule(run);
    }
  });
  observer.observe(root, { childList: true, subtree: true });
  run();
  return () => observer.disconnect();
}
