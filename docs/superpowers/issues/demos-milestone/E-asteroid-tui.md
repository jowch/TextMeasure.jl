# E — Tachikoma ASCII Asteroid Blaster (`examples/asteroid_tui/`)

> Wave 2 demo · the headline gif-able exhibit.

## Pitch

**First measurement-driven editorial-typography demo in terminal space.** Prior-art review (see spec) found no shape-conforming text packing or measure-once-layout-many primitive in any surveyed TUI framework (ncurses / ratatui / notcurses / Textual / lipgloss / Charm / Tachikoma). The composition — procedural silhouette + shape-packed prose + word-boundary fracture + variable-width figlet + low-Hz rotation reflow — has no precedent in TUI; pretext.js itself is browser-only.

## Visual direction (locked)

- **Ship: Arwing** — wedge nose, swept-back wings, thruster glyphs at base. Physics state (x, y, φ, v) packed via `shape_pack` into the wedge interior; re-packed every frame as values update.
- **Asteroids: varied silhouettes** — dagger, crescent, lumpy potato, multi-lobed peanut. Generated per spawn from `asteroid_polygon`. Descriptive prose packed inside.
- **Stat tags above each asteroid** in flipped-bracket format: `┌─ d:142m  ETA:3.4s  v:0.21µ ─┐`. Ends point down.
- **Beam: onomatopoeia** (`PEW` repeated) length-scaled to `floor(dist / measure(b, "PEW "))`.
- **Charge: 5 stages**, asterisk at ship tip growing from `·` → `*` → `─*─` → `\*/` → full sunburst over hold ~0.15s → ~1.5s.
- **Respawn:** ship blows up on hit; respawns with ~2s invulnerability at ~3Hz blink, intangible, player can reposition.
- **Debug overlay (`?`):** every measured word's bbox drawn in cyan.

## Mechanics (locked)

- Asteroids rotate at ω sampled from `[-0.4, +0.4]` rad/s. Silhouette re-rasterizes every ~5 frames; `shape_pack` re-runs against the new cell raster; word widths in the `Prepared` are reused (no re-measurement).
- Word-boundary fracture on impact: nearest placed segment → snap back to start of its `:word` → `subprep` slice → re-pack each half into a child silhouette (`voronoi_shatter` seeded at impact).
- Prose pool: ≥50 procedurally varied templates (class × material × callsign × spin rate).
- **No HP/ammo system.** Hit → explode → respawn.

**Crayons.jl is not used.** Tachikoma handles ANSI colors natively in its own renderer.

## Plan B for Tachikoma

Tachikoma is the primary substrate. If it proves unworkable (upstream API churn, abandonment, fundamental fit issue), the fallback is **`REPL.Terminals`** (stdlib — `TTYTerminal`, raw-mode toggle) **+ `Base.RawFD` + `termios` ioctl + manual ANSI escape codes**, double-buffered into a cell raster. The demo's core (`shape_pack` against a cell raster + FigletBackend measurement) is renderer-agnostic; only the event loop and draw plumbing would need rework. (`REPL.TerminalMenus` is **not** the Plan B — it's a blocking menu API. `TermInterface.jl` is unrelated — it's the JuliaSymbolics expression-interface package.)

## Cross-platform scope

Linux and macOS only for v1. Windows is OOS due to ANSI / raw-mode / sigwinch fragility.

## Julia compat

Tachikoma.jl requires Julia 1.12+, higher than TextMeasure's 1.11 floor. Because each demo has its own `Project.toml`/`Manifest.toml`, `examples/asteroid_tui/Project.toml` sets `julia = "1.12"` independently. Does not affect TextMeasure's published compat.

## Acceptance

- Hit one asteroid, observe legible split into two shard-prose chunks. **"Legible" defined operationally:** every glyph from the original prose appears in exactly one shard's render, in original order, with no character drops or duplicates.
- ≥30fps on Linux/macOS in a 120×40 terminal during steady-state play with ~5 asteroids (measured via wall-clock between frame swaps).
- Debug overlay correctly highlights every measured word.
- Respawn flash + invulnerability works as described.
- Headless tick-loop test in CI (no actual terminal needed): boot game, run 60 ticks of a scripted scenario, snapshot the cell buffer, checksum against a committed golden. **Mechanism:** the game core writes to a renderer-agnostic `CellBuffer` (`Matrix{Char}` + ANSI color metadata). Both Tachikoma and Plan B's raw-ANSI renderer drain `CellBuffer`. The CI test never instantiates a renderer — it constructs a `CellBuffer`, drives 60 ticks of the game loop against a scripted input sequence, and checksums the resulting `Matrix{Char}` plus color metadata. This avoids depending on Tachikoma's event-loop API (which is not yet pinned in our spec) for the test path.
- `examples/asteroid_tui/README.md` and `examples/asteroid_tui/Project.toml` exist; demo runs via `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.instantiate(); include("examples/asteroid_tui/run.jl")'`.

## Depends on / Blocks

- **Depends on:** #A (`subprep`), #B (FigletBackend ext on the existing FIGlet.jl), #C (`shape_pack`), #D (silhouettes).
- **Blocks:** #I (README hero gif may come from #E), #J (golden-snapshot tick-loop test).

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#E — Tachikoma ASCII Asteroid Blaster" and the prior-art research summary in "Motivation."
- **External deps:** `Tachikoma.jl` (primary substrate); [`FIGlet.jl`](https://github.com/kdheepak/FIGlet.jl) (regular `Pkg.add("FIGlet")` — triggers the #B ext); `TextMeasure.jl` via `Pkg.develop(path="../..")`.
- **Conventions:** `CLAUDE.md`.

## Suggested labels

`demos-milestone` · `wave-2` · `examples` · `demo`

## Open questions for the planner

- Specific prose-pool templates (≥50 needed). Procedural composition rules described in spec; planner can outline a generator.
- Tachikoma event-loop API specifics — not pinned in the spec.
