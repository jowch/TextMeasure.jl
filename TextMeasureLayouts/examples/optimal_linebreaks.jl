# SPDX-License-Identifier: MIT
#
# Optimal vs greedy paragraph line-breaking, shown FLUSH-justified to the measure.
# `knuth_plass` minimizes TOTAL badness over the whole paragraph; `greedy_justify` takes the
# first break that fits (what `layout` does). Run:
#   julia --project=TextMeasureLayouts TextMeasureLayouts/examples/optimal_linebreaks.jl

using TextMeasure, TextMeasureLayouts
using TextMeasure: MonospaceBackend, prepare

const PROSE = "in the practice of typesetting a paragraph reads best when its lines are evenly \
loose rather than tight here then loose there which is exactly the trade the greedy rule keeps \
making while the optimal program looks ahead to spread the slack"

# fontsize=1 / advance=1 ⇒ one glyph is one column, so widths read as character counts.
prep = prepare(MonospaceBackend(fontsize = 1.0, advance_ratio = 1.0, lineheight_ratio = 1.0), PROSE)
const W = 40

# Flush-justify `words` across W cells by padding the gaps; the ragged last line stays natural.
function justify(words; ragged = false)
    n = length(words); nat = join(words, " "); slack = W - length(nat)
    (ragged || n < 2 || slack <= 0) && return nat
    base, extra = divrem(slack, n - 1)
    io = IOBuffer()
    for k in 1:n
        print(io, words[k])
        k < n && print(io, ' '^(1 + base + (k <= extra ? 1 : 0)))
    end
    return String(take!(io))
end

function show_para(title, j)
    println(title, "  (total badness ", round(j.total_badness, digits = 1), ")")
    for (i, ln) in enumerate(j.lines)
        words = [prep.segments[k].str for k in ln.words]
        println("  | ", justify(words; ragged = i == lastindex(j.lines)))
    end
    println()
end

gdy = greedy_justify(prep; max_width = W)
opt = knuth_plass(prep; max_width = W)

show_para("greedy_justify:", gdy)
show_para("knuth_plass:", opt)

@assert opt.total_badness <= gdy.total_badness   # optimal never loses to greedy on total badness
println("✓ knuth_plass total badness ≤ greedy ($(round(opt.total_badness, digits=1)) ≤ $(round(gdy.total_badness, digits=1)))")
