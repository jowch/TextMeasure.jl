const FADE_FRAMES = 9

mutable struct FadeState
    born  :: Dict{Int,Int}   # town_id → frame it entered the active set
    _last :: Int             # most recent frame passed to update_fade!
end
FadeState() = FadeState(Dict{Int,Int}(), -1)

"Register the active set for `frame`: record births, forget departures, remember the frame."
function update_fade!(fs::FadeState, active_ids, frame::Int)
    a = Set(active_ids)
    for id in active_ids
        haskey(fs.born, id) || (fs.born[id] = frame)
    end
    for id in collect(keys(fs.born))
        id in a || delete!(fs.born, id)
    end
    fs._last = frame
    fs
end

"smoothstep alpha for a town at the most-recently-registered frame (0 if unknown/departed)."
function alpha_of(fs::FadeState, id::Int)
    haskey(fs.born, id) || return 0.0
    smoothstep((fs._last - fs.born[id]) / FADE_FRAMES)
end
