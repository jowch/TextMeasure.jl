# SPDX-License-Identifier: MIT
# #F1 — DOIInfograph data layer: API clients, abstract reconstruction, offline cache.
#
# PROBE-FIRST deviations baked in here (see plan):
#  - SemanticScholarClient is a thin HTTP wrapper (SemanticScholar.jl can't coexist with CairoMakie).
#  - S2 arXiv DOIs use the ARXIV:<id> id scheme, not DOI:<doi>.
#  - OpenAlex lowercases DOIs in lookups.
#  - given/family come from CrossRef; OpenAlex/S2 expose only a single name string.
#  - HTTP 2.0: stable surface only (no readtimeout); compat "1, 2".

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

"A single author. `given`/`family` split from CrossRef; `affiliation` optional."
struct AuthorRef
    given       :: String
    family      :: String
    affiliation :: Union{String,Nothing}
end
AuthorRef(given, family) = AuthorRef(given, family, nothing)

"Unified paper metadata merged from OpenAlex (primary), CrossRef, Semantic Scholar."
Base.@kwdef struct PaperMetadata
    title             :: String
    authors           :: Vector{AuthorRef}             = AuthorRef[]
    abstract          :: Union{String,Nothing}         = nothing
    tldr              :: Union{String,Nothing}         = nothing
    citation_count    :: Int                           = 0
    citations_by_year :: Vector{Tuple{Int,Int}}        = Tuple{Int,Int}[]
    concepts          :: Vector{Tuple{String,Float64}} = Tuple{String,Float64}[]
    oa_status         :: Symbol                        = :unknown
    oa_url            :: Union{String,Nothing}         = nothing
    figure_url        :: Union{String,Nothing}         = nothing
    pp                :: Union{String,Nothing}         = nothing
    journal           :: Union{String,Nothing}         = nothing
    year              :: Union{Int,Nothing}            = nothing
    doi               :: String
end

# ---------------------------------------------------------------------------
# Abstract reconstruction (OpenAlex inverted index)
# ---------------------------------------------------------------------------

"""
    reconstruct_abstract(inv) -> Union{String,Nothing}

Rebuild text from an OpenAlex `abstract_inverted_index` (`word => [positions...]`).
Emits one `(position, word)` per occurrence, sorts by position (stable — duplicate
positions keep insertion order), joins with single spaces. `nothing`/empty ⇒ `nothing`.
Content-equivalent, not byte-equivalent (the index drops case/entity/punctuation info).
"""
reconstruct_abstract(::Nothing) = nothing
function reconstruct_abstract(inv)
    isempty(inv) && return nothing
    pairs = Tuple{Int,String}[]
    for (word, positions) in pairs_of(inv), p in positions
        push!(pairs, (Int(p), String(word)))
    end
    isempty(pairs) && return nothing
    sort!(pairs; by = first)        # Base sort! is stable ⇒ duplicate positions keep order
    return join((w for (_, w) in pairs), " ")
end

# Iterate (key, value) pairs over either a Dict or a JSON3.Object.
pairs_of(d::AbstractDict) = pairs(d)
pairs_of(o) = pairs(o)              # JSON3.Object supports pairs()

# ---------------------------------------------------------------------------
# Cache + HTTP
# ---------------------------------------------------------------------------

const _CACHE_DIR = normpath(joinpath(@__DIR__, "..", "data", "cache"))
const _DOIS_TOML = normpath(joinpath(@__DIR__, "..", "data", "canonical_dois.toml"))
const _UA_TMPL   = "TextMeasure.jl DOIInfograph (mailto=%s)"

"The six canonical demonstration DOIs (grid order). Source: `data/canonical_dois.toml`."
canonical_dois()::Vector{String} = String.(TOML.parsefile(_DOIS_TOML)["dois"])

# filesystem-safe cache key
_slug(doi::AbstractString) = replace(doi, r"[^A-Za-z0-9._-]" => "_")
cache_path(source::Symbol, doi::AbstractString) =
    joinpath(_CACHE_DIR, string(source, "_", _slug(doi), ".json"))

