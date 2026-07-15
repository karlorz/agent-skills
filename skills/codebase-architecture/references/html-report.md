# HTML Report Format (improve-codebase-architecture)

The architectural review is rendered as a single self-contained HTML file in the OS temp directory — **not** under wiki or `docs/`. Tailwind and Mermaid both come from CDNs (browser will execute third-party JS). Prefer the **offline Markdown** fallback when network is unknown or policy blocks CDNs. Mermaid handles graph-shaped diagrams; hand-built divs and inline SVG handle editorial visuals.

## Path

Resolve temp dir from `$TMPDIR`, fallback `/tmp` (or `%TEMP%` on Windows):

```
{tmpdir}/architecture-review-{timestamp}.html
```

Open for the user (`open` / `xdg-open` / `start`) and report the absolute path.

## Offline / no-CDN fallback

If CDN scripts cannot load (air-gapped, policy, or user request), write Markdown instead:

```
{tmpdir}/architecture-review-{timestamp}.md
```

Same candidate sections; use fenced Mermaid for before/after graphs. Do not put this file under wiki or `docs/` unless the user explicitly asks to archive a copy.

## Scaffold

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Architecture review — {{repo name}}</title>
    <!-- Prefer offline MD when CDN is blocked. Mermaid pinned; layout CSS is local (no unpinned Tailwind CDN). -->
    <script type="module">
      import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11.6.0/dist/mermaid.esm.min.mjs";
      // Prefer strict: do not execute HTML inside diagram text.
      // Escape or strip angle brackets from untrusted labels (repo paths, symbol names).
      mermaid.initialize({ startOnLoad: true, theme: "neutral", securityLevel: "strict" });
    </script>
    <style>
      body { background: #fafaf9; color: #0f172a; font-family: system-ui, sans-serif; }
      main { max-width: 64rem; margin: 0 auto; padding: 3rem 1.5rem; }
      .space-y-12 > * + * { margin-top: 3rem; }
      .space-y-10 > * + * { margin-top: 2.5rem; }
      .seam { stroke-dasharray: 4 4; }
      .leak { stroke: #dc2626; }
      .deep { background: linear-gradient(135deg, #0f172a, #1e293b); }
      .badge-strong { color: #065f46; }
      .badge-explore { color: #b45309; }
      .badge-spec { color: #475569; }
    </style>
  </head>
  <body>
    <main class="space-y-12">
      <header>...</header>
      <section id="candidates" class="space-y-10">...</section>
      <section id="top-recommendation">...</section>
    </main>
  </body>
</html>
```

## Header

Repo name, date, and a compact legend: solid box = module, dashed line = seam, red arrow = leakage, thick dark box = deep module. No introduction paragraph — straight into the candidates.

## Candidate card

Use **codebase-design** glossary terms without ceremony. Each candidate is one `<article>`:

- **Title** — short, names the deepening
- **Badge row** — strength (`Strong` = emerald, `Worth exploring` = amber, `Speculative` = slate) + dependency category (`in-process`, `local-substitutable`, `ports & adapters`, `mock`)
- **Files** — monospaced list
- **Before / After diagram** — centrepiece, two columns
- **Problem** / **Solution** — one sentence each
- **Wins** — bullets, ≤6 words each
- **ADR callout** (if applicable) — amber box

No paragraphs of explanation. If the diagram needs a paragraph, redraw the diagram.

## Diagram patterns

### Mermaid graph

```html
<div class="rounded-lg border border-slate-200 bg-white p-4">
  <pre class="mermaid">
    flowchart LR
      A[OrderHandler] --> B[OrderValidator]
      B --> C[OrderRepo]
      C -.leak.-> D[PricingClient]
      classDef leak stroke:#dc2626,stroke-width:2px;
      class C,D leak
  </pre>
</div>
```

Sanitize node labels from untrusted path segments (no raw HTML, no unescaped quotes that break the fence).

### Hand-built boxes

Modules as bordered `<div>`s; arrows as SVG. Use when the "after" should feel like one thick deep module with greyed-out internals.
