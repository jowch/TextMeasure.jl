# pois.jl — hand-placed feature anchors (the ONLY hand-positioned data in the
# piece: each POI / areal carries a real geographic location. Everything that
# follows — every label box — is MEASURED by TextMeasure and PLACED by
# MakieTextRepel's solve_cluster. These structs supply anchors only, never the
# label's final screen position.
#
# Included after data.jl (uses project_point / Point2f).

"A named point of interest (landmark) anchored at a real lon/lat."
struct POI
    name :: String
    pos  :: Point2f     # projected map-units (same space as Town.pos)
    kind :: Symbol      # :landmark — lets render mark POIs distinctly from towns
end

"""
    atlas_pois() -> Vector{POI}

The ~5 SLO-area landmarks. Locations are real; render marks them with a distinct
glyph from town dots. Add/trim freely — render LoD-gates by on-screen test only.
"""
function atlas_pois()
    raw = [
        ("Morro Rock",      -120.866, 35.369),
        ("Hearst Castle",   -121.168, 35.685),
        ("Montaña de Oro",  -120.887, 35.276),
        ("Point Buchon",    -120.898, 35.254),
        ("Pismo Dunes",     -120.633, 35.098),
    ]
    [POI(nm, Point2f(project_point(lon, lat)...), :landmark) for (nm, lon, lat) in raw]
end

"""
A rotated region label ("areal"): water bodies, ranges. Anchored at a real lon/lat,
drawn rotated to follow a feature. `text` is the raw caps string (render letterspaces
it); `rotation` is degrees; `fontsize` in pt. The label box is MEASURED by TextMeasure
at draw time — these fields are inputs to measurement, not a hand-sized box.
"""
struct Areal
    text     :: String
    pos      :: Point2f     # projected map-units
    rotation :: Float64     # degrees (counter-clockwise)
    fontsize :: Float64     # pt
    kind     :: Symbol      # :water | :range
    wmin     :: Float64     # eligible when wmin ≤ view_width(°) ≤ wmax …
    wmax     :: Float64     # … so big regions label the WIDE shots, small features the TIGHT ones
end

"""
    atlas_areals() -> Vector{Areal}

Region labels, zoom-gated like a real map: the big regions (Pacific Ocean, the range)
appear only on the WIDE establishing shots where there's room; small features (Estero
Bay) appear on the TIGHT shots. Each row is
`(text, lon, lat, rotation_deg, fontsize, kind, wmin°, wmax°)` — easy to nudge visually.
"""
function atlas_areals()
    # fontsizes are √2 RAMP tiers (display 44 · deck 31 · subhead 16) — never off-ramp.
    raw = [
        ("PACIFIC OCEAN",      -121.35, 35.25, -34.0, 44.0, :water, 1.2, Inf),  # display
        ("SANTA LUCIA RANGE",  -120.45, 35.62, -42.0, 31.0, :range, 0.9, Inf),  # deck
        ("ESTERO BAY",         -120.95, 35.42, -30.0, 16.0, :water, 0.0, 1.0),  # subhead
    ]
    [Areal(txt, Point2f(project_point(lon, lat)...), rot, fs, kind, wmin, wmax)
     for (txt, lon, lat, rot, fs, kind, wmin, wmax) in raw]
end
