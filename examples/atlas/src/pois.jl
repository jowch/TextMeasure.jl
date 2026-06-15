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
end

"""
    atlas_areals() -> Vector{Areal}

Region labels. Positions / rotations are FIRST GUESSES — easy to nudge: each is one
`(text, lon, lat, rotation_deg, fontsize, kind)` row. The operator fine-tunes visually.
"""
function atlas_areals()
    raw = [
        ("PACIFIC OCEAN",      -121.05, 35.15, -38.0, 30.0, :water),
        ("SANTA LUCIA RANGE",  -120.62, 35.55, -40.0, 20.0, :range),
        ("ESTERO BAY",         -120.95, 35.42, -30.0, 14.0, :water),
    ]
    [Areal(txt, Point2f(project_point(lon, lat)...), rot, fs, kind)
     for (txt, lon, lat, rot, fs, kind) in raw]
end
