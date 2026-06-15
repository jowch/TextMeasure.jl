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

function load_atlas_data()
    coastline = _load_lines(joinpath(_DATA_DIR, "coastline.geojson"))
    land      = _load_lines(joinpath(_DATA_DIR, "land.geojson"))
    towns = Town[]
    for r in CSV.File(joinpath(_DATA_DIR, "towns.csv"))
        push!(towns, Town(r.town_id, r.name,
                          Point2f(project_point(r.lon, r.lat)...),
                          r.pop, r.rank, r.source))
    end
    AtlasData(coastline, land, towns)
end
