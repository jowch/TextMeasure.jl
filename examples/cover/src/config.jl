# SPDX-License-Identifier: MIT
#
# load_config — parse cover.toml into a typed CoverConfig. Fonts are NOT read from
# the TOML (pinned in Cover.jl for golden reproducibility); only meta/layout/inset/
# body/pull_quote geometry + text come from the file.

_f(x) = Float64(x)

"""
    load_config(path) -> CoverConfig

Parse a `cover.toml` (schema in the issue body) into a [`CoverConfig`](@ref).
`page_size` must be one of `keys(PAGE_SIZES)`. `config_dir` is `dirname(path)`,
used to resolve `inset.svg_path` relative to the TOML file.
"""
function load_config(path::AbstractString)::CoverConfig
    raw = TOML.parsefile(path)
    meta   = get(raw, "meta", Dict{String,Any}())
    layout = get(raw, "layout", Dict{String,Any}())
    inset  = get(raw, "inset", Dict{String,Any}())
    bodies = get(raw, "body", Any[])
    pqs    = get(raw, "pull_quote", Any[])

    page_size = String(get(layout, "page_size", "letter"))
    haskey(PAGE_SIZES, page_size) ||
        throw(ArgumentError("unknown page_size $(repr(page_size)); valid: $(sort(collect(keys(PAGE_SIZES))))"))

    isempty(bodies) && throw(ArgumentError("cover.toml needs at least one [[body]] paragraph"))

    inset_spec = InsetSpec(
        String(inset["svg_path"]),
        _f(inset["x_px"]), _f(inset["y_px"]),
        _f(inset["width_px"]), _f(inset["height_px"]),
    )

    body = BodyPara[BodyPara(String(b["paragraph"]), Bool(get(b, "dropcap", false))) for b in bodies]

    pull_quotes = PullQuoteSpec[
        PullQuoteSpec(String(p["text"]), String(get(p, "attribution", "")),
                      _f(p["x_px"]), _f(p["y_px"]), _f(p["width_px"]))
        for p in pqs
    ]

    return CoverConfig(
        String(get(meta, "title", "")),
        String(get(meta, "subtitle", "")),
        String(get(meta, "byline", "")),
        page_size,
        _f(get(layout, "margin_px", 36)),
        Int(get(layout, "dropcap_lines", 3)),
        _f(get(layout, "gutter_px", 6)),
        inset_spec,
        body,
        pull_quotes,
        dirname(abspath(path)),
    )
end
