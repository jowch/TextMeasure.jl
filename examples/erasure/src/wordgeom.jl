"One word's recovered box. `x0/x1` are the left-aligned run extent in px; `baseline`
is block-top-relative (same coordinate system as `Line.baseline`). `seg_index` indexes
`prep.segments`."
struct WordBox
    seg_index :: Int
    line      :: Int
    x0        :: Float64
    x1        :: Float64
    baseline  :: Float64
end

"""
    word_boxes(prep; max_width=Inf, lineheight=1.0) -> Vector{WordBox}

Recover a per-word geometry table by re-walking `prep.segments` with the SAME greedy +
whitespace-trim rule `TextMeasure.layout` uses. Exact under `align=:left` (no kerning):
the accumulated x equals layout's placement. One WordBox per `:word` segment, in source
order. Verified against `layout(prep).lines` by the golden assertion in test_wordgeom.jl.
"""
function word_boxes(prep; max_width = Inf, lineheight = 1.0)
    m  = prep.metrics
    la = lineheight * m.line_advance
    mw = (isnan(max_width) || max_width <= 0) ? Inf : Float64(max_width)

    boxes   = WordBox[]
    line    = 1
    cur_x   = 0.0            # running right edge of committed content on this line
    has_word = false         # any word committed on this line yet?
    pending_w = 0.0          # width of a pending (not-yet-committed) space
    pending_open = false

    newline!() = (line += 1; cur_x = 0.0; has_word = false; pending_w = 0.0; pending_open = false)

    for (i, seg) in enumerate(prep.segments)
        if seg.kind === :newline
            newline!()
        elseif seg.kind === :space
            pending_w = seg.width; pending_open = true
        else  # :word
            if !has_word
                # first word on the line: no leading space, starts at x=0 (trim)
                x0 = 0.0
                push!(boxes, WordBox(i, line, x0, x0 + seg.width,
                                     m.ascent + (line - 1) * la))
                cur_x = seg.width; has_word = true; pending_open = false; pending_w = 0.0
            else
                extra = (pending_open ? pending_w : 0.0) + seg.width
                if cur_x + extra > mw
                    newline!()
                    x0 = 0.0
                    push!(boxes, WordBox(i, line, x0, x0 + seg.width,
                                         m.ascent + (line - 1) * la))
                    cur_x = seg.width; has_word = true
                else
                    x0 = cur_x + (pending_open ? pending_w : 0.0)
                    push!(boxes, WordBox(i, line, x0, x0 + seg.width,
                                         m.ascent + (line - 1) * la))
                    cur_x = x0 + seg.width; pending_open = false; pending_w = 0.0
                end
            end
        end
    end
    return boxes
end
