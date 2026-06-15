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
        ("Morro Rock",              -120.866,  35.369),
        ("Hearst Castle",           -121.168,  35.685),
        ("Montaña de Oro",          -120.887,  35.276),
        ("Point Buchon",            -120.898,  35.254),
        ("Pismo Dunes",             -120.633,  35.098),
        ("Bishop Peak",             -120.690,  35.305),
        ("Cerro San Luis",          -120.674,  35.281),
        ("Lopez Lake",              -120.470,  35.243),
        ("Santa Margarita Lake",    -120.503,  35.339),
        ("Lake Nacimiento",         -120.902,  35.752),
        ("Mission San Luis Obispo", -120.6655, 35.2806),
        ("Point Sal",               -120.672,  34.902),
    ]
    [POI(nm, Point2f(project_point(lon, lat)...), :landmark) for (nm, lon, lat) in raw]
end

"""
A CURVED region label ("areal"): water bodies, ranges. Anchored at a real lon/lat, laid
out glyph-by-glyph along a circular arc (each glyph MEASURED by TextMeasure). Its size is
GEOGRAPHIC — `ground` is its em in degrees of latitude, so it grows with zoom; `max_px`
is the upper hand-off (a coarse region hides once its type outgrows that pixel height).
`rotation` is the base tilt (deg); `sweep` is the signed total bend across the baseline
(deg, 0 = straight); `tracking` is extra px added per glyph advance (caps breathing room).
"""
struct Areal
    text     :: String
    pos      :: Point2f     # projected map-units
    rotation :: Float64     # base tilt, degrees (counter-clockwise)
    ground   :: Float64     # ground em (degrees latitude) → font_px = ground * P
    kind     :: Symbol      # :water | :range
    max_px   :: Float64     # upper band: hide (hand off) when font_px exceeds this
    sweep    :: Float64     # signed total bend across the baseline, degrees (0 = straight)
    tracking :: Float64     # extra px per-glyph advance fraction of font_px (caps breathing)
end

"""
    atlas_areals() -> Vector{Areal}

Region labels, curved + sized geographically. The big regions (Pacific Ocean, the range)
have the largest ground ems so they dominate the WIDE establishing shots, then HAND OFF
once they outgrow the frame past `max_px`; smaller features (Estero Bay) reach legibility
later in the dive. Each row is
`(text, lon, lat, rotation°, ground°, kind, max_px, sweep°, tracking)` — easy to nudge.
`tracking` is a FRACTION of font_px added to each glyph advance (range breathes; water 0).
"""
function atlas_areals()
    # ground°/max_px tuned to the [2.0, 0.55] dive (Ocean → Mountains → … → Bay):
    # Pacific dominant at w2 (~68px), hands off ~w1.1; Range present at w2 (~44px), peaks
    # ~w1.2, hands off ~w0.68; Estero swells in the cluster. Range anchor nudged east to
    # -120.78 so it stays in-frame at the narrower W_WIDE=2.0.
    raw = [
        ("PACIFIC OCEAN",      -121.35, 35.25, -34.0, 0.070, :water, 120.0,  26.0, 0.0),
        ("SANTA LUCIA RANGE",  -120.78, 35.52, -42.0, 0.045, :range, 130.0, -18.0, 0.25),
        ("ESTERO BAY",         -120.95, 35.42, -30.0, 0.018, :water, 100.0,  28.0, 0.0),
    ]
    [Areal(txt, Point2f(project_point(lon, lat)...), rot, ground, kind, max_px, sweep, tracking)
     for (txt, lon, lat, rot, ground, kind, max_px, sweep, tracking) in raw]
end
