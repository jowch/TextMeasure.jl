# SPDX-License-Identifier: MIT
"""
    Input(; up=false, down=false, left=false, right=false, fire=false,
            aim=nothing, debug=false, quit=false)

One tick's intent, decoupled from key encoding (twin-stick).
  * `up`/`down`/`left`/`right` are **strafe** flags — direct-velocity movement; `left`/`right`
    strafe, they do NOT turn.
  * `fire` held grows the charge; the first `fire=false` after `fire=true` launches.
  * `aim` is the **cursor cell** `(cx, cy)` or `nothing`. The sim turns it into a heading from the
    live ship position; `nothing` ⇒ leave φ unchanged (headless paths stay reproducible).
All fields keyword-only.
"""
Base.@kwdef struct Input
    up::Bool    = false
    down::Bool  = false
    left::Bool  = false
    right::Bool = false
    fire::Bool  = false
    aim::Union{Nothing,Tuple{Float64,Float64}} = nothing
    debug::Bool = false
    quit::Bool  = false
end

"""
    ScriptedInput(seq::Vector{Input})

Deterministic input source for the headless golden test. `next_input!` returns the
next entry, repeating the last once exhausted.
"""
mutable struct ScriptedInput
    seq::Vector{Input}
    i::Int
end
ScriptedInput(seq::Vector{Input}) = ScriptedInput(seq, 0)
function next_input!(s::ScriptedInput)
    s.i = min(s.i + 1, length(s.seq))
    return isempty(s.seq) ? Input() : s.seq[s.i]
end