"Read a cached JSON response for `(source, doi)`; `nothing` if not cached."
function load_cached(source::Symbol, doi::AbstractString)
    p = cache_path(source, doi)
    isfile(p) || return nothing
    return JSON3.read(read(p, String))
end

_write_cache() = get(ENV, "DOIINFOGRAPH_WRITE_CACHE", "0") == "1"

# Shared fetch: cache-first; live HTTP only when DOIINFOGRAPH_WRITE_CACHE=1 (cache builder).
# Tests never set that var ⇒ pure offline, no network. Returns parsed JSON or `nothing`.
function _get_json(source::Symbol, doi::AbstractString, url::AbstractString; mailto::AbstractString)
    cached = load_cached(source, doi)
    cached === nothing || return cached
    _write_cache() || return nothing
    backoff = 1.0
    ua = replace(_UA_TMPL, "%s" => mailto)
    for _ in 1:4
        r = HTTP.get(url; status_exception=false, retry=false, headers=["User-Agent" => ua])
        if r.status == 200
            obj = JSON3.read(r.body)
            mkpath(_CACHE_DIR)
            write(cache_path(source, doi), JSON3.write(obj))
            return obj
        elseif r.status == 429
            ra = HTTP.header(r, "Retry-After", "")
            sleep(something(tryparse(Float64, ra), backoff)); backoff *= 2
        elseif r.status == 404
            return nothing
        else
            sleep(backoff); backoff *= 2
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Clients
# ---------------------------------------------------------------------------

struct OpenAlexClient;        mailto::String; end
struct CrossRefClient;        mailto::String; end
struct SemanticScholarClient; mailto::String; end
OpenAlexClient(; mailto::String)        = OpenAlexClient(mailto)
CrossRefClient(; mailto::String)        = CrossRefClient(mailto)
SemanticScholarClient(; mailto::String) = SemanticScholarClient(mailto)

# OpenAlex lowercases DOIs (Deviation 4).
function fetch(c::OpenAlexClient, doi::AbstractString)
    url = "https://api.openalex.org/works/doi:$(lowercase(doi))?mailto=$(c.mailto)"
    _get_json(:openalex, doi, url; mailto=c.mailto)
end

function fetch(c::CrossRefClient, doi::AbstractString)
    url = "https://api.crossref.org/works/$(HTTP.escapeuri(doi))?mailto=$(c.mailto)"
    _get_json(:crossref, doi, url; mailto=c.mailto)
end

# S2: arXiv DOIs use ARXIV:<id> (Deviation 2); everything else DOI:<doi>.
function _s2_id(doi::AbstractString)
    m = match(r"^10\.48550/arxiv\.(.+)$"i, doi)
    m === nothing ? "DOI:$doi" : "ARXIV:$(m.captures[1])"
end
function fetch(c::SemanticScholarClient, doi::AbstractString)
    fields = "tldr,abstract,title,authors,year,citationCount,openAccessPdf,venue"
    url = "https://api.semanticscholar.org/graph/v1/paper/$(_s2_id(doi))?fields=$fields"
    _get_json(:s2, doi, url; mailto=c.mailto)
end

# Map a Semantic Scholar openAccessPdf.status to our oa_status symbol.
function _s2_oa_status(status)
    status === nothing && return :unknown
    s = lowercase(String(status))
    s == "gold"   ? :gold   : s == "green"  ? :green  :
    s == "hybrid" ? :hybrid : s == "bronze" ? :hybrid :
    s == "closed" ? :closed : :unknown
end

# ---------------------------------------------------------------------------
# JSON helpers (tolerant accessors over JSON3 objects)
# ---------------------------------------------------------------------------

_str(::Nothing) = nothing
_str(x) = (s = String(x); isempty(s) ? nothing : s)
# first element of a CrossRef-style array field (title/container-title are arrays)
_first_str(::Nothing) = nothing
_first_str(a) = isempty(a) ? nothing : _str(a[1])

# split a single display name into (given, family): family = last token, given = rest.
function _author_from_name(name::AbstractString, affil::Union{String,Nothing}=nothing)
    parts = split(strip(name))
    isempty(parts) && return AuthorRef("", "", affil)
    length(parts) == 1 && return AuthorRef("", String(parts[1]), affil)
    return AuthorRef(join(parts[1:end-1], " "), String(parts[end]), affil)
