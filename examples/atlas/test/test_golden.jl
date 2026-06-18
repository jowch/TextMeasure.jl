# SPDX-License-Identifier: MIT
using Atlas
using Atlas: golden_rows, atlas_digest, GOLDEN_FRAMES, placement_rows, atlas_placement_digest
using Test

# THE DETERMINISTIC GOLDEN. The gallery invariant: hash the COMPUTED layout table, NEVER pixels.
# The Atlas table is its per-feature LoD/opacity table — purely geometric (font_px from ground-ems,
# band = legibility/size fade × edge fade over a verified affine projection), so it needs no font
# engine, no solver, no Makie. Any change to the scaling/fade math (town growth, the areal cloud
# hand-off, edge fade) moves the digest. Update with `UPDATE_GOLDEN=1`.

const GOLDEN_DIR = joinpath(@__DIR__, "golden")

@testset "golden: deterministic Atlas LoD/opacity table (geometric, no pixels)" begin
    rows = golden_rows()
    @test !isempty(rows)
    # fixed-size table: (24 towns + 12 POIs + 4 areals) × 6 frames = 240 rows.
    @test length(rows) == 240

    cs = atlas_digest()
    @test length(cs) == 64                                   # sha256 hex

    # non-vacuous structural checks across the pinned frames:
    # the Range areal is FULLY OPAQUE on the wide shot and FADED OUT by the town-scale frame —
    # the cloud hand-off we tuned (gone by the time the inland towns arrive).
    @test any(r -> startswith(r, "0|areal|SANTA LUCIA RANGE|") && endswith(r, "|1.0"), rows)
    @test any(r -> startswith(r, "128|areal|SANTA LUCIA RANGE|") && endswith(r, "|0.0"), rows)
    # a major town is HIDDEN wide (band 0) and SHOWN (band > 0) at the apex — geographic scaling.
    @test any(r -> startswith(r, "0|town|") && endswith(r, "|0.0"), rows)
    @test any(r -> startswith(r, "180|town|") && occursin(r"\|0\.[1-9]", r), rows)

    path = joinpath(GOLDEN_DIR, "atlas.sha256")
    if get(ENV, "UPDATE_GOLDEN", "") == "1"
        mkpath(GOLDEN_DIR)
        write(path, cs)
        write(joinpath(GOLDEN_DIR, "atlas.rows.txt"), join(rows, "\n"))
    end
    @test isfile(path)                                       # fails closed without the sha file
    @test cs == strip(read(path, String))                   # regression anchor
end

# Placement golden: the solver's DISCRETE decisions (which side each label leans + dropped),
# now that MakieTextRepel guarantees solver determinism (public warm_solve, PR #27). Hashes the
# side quadrant — NOT pixel offsets — so it stays machine-stable (a quadrant only flips on a real
# re-placement; offset magnitude/continuity is covered by test_loop's warm-start delta bound).
# Update with `UPDATE_GOLDEN=1`.
@testset "golden: deterministic Atlas placement decisions (side + dropped, machine-stable)" begin
    prows = placement_rows()
    @test !isempty(prows)

    ps = atlas_placement_digest()
    @test length(ps) == 64                                   # sha256 hex

    # non-vacuous: the solver actually distributes labels — not every label leans the same way.
    @test any(r -> endswith(r, "|+|+"), prows)               # some lean upper-right
    @test any(r -> occursin("|-|", r), prows)                # some lean left
    @test length(prows) >= 20                                # labels actually get placed across the dive

    ppath = joinpath(GOLDEN_DIR, "atlas-placement.sha256")
    if get(ENV, "UPDATE_GOLDEN", "") == "1"
        mkpath(GOLDEN_DIR)
        write(ppath, ps)
        write(joinpath(GOLDEN_DIR, "atlas-placement.rows.txt"), join(prows, "\n"))
    end
    @test isfile(ppath)                                      # fails closed without the sha file
    @test ps == strip(read(ppath, String))                  # regression anchor
end
