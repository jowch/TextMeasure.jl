using HouseStyle: digest_rows
using TextMeasure: prepare, MonospaceBackend

"The deterministic monospace backend the golden + toy use (redaction face at RAMP.subhead).
Coupled with the hero's MakieBackend fontsize so the page-filling geometry stays in sync."
golden_backend() = MonospaceBackend(fontsize = 16.0)

"Hero wrap width in px under the golden backend. Tuned so the whole LICENSE forms a
pleasing wide landscape block (~14 lines at subhead-16 mono). Kept in lockstep with the
literal in test_wordgeom.jl's full-LICENSE agreement case."
const HERO_MAX_WIDTH = 700.0

"""
    geometry_rows(; max_width=HERO_MAX_WIDTH) -> Vector{String}

Build the canonical per-word geometry table for the curated hero: `kept|line|x0|x1|base`,
floats rounded to 0.01px. Deterministic (MonospaceBackend). Fed to `digest_rows`.
"""
function geometry_rows(; max_width = HERO_MAX_WIDTH)
    b = golden_backend()
    prep  = prepare(b, LICENSE_TEXT)
    boxes = word_boxes(prep; max_width = max_width)
    kept  = Set(kept_seg_indices(prep))
    rows = String[]
    for wb in boxes
        k = wb.seg_index in kept ? 1 : 0
        push!(rows, string(k, "|", wb.line, "|",
                           round(wb.x0; digits = 2), "|",
                           round(wb.x1; digits = 2), "|",
                           round(wb.baseline; digits = 2)))
    end
    return rows
end

"SHA-256 hex of the canonical hero geometry table."
hero_digest(; max_width = HERO_MAX_WIDTH) = digest_rows(geometry_rows(; max_width = max_width))
