import TextMeasure
using TextMeasure: Segment, Prepared, FontMetrics
using TextMeasureLayouts: knuth_plass

"""
    Placement(index, str, font, size, color, role, x, baseline)

One laid-out word in the justified body. `index` is the 1-based word index; `str` the
sentence-cased display string; `font`/`size`/`color` the rendered face; `role` is
`:red` / `:black` / `:ghost`; `x` the justified left edge and `baseline` the block-top-frame
baseline (both in px). Read-only by convention.
"""
struct Placement
    index    :: Int
    str      :: String
    font     :: String
    size     :: Int
    color    :: Any
    role     :: Symbol
    x        :: Float64
    baseline :: Float64
end

# Role of a word from its style — the colour-keyed poem membership (for the golden table).
function _role(s::WStyle, ghost_color, red_color, black_color)
    s.lit || return :ghost
    s.color === red_color   && return :red
    s.color === black_color && return :black
    return :ghost
end

"""
    placement_table(make_backend; ghost_color, red_color, black_color,
                    measure_ch=MEASURE_CH) -> (placements, layout, pitch)

THE engine showcase. Given `make_backend(font_path, size) -> backend`, MEASURE every license
word at its real face/size, build a synthetic `Prepared` of MIXED-size boxes (interword glue
scaled by the larger neighbouring size; a `:newline` at each paragraph break), justify it with
`knuth_plass` on a constant pre-calculated `pitch` (fits the tallest word), and return the
placement table (one `Placement` per word, in reading order) plus the raw `JustifiedLayout`.

The measure→synthetic-Prepared→`knuth_plass` pipeline is parameterized only by `make_backend`,
so the hero passes `MakieBackend` (real font widths) and the golden passes `MonospaceBackend`
(deterministic widths) through the SAME code.
"""
function placement_table(make_backend; ghost_color, red_color, black_color,
                         measure_ch = MEASURE_CH)
    words, styles, para_start =
        styled_words(; ghost_color = ghost_color, red_color = red_color,
                       black_color = black_color)
    N = length(words)

    # backend cache keyed by (font, size); measure/metrics primitives over it.
    cache = Dict{Tuple{String,Float64},Any}()
    bk(font, size) = get!(() -> make_backend(font, Float64(size)), cache, (font, Float64(size)))
    advance(font, size, txt) = TextMeasure.measure(bk(font, size), txt)
    metrics(font, size)      = TextMeasure.font_metrics(bk(font, size))

    disp(i) = display_str(words, styles, para_start, i)

    # measure every word at its real face; ghost reference geometry on the Plex body face.
    plex = HouseStyle.plexmono("Regular")
    col_w   = measure_ch * advance(plex, BODY_PT, "M")
    space_w = advance(plex, BODY_PT, " ")

    wwidth = [advance(styles[i].font, styles[i].size, disp(i)) for i in 1:N]
    wasc   = [metrics(styles[i].font, styles[i].size).ascent  for i in 1:N]
    wdesc  = [metrics(styles[i].font, styles[i].size).descent for i in 1:N]
    asc   = maximum(wasc)
    desc  = maximum(wdesc)
    pitch = asc + desc + 5.0          # constant, pre-calculated line height (fits the tallest word)

    # synthetic Prepared: MIXED-size boxes carrying measured widths; interword glue scales
    # with the larger neighbouring size; a paragraph break is a forced :newline.
    syn = Segment[]
    synmap = Dict{Int,Int}()           # synthetic-segment index -> word index
    for i in 1:N
        push!(syn, Segment(disp(i), wwidth[i], :word))
        synmap[length(syn)] = i
        if i < N
            if (i + 1) in para_start
                push!(syn, Segment("", 0.0, :newline))
            else
                glue = space_w * max(Float64(styles[i].size), Float64(styles[i + 1].size)) / BODY_PT
                push!(syn, Segment(" ", glue, :space))
            end
        end
    end
    prep = Prepared(syn, FontMetrics(asc, desc, pitch))
    jl = knuth_plass(prep; max_width = col_w, lineheight = 1.0)

    placements = Placement[]
    for ln in jl.lines
        for (synidx, x) in zip(ln.words, ln.word_x)
            i = synmap[synidx]
            s = styles[i]
            push!(placements, Placement(i, disp(i), s.font, s.size, s.color,
                                        _role(s, ghost_color, red_color, black_color),
                                        x, body_top_baseline(ln.baseline)))
        end
    end
    # keep placements in reading order (word index) for stable downstream consumers.
    sort!(placements; by = p -> p.index)
    return placements, jl, pitch
end

# Identity offset hook: the layout frame's baselines are block-top = 0. The hero adds its
# own page offset; the golden hashes these raw baselines. Kept as a named seam for clarity.
body_top_baseline(b) = b
