using HouseStyle: digest_rows
using TextMeasure: MonospaceBackend

# Deterministic, machine-stable role sentinels for the golden table. The golden hashes the
# COMPUTED placement table built with MonospaceBackend (per-word, at each word's size) — never
# MakieBackend widths and never pixels — so the digest is reproducible across machines/fonts.
const _GHOST = :ghost
const _RED   = :red
const _BLACK = :black

"Per-word deterministic backend: MonospaceBackend at the word's size. Font path is ignored
(monospace advance is per-grapheme), so the table depends only on sizes + text."
golden_backend(_font, size) = MonospaceBackend(fontsize = Float64(size))

"""
    geometry_rows() -> Vector{String}

Build the canonical per-word placement table with the deterministic MonospaceBackend and
format one row per word: `role|font|size|round(x,2)|round(baseline,2)|display`. Rows are
returned in reading order; `digest_rows` sorts them, so the digest is emission-order-independent.
"""
function geometry_rows()
    placements, _, _ = placement_table(golden_backend;
        ghost_color = _GHOST, red_color = _RED, black_color = _BLACK)
    rows = String[]
    for p in placements
        push!(rows, string(p.role, "|", basename(p.font), "|", p.size, "|",
                           round(p.x; digits = 2), "|",
                           round(p.baseline; digits = 2), "|", p.str))
    end
    return rows
end

"SHA-256 hex of the canonical (Monospace, deterministic) placement table."
hero_digest() = digest_rows(geometry_rows())
