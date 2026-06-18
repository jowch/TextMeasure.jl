<!-- SPDX-License-Identifier: MIT -->
# TextMeasure.jl — demo gallery

Three **measurement-driven** gallery pieces built on
[TextMeasure.jl](../README.md), one shared house-style spine, three registers —
*measure once, then **knead · weave · place** — many.* Each piece is a self-contained Julia
project under `examples/<piece>/` with its own `Project.toml`, `README.md`, and deterministic
golden test (hash the **computed** layout table, never pixels).

## Running a piece

Each project resolves the in-repo packages by path (`[sources]` in its `Project.toml`), so setup
is just an instantiate — no manual `Pkg.develop`:

```bash
julia --project=examples/<piece> -e 'using Pkg; Pkg.instantiate()'
```

---

## The Tide — *knead*

<video src="https://github.com/user-attachments/assets/e9bd9d54-4def-4d6d-8b5b-e732e0550d8c" controls muted loop></video>

<sub>▶ inline loop above (renders on GitHub) · [hero still](tide/tide-hero.png)</sub>

A short original prose passage about the sea working the shore, set as a justified block on a
warm sunset palette. A wavy coral **tide-line** sweeps around the block and **kneads** the text:
each frame, the engine re-flows the prose into whatever region the wave leaves behind. The font
engine is touched **once**; every frame after is one `shape_pack` over the cached widths.

```bash
julia --project=examples/tide examples/tide/build.jl    # → tide-loop.mp4 + tide-hero.png
```

→ [`tide/README.md`](tide/README.md)

---

## Woven — *weave*

![Woven](woven/woven-hero.png)

The project's own MIT `LICENSE`, laid out once by the engine and faded to a Plex Mono ghost, with
**two found poems lit in place** through it — exact per-word positions recovered by re-walking the
prepared segments. Subtraction as composition: the poems were always in the license text.

```bash
julia --project=examples/woven -e 'using Woven; Woven.hero("examples/woven/woven-hero.png")'
```

→ [`woven/README.md`](woven/README.md)

---

## The Atlas — *place*

<video src="https://github.com/user-attachments/assets/4e82d0a3-eec8-456f-bc18-7044bf49293e" controls muted loop></video>

<sub>▶ inline dive above (renders on GitHub) · [hero still](atlas/atlas-hero.png)</sub>

A seamless-loop **zoom-dive** over the California Central Coast whose every place-label is
*measured* by TextMeasure and *placed* collision-free by **MakieTextRepel.jl** — re-solved on
every frame as the camera descends. Region labels scale with altitude and dissolve like clouds
you fall past; coastal labels lean over open water. Nothing is hand-positioned but the lon/lat
anchors.

```bash
julia --project=examples/atlas examples/atlas/build.jl    # → atlas-dive.mp4 + atlas-hero.png
```

→ [`atlas/README.md`](atlas/README.md)

---

## Shared infrastructure (not standalone demos)

| Path | Role |
|------|------|
| `_housestyle/` | `HouseStyle` — the shared spine: palette, type ramp, pinned font helpers, the golden-digest helper. |
| `fonts/` | The pinned OFL font families used across the pieces (Hanken Grotesk, Newsreader, IBM Plex Mono, Libre Caslon, Fraunces). |
| `layouts/` | `TextMeasureLayouts` — `shape_pack` (shape-conforming packing) + the Knuth–Plass / greedy justify utilities, consumed by **The Tide** and **Woven**. Library only. |
