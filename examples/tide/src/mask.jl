# SPDX-License-Identifier: MIT
# mask.jl — the per-frame region mask: this frame's surviving (un-flooded) area as a BitMatrix.
#
# THE ENGINE TECHNIQUE this file showcases: a region for `shape_pack` is just a BitMatrix of
# `true` (text may live here) / `false` (flooded sea) cells. ANY shape works — here it's a wavy
# advancing tide-line, but the packer neither knows nor cares. `region_mask` builds the cells;
# `raster_chord_fn` (from the engine) turns them into the chord function `shape_pack` consumes.
#
# A direction's wall advances INTO the region by `depth_px` (0 ⇒ no wall ⇒ full rectangle). Cells
# on the SEA side of the live (wavy) edge are knocked out, so `shape_pack` re-flows the prose
# flush to the undulating margin. Each of the 6 directions yields AT MOST ONE run of `true` cells
# per raster row — the `fill = :widest` invariant the packer relies on (see the per-row reasoning
# in `region_mask`).
#
# ANCHORING: the bottom-corner bites (SW/SE) anchor their deep end to `deep_y` — the deepest line
# the text ever occupies — so the diagonal eats UP into the type (kneading the last lines), not
# into the empty tail below it. Top corners (NW/NE) anchor to the text top (`top_y = 0`).

const WAVE_A = 8.0          # tide-line amplitude (px) — how far the wave wobbles off its base cut
const CELL   = 1.0          # raster cell size (px); 1 cell = 1 px

"Tide-line wavelength (px) ≈ 2 line-advances — a graceful, type-scaled wave."
wave_L(line_advance) = 2.0 * line_advance

