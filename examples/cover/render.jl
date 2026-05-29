# SPDX-License-Identifier: MIT
# CLI: render a cover-vN.toml to a vector PDF (+ optional PNG for the visual gate).
#   julia --project=examples/cover examples/cover/render.jl data/cover-v1.toml [out.pdf]
using Cover

function main(args)
    isempty(args) && error("usage: render.jl <cover.toml> [out.pdf]")
    cfg = args[1]
    out = length(args) >= 2 ? args[2] : nothing
    pdf = render_cover(cfg; out = out, png = true)
    println("wrote ", pdf, " and ", replace(pdf, r"\.pdf$" => ".png"))
end

main(ARGS)
