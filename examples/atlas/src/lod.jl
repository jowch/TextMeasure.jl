"Switch-on view width for a town from its LoD priority (majors appear wide, necklace late)."
function w_on_for(t)::Float64
    t.rank ≤ 5 ? 3.0 :          # majors: visible from the widest establishing shot
    t.rank ≤ 7 ? 1.5 :          # mid-dive band
                 0.7            # necklace: only as the cluster opens
end

const _HYST = 1.08

"Town ids eligible at view width w, with hysteresis vs the previously-active set."
function active_ids(towns, w::Real, prev_active)
    prev = Set(prev_active)
    ids = Int[]
    for t in towns
        won = w_on_for(t)
        thresh = (t.town_id in prev) ? _HYST * won : won   # sticky-off band
        w ≤ thresh && push!(ids, t.town_id)
    end
    ids
end
