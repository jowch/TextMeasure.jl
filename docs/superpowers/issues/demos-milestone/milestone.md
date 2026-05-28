# Demos Milestone — TextMeasure in action

Four demos — one terminal action game (asteroid TUI) and three CairoMakie print artifacts (DOIInfograph, Map Feature Page, "Newer Yorker" correctness exhibit) — plus two cross-cutting issues (demo health CI; an optional Knuth–Plass stretch). Together they exercise TextMeasure.jl's `prepare`/`layout` split across multiple backends and downstream layout consumers.

The library gains one small addition (`Prepared` segment-slice helper) plus a `FigletBackend` shipped as a weakdep extension on **the existing `FIGlet.jl` package** (kdheepak, MIT, on JuliaRegistries) — the third instance of the established `FreeTypeBackend` / `MakieBackend` weakdep-ext pattern. Shared utilities (`shape_pack`, silhouettes) live in `examples/` with a documented migration path to `TextMeasureLayouts.jl`. Per-demo `Project.toml`/`Manifest.toml` keep TextMeasure's own dependency graph clean.

## Design spec

[`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — the converged design doc, eight commits of brainstorming + 4-round reviewer convergence + deep verification pass.

## Dependency graph

```
#A ─→ #E
#B ─→ #E
#D ─→ #E
                      ┌──→ #E
#C ─→ ┬──→ #F2 → #F3 ─┤
      ├──→ #G ────────┤
      └──→ #H ────────┤
                      ├──→ #I (all completed demos)
                      └──→ #J (all completed demos)
#F1 ─→ #F2

#K (stretch) ──optional consumer──→ #F2, #H
```

## Waves

- **Wave 1 — Unblockers (parallel):** #A, #B, #C, #D.
- **Wave 2 — Demos (parallel after wave 1):** #E asteroid TUI; #F1 → #F2 → #F3 serial chain; #G map feature; #H correctness exhibit.
- **Wave 3 — Integration (after wave 2):** #I README/gallery/release-hygiene; #J demo-health CI.
- **Stretch:** #K Knuth–Plass — interleaved with wave 2 if appetite.

## Non-goals

- Justification, hyphenation, UAX-#14 line-breaking, CJK, bidi, rotation in the layout API (per CLAUDE.md).
- PDF figure extraction; authentication for closed-access papers; Tachikoma sixel/kitty mode; Windows TUI; **time estimates** (issues describe scope and acceptance, not effort).
