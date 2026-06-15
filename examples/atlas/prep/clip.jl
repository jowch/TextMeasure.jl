#!/usr/bin/env julia
# prep/clip.jl — one-shot fetcher + clipper for Atlas basemap data
# Run manually: julia --project examples/atlas/prep/clip.jl
# Writes to examples/atlas/data/. DO NOT run from tests (network-touching).
#
# Sources:
#   Natural Earth 1:10m coastline + land + populated_places
#   https://github.com/nvkelso/natural-earth-vector (public domain)

using Downloads, JSON3

# ── bbox ──────────────────────────────────────────────────────────────────────
const LON_MIN = -122.2
const LON_MAX = -119.6
const LAT_MIN =  34.3
const LAT_MAX =  37.0
const EXPAND  =   0.5   # degrees of margin when deciding which vertices to keep
                         # (0.5° ensures paths entering/leaving the frame aren't
                         #  clipped at the bbox edge; extra verts outside the
                         #  visible area are harmless and keep lines continuous)

const ELON_MIN = LON_MIN - EXPAND
const ELON_MAX = LON_MAX + EXPAND
const ELAT_MIN = LAT_MIN - EXPAND
const ELAT_MAX = LAT_MAX + EXPAND

# ── helpers ───────────────────────────────────────────────────────────────────

"""
    in_expanded_bbox(lon, lat) -> Bool
"""
in_expanded_bbox(lon, lat) =
    ELON_MIN ≤ lon ≤ ELON_MAX && ELAT_MIN ≤ lat ≤ ELAT_MAX

"""
    feature_bbox_intersects(coords_flat) -> Bool
Check if ANY vertex in a flattened coordinate list touches the expanded bbox.
"""
function any_in_expanded(coords)
    for pt in coords
        in_expanded_bbox(pt[1], pt[2]) && return true
    end
    return false
end

"""
    split_path(pts) -> Vector{Vector}
Walk a coordinate path; split wherever a vertex exits the expanded bbox.
Each returned sub-path contains only in-bbox vertices (run of consecutive).
"""
function split_path(pts)
    subpaths = Vector{Vector}()
    current = []
    for pt in pts
        if in_expanded_bbox(pt[1], pt[2])
            push!(current, pt)
        else
            if length(current) >= 2
                push!(subpaths, current)
            end
            current = []
        end
    end
    if length(current) >= 2
        push!(subpaths, current)
    end
    return subpaths
end

"""
    clip_linestring_coords(coords) -> Vector{Vector{Vector}}
For a LineString coordinate array, return clipped sub-paths (each is a coord array).
"""
clip_linestring_coords(coords) = split_path(coords)

"""
    clip_polygon_ring(ring) -> Union{Vector, Nothing}
Keep ring vertices that are in expanded bbox, return nothing if degenerate (<4 pts).
For polygons we do a simpler keep-if-in-bbox (no splitting to avoid open rings).
"""
function clip_polygon_ring(ring)
    kept = filter(pt -> in_expanded_bbox(pt[1], pt[2]), ring)
    # Close the ring if needed
    if length(kept) >= 4
        if kept[1] != kept[end]
            push!(kept, kept[1])
        end
        return kept
    end
    return nothing
end

# ── fetch ─────────────────────────────────────────────────────────────────────

const BASE_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson"

function fetch_geojson(name)
    url = "$BASE_URL/$name.geojson"
    dest = joinpath(tempdir(), "$name.geojson")
    if isfile(dest)
        println("  (using cached $dest)")
    else
        println("  downloading $url ...")
        Downloads.download(url, dest)
    end
    println("  parsing $(filesize(dest) ÷ 1024) KB ...")
    data = JSON3.read(read(dest, String))
    return data
end

# ── clip coastline (LineString features) ─────────────────────────────────────

function clip_coastline(data)
    out_features = []
    total_verts = 0

    for feat in data["features"]
        geom = feat["geometry"]
        geom === nothing && continue
        gtype = geom["type"]
        coords = geom["coordinates"]

        subpaths = []

        if gtype == "LineString"
            any_in_expanded(coords) || continue
            subpaths = clip_linestring_coords(coords)

        elseif gtype == "MultiLineString"
            for line in coords
                any_in_expanded(line) || continue
                append!(subpaths, clip_linestring_coords(line))
            end

        else
            continue  # skip polygons in coastline file
        end

        isempty(subpaths) && continue

        for sp in subpaths
            nv = length(sp)
            nv < 2 && continue
            total_verts += nv
            push!(out_features, Dict(
                "type" => "Feature",
                "geometry" => Dict(
                    "type" => "LineString",
                    "coordinates" => sp,
                ),
                "properties" => Dict(),
            ))
        end
    end

    println("  coastline: $(length(out_features)) features, $total_verts vertices")
    return out_features, total_verts
