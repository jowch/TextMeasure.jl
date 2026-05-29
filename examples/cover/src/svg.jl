# SPDX-License-Identifier: MIT
#
# Minimal SVG parser for the editorial-inset illustration. STRAIGHT-LINE primitives
# only (rect/circle/ellipse/line/polyline/polygon/path with M/L/H/V/Z) so every shape
# becomes a Makie poly!/lines! ring — guaranteed native vector content, never a bitmap.
# Curves/arcs/transforms/CSS are intentionally UNSUPPORTED, and the parser FAILS LOUDLY
# (throws ArgumentError) when it sees them — a future asset edit that strays out of the
# subset must break the parse, never silently drop shapes.

using GeometryBasics: Point2f

const _NAMED_COLORS = Dict{String,NTuple{3,Float64}}(
    "black"=>(0,0,0), "white"=>(1,1,1), "red"=>(1,0,0), "green"=>(0,0.5,0),
    "blue"=>(0,0,1), "gray"=>(0.5,0.5,0.5), "grey"=>(0.5,0.5,0.5),
    "orange"=>(1,0.65,0), "gold"=>(1,0.84,0), "navy"=>(0,0,0.5),
    "steelblue"=>(0.27,0.51,0.71), "firebrick"=>(0.7,0.13,0.13),
)

# A parsed style color as an RGB tuple, or nothing for "none"/absent.
function _parse_color(s::Union{Nothing,AbstractString})
    s === nothing && return nothing
    s = strip(lowercase(String(s)))
    (s == "none" || isempty(s)) && return nothing
    if startswith(s, "#")
        hex = s[2:end]
        if length(hex) == 3
            r = parse(Int, hex[1]*hex[1]; base=16)
            g = parse(Int, hex[2]*hex[2]; base=16)
            b = parse(Int, hex[3]*hex[3]; base=16)
            return (r/255, g/255, b/255)
        elseif length(hex) == 6
            return (parse(Int, hex[1:2]; base=16)/255,
                    parse(Int, hex[3:4]; base=16)/255,
                    parse(Int, hex[5:6]; base=16)/255)
        end
        return nothing
    end
    return get(_NAMED_COLORS, s, nothing)
end

# One source-space primitive: a list of (x,y) in viewBox coords + style + closed flag.
struct SvgPrim
    pts          :: Vector{Tuple{Float64,Float64}}
    closed       :: Bool
    fill         :: Union{Nothing,NTuple{3,Float64}}
    fill_opacity :: Float64
    stroke       :: Union{Nothing,NTuple{3,Float64}}
    stroke_width :: Float64
end

struct SvgDoc
    viewbox :: NTuple{4,Float64}     # (minx, miny, width, height)
    prims   :: Vector{SvgPrim}
end

# A fitted ring in ABSOLUTE page coords (block-top), ready for Makie.
struct SvgRing
    points       :: Vector{Point2f}
    closed       :: Bool
    fill         :: Union{Nothing,NTuple{3,Float64}}
    fill_opacity :: Float64
    stroke       :: Union{Nothing,NTuple{3,Float64}}
    stroke_width :: Float64
end

# ---- tiny attribute scraping (regex over a single element's text) ----------
_attr(el, name) = (m = match(Regex("\\b$(name)\\s*=\\s*\"([^\"]*)\""), el)) === nothing ? nothing : m.captures[1]
_attrf(el, name, default) = (v = _attr(el, name)) === nothing ? default : parse(Float64, v)
_nums(s) = [parse(Float64, t) for t in split(s, r"[\s,]+"; keepempty=false)]

function _circle_ring(cx, cy, rx, ry; nseg=48)
    [(cx + rx*cos(2π*k/nseg), cy + ry*sin(2π*k/nseg)) for k in 0:(nseg-1)]
end

# Parse a path's straight-line subset (M/L/H/V/Z + lowercase). Returns (pts, closed).
# Throws on curve/arc commands (C/S/Q/T/A) — see parse_svg's loud-failure contract.
function _parse_path(d::AbstractString)
    occursin(r"[CcSsQqTtAa]", d) &&
        throw(ArgumentError("SVG path command out of supported subset (curve/arc C/S/Q/T/A) in d=$(repr(d)); only M/L/H/V/Z are supported"))
    toks = collect(eachmatch(r"([MLHVZmlhvz])|(-?\d*\.?\d+(?:e-?\d+)?)", d))
    pts = Tuple{Float64,Float64}[]; closed = false
    cx = cy = 0.0; cmd = 'M'
    stream = Any[]
    for m in toks
        if m.captures[1] !== nothing
            push!(stream, m.captures[1][1])
        else
            push!(stream, parse(Float64, m.match))
        end
    end
    j = 1
    while j <= length(stream)
        t = stream[j]
        if t isa Char
            cmd = t; j += 1
            cmd in ('Z','z') && (closed = true)
            continue
        end
        if cmd in ('M','L')
            x = stream[j]; y = stream[j+1]; j += 2
            cx, cy = x, y; push!(pts, (cx, cy)); cmd == 'M' && (cmd = 'L')
        elseif cmd in ('m','l')
            x = stream[j]; y = stream[j+1]; j += 2
            cx += x; cy += y; push!(pts, (cx, cy)); cmd == 'm' && (cmd = 'l')
        elseif cmd == 'H'; cx = stream[j]; j += 1; push!(pts, (cx, cy))
        elseif cmd == 'h'; cx += stream[j]; j += 1; push!(pts, (cx, cy))
        elseif cmd == 'V'; cy = stream[j]; j += 1; push!(pts, (cx, cy))
        elseif cmd == 'v'; cy += stream[j]; j += 1; push!(pts, (cx, cy))
        else; j += 1
        end
    end
    return pts, closed
