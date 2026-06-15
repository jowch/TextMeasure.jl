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
drawn rotated to follow a feature. Its on-screen size is GEOGRAPHIC — `ground` is its
em in degrees of latitude, so it grows with zoom like every other label. `max_px` is
the upper hand-off: a coarse region hides once its type outgrows that pixel height.
The drawn box is MEASURED by TextMeasure at the current font_px — these are inputs to
measurement, never a hand-sized box.
"""
struct Areal
    text     :: String
    pos      :: Point2f     # projected map-units
    rotation :: Float64     # degrees (counter-clockwise)
    ground   :: Float64     # ground em (degrees latitude) → font_px = ground * P
    kind     :: Symbol      # :water | :range
    max_px   :: Float64     # upper band: hide (hand off) when font_px exceeds this
end

"""
    atlas_areals() -> Vector{Areal}

Region labels sized geographically: the big regions (Pacific Ocean, the range) have the
largest ground ems so they dominate the WIDE establishing shots, then HAND OFF (hide)
once they outgrow the frame past `max_px`; smaller features (Estero Bay) reach legibility
later in the dive. Each row is `(text, lon, lat, rotation_deg, ground°, kind, max_px)` —
easy to nudge visually.
"""
function atlas_areals()
    raw = [
        ("PACIFIC OCEAN",      -121.35, 35.25, -34.0, 0.10,  :water, 150.0),
        ("SANTA LUCIA RANGE",  -120.45, 35.62, -42.0, 0.065, :range, 200.0),
        ("ESTERO BAY",         -120.95, 35.42, -30.0, 0.035, :water, 120.0),
    ]
    [Areal(txt, Point2f(project_point(lon, lat)...), rot, ground, kind, max_px)
     for (txt, lon, lat, rot, ground, kind, max_px) in raw]
end
