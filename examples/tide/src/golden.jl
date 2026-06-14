# golden.jl — the DETERMINISTIC golden invariant for The Tide.
#
# THE GALLERY RULE: hash the COMPUTED layout table, never the rendered pixels. The table is built
# with the MonospaceBackend (per-grapheme advance, font-path-independent) and floats are rounded,
# so the digest is reproducible across machines/fonts/OSes. No MakieBackend, no pixels.
#
# We run the SAME `frame_layout` the renderer uses — including the per-band justify — just driven
# by the deterministic backend factory, at a handful of STRUCTURALLY-DISTINCT frames so every
# layout family is pinned: rest (full rectangle), a cardinal wavy wall, and both a bottom-corner
# and a top-corner straight diagonal.

using HouseStyle: digest_rows
using TextMeasure: MonospaceBackend

# Deterministic backend factory: MonospaceBackend at the requested size. The font path is ignored
# (monospace advance is per-grapheme), so the table depends only on size + text. This is the SAME
# factory the test files use, so the golden matches the tested layout path exactly.
golden_backend(_font, size) = MonospaceBackend(fontsize = Float64(size))

# Structurally-distinct frames to pin (label is only for the human-readable rows file):
#   frame 0   — rest: the full-width rectangle (no wall).
#   frame 100 — W peak: a cardinal wavy vertical wall (peak_frame(:W)).
#   frame 300 — SW peak: a bottom-corner straight diagonal (peak_frame(:SW)).
#   frame 900 — NE peak: a top-corner straight diagonal (peak_frame(:NE)).
const GOLDEN_FRAMES = (0, 100, 300, 900)

"""
    geometry_rows() -> Vector{String}

Build the canonical, deterministic placement table across `GOLDEN_FRAMES`. One `prepare_tide`
with the MonospaceBackend factory, then `frame_layout` at each pinned frame; for every placement
emit one row: `frame|dir|segidx|round(x,2)|round(y,2)|lit|str` where `x` is the JUSTIFIED local x
(`justx`) and `lit` (via `has_lit`) flags the coral-bearing "kneads" placement — including the
compound "kneads—smoothing" token, whose "kneads" run the renderer lights. Rows are in emission
order; `digest_rows` sorts them, so the digest is emission-order-independent.
"""
function geometry_rows()
    pb = prepare_tide(golden_backend; body_font = "monospace", fontsize = 11.0)
    rows = String[]
    for frame in GOLDEN_FRAMES
        fl = frame_layout(pb, frame)
        for p in fl.placements
            s = fl.segs[p.segment_index].str
            push!(rows, string(
                frame, "|", fl.dir, "|", p.segment_index, "|",
                round(fl.justx[p]; digits = 2), "|",
                round(p.y; digits = 2), "|",
                has_lit(s), "|", s))
        end
    end
    return rows
end

"SHA-256 hex of the canonical (Monospace, deterministic) Tide layout table."
tide_digest() = digest_rows(geometry_rows())
