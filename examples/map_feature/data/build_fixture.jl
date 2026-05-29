# SPDX-License-Identifier: MIT
# One-time builder for the bundled Vermont fixture. Requires network (Census FTP).
# Run from the repo root:  julia --project=examples/map_feature examples/map_feature/data/build_fixture.jl
# NOT invoked by the test suite — the committed data/vermont.{shp,shx,dbf} is the offline source.
using Shapefile

const DATADIR = @__DIR__
tmp = mktempdir()
zip = joinpath(tmp, "states.zip")
run(`curl -s -o $zip ftp://ftp2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_state_500k.zip`)
run(`unzip -o -q $zip -d $tmp`)
tbl = Shapefile.Table(joinpath(tmp, "cb_2023_us_state_500k.shp"))
i = findfirst(==("VT"), tbl.STUSPS)
i === nothing && error("Vermont not found in Census state file")
geom = Shapefile.shapes(tbl)[i]
w = Shapefile.Writer([geom], (NAME=["Vermont"], STUSPS=["VT"], STATEFP=["50"]), nothing)
Shapefile.write(joinpath(DATADIR, "vermont.shp"), w; force=true)
println("wrote vermont.{shp,shx,dbf} (", length(geom.points), " points)")
