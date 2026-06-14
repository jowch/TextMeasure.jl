using Random
using TextMeasure: prepare

const _STOPWORDS = Set(["is","the","to","of","a","an","in","and","or","for","be","by",
                        "so","do","any","no","with","from","out","this","shall"])

"Headless toy state: cached geometry + a mutable kept-set. Toggles never re-measure."
mutable struct Toy
    prep
    boxes :: Vector{WordBox}
    kept  :: Set{Int}             # seg_index of kept words
end

"""
    new_toy(; max_width=HERO_MAX_WIDTH) -> Toy

Build the deterministic monospace field ONCE (prepare + word_boxes) and DEFAULT the
kept-set to the curated hero poem (SPEC §6 — the curated poem is first contact).
"""
function new_toy(; max_width = HERO_MAX_WIDTH)
    b = golden_backend()
    prep  = prepare(b, LICENSE_TEXT)
    boxes = word_boxes(prep; max_width = max_width)
    kept  = Set(kept_seg_indices(prep))
    return Toy(prep, boxes, kept)
end

"Toggle a word (by `prep.segments` index) kept<->blacked. O(1); no re-measure/layout."
function toggle!(t::Toy, seg_index::Int)
    seg_index in t.kept ? delete!(t.kept, seg_index) : push!(t.kept, seg_index)
    return t
end

"The current poem: kept words in reading (seg-index) order, space-joined."
function poem_readout(t::Toy)
    idxs = sort([wb.seg_index for wb in t.boxes if wb.seg_index in t.kept])
    return join((t.prep.segments[i].str for i in idxs), " ")
end

"""
    surprise!(t; seed, p=0.06) -> Toy

Labeled NON-ENGINE subtractive procgen: walk words in reading order, keep with prob `p`,
skip stop-words, never keep two adjacent words. Produces *a* poem, rarely *the* poem —
a secondary opt-in (never first contact). Seeded for deterministic tests.
"""
function surprise!(t::Toy; seed::Integer = 0, p::Float64 = 0.06)
    rng = Xoshiro(seed)
    empty!(t.kept)
    prev_kept = false
    for wb in t.boxes
        w = t.prep.segments[wb.seg_index].str
        if !prev_kept && !(lowercase(w) in _STOPWORDS) && rand(rng) < p
            push!(t.kept, wb.seg_index); prev_kept = true
        else
            prev_kept = false
        end
    end
    isempty(t.kept) && push!(t.kept, t.boxes[1].seg_index)  # never empty
    return t
end
