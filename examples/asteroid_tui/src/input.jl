# SPDX-License-Identifier: MIT
"""
    Input(; thrust=false, left=false, right=false, fire=false, debug=false, quit=false)

One tick's intent, decoupled from any key encoding. `fire` held across ticks grows
the charge; releasing it (a tick with `fire=false` after `fire=true`) launches.
"""
Base.@kwdef struct Input
    thrust::Bool = false
    left::Bool   = false
    right::Bool  = false
    fire::Bool   = false
    debug::Bool  = false
    quit::Bool   = false
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