end

"""
    parse_svg(path) -> SvgDoc

Parse the supported straight-line subset of an SVG file into source-space
primitives. `viewBox` defaults to `(0,0,100,100)` when absent.

**Loud failure:** throws `ArgumentError` on out-of-subset input — `<g>`/`<use>`
wrappers, any `transform=` attribute, or path curve/arc commands (`C/S/Q/T/A`).
Béziers, arcs, transforms, gradients, and CSS are not supported; a future asset
edit straying out of the subset breaks the parse rather than silently dropping
shapes.
"""
function parse_svg(path::AbstractString)::SvgDoc
    s = read(path, String)
    occursin(r"<\s*(g|use)\b", s) &&
        throw(ArgumentError("unsupported SVG element <g>/<use> in $(path); flatten the illustration to top-level primitives"))
    occursin(r"\btransform\s*=", s) &&
        throw(ArgumentError("unsupported SVG transform= attribute in $(path); bake transforms into coordinates"))
    vbm = match(r"viewBox\s*=\s*\"([^\"]*)\"", s)
    vb = vbm === nothing ? (0.0,0.0,100.0,100.0) : (let n=_nums(vbm.captures[1]); (n[1],n[2],n[3],n[4]); end)
    prims = SvgPrim[]
    for m in eachmatch(r"<(rect|circle|ellipse|line|polyline|polygon|path)\b([^>]*)>", s)
        tag = m.captures[1]; el = m.match
        fill   = _parse_color(_attr(el, "fill"))
        stroke = _parse_color(_attr(el, "stroke"))
        fo     = _attrf(el, "fill-opacity", 1.0)
        sw     = _attrf(el, "stroke-width", 1.0)
        if tag == "rect"
            x = _attrf(el,"x",0); y = _attrf(el,"y",0); w = _attrf(el,"width",0); h = _attrf(el,"height",0)
            pts = [(x,y),(x+w,y),(x+w,y+h),(x,y+h)]; closed = true
        elseif tag == "circle"
            cx=_attrf(el,"cx",0); cy=_attrf(el,"cy",0); r=_attrf(el,"r",0)
            pts = _circle_ring(cx,cy,r,r); closed = true
        elseif tag == "ellipse"
            cx=_attrf(el,"cx",0); cy=_attrf(el,"cy",0); rx=_attrf(el,"rx",0); ry=_attrf(el,"ry",0)
            pts = _circle_ring(cx,cy,rx,ry); closed = true
        elseif tag == "line"
            pts = [(_attrf(el,"x1",0),_attrf(el,"y1",0)),(_attrf(el,"x2",0),_attrf(el,"y2",0))]; closed = false
        elseif tag in ("polyline","polygon")
            v = _nums(something(_attr(el,"points"),""))
            pts = [(v[2k-1], v[2k]) for k in 1:(length(v)÷2)]; closed = (tag == "polygon")
        else # path
            pts, closed = _parse_path(something(_attr(el,"d"),""))
        end
        isempty(pts) && continue
        push!(prims, SvgPrim(pts, closed, fill, fo, stroke, sw))
    end
    return SvgDoc(vb, prims)
end

"""
    svg_rings(doc, rect::BBox) -> Vector{SvgRing}

Fit `doc`'s primitives into `rect` (absolute page coords, block-top) with a uniform
"meet" scale (preserve aspect, center). Source y is in SVG's y-down space, which
matches our block-top frame, so no y-flip is applied here (the render layer flips
once, globally). `stroke_width` is scaled by the same uniform factor.
"""
function svg_rings(doc::SvgDoc, rect::BBox)::Vector{SvgRing}
    minx, miny, vw, vh = doc.viewbox
    rw = rect.right - rect.left; rh = rect.bottom - rect.top
    (vw <= 0 || vh <= 0) && (vw = max(vw,1); vh = max(vh,1))
    s = min(rw / vw, rh / vh)                       # uniform meet
    offx = rect.left + (rw - s*vw)/2
    offy = rect.top  + (rh - s*vh)/2
    tf((x,y)) = Point2f(offx + s*(x - minx), offy + s*(y - miny))
    return [SvgRing([tf(p) for p in pr.pts], pr.closed, pr.fill, pr.fill_opacity,
                    pr.stroke, s*pr.stroke_width) for pr in doc.prims]
end
