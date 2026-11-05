#!/usr/bin/env python3
"""Write board/public.html: the drift board as a standalone page for GitHub Pages.

    python3 -I lab/board/make_public.py [--dry-run]

index.html is written for the claude.ai dashboard runtime, which supplies `dash`, d3 and the design tokens.
This wraps it with a small stand-in for that runtime: d3 from cdnjs, the tokens as plain CSS, and a `dash`
object that loads the run CSVs next to it. index.html itself is not changed.
--dry-run prints what would be written instead of writing it.
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
SRC, OUT = HERE / "index.html", HERE / "public.html"

# data source id in index.html -> CSV written by make_board_data.py
SOURCES = {
    "lab8": "lab8-runs.csv",
    "lab8b": "lab8b-runs.csv",
    "lab8bstart": "lab8b-start-runs.csv",
    "lab8bnamed": "lab8b-named-runs.csv",
    "lab8blookpast": "lab8b-lookpast-runs.csv",
}

HEAD = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Agent drift board</title>
<style>
  :root {
    --font-anthropic-sans: system-ui, -apple-system, "Segoe UI", Roboto, Arial, sans-serif;
    --font-anthropic-serif: Georgia, "Times New Roman", serif;
    --color-fg: #1f1e2b; --color-fg-muted: #5f5d70; --color-panel: #ffffff; --color-border-line: #dedce8;
    --color-ok: #2e8b57; --color-bad: #c8323c;
    --cds-chart-muted: #b9b7c6; --cds-chart-status-critical: #c8323c;
    --cds-text-secondary: #5f5d70; --cds-surface-popover: #ffffff; --cds-shadow-popover: 0 4px 16px rgba(0,0,0,.15);
    --cds-border: 1px solid #dedce8; --cds-radius: 10px; --cds-dur-slow: .3s; --cds-font-weight-medium: 500;
    --cds-font-size-caption: .8rem; --cds-font-size-heading: 1.15rem; --cds-font-size-title: 1.9rem;
    --cds-gap-xs: .25rem; --cds-gap-sm: .5rem; --cds-gap-md: .9rem; --cds-gap-lg: 1.4rem; --cds-gap-xl: 2rem;
    --cds-pad-xs: .25rem; --cds-pad-sm: .5rem; --cds-pad-md: .75rem; --cds-pad-lg: 1.1rem;
  }
  [hidden] { display: none !important; }
  body { background: #f6f5fa; color: var(--color-fg); margin: 0; padding: 24px 16px 48px; }
  .pub-note { max-width: 82rem; margin: 0 auto 16px; font: .85rem var(--font-anthropic-sans); color: var(--color-fg-muted); }
  .pub-note a { color: inherit; }
</style>
<script src="https://cdnjs.cloudflare.com/ajax/libs/d3/7.9.0/d3.min.js"></script>
<script>
// Stand-in for the dashboard runtime: just enough of `dash` for this page.
window.dash = (() => {
  const SOURCES = __SOURCES__;
  const raw = {}, calcs = {}, draws = [];
  let ready = false;
  const data = (id) => {
    if (!ready) return { status: 'loading', data: [] };
    if (id in raw) return { status: 'ok', data: raw[id] };
    const c = calcs[id];
    if (!c) return { status: 'error', data: [] };
    if (!c.cache) c.cache = c.fn(...c.inputs.map((i) => data(i).data));
    return { status: 'ok', data: c.cache };
  };
  const run = ([name, fn]) => document.querySelectorAll(`[data-draw="${name}"]`).forEach((el) => fn(el));
  const api = {
    colors: ['#5b3fd1', '#e0457b', '#1f9e89', '#f2a541', '#3d7dd8', '#8c6bb1', '#6b8e23', '#a0522d'],
    calc: (id, spec) => { calcs[id] = { fn: spec.fn, inputs: spec.inputs }; },
    data,
    draw: (name, fn) => { draws.push([name, fn]); if (ready) run([name, fn]); },
    setLink: (id) => { history.replaceState(null, '', '#' + id); draws.forEach(run); },
  };
  Promise.all(Object.entries(SOURCES).map(([id, f]) => d3.csv(f).then((rows) => { raw[id] = rows; })))
    .then(() => { ready = true; draws.forEach(run); })
    .catch((e) => { console.error(e); document.body.insertAdjacentHTML('afterbegin', '<p class="pub-note">Could not load the run data.</p>'); });
  let t; addEventListener('resize', () => { clearTimeout(t); t = setTimeout(() => draws.forEach(run), 200); });
  return api;
})();
</script>
</head>
<body>
<p class="pub-note">Lab 8 and 8b results from <a href="https://github.com/mclose/moderne-lab">github.com/mclose/moderne-lab</a>.
Data: the run CSVs in this folder, built by make_board_data.py. Generated from index.html by make_public.py.</p>
"""

TAIL = "\n</body>\n</html>\n"


def main() -> int:
    dry = sys.argv[1:] == ["--dry-run"]
    if sys.argv[1:] not in ([], ["--dry-run"]):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    missing = [f for f in SOURCES.values() if not (HERE / f).is_file()]
    if missing:
        print(f"missing CSVs: {missing}; run make_board_data.py first", file=sys.stderr)
        return 1
    body = SRC.read_text(encoding="utf-8")
    js_sources = "{" + ", ".join(f"'{k}': '{v}'" for k, v in SOURCES.items()) + "}"
    page = HEAD.replace("__SOURCES__", js_sources) + body + TAIL
    if dry:
        print(f"would write {OUT} ({len(page)} bytes) from {SRC.name} + {len(SOURCES)} CSVs")
        return 0
    OUT.write_text(page, encoding="utf-8")
    print(f"wrote {OUT} ({len(page)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