# ---------------------------------------------------------------------------------------------
# region_mask — the 6 raking directions (W, E, SW, SE, NW, NE).
# ---------------------------------------------------------------------------------------------
"""
    region_mask(W, H, dir, depth_px, phase; cell=1.0, line_advance=2.0, floor_y=H,
                deep_y=floor_y, top_y=0.0) -> BitMatrix

Wavy advancing-tide raster of size ⌈H⌉×⌈W⌉. `dir ∈ DIRECTIONS`; `depth_px` is how far the wall
has advanced inward (0 ⇒ all-true rest rectangle); `phase` shifts the wave per frame. `deep_y`
anchors the DEEP end of the bottom-corner diagonals (the deepest line text occupies); `top_y`
anchors the deep end of the top-corner diagonals (the text top). `floor_y` (the rest text bottom)
is threaded through for reference but the corner geometry uses `deep_y`/`top_y`.

Geometry per family (block-top frame: x right, y DOWN):
- **W/E** — a vertical wavy wall perpendicular to the text flow. Each row is cut at a single
  x = base ± WAVE_A·sin(y/λ·2π + phase); knock the sea side. One x-cut ⇒ one interval.
- **SW/SE** — a wavy bite at a BOTTOM corner as one straight diagonal (slope 1): the cut ramps
  linearly from 0 at `deep_y − b − A` up to its max `b` at `deep_y` (the deepest occupied line),
  so the bottom lines sit at the deepest part of the ramp and stay compressed. SE mirrors SW
  (x → W−x).
- **NW/NE** — a wavy bite at a TOP corner as one straight diagonal anchored to `top_y`: the cut
  ramps from its max `b` at `top_y` down to 0 at `top_y + b + A`. NE mirrors NW (x → W−x).
A diagonal cut is monotone across a row ⇒ one interval.

`depth_px` is assumed pre-clamped by the caller (`frame.jl` clamps to each direction's d_max so
no surviving band falls below `floor_w`); this builder applies the geometry only.

# Examples
```jldoctest
julia> m = region_mask(10, 4, :W, 0.0, 0.0);   # depth 0 ⇒ the full rest rectangle

julia> size(m)                                 # ⌈H⌉ rows × ⌈W⌉ cols
(4, 10)

julia> all(m)                                  # nothing flooded yet
true
```
"""
function region_mask(W, H, dir::Symbol, depth_px::Real, phase::Real;
                     cell::Real = CELL, line_advance::Real = wave_L(1.0),
                     floor_y::Real = H, deep_y::Real = floor_y, top_y::Real = 0.0)
    cs = Float64(cell)
    nr = ceil(Int, H / cs); nc = ceil(Int, W / cs)
    r = trues(nr, nc)
    b = Float64(depth_px)
    b <= 0.0 && return r                          # rest rectangle, no wall
    λ = wave_L(line_advance)
    ph = Float64(phase)
    Wf = Float64(W); dy = Float64(deep_y); ty = Float64(top_y)

    xc(col) = (col - 0.5) * cs                     # cell center x
    yc(row) = (row - 0.5) * cs                     # cell center y
    wav(t)  = WAVE_A * sin(2π * t / λ + ph)

    if dir === :W
        # left wall advancing right: edge x = b + wave(y); knock x < edge.
        for row in 1:nr
            edge = b + wav(yc(row))
            for col in 1:nc; xc(col) < edge && (r[row, col] = false); end
        end
    elseif dir === :E
        # right wall advancing left: edge x = W - b + wave(y); knock x > edge. (W and E share the
        # same +wave sign convention — see the matching tideline in frame.jl.)
        for row in 1:nr
            edge = Wf - b + wav(yc(row))
            for col in 1:nc; xc(col) > edge && (r[row, col] = false); end
        end
    elseif dir === :SW
        # bottom-LEFT corner bite — one straight diagonal (slope 1, 45°): the cut ramps from 0 at
        # (deep_y - b - A) up to its max (b) at `deep_y`, the deepest line text ever occupies. So
        # the bottom lines are the deepest part of the ramp and stay compressed. The sine WAVE_A
        # rides on the straight path.
        cut_top = dy - b - WAVE_A
        for row in 1:nr
            yy = yc(row); (yy < cut_top || yy > dy) && continue
            cut = (yy - (dy - b)) + wav(yy)
            for col in 1:nc; xc(col) < cut && (r[row, col] = false); end
        end
    elseif dir === :SE
        # bottom-RIGHT corner bite: mirror SW across x (knock (W-x) < cut). Single straight diagonal.
        cut_top = dy - b - WAVE_A
        for row in 1:nr
            yy = yc(row); (yy < cut_top || yy > dy) && continue
            cut = (yy - (dy - b)) + wav(yy)
            for col in 1:nc; (Wf - xc(col)) < cut && (r[row, col] = false); end
        end
    elseif dir === :NW
        # top-LEFT corner bite — one straight diagonal anchored to the text top `top_y`: the cut
        # ramps from its max (b) at top_y down to 0 at (top_y + b + A). Top lines are the deepest.
        cut_bot = ty + b + WAVE_A
        for row in 1:nr
            yy = yc(row); (yy < ty || yy > cut_bot) && continue
            cut = (b - (yy - ty)) + wav(yy)
            for col in 1:nc; xc(col) < cut && (r[row, col] = false); end
        end
    elseif dir === :NE
        # top-RIGHT corner bite: mirror NW across x. Single straight diagonal.
        cut_bot = ty + b + WAVE_A
        for row in 1:nr
            yy = yc(row); (yy < ty || yy > cut_bot) && continue
            cut = (b - (yy - ty)) + wav(yy)
            for col in 1:nc; (Wf - xc(col)) < cut && (r[row, col] = false); end
        end
    else
        throw(ArgumentError("region_mask: unknown direction $(repr(dir))"))
    end
    return r
end

"""
    make_band_interval(chord_fn, asc, line_advance) -> (y, x1) -> (L, R)

Resolve the `(L,R)` interval a band actually used, reproducing the packer's band window
exactly: baseline y => band = round((y-ascent)/la)+1, window [(band-1)la, band*la].
(Recomputing at y±asc/desc samples a DIFFERENT center row under the wavy cut, which can fail
to bracket words[1].x — hence we mirror the packer's own window here.)
"""
function make_band_interval(chord_fn, asc, line_advance)
    function band_interval(y, x1)
        bandi = round(Int, (y - asc) / line_advance) + 1
        ivs = chord_intervals(chord_fn, (bandi - 1) * line_advance, bandi * line_advance)
        for (L, R) in ivs
            (x1 >= L - 1e-6 && x1 <= R + 1e-6) && return (Float64(L), Float64(R))
        end
        isempty(ivs) && return (NaN, NaN)
        best = ivs[1]; bw = best[2] - best[1]      # fallback: widest interval
        for iv in ivs; (iv[2] - iv[1]) > bw && (best = iv; bw = iv[2] - iv[1]); end
        return (Float64(best[1]), Float64(best[2]))
    end
    return band_interval
end