end

# ---------------------------------------------------------------------------
# Merge → PaperMetadata
# ---------------------------------------------------------------------------

"""
    fetch_doi_metadata(doi; mailto, fetch_figure=false) -> PaperMetadata

Fetch + merge metadata for `doi`. OpenAlex is primary (abstract via inverted-index
reconstruction, concepts, citation timeline, OA, year, journal, page); CrossRef supplies
the split-name author list (+ journal/page/year/citation fallbacks); Semantic Scholar
supplies the TLDR (and an abstract fallback). Offline-first via `data/cache/` — returns
fully-populated metadata without network when the cache is present.

`fetch_figure=false` (default) never scrapes; `true` opts into an `og:image` scrape of the
publisher page with an explicit `User-Agent` (respect publisher ToS).
"""
function fetch_doi_metadata(doi::AbstractString; mailto::AbstractString, fetch_figure::Bool=false)
    oa = fetch(OpenAlexClient(; mailto), doi)
    cr = fetch(CrossRefClient(; mailto), doi)
    s2 = fetch(SemanticScholarClient(; mailto), doi)

    # --- title (OpenAlex → CrossRef → Semantic Scholar) ---
    title = something(oa === nothing ? nothing : _str(get(oa, :title, nothing)),
                      cr === nothing ? nothing : _first_str(get(cr, :title, nothing)),
                      s2 === nothing ? nothing : _str(get(s2, :title, nothing)),
                      "(title unavailable)")

    # --- authors: CrossRef primary (split names) → OpenAlex display names → S2 names ---
    authors = AuthorRef[]
    if cr !== nothing && get(cr, :author, nothing) !== nothing
        for a in cr.author
            given  = something(_str(get(a, :given, nothing)), "")
            family = something(_str(get(a, :family, nothing)),
                               _str(get(a, :name, nothing)), "")
            affs   = get(a, :affiliation, nothing)
            affil  = (affs === nothing || isempty(affs)) ? nothing : _str(get(affs[1], :name, nothing))
            push!(authors, AuthorRef(given, family, affil))
        end
    elseif oa !== nothing && get(oa, :authorships, nothing) !== nothing
        for au in oa.authorships
            nm = _str(get(get(au, :author, Dict()), :display_name, nothing))
            nm === nothing && continue
            ras = get(au, :raw_affiliation_strings, nothing)
            affil = (ras === nothing || isempty(ras)) ? nothing : _str(ras[1])
            push!(authors, _author_from_name(nm, affil))
        end
    elseif s2 !== nothing && get(s2, :authors, nothing) !== nothing
        # arXiv DOIs are absent from OpenAlex/CrossRef (DataCite) — S2 carries the author list.
        for a in s2.authors
            nm = _str(get(a, :name, nothing)); nm === nothing && continue
            push!(authors, _author_from_name(nm))
        end
    end

    # --- abstract: OpenAlex inverted index, fallback S2 abstract ---
    abstract = oa === nothing ? nothing : reconstruct_abstract(get(oa, :abstract_inverted_index, nothing))
    if abstract === nothing && s2 !== nothing
        abstract = _str(get(s2, :abstract, nothing))
    end

    # --- tldr (S2) ---
    tldr = nothing
    if s2 !== nothing
        t = get(s2, :tldr, nothing)
        tldr = t === nothing ? nothing : _str(get(t, :text, nothing))
    end

    # --- citation count + timeline ---
    citation_count = 0
    citations_by_year = Tuple{Int,Int}[]
    if oa !== nothing
        citation_count = Int(something(get(oa, :cited_by_count, nothing), 0))
        cby = get(oa, :counts_by_year, nothing)
        if cby !== nothing
            for e in cby
                push!(citations_by_year, (Int(e.year), Int(e.cited_by_count)))
            end
            sort!(citations_by_year; by=first)
        end
    end
    if citation_count == 0 && cr !== nothing
        citation_count = Int(something(get(cr, Symbol("is-referenced-by-count"), nothing), 0))
    end
    if citation_count == 0 && s2 !== nothing
        citation_count = Int(something(get(s2, :citationCount, nothing), 0))
    end

    # --- concepts (OpenAlex) ---
    concepts = Tuple{String,Float64}[]
    if oa !== nothing && get(oa, :concepts, nothing) !== nothing
        for c in oa.concepts
            nm = _str(get(c, :display_name, nothing)); nm === nothing && continue
            push!(concepts, (nm, Float64(something(get(c, :score, nothing), 0.0))))
        end
    end

    # --- open access (OpenAlex → S2 openAccessPdf) ---
    oa_status = :unknown; oa_url = nothing
    if oa !== nothing && get(oa, :open_access, nothing) !== nothing
        st = _str(get(oa.open_access, :oa_status, nothing))
        oa_status = st === nothing ? :unknown : Symbol(st)
        oa_url = _str(get(oa.open_access, :oa_url, nothing))
    end
    if oa_status === :unknown && s2 !== nothing
        pdf = get(s2, :openAccessPdf, nothing)
        if pdf !== nothing
            oa_status = _s2_oa_status(get(pdf, :status, nothing))
            oa_url === nothing && (oa_url = _str(get(pdf, :url, nothing)))
        end
    end
    # arXiv preprints are green OA by definition (DataCite DOIs lack OA metadata).
    oa_status === :unknown && occursin(r"^10\.48550/arxiv\."i, doi) && (oa_status = :green)

    # --- page range (OpenAlex biblio, fallback CrossRef page) ---
    pp = nothing
    if oa !== nothing && get(oa, :biblio, nothing) !== nothing
        fp = _str(get(oa.biblio, :first_page, nothing))
        lp = _str(get(oa.biblio, :last_page, nothing))
        pp = fp === nothing ? nothing : (lp === nothing ? fp : "$fp-$lp")
    end
    pp === nothing && cr !== nothing && (pp = _str(get(cr, :page, nothing)))

    # --- journal ---
    journal = nothing
    if oa !== nothing
        pl = get(oa, :primary_location, nothing)
        src = pl === nothing ? nothing : get(pl, :source, nothing)
        journal = src === nothing ? nothing : _str(get(src, :display_name, nothing))
    end
    journal === nothing && cr !== nothing && (journal = _first_str(get(cr, Symbol("container-title"), nothing)))
    journal === nothing && s2 !== nothing && (journal = _str(get(s2, :venue, nothing)))

    # --- year ---
    year = oa === nothing ? nothing : (y = get(oa, :publication_year, nothing); y === nothing ? nothing : Int(y))
    if year === nothing && cr !== nothing
        iss = get(cr, :issued, nothing)
        dp = iss === nothing ? nothing : get(iss, Symbol("date-parts"), nothing)
        if dp !== nothing && !isempty(dp) && !isempty(dp[1])
            year = Int(dp[1][1])
        end
    end
    if year === nothing && s2 !== nothing
        y = get(s2, :year, nothing); year = y === nothing ? nothing : Int(y)
    end

    # --- optional figure scrape ---
    figure_url = nothing
    if fetch_figure
        figure_url = _scrape_og_image_for(doi, oa_url; mailto)
    end

    return PaperMetadata(; title, authors, abstract, tldr, citation_count, citations_by_year,
                         concepts, oa_status, oa_url, figure_url, pp, journal, year, doi)
end

# ---------------------------------------------------------------------------
# Opt-in og:image scrape (default off)
# ---------------------------------------------------------------------------

"Extract the `og:image` URL from an HTML string, or `nothing`."
function _scrape_og_image(html::AbstractString)
    m = match(r"og:image\"[^>]*content=\"([^\"]+)\""i, html)
    m === nothing && return nothing
    return String(m.captures[1])
end

# Live scrape of the OA landing page (only reached when fetch_figure=true).
function _scrape_og_image_for(doi::AbstractString, url::Union{String,Nothing}; mailto::AbstractString)
    url === nothing && return nothing
    try
        ua = replace(_UA_TMPL, "%s" => mailto)
        r = HTTP.get(url; status_exception=false, retry=false, headers=["User-Agent" => ua])
        r.status == 200 || return nothing
        return _scrape_og_image(String(r.body))
    catch
        return nothing
    end
end