end

# ── clip land (Polygon features) ─────────────────────────────────────────────

function clip_land(data)
    out_features = []
    total_verts = 0

    for feat in data["features"]
        geom = feat["geometry"]
        geom === nothing && continue
        gtype = geom["type"]
        coords = geom["coordinates"]

        rings = []

        if gtype == "Polygon"
            any_in_expanded(coords[1]) || continue
            for ring in coords
                clipped = clip_polygon_ring(collect(ring))
                clipped !== nothing && push!(rings, clipped)
            end
            isempty(rings) && continue
            total_verts += sum(length.(rings))
            push!(out_features, Dict(
                "type" => "Feature",
                "geometry" => Dict(
                    "type" => "Polygon",
                    "coordinates" => rings,
                ),
                "properties" => Dict(),
            ))

        elseif gtype == "MultiPolygon"
            kept_polys = []
            for poly in coords
                any_in_expanded(poly[1]) || continue
                poly_rings = []
                for ring in poly
                    clipped = clip_polygon_ring(collect(ring))
                    clipped !== nothing && push!(poly_rings, clipped)
                end
                isempty(poly_rings) && continue
                total_verts += sum(length.(poly_rings))
                push!(kept_polys, poly_rings)
            end
            isempty(kept_polys) && continue
            push!(out_features, Dict(
                "type" => "Feature",
                "geometry" => Dict(
                    "type" => "MultiPolygon",
                    "coordinates" => kept_polys,
                ),
                "properties" => Dict(),
            ))
        end
    end

    println("  land: $(length(out_features)) features, $total_verts vertices")
    return out_features, total_verts
end

# ── extract NE populated places ───────────────────────────────────────────────

function extract_ne_places(data)
    in_bbox = []
    for feat in data["features"]
        geom = feat["geometry"]
        geom === nothing && continue
        props = feat["properties"]
        lon, lat = geom["coordinates"][1], geom["coordinates"][2]
        LON_MIN ≤ lon ≤ LON_MAX && LAT_MIN ≤ lat ≤ LAT_MAX || continue
        push!(in_bbox, (
            name = get(props, "NAME", ""),
            lon  = round(lon; digits=4),
            lat  = round(lat; digits=4),
            pop  = get(props, "POP_MAX", 0),
            scalerank = get(props, "SCALERANK", 99),
            source = "NE",
        ))
    end
    sort!(in_bbox; by = x -> x.scalerank)
    println("  populated_places: $(length(in_bbox)) in bbox")
    for p in in_bbox
        println("    $(p.name)  lon=$(p.lon) lat=$(p.lat) pop=$(p.pop) scalerank=$(p.scalerank)")
    end
    return in_bbox
end

# ── write GeoJSON ─────────────────────────────────────────────────────────────

function write_geojson(path, features)
    fc = Dict(
        "type" => "FeatureCollection",
        "features" => features,
    )
    open(path, "w") do io
        JSON3.write(io, fc)
    end
    println("  wrote $(filesize(path) ÷ 1024) KB → $path")
end

# ── main ──────────────────────────────────────────────────────────────────────

function main()
    data_dir = joinpath(@__DIR__, "..", "data")
    mkpath(data_dir)

    println("\n=== Coastline ===")
    coast_data = fetch_geojson("ne_10m_coastline")
    coast_features, coast_verts = clip_coastline(coast_data)
    write_geojson(joinpath(data_dir, "coastline.geojson"), coast_features)

    println("\n=== Land ===")
    land_data = fetch_geojson("ne_10m_land")
    land_features, land_verts = clip_land(land_data)
    write_geojson(joinpath(data_dir, "land.geojson"), land_features)

    println("\n=== Populated Places ===")
    places_data = fetch_geojson("ne_10m_populated_places")
    ne_places = extract_ne_places(places_data)

    println("\n=== Summary ===")
    println("  coastline vertices : $coast_verts  (gate: ≥400)")
    println("  land vertices      : $land_verts")
    coast_verts < 400 && @warn "coastline vertex count is LOW — check clipping / source data"

    println("\nDone. Now author towns.csv using the NE places printed above.")
    println("NE rows extracted: $(length(ne_places))")
end

main()
