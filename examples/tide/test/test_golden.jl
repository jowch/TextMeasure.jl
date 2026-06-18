# SPDX-License-Identifier: MIT
using Tide
using Tide: geometry_rows, tide_digest, GOLDEN_FRAMES
using Test

# THE DETERMINISTIC GOLDEN. The gallery invariant: hash the COMPUTED layout table (built with the
# machine-independent MonospaceBackend, floats rounded), NEVER the rendered pixels. `geometry_rows`
# runs the SAME `frame_layout` the renderer uses — including the per-band justify — at a handful of
# structurally-distinct frames (rest, a cardinal wall, a bottom-corner diagonal, a top-corner
# diagonal), so any change to the layout math moves the digest. Update with `UPDATE_GOLDEN=1`.

const GOLDEN_DIR = joinpath(@__DIR__, "golden")

@testset "golden: deterministic Tide layout table (Monospace, no pixels)" begin
    rows = geometry_rows()
    @test !isempty(rows)
    # non-vacuous: across the 4 pinned frames every word places, so the table is large.
    @test length(rows) > 200

    cs = tide_digest()
    @test length(cs) == 64                           # sha256 hex

    # ≥1 row from a DIAGONAL frame (SW peak = 300 or NE peak = 900) is present — the straight-
    # diagonal corner layouts are actually exercised, not just the rectangle + cardinal wall.
    @test any(r -> startswith(r, "300|") || startswith(r, "900|"), rows)
    # The lit column (via `has_lit`) flags the coral-bearing "kneads" placement in every pinned
    # frame — including the compound "kneads—smoothing" token, whose "kneads" run the renderer
    # lights. Assert the `lit==true` column is actually populated per frame (non-vacuous).
    for frame in GOLDEN_FRAMES
        @test any(r -> startswith(r, "$(frame)|") && occursin("|true|", r), rows)
    end

    path = joinpath(GOLDEN_DIR, "tide.sha256")
    if get(ENV, "UPDATE_GOLDEN", "") == "1"
        mkpath(GOLDEN_DIR)
        write(path, cs)
        write(joinpath(GOLDEN_DIR, "tide.rows.txt"), join(rows, "\n"))
    end
    @test isfile(path)                               # fails closed without the sha file
    @test cs == strip(read(path, String))            # regression anchor
end
