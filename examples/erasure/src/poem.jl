# Survivors as (word, occurrence-ordinal-among-:word-segments). Ordinals are fixed by
# the verbatim LICENSE_TEXT word sequence; the test re-derives & verifies them, so a
# wrong ordinal fails loudly. SPEC §3 Candidate A reading order.
#
# NOTE: `prepare` tokenizes on whitespace only, so punctuation rides with its word
# (e.g. "granted,", "Software,", "SOFTWARE."). The kept tokens below are therefore the
# EXACT segment strings — the test asserts `prep.segments[segi].str == k`. Ordinals are
# the explicit occurrence index of each token (computed once from LICENSE_TEXT), so the
# three "to"/"the"/"THE" repeats resolve to their intended position.
const KEPT_SPEC = [
    ("Permission",   1),                       # #1
    ("granted,",     1),                       # "...hereby granted,"
    ("to",           1), ("deal",      1),     # "to deal"
    ("without",      1), ("restriction,", 1),  # "without restriction,"
    ("to",           3), ("use,",      1),     # "to use,"
    ("modify,",      1),
    ("merge,",       1),
    ("distribute,",  1),
    ("the",          3), ("Software,", 1),     # "...sell copies of the Software,"
    ("WITHOUT",      1), ("WARRANTY",  1),
    ("OF",           1), ("ANY",       1), ("KIND,", 1),
    ("THE",          3), ("AUTHORS",   1),     # "...SHALL THE AUTHORS..."
    ("LIABLE",       1),
    ("ARISING",      1), ("FROM,",     1),
    ("THE",          6), ("SOFTWARE.", 1),     # "...DEALINGS IN THE SOFTWARE."
]

# Display list (what the margin readout / caption shows), the human-readable poem words.
const KEPT_WORDS = [w for (w, _) in KEPT_SPEC]

"""
    kept_seg_indices(prep) -> Vector{Int}

Resolve each survivor to its `prep.segments` index. For entries with a nonzero ordinal
we honor it; ordinal `0` means "the next not-yet-used occurrence of this word at or
after the previously matched word" (forward scan). Returns indices in reading order.
"""
function kept_seg_indices(prep)
    word_pos = [i for (i, s) in enumerate(prep.segments) if s.kind === :word]
    # ordinal -> segment index
    nth(word_str, want) = begin
        c = 0
        for (ord, i) in enumerate(word_pos)
            if prep.segments[i].str == word_str
                c += 1
                c == want && return i
            end
        end
        error("word $(repr(word_str)) occurrence $want not found")
    end
    idxs = Int[]
    last_i = 0
    for (w, ord) in KEPT_SPEC
        i = if ord > 0
            nth(w, ord)
        else
            # next occurrence strictly after last_i
            j = findfirst(p -> p > last_i && prep.segments[p].str == w, word_pos)
            j === nothing && error("word $(repr(w)) not found after index $last_i")
            word_pos[j]
        end
        push!(idxs, i); last_i = i
    end
    return idxs
end
