#!/usr/bin/env julia
# prep/clip_water.jl — fetch + clip inland-water layers (lakes + rivers) into the Atlas
# basemap data dir, mirroring prep/clip.jl. Run manually (network-touching):
#   julia --project examples/atlas/prep/clip_water.jl
# Writes examples/atlas/data/lakes.geojson + rivers.geojson and PRINTS what landed in bbox
# (named lakes especially), so we can judge what real geological detail Natural Earth carries
# here before wiring it into the render. DO NOT run from tests.

using Downloads, JSON3

const LON_MIN = -122.2; const LON_MAX = -119.6
const LAT_MIN =  34.3;  const LAT_MAX =  37.0
const EXPAND  =   0.5
const ELON_MIN = LON_MIN - EXPAND; const ELON_MAX = LON_MAX + EXPAND
const ELAT_MIN = LAT_MIN - EXPAND; const ELAT_MAX = LAT_MAX + EXPAND

in_bbox(lon, lat) = ELON_MIN ≤ lon ≤ ELON_MAX && ELAT_MIN ≤ lat ≤ ELAT_MAX
any_in(coords) = any(p -> in_bbox(p[1], p[2]), coords)

"Coerce a possibly-null GeoJSON property to a String."
_str(x) = x === nothing ? "" : String(x)
_name(props) = _str(get(props, "name", get(props, "Name", "")))

function split_path(pts)
    subs = Vector{Vector}(); cur = []
    for pt in pts
        if in_bbox(pt[1], pt[2]); push!(cur, pt)
        else; length(cur) ≥ 2 && push!(subs, cur); cur = []; end
    end
    length(cur) ≥ 2 && push!(subs, cur)
    subs
end

function clip_ring(ring)
    kept = filter(pt -> in_bbox(pt[1], pt[2]), ring)
    length(kept) ≥ 4 || return nothing
    kept[1] != kept[end] && push!(kept, kept[1])
    kept
end

const BASE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson"
function fetch_geojson(name)
    dest = joinpath(tempdir(), "$name.geojson")
    isfile(dest) ? println("  (cached $dest)") :
        (println("  downloading $name ..."); Downloads.download("$BASE/$name.geojson", dest))
    JSON3.read(read(dest, String))
end

# ── lakes (polygons) ─────────────────────────────────────────────────────────
function clip_lakes(data)
    feats = []; nv = 0; named = String[]
    for feat in data["features"]
        geom = feat["geometry"]; geom === nothing && continue
        props = feat["properties"]; nm = _name(props)
        gtype = geom["type"]; coords = geom["coordinates"]
        rings_out = []
        if gtype == "Polygon"
            any_in(coords[1]) || continue
            for r in coords; c = clip_ring(collect(r)); c !== nothing && push!(rings_out, c); end
            isempty(rings_out) && continue
            push!(feats, Dict("type"=>"Feature","properties"=>Dict("name"=>nm),
                  "geometry"=>Dict("type"=>"Polygon","coordinates"=>rings_out)))
        elseif gtype == "MultiPolygon"
            polys = []
            for poly in coords
                any_in(poly[1]) || continue
                pr = []; for r in poly; c = clip_ring(collect(r)); c !== nothing && push!(pr, c); end
                isempty(pr) || push!(polys, pr)
            end
            isempty(polys) && continue
            push!(feats, Dict("type"=>"Feature","properties"=>Dict("name"=>nm),
                  "geometry"=>Dict("type"=>"MultiPolygon","coordinates"=>polys)))
        else; continue; end
        nv += 1; isempty(nm) || push!(named, nm)
    end
    println("  lakes: $(length(feats)) features in bbox; named: ", isempty(named) ? "(none)" : join(unique(named), ", "))
    feats
end

# ── rivers (linestrings) ─────────────────────────────────────────────────────
function clip_rivers(data)
    feats = []; named = String[]
    for feat in data["features"]
        geom = feat["geometry"]; geom === nothing && continue
        props = feat["properties"]; nm = _name(props)
        gtype = geom["type"]; coords = geom["coordinates"]
        subs = []
        if gtype == "LineString"
            any_in(coords) || continue; append!(subs, split_path(coords))
        elseif gtype == "MultiLineString"
            for ln in coords; any_in(ln) && append!(subs, split_path(ln)); end
        else; continue; end
        isempty(subs) && continue
        for sp in subs
            length(sp) < 2 && continue
            push!(feats, Dict("type"=>"Feature","properties"=>Dict("name"=>nm),
                  "geometry"=>Dict("type"=>"LineString","coordinates"=>sp)))
        end
        isempty(nm) || push!(named, nm)
    end
    println("  rivers: $(length(feats)) sub-paths in bbox; named: ", isempty(named) ? "(none)" : join(unique(named), ", "))
    feats
end

function write_fc(path, feats)
    open(path, "w") do io; JSON3.write(io, Dict("type"=>"FeatureCollection","features"=>feats)); end
    println("  wrote $(filesize(path) ÷ 1024) KB → $path")
end

function main()
    data_dir = joinpath(@__DIR__, "..", "data")
    println("\n=== Lakes ===");  L = clip_lakes(fetch_geojson("ne_10m_lakes"))
    # North America detail set carries more reservoirs; merge if present.
    try
        L2 = clip_lakes(fetch_geojson("ne_10m_lakes_north_america")); append!(L, L2)
        println("  (merged ne_10m_lakes_north_america)")
    catch e; println("  (no NA lakes set: $e)"); end
    write_fc(joinpath(data_dir, "lakes.geojson"), L)
    println("\n=== Rivers ==="); R = clip_rivers(fetch_geojson("ne_10m_rivers_lake_centerlines"))
    write_fc(joinpath(data_dir, "rivers.geojson"), R)
    println("\nDone.")
end
main()
