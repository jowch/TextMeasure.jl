using CSV, GeoJSON, GeoInterface
using GeometryBasics: Point2f

const PHI0 = 35.7                       # reference latitude (deg)
const KX   = cosd(PHI0)                 # ≈ 0.812 — x-correction factor

"Pure affine lon/lat → shared map-units (x compressed by cos φ0, y = lat)."
project_point(lon::Real, lat::Real) = (KX * lon, float(lat))

struct Town
    town_id :: Int
    name    :: String
    pos     :: Point2f      # projected map-units
    pop     :: Int
    rank    :: Int
    source  :: String
end

struct AtlasData
    coastline :: Vector{Vector{Point2f}}   # projected polylines
    land      :: Vector{Vector{Point2f}}   # projected rings
    towns     :: Vector{Town}
    lakes     :: Vector{Vector{Point2f}}   # projected lake rings (inland water polygons)
    rivers    :: Vector{Vector{Point2f}}   # projected river centrelines (hydrography lines)
end

const _DATA_DIR = normpath(joinpath(@__DIR__, "..", "data"))

# Convert a single (lon, lat) tuple to a projected Point2f.
_pt(t::Tuple) = Point2f(project_point(t[1], t[2])...)

function _load_lines(path)
    fc = GeoJSON.read(read(path, String))
    out = Vector{Point2f}[]
    for feat in fc
        g = GeoInterface.geometry(feat)
        trait = GeoInterface.geomtrait(g)
        coords = GeoInterface.coordinates(g)
        if trait isa GeoInterface.LineStringTrait
            # coords::Vector{Tuple{Float32,Float32}} — one polyline per feature
            push!(out, [_pt(p) for p in coords])
        elseif trait isa GeoInterface.PolygonTrait
            # coords::Vector{rings}; ring = Vector{Tuple} — one ring list per polygon
            for ring in coords
                push!(out, [_pt(p) for p in ring])
            end
        elseif trait isa GeoInterface.MultiPolygonTrait
            # coords::Vector{polygons} where polygon = Vector{rings},
            # ring = Vector{Tuple{Float32,Float32}}
            for poly in coords
                for ring in poly
                    push!(out, [_pt(p) for p in ring])
                end
            end
        else
            @warn "Unhandled geometry trait: $trait in $path"
        end
    end
    out
end

# Chaikin corner-cutting: smooths an angular polyline by replacing each segment
# with points at 1/4 and 3/4, keeping the endpoints. 2 iterations rounds the
# coarse 10m generalization without inventing large new features.
function _chaikin(pts::Vector{Point2f}, iters::Int = 2)
    length(pts) < 3 && return pts
    out = pts
    for _ in 1:iters
        new = Point2f[out[1]]
        for i in 1:length(out)-1
            p, q = out[i], out[i+1]
            push!(new, Point2f(0.75f0 .* p .+ 0.25f0 .* q))
            push!(new, Point2f(0.25f0 .* p .+ 0.75f0 .* q))
        end
        push!(new, out[end])
        out = new
    end
    out
end

# Optional layer (lakes/rivers were added after the first basemap); load gracefully so a
# data dir without them still works. Chaikin-smoothed like the coast.
function _load_optional(name, smooth)
    path = joinpath(_DATA_DIR, name)
    isfile(path) || return Vector{Point2f}[]
    [_chaikin(seg, smooth) for seg in _load_lines(path)]
end

function load_atlas_data(; smooth::Int = 2)
    coastline = [_chaikin(seg, smooth) for seg in _load_lines(joinpath(_DATA_DIR, "coastline.geojson"))]
    land      = [_chaikin(ring, smooth) for ring in _load_lines(joinpath(_DATA_DIR, "land.geojson"))]
    lakes     = _load_optional("lakes.geojson",  smooth)
    rivers    = _load_optional("rivers.geojson", smooth)
    towns = Town[]
    for r in CSV.File(joinpath(_DATA_DIR, "towns.csv"))
        push!(towns, Town(r.town_id, r.name,
                          Point2f(project_point(r.lon, r.lat)...),
                          r.pop, r.rank, r.source))
    end
    AtlasData(coastline, land, towns, lakes, rivers)
end
