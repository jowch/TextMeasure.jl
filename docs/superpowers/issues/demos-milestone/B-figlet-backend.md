# B — `FigletBackend` weakdep extension on `FIGlet.jl`

> Wave 1 unblocker · library addition.

## Scope

Wire TextMeasure to the existing **`FIGlet.jl`** package (kdheepak, MIT, on JuliaRegistries, current version 0.2.2, Julia 1.10+) via the canonical weakdep-extension pattern that `FreeTypeBackend` and `MakieBackend` already use.

**Why we don't build our own parser/font store.** `FIGlet.jl` already ships a pure-Julia `.flf` parser, an `Artifacts`-managed bundled font collection (`FIGletFonts-0.5.0`), the `FIGletFont` / `FIGletHeader` / `FIGletChar` types, `readfont(name)` / `readfont(io)` loaders, and a `render` function. Building our own would be pure cost; the teaching value sits in `ext/TextMeasureFigletExt.jl` regardless of where the parser lives.

### Pieces of work

- **`src/backend_containers.jl`** gains a `FigletBackend` struct alongside the existing two:
  ```julia
  struct FigletBackend{F} <: AbstractMeasurementBackend
      font       :: F          # opaque; FIGlet.FIGletFont once the ext loads
      letter_gap :: Int
  end
  ```
  The container does NOT name `FIGlet.FIGletFont` — it's parametric over `F`, matching the existing `FreeTypeBackend{F}` / `MakieBackend{F}` pattern.

- **`Project.toml`**: add `FIGlet` under `[weakdeps]` and `TextMeasureFigletExt = "FIGlet"` under `[extensions]`. Pin `FIGlet = "0.2"` lower bound under `[compat]`.

- **`ext/TextMeasureFigletExt.jl`** mirrors `ext/TextMeasureFreeTypeExt.jl` / `ext/TextMeasureMakieExt.jl`:
  - Keyword constructor `FigletBackend(; font::Union{String,FIGlet.FIGletFont}=FIGlet.DEFAULTFONT, letter_gap::Int=0)` — `String` → `FIGlet.readfont(name)`; `FIGletFont` → use directly. No separate `font_data` escape hatch needed because `FIGlet.readfont(io)` already handles user-supplied data.
  - `TextMeasure.measure(b::FigletBackend, text::AbstractString) -> Float64` summing per-character widths from `size(b.font.font_characters[c].thechar, 2)` for each `c in text`, plus `letter_gap * (length(text) - 1)`. Integer-valued, returned as `Float64` to honor the `measure` return-type contract.
  - `TextMeasure.font_metrics(b::FigletBackend) -> FontMetrics` derived from `b.font.header.height` (line advance) and `b.font.header.baseline` (ascent; descent = height − baseline).
  - **Does NOT implement `measure_bounds`** — Figlet is plain monospace-cell text with no styled-text analog (unlike Makie's `RichText`).
  - Heavy preamble commentary explicitly framing this as "the third example of the canonical weakdep-extension backend pattern" with cross-references to `TextMeasureFreeTypeExt.jl` and `TextMeasureMakieExt.jl`.

## Acceptance

- Deterministic test widths for known strings against `FIGlet.DEFAULTFONT` (`"Standard"`) and at least one other bundled font (e.g., `"Small"`): `using TextMeasure, FIGlet; measure(FigletBackend(), "hello") == <pinned value>`.
- The extension is correctly registered: importing `FIGlet` after `TextMeasure` activates the ext (verifiable via `Base.get_extension(TextMeasure, :TextMeasureFigletExt) !== nothing`).
- `FigletBackend` passes backend conformance tests (cell-space measurement, integer-valued widths returned as `Float64`, ascent/descent matches `FIGletHeader` fields).
- `Project.toml`'s `[compat]` block pins a `FIGlet = "0.2"` lower bound.
- The ext file's preamble explains the pattern; `AbstractMeasurementBackend`'s docstring cross-references all three exts.
- CI runs an integration test against the actual published `FIGlet.jl`.
- `CHANGELOG.md` entry under "Added."

## Depends on / Blocks

- **Depends on:** nothing.
- **Blocks:** #E.

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#B — `FigletBackend` weakdep extension on `FIGlet.jl`" and the "`FigletBackend` ships as a weakdep extension on `FIGlet.jl`" architecture subsection.
- **Existing code (the pattern to mirror):**
  - `ext/TextMeasureFreeTypeExt.jl` — reference for the ext pattern.
  - `ext/TextMeasureMakieExt.jl` — second reference (also has `measure_bounds` — not needed for Figlet).
  - `src/backend_containers.jl` — where `FigletBackend` struct goes.
  - `Project.toml` — current `[weakdeps]` and `[extensions]` blocks.
- **External dependency:** [`FIGlet.jl`](https://github.com/kdheepak/FIGlet.jl) — read `src/FIGlet.jl` for the exact API surface (`readfont`, `FIGletFont`, `FIGletChar.thechar`, `FIGletHeader.height/baseline`).
- **Conventions:** `CLAUDE.md` — "Adding a backend = subtype `AbstractMeasurementBackend` + implement the two methods. If it needs a heavy dep, add it as a weakdep…"

## Suggested labels

`demos-milestone` · `wave-1` · `library`
