# Pre-flight check for the gallery's pinned fonts.
#
# Loads every static TTF in this directory BY FILE PATH through the real
# FreeTypeBackend (measure + font_metrics) — the same path the demos use — and
# fails loudly if any font won't load or render. Run this before kicking off the
# gallery /goal so a bad/missing font surfaces here, not mid-render.
#
#   julia --project=test examples/fonts/smoke_test.jl
#
# (test/Project.toml carries FreeTypeAbstraction; the FreeType extension supplies
# measure/font_metrics for FreeTypeBackend.)

using TextMeasure, FreeTypeAbstraction
const FTA = FreeTypeAbstraction

const FONTROOT = @__DIR__

files = String[]
for d in ("Fraunces", "IBMPlexMono")
    dir = joinpath(FONTROOT, d)
    isdir(dir) || continue
    for f in sort(readdir(dir))
        endswith(f, ".ttf") && push!(files, joinpath(dir, f))
    end
end
isempty(files) && error("no .ttf files found under $FONTROOT")

loadface(path) = try
    FTA.FTFont(path)
catch
    FTA.try_load(path)
end

pass = 0; fail = 0
for path in files
    try
        face = loadface(path)
        face === nothing && error("loader returned nothing")
        b = TextMeasure.FreeTypeBackend(face, 11.0, 72.0)
        w = TextMeasure.measure(b, "Measure")
        fm = TextMeasure.font_metrics(b)
        println("OK   ", rpad(basename(path), 30),
                " fam=", rpad(FTA.family_name(face), 22),
                " adv=", rpad(round(w, digits=2), 7),
                " asc=", round(fm.ascent, digits=2),
                " desc=", round(fm.descent, digits=2),
                " la=", round(fm.line_advance, digits=2))
        global pass += 1
    catch e
        println("FAIL ", rpad(basename(path), 30), " ", e)
        global fail += 1
    end
end
println("\n", pass, " ok / ", fail, " fail / ", length(files), " total")
fail == 0 || error("font smoke test FAILED")
println("SMOKE TEST PASSED")
