"A solid ink redaction rectangle in block coordinates (y down)."
struct RedactRect
    x0 :: Float64
    x1 :: Float64
    y0 :: Float64   # top
    y1 :: Float64   # bottom
end

"""
    redaction_rects(boxes, prep, kept_seg_indices; bleed=1.0) -> Vector{RedactRect}

Merge maximal runs of consecutive BLACKED words on each line into one continuous bar
(spaces between two blacked words are covered; a kept word breaks the run, leaving its
adjacent spaces paper). `bleed` px is added at each run end so adjacent bars read as one
censor line. Vertical band = the full line band (ascent+descent) from `prep.metrics`.
"""
function redaction_rects(boxes, prep, kept; bleed = 1.0)
    keptset = Set(kept)
    m = prep.metrics
    band = m.ascent + m.descent
    rects = RedactRect[]
    i = 1
    n = length(boxes)
    while i <= n
        wb = boxes[i]
        if wb.seg_index in keptset
            i += 1; continue                      # survivors are never redacted
        end
        # start a run on this line of blacked words
        run_line = wb.line
        x0 = wb.x0
        x1 = wb.x1
        top = wb.baseline - m.ascent
        j = i + 1
        while j <= n && boxes[j].line == run_line && !(boxes[j].seg_index in keptset)
            x1 = boxes[j].x1
            j += 1
        end
        push!(rects, RedactRect(x0 - bleed, x1 + bleed, top, top + band))
        i = j
    end
    return rects
end
