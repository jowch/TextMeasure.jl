# SPDX-License-Identifier: MIT
using Atlas: view_width, view_center, camera_rect, W_WIDE, W_TIGHT, N_FRAMES
using Test

@testset "camera: geometric zoom + seamless loop" begin
    # the dive is a less-extreme 2.0° → 0.55° (~3.6×), staying where the coast is rich
    @test W_WIDE  ≈ 2.0
    @test W_TIGHT ≈ 0.55
    @test view_width(0.0) ≈ W_WIDE
    @test view_width(0.5) ≈ W_TIGHT          # apex at the loop midpoint
    @test view_width(1.0) ≈ W_WIDE           # loop closes on width
    # geometric (log-linear) on the way down: midpoint of first half is the geo-mean
    @test view_width(0.25) ≈ exp((log(W_WIDE)+log(W_TIGHT))/2) rtol=0.05
    # velocity ~0 at seam and apex (smoothstep dwell) → finite-diff slope tiny
    d(f,p;h=1e-4) = (f(p+h)-f(p-h))/(2h)
    for p in (0.0, 0.5, 1.0)
        @test abs(d(view_width, mod(p,1.0))) < 0.2
    end
    # center pans toward the cluster and returns
    @test view_center(0.5)[1] > view_center(0.0)[1]   # panned east (less negative lon)
    @test collect(view_center(1.0)) ≈ collect(view_center(0.0))

    # camera_rect: the data window matches the requested CONTENT aspect, so an
    # isotropic projection fills the frame without distortion. width/height of the
    # returned rect (in map-units) ≈ aspect.
    for A in (5/4, 16/10, 1.0)
        xmin, xmax, ymin, ymax = camera_rect(0.3; aspect = A)
        @test (xmax - xmin) / (ymax - ymin) ≈ A
    end
end
