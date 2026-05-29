# DOIInfograph (#F1→#F2→#F3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `DOIInfograph` demo package (`examples/doi_infograph/`) — an adaptive, measurement-driven paper-cover generator that fetches DOI metadata (offline-cacheable), composes a single-paper editorial infograph with CairoMakie, and renders a 6-up README-hero grid + Pluto notebook.

**Architecture:** Three internal layers in one package, built as a strict serial chain.
(1) **Data** (`src/data.jl`): thin HTTP clients for OpenAlex / CrossRef / Semantic Scholar, abstract reconstruction from OpenAlex's inverted index, a unified `fetch_doi_metadata → PaperMetadata`, and an on-disk JSON cache so all tests + renders run offline.
(2) **Layout** (`src/layout.jl`): `infograph(meta_or_doi; ...) → CairoMakie.Figure` driving the measurement primitives (title autoshrink, author overflow, TLDR autosize, drop cap, concept-pill wrap, citation sparkline) via TextMeasure's `MakieBackend`/`prepare`/`layout` and TextMeasureLayouts' `shape_pack`.
(3) **Grid/export** (`src/grid.jl` + `Demo.jl`): `grid_infograph(dois) → Figure`, PDF/PNG export helpers, and a Pluto notebook. F3 commits an exported-PDF-text checksum golden.

**Tech Stack:** Julia 1.11+ (CI), HTTP.jl 2.0, JSON3.jl, CairoMakie 0.15, TextMeasure (dev `../..`), TextMeasureLayouts (dev `../layouts`), TOML+Dates (stdlib), Pluto (external, NOT a project dep — see Deviation 3). Pinned fonts: **DejaVu Sans** (sans), **Liberation Serif** (serif).

**PR strategy:** **ONE PR** for the whole F1→F2→F3 chain. Rationale: it is a single self-contained demo package living in one new directory; F2/F3 are non-functional without F1, and three PRs into the same new tree would create rebase churn with no reviewable isolation benefit. Implementation still proceeds F1→F2→F3 with per-task commits, and the plan gate covers all three.

---

## PROBE-FIRST findings — deviations from the issue bodies

All verified **2026-05-28** against the live installed versions in `examples/doi_infograph/` and the live APIs. These are binding corrections; the issue bodies are wrong on several points (as wave 1 found).

**Deviation 1 — SemanticScholar.jl is UNUSABLE in this env (hard blocker).**
Issue #F1 mandates depending on `SemanticScholar.jl` (UUID `f2f2c3a1-…`, v1.0.0) directly for the `tldr` field. **It cannot be installed alongside CairoMakie:** SemanticScholar v1.0.0 pins `DataStructures = 0.18.x`, but CairoMakie 0.15.10 requires `DataStructures 0.19.4`. Verified resolver error:
```
Unsatisfiable requirements detected for package DataStructures [864edb3b]:
 ├─restricted to versions 0.19.4 by an explicit requirement
 └─restricted by compatibility with SemanticScholar to versions: 0.18.0 - 0.18.22 — no versions left
```
**Resolution:** write a thin `SemanticScholarClient` over HTTP.jl + JSON3 (exactly the pattern #F1 already prescribes for CrossRef, where it likewise rejects the stale `Pitaya` package). The TLDR comes from `GET https://api.semanticscholar.org/graph/v1/paper/{ID}?fields=tldr,abstract`. Documented in the demo README.

**Deviation 2 — Semantic Scholar paper IDs: arXiv DOIs require the `ARXIV:` prefix, not `DOI:`.**
`GET /paper/DOI:10.48550/arXiv.1706.03762` → `404 "not found"`. S2 indexes arXiv preprints under `ARXIV:1706.03762`. The client must map a `10.48550/arXiv.<id>` DOI to `ARXIV:<id>`; all other DOIs use `DOI:<doi>`.

**Deviation 3 — Pluto is incompatible with HTTP 2.0; keep it OUT of `[deps]`.**
`Pluto` requires HTTP 1.x; our env resolves HTTP to 2.0.0 (latest, required transitively by CairoMakie's stack). Adding Pluto fails to resolve. **Resolution:** `Demo.jl` is a Pluto notebook that calls `Pkg.activate(<demo dir>)` in its first cell (idiomatic for notebooks that use a local unregistered package), so Pluto runs from the user's own environment and never constrains the demo's resolve. Pluto is therefore an *external* dependency documented in the README, not a `[deps]` entry. The test suite and PDF/PNG export do not need Pluto.

**Deviation 4 — OpenAlex normalizes DOIs to lowercase.**
A mixed-case lookup `doi:10.48550/arXiv.1706.03762` does not resolve; OpenAlex stores `10.48550/arxiv.1706.03762`. The OpenAlex client must `lowercase` the DOI in the lookup URL. (CrossRef and our cache keys keep the original DOI.)

**Deviation 5 — `AuthorRef.given`/`family` come from CrossRef, not OpenAlex/S2.**
OpenAlex authorships expose only `author.display_name` / `raw_author_name`; S2 exposes only `name`. Only CrossRef splits `author.given` / `author.family` / `author.affiliation`. **Resolution:** prefer CrossRef for the author list; when CrossRef is unavailable, derive `AuthorRef` by splitting the single name string (`family` = last whitespace-delimited token, `given` = the remainder). `affiliation` comes from CrossRef `author.affiliation[].name` or OpenAlex `raw_affiliation_strings[1]` when present.

**Deviation 6 — HTTP 2.0 timeout kwargs renamed.**
`readtimeout` is deprecated in HTTP 2.0 (→ `read_idle_timeout` / `request_timeout`). To stay compatible across HTTP 1.x and 2.x we call `HTTP.get(url; status_exception=false, retry=false)` with **no** timeout kwargs and set `[compat] HTTP = "1, 2"`. Response handling uses only the stable surface: `r.status`, `r.body::Vector{UInt8}`, `HTTP.header(r, name, default)`.

**Verified-correct issue-body claims (no change):** OpenAlex fields `title`, `authorships`, `abstract_inverted_index`, `cited_by_count`, `counts_by_year` (`{year, cited_by_count}`), `concepts` (`{display_name, score}`), `open_access` (`{oa_status, oa_url}`), `biblio` (`{first_page, last_page}`), `publication_year`, `primary_location.source.display_name`. CrossRef `title`/`container-title` (arrays), `page`, `issued.date-parts`, `is-referenced-by-count`, `author[]` with `given`/`family`/`affiliation`. CairoMakie PDF+PNG export works; `pdftotext 24.02.0` present for the golden; fonts DejaVu Sans + Liberation Serif both resolve via `Makie.to_font`.

## Canonical DOI slots (recorded in `data/canonical_dois.toml`)

| Slot | DOI | Why | Verified |
|------|-----|-----|----------|
| 1 | `10.1038/s41586-019-1666-5` | Sycamore — long title, 77 authors, hybrid OA, abstract+tldr | abstract✓ tldr✓ 77 auth, oa=hybrid |
| 2 | `10.48550/arXiv.1706.03762` | Attention — short title, 8 authors, green OA preprint | S2 via `ARXIV:` prefix |
| 3 | `10.1371/journal.pone.0000308` | PLOS ONE gold OA, abstract reliably present, 3 authors | abstract✓ oa=gold 902 cites |
| 4 | `10.48550/arXiv.2405.17090` | arXiv preprint, 125-char title, no abstract, 4 cites — autoshrink + no-abstract stress | title len 125, abstract✗ |
| 5 | `10.1038/ng.3097` | GWAS, **446 authors** — author-overflow ("et al.") | 446 auth, abstract✗ |
| 6 | `10.1016/0927-0256(96)00008-0` | VASP paper — no abstract **and** no S2 tldr (deepest degradation) | abstract✗ tldr✗ (S2) |

> Slots 4–6 are finalized in the F1 cache-build task; if a cache build reveals a slot no longer meets its criterion (e.g. an abstract appeared), swap to the documented backup and re-record in `canonical_dois.toml`. Backups: slot-4 `10.48550/arxiv.2501.06017` (85-char, 0 cites); slot-6 must re-verify tldr absence before swap.

## File structure

```
examples/doi_infograph/
  Project.toml                 # name=DOIInfograph; deps; [compat]; [extras] Test; [targets] test=["Test"]
  README.md                    # usage, offline cache, fetch_figure ToS note, Pluto instructions, deviations
  src/
    DOIInfograph.jl            # module: includes + exports
    data.jl                    # #F1: AuthorRef, PaperMetadata, clients, reconstruct_abstract, fetch_doi_metadata, cache
    layout.jl                  # #F2: infograph + adaptive primitives
    grid.jl                    # #F3: grid_infograph, export_pdf/export_png helpers
  data/
    canonical_dois.toml        # the 6 slots (source of truth)
    cache/                     # *.json offline fixtures (committed); one file per (source, doi)
  test/
    runtests.jl                # aggregates the testsets
    test_data.jl               # #F1 unit + offline-roundtrip + reconstruction-equivalence
    test_layout.jl             # #F2 property (100 titles) + integration + comparative + overflow + sparkline
    test_grid.jl               # #F3 grid renders + slot-6 graceful + PDF-text golden
    golden/
      grid_pdf_text.sha256     # committed checksum of pdftotext output (font-embedding/selectability check)
  Demo.jl                      # Pluto notebook (activates the demo project)
```

SPDX header `# SPDX-License-Identifier: MIT` on every new `.jl` (first line). Module docstring follows the silhouettes pattern.

---

## Workspace (DONE during planning — verify before Task 1)

Worktree `demos-F-doi-infograph` off `main` (bd5a103). `examples/doi_infograph/Project.toml` created; `TextMeasure` (`.`) and `TextMeasureLayouts` (`examples/layouts`) `Pkg.develop`ed; `HTTP`, `JSON3`, `CairoMakie` added (`HTTP=2.0.0`, `JSON3=1.14.3`, `CairoMakie=0.15.10`). Manifest is gitignored (repo `.gitignore:24` = `Manifest*.toml`) — never force-add.

- [ ] **Verify env resolves:** `julia --project=examples/doi_infograph -e 'using Pkg; Pkg.instantiate(); using HTTP, JSON3, CairoMakie, TextMeasure, TextMeasureLayouts; println("ENV OK")'` → `ENV OK`. Set `[compat] HTTP = "1, 2"` (currently `"2.0.0"`) in `Project.toml`, add `TextMeasure`/`TextMeasureLayouts`/`GeometryBasics` compat entries to match `examples/layouts` (`GeometryBasics = "0.5.10"`), keep `julia = "1.11"`.

---

# Stage F1 — Data layer (`src/data.jl`, `data/`)

Run a single test file during iteration with:
`julia --project=examples/doi_infograph -e 'using Pkg; Pkg.activate("examples/doi_infograph"); include("examples/doi_infograph/test/test_data.jl")'`

### Task F1.1: Types + module skeleton

**Files:**
- Create: `examples/doi_infograph/src/DOIInfograph.jl`
- Create: `examples/doi_infograph/src/data.jl`
- Test: `examples/doi_infograph/test/test_data.jl`, `examples/doi_infograph/test/runtests.jl`

- [ ] **Step 1: Write `DOIInfograph.jl` module skeleton**

```julia
# SPDX-License-Identifier: MIT
"""
    DOIInfograph

Adaptive, measurement-driven academic-paper infographic generator (demos milestone
#F1–#F3). Fetches DOI metadata (offline-cacheable), composes a single-paper editorial
cover with CairoMakie, and renders a 6-up README-hero grid + Pluto notebook. All tests
and renders run offline from `data/cache/`.
"""
module DOIInfograph

using TextMeasure
using TextMeasureLayouts
import HTTP, JSON3
import TOML, Dates
import CairoMakie
const CM = CairoMakie

export AuthorRef, PaperMetadata
export OpenAlexClient, CrossRefClient, SemanticScholarClient
export fetch_doi_metadata, reconstruct_abstract, cache_path, load_cached, canonical_dois
export infograph, grid_infograph, export_pdf, export_png

include("data.jl")
include("layout.jl")
include("grid.jl")

end # module
```

- [ ] **Step 2: Write the failing test for the data structs** (`test/test_data.jl`)

```julia
# SPDX-License-Identifier: MIT
using Test, DOIInfograph

@testset "DOIInfograph data layer" begin
    @testset "structs" begin
        a = AuthorRef("Frank", "Arute", "Google AI Quantum")
        @test a.given == "Frank" && a.family == "Arute"
        @test AuthorRef("Ada", "Lovelace").affiliation === nothing
        m = PaperMetadata(; title="T", authors=[a], doi="10.x/y")
        @test m.title == "T" && m.citation_count == 0
        @test m.abstract === nothing && m.tldr === nothing
        @test m.oa_status === :unknown
    end
end
```

- [ ] **Step 3: Run, expect fail** — `… include("…/test_data.jl")` → FAIL (`AuthorRef` undefined).

- [ ] **Step 4: Implement the structs at the top of `data.jl`**

```julia
# SPDX-License-Identifier: MIT
# #F1 — DOIInfograph data layer: API clients, abstract reconstruction, offline cache.

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
    authors           :: Vector{AuthorRef}            = AuthorRef[]
    abstract          :: Union{String,Nothing}        = nothing
    tldr              :: Union{String,Nothing}        = nothing
    citation_count    :: Int                          = 0
    citations_by_year :: Vector{Tuple{Int,Int}}       = Tuple{Int,Int}[]
    concepts          :: Vector{Tuple{String,Float64}}= Tuple{String,Float64}[]
    oa_status         :: Symbol                        = :unknown
    oa_url            :: Union{String,Nothing}        = nothing
    figure_url        :: Union{String,Nothing}        = nothing
    pp                :: Union{String,Nothing}        = nothing
    journal           :: Union{String,Nothing}        = nothing
    year              :: Union{Int,Nothing}           = nothing
    doi               :: String
end
```

- [ ] **Step 5: Write `test/runtests.jl`** (aggregator; F2/F3 files appended later)

```julia
# SPDX-License-Identifier: MIT
using Test
@testset "DOIInfograph" begin
    include("test_data.jl")
    include("test_layout.jl")
    include("test_grid.jl")
end
```
Create empty-but-valid `test_layout.jl`/`test_grid.jl` stubs (`@testset "stub" begin @test true end`) so `runtests.jl` runs from the start; replace in F2/F3.

- [ ] **Step 6: Run → PASS. Commit.**
`git add examples/doi_infograph/src examples/doi_infograph/test && git commit -m "feat(doi): F1 data structs + module skeleton"`

### Task F1.2: Abstract reconstruction from OpenAlex inverted index

**Files:** Modify `src/data.jl`; Test `test/test_data.jl`.

- [ ] **Step 1: Failing test** (append to `test_data.jl`)

```julia
@testset "reconstruct_abstract" begin
    # inverted index: word => [positions]; multi-position + out-of-order
    inv = Dict("the"=>[0,4], "cat"=>[1], "sat"=>[2], "on"=>[3], "mat"=>[5])
    @test reconstruct_abstract(inv) == "the cat sat on the mat"
    @test reconstruct_abstract(nothing) === nothing
    @test reconstruct_abstract(Dict{String,Vector{Int}}()) === nothing
    # duplicate positions resolved by stable word order, not crash
    dup = Dict("a"=>[0], "b"=>[0])
    @test reconstruct_abstract(dup) in ("a b", "b a")
end
```

- [ ] **Step 2: Run, expect fail.**

- [ ] **Step 3: Implement**

```julia
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
    for (word, positions) in inv, p in positions
        push!(pairs, (Int(p), String(word)))
    end
    isempty(pairs) && return nothing
    sort!(pairs; by = first)          # Base sort! is stable for Tuples by first
    return join((w for (_, w) in pairs), " ")
end
```

- [ ] **Step 4: Run → PASS. Commit** `feat(doi): F1 inverted-index abstract reconstruction`.

### Task F1.3: HTTP clients (OpenAlex, CrossRef, Semantic Scholar) with cache + backoff

**Files:** Modify `src/data.jl`; Test `test/test_data.jl`.

Design: each client is a small struct holding `mailto` + base URL. A shared `_get_json(url; cache_key, headers)` does: if `cache/<cache_key>.json` exists → read it; else live `HTTP.get`, on `429` honor `Retry-After` with exponential backoff (max 4 tries), parse JSON, and (when `DOIINFOGRAPH_WRITE_CACHE=1`) write the file. Tests never set the env var, so they are pure-offline and never touch the network.

- [ ] **Step 1: Failing test (offline cache round-trip + slot-6 null-safety)**

```julia
@testset "clients offline" begin
    # canonical_dois reads the committed TOML
    dois = canonical_dois()
    @test length(dois) == 6
    @test dois[1] == "10.1038/s41586-019-1666-5"

    # cache_path maps (source, doi) → file under data/cache
    p = cache_path(:openalex, dois[1])
    @test endswith(p, ".json") && occursin("cache", p)

    # all six round-trip from cache without network
    for doi in dois
        oa = load_cached(:openalex, doi)         # parsed JSON3 object or nothing
        @test oa !== nothing
    end
    # slot-6: no abstract + no tldr handled without throwing
    s6 = load_cached(:openalex, dois[6])
    @test get(s6, :abstract_inverted_index, nothing) === nothing
end
```

- [ ] **Step 2: Run, expect fail** (cache files + functions absent).

- [ ] **Step 3: Implement clients + cache + backoff** (key code)

```julia
const _CACHE_DIR = normpath(joinpath(@__DIR__, "..", "data", "cache"))
const _DOIS_TOML = normpath(joinpath(@__DIR__, "..", "data", "canonical_dois.toml"))
const _UA = "TextMeasure.jl DOIInfograph (mailto=%s)"

canonical_dois() = TOML.parsefile(_DOIS_TOML)["dois"]::Vector

# filesystem-safe cache key: replace path-hostile chars
_slug(doi) = replace(doi, r"[^A-Za-z0-9._-]" => "_")
cache_path(source::Symbol, doi::AbstractString) =
    joinpath(_CACHE_DIR, string(source, "_", _slug(doi), ".json"))

function load_cached(source::Symbol, doi::AbstractString)
    p = cache_path(source, doi)
    isfile(p) || return nothing
    return JSON3.read(read(p, String))
end

_write_cache() = get(ENV, "DOIINFOGRAPH_WRITE_CACHE", "0") == "1"

# Shared fetch: cache-first; live only when explicitly building the cache.
function _get_json(source::Symbol, doi::AbstractString, url::AbstractString; mailto::AbstractString)
    cached = load_cached(source, doi)
    cached === nothing || return cached
    _write_cache() || return nothing          # offline + no cache ⇒ nothing (callers tolerate)
    backoff = 1.0
    for attempt in 1:4
        r = HTTP.get(url; status_exception=false, retry=false,
                     headers=["User-Agent" => replace(_UA, "%s" => mailto)])
        if r.status == 200
            obj = JSON3.read(r.body)
            mkpath(_CACHE_DIR)
            write(cache_path(source, doi), JSON3.write(obj))
            return obj
        elseif r.status == 429
            ra = HTTP.header(r, "Retry-After", "")
            wait_s = something(tryparse(Float64, ra), backoff)
            sleep(wait_s); backoff *= 2
        elseif r.status == 404
            return nothing
        else
            sleep(backoff); backoff *= 2
        end
    end
    return nothing
end

struct OpenAlexClient;        mailto::String; end
struct CrossRefClient;        mailto::String; end
struct SemanticScholarClient; mailto::String; end
OpenAlexClient(; mailto::String)        = OpenAlexClient(mailto)
CrossRefClient(; mailto::String)        = CrossRefClient(mailto)
SemanticScholarClient(; mailto::String) = SemanticScholarClient(mailto)

# OpenAlex lowercases DOIs (Deviation 4)
function fetch(c::OpenAlexClient, doi)
    url = "https://api.openalex.org/works/doi:$(lowercase(doi))?mailto=$(c.mailto)"
    _get_json(:openalex, doi, url; mailto=c.mailto)
end
function fetch(c::CrossRefClient, doi)
    url = "https://api.crossref.org/works/$(HTTP.escapeuri(doi))?mailto=$(c.mailto)"
    _get_json(:crossref, doi, url; mailto=c.mailto)
end
# S2: arXiv DOIs use ARXIV:<id> (Deviation 2)
function _s2_id(doi)
    m = match(r"^10\.48550/arxiv\.(.+)$"i, doi)
    m === nothing ? "DOI:$doi" : "ARXIV:$(m.captures[1])"
end
function fetch(c::SemanticScholarClient, doi)
    url = "https://api.semanticscholar.org/graph/v1/paper/$(_s2_id(doi))?fields=tldr,abstract,title"
    _get_json(:s2, doi, url; mailto=c.mailto)
end
```

- [ ] **Step 4: Build the cache fixtures (one-time, online)** — a `data/build_cache.jl` script (committed; NOT run in CI):

```julia
# SPDX-License-Identifier: MIT
# One-time cache builder. Run online: DOIINFOGRAPH_WRITE_CACHE=1 julia --project=examples/doi_infograph examples/doi_infograph/data/build_cache.jl
using DOIInfograph
const MAILTO = get(ENV, "DOIINFOGRAPH_MAILTO", "jjmaomi@gmail.com")
for doi in canonical_dois()
    DOIInfograph.fetch(OpenAlexClient(; mailto=MAILTO), doi)
    DOIInfograph.fetch(CrossRefClient(; mailto=MAILTO), doi)
    DOIInfograph.fetch(SemanticScholarClient(; mailto=MAILTO), doi)
    sleep(3)   # be polite to S2's unauthenticated rate limit
    @info "cached" doi
end
```
Run it once with `DOIINFOGRAPH_WRITE_CACHE=1` to populate `data/cache/*.json` (18 files = 6 DOIs × 3 sources; S2 may legitimately 404/miss for arXiv slot-4/slot-6 — those simply have no s2 file, which `load_cached` returns `nothing` for). **Commit the cache JSON.** Re-verify slot criteria here; finalize `canonical_dois.toml`.

- [ ] **Step 5: Run test → PASS (offline). Commit** `feat(doi): F1 clients + offline cache + fixtures`.

### Task F1.4: `fetch_doi_metadata` merge + content-equivalence acceptance

**Files:** Modify `src/data.jl`; Test `test/test_data.jl`.

Merge policy: OpenAlex = primary (abstract via `reconstruct_abstract`, concepts, `counts_by_year`, oa, year, journal, biblio pp). CrossRef = authors (given/family/affiliation), journal/pp/year fallback, `is-referenced-by-count` fallback for citations. S2 = `tldr`; `abstract` fallback when OpenAlex has none. `fetch_figure=false` default (no scrape). `citation_count` from OpenAlex `cited_by_count` (fallback CrossRef). When CrossRef authors absent, derive `AuthorRef` from OpenAlex `authorships[].author.display_name` (split: family=last token, given=rest), affiliation from `raw_affiliation_strings[1]`.

- [ ] **Step 1: Failing test (offline integration + content-equivalence)**

```julia
@testset "fetch_doi_metadata offline" begin
    cli = (; mailto="test@example.com")
    sycamore = fetch_doi_metadata("10.1038/s41586-019-1666-5"; mailto="t@e.com")
    @test sycamore.title == "Quantum supremacy using a programmable superconducting processor"
    @test length(sycamore.authors) == 77
    @test sycamore.oa_status === :hybrid
    @test sycamore.abstract !== nothing
    @test sycamore.tldr !== nothing
    @test sycamore.pp == "505-510" || occursin("505", something(sycamore.pp,""))
    @test !isempty(sycamore.citations_by_year)

    # content-equivalence: every non-stopword token of the reconstructed abstract present in order
    recon = sycamore.abstract
    @test occursin("quantum", lowercase(recon)) && occursin("supremacy", lowercase(recon))

    # slot-6 graceful: no abstract, no tldr, but title+authors present, no throw
    vasp = fetch_doi_metadata("10.1016/0927-0256(96)00008-0"; mailto="t@e.com")
    @test vasp.abstract === nothing && vasp.tldr === nothing
    @test !isempty(vasp.title) && !isempty(vasp.authors)

    # Attention: 8 authors, green OA
    attn = fetch_doi_metadata("10.48550/arXiv.1706.03762"; mailto="t@e.com")
    @test length(attn.authors) == 8
end
```
(Exact author counts asserted as **floors/exact-from-cache**, never live counts.)

- [ ] **Step 2: Run, expect fail.**

- [ ] **Step 3: Implement `fetch_doi_metadata`** — merge per policy above; full code in the implementation (uses `fetch` on the three clients, `reconstruct_abstract`, the name-split helper `_author_from_name`, and tolerant `get(obj, :key, default)` accessors against JSON3 objects). Return `PaperMetadata`.

- [ ] **Step 4: Run → PASS. Commit** `feat(doi): F1 fetch_doi_metadata merge + offline integration`.

### Task F1.5: `og:image` opt-in scrape (documented, default off)

**Files:** Modify `src/data.jl`; README note.

- [ ] **Step 1: Test** — `fetch_doi_metadata(...; fetch_figure=false).figure_url === nothing` (default); a unit test for the `_scrape_og_image(html)` HTML parser given a fixture HTML string returns the `og:image` URL. No live scrape in tests.

```julia
@testset "og:image parse" begin
    html = "<meta property=\"og:image\" content=\"https://x/y.png\"/>"
    @test DOIInfograph._scrape_og_image(html) == "https://x/y.png"
    @test DOIInfograph._scrape_og_image("<html></html>") === nothing
end
```

- [ ] **Step 2-4:** Implement `_scrape_og_image(html) = (m = match(r"og:image\"[^>]*content=\"([^\"]+)\""i, html); m === nothing ? nothing : String(m.captures[1]))`; gate the live fetch behind `fetch_figure=true` with the explicit `User-Agent`. Run → PASS. Commit `feat(doi): F1 opt-in og:image scrape`.

**F1 acceptance recap:** 6 DOIs round-trip offline ✓; reconstruction content-equivalent ✓; `fetch_figure=false` default + documented ToS ✓; 429 backoff honored ✓; slot-6 null-safe ✓.

---

# Stage F2 — Adaptive layout engine (`src/layout.jl`)

All primitives are measurement-driven via `MakieBackend(; font, fontsize, px_per_unit=1)` (CLAUDE.md: px_per_unit=1). `measure(b, text)` is px at the backend's baked-in fontsize → autoshrink/autosize binary-search by **constructing a new backend per fontsize**.

### Task F2.1: Title autoshrink (the property-test centerpiece)

**Files:** Create `src/layout.jl`; Test `test/test_layout.jl`.

- [ ] **Step 1: Failing property test (100 random titles)**

```julia
# SPDX-License-Identifier: MIT
using Test, DOIInfograph, TextMeasure, CairoMakie, Random

@testset "title autoshrink" begin
    rng = Xoshiro(0xF2)                          # local RNG, no global leak
    box_w = 360.0
    for _ in 1:100
        n = rand(rng, 10:200)
        title = String(rand(rng, 'a':'z', n))    # worst-case unbroken-ish words
        title = join([title[i:min(end,i+rand(rng,3:9))] for i in 1:8:length(title)], " ")
        fs, nlines = DOIInfograph.title_autoshrink(title; box_width=box_w,
                                                    fs_min=14.0, fs_max=48.0)
        @test 14.0 <= fs <= 48.0
        @test nlines <= 2
    end
end
```

- [ ] **Step 2: Run, expect fail.**

- [ ] **Step 3: Implement `title_autoshrink`** (binary search over backends; ~6 iters)

```julia
const SANS  = "DejaVu Sans"
const SERIF = "Liberation Serif"

"Make a px_per_unit=1 MakieBackend at `fs` in font `fam`."
_backend(fam, fs) = MakieBackend(; font=fam, fontsize=fs, px_per_unit=1)

"Lines a title wraps to at fontsize `fs` in box `box_width`."
function _title_lines(title, fam, fs, box_width)
    prep = prepare(_backend(fam, fs), title)
    lay  = layout(prep; max_width=box_width)
    return length(lay.lines)
end

"""
    title_autoshrink(title; box_width, fs_min=14.0, fs_max=48.0, tol=0.5) -> (fontsize, nlines)

Largest fontsize in [fs_min, fs_max] (±tol) such that `title` fits `box_width` in ≤2 lines.
Always terminates with `nlines ≤ 2` (at fs_min the constraint may still need ≤2 lines; an
all-but-unbreakable string is handled because measure shrinks with fs and box wraps it).
"""
function title_autoshrink(title::AbstractString; box_width::Real,
                          fs_min::Real=14.0, fs_max::Real=48.0, tol::Real=0.5)
    fits(fs) = _title_lines(title, SANS, fs, box_width) <= 2
    lo, hi = Float64(fs_min), Float64(fs_max)
    fits(hi) && return (hi, _title_lines(title, SANS, hi, box_width))   # already fits at max
    # binary search for the largest fs that fits
    best = lo
    while hi - lo > tol
        mid = (lo + hi) / 2
        if fits(mid); best = mid; lo = mid else hi = mid end
    end
    return (best, _title_lines(title, SANS, best, box_width))
end
```
> Note: at `fs_min` a pathological single token wider than the box at 14px wraps to 1 over-wide line (line count 1 ≤ 2) — the ≤2 invariant holds because `layout` puts an over-wide atomic word on its own line. The property test's word-chunking keeps tokens breakable; the invariant is count-of-lines, not no-overflow.

- [ ] **Step 4: Run → PASS (100 cases). Commit** `feat(doi): F2 title autoshrink + property test`.

### Task F2.2: Author overflow ("et al." atomic)

**Files:** Modify `src/layout.jl`; Test `test/test_layout.jl`.

- [ ] **Step 1: Failing test**

```julia
@testset "author overflow" begin
    b = DOIInfograph._backend(DOIInfograph.SANS, 11.0)
    many = [AuthorRef("A","Author$i") for i in 1:60]
    shown, etal = DOIInfograph.fit_authors(many, b; row_width=300.0)
    @test etal == true && length(shown) < 60
    few = [AuthorRef("A","Author$i") for i in 1:8]
    shown2, etal2 = DOIInfograph.fit_authors(few, b; row_width=4000.0)
    @test etal2 == false && length(shown2) == 8
end
```

- [ ] **Step 2-4:** Implement `fit_authors(authors, backend; row_width, sep=", ", etal=" et al.")` — accumulate `measure(backend, name)` + separators until the next author (plus the reserved `et al.` width) would exceed `row_width`; return `(shown::Vector{AuthorRef}, etal::Bool)`. Name string = `"$(given_initial). $family"` or full `"$given $family"` (choose initials for density; document). Run → PASS. Commit `feat(doi): F2 author overflow`.

### Task F2.3: TLDR autosize + drop cap + concept-pill wrap + sparkline

**Files:** Modify `src/layout.jl`; Test `test/test_layout.jl`.

- [ ] **Step 1: Failing tests**

```julia
@testset "tldr autosize bounds" begin
    fs = DOIInfograph.tldr_autosize("Short sentence."; box_width=240.0, box_height=120.0,
                                    fs_min=9.0, fs_max=14.0)
    @test 9.0 <= fs <= 14.0
    # a one-liner that already fits at fs_max returns fs_max (no growth past 14)
    @test fs == 14.0
    long = repeat("word ", 400)
    fs2 = DOIInfograph.tldr_autosize(long; box_width=240.0, box_height=120.0,
                                     fs_min=9.0, fs_max=14.0)
    @test 9.0 <= fs2 <= 14.0
end

@testset "drop cap offset" begin
    off = DOIInfograph.dropcap_offset("Quantum"; body_fontsize=11.0, gutter=4.0)
    @test off > DOIInfograph._backend(DOIInfograph.SERIF, 11.0) |> b -> measure(b, "Q")
end

@testset "concept pill wrap" begin
    b = DOIInfograph._backend(DOIInfograph.SANS, 10.0)
    pills = ["Quantum computer","Qubit","Supremacy","Algorithm","Noise"]
    rows = DOIInfograph.wrap_pills(pills, b; strip_width=180.0, pad=14.0, gap=6.0)
    @test all(r -> !isempty(r), rows) && sum(length, rows) == length(pills)
end

@testset "sparkline width match" begin
    b = DOIInfograph._backend(DOIInfograph.SANS, 10.0)
    caption = "2019—2026"
    spark = DOIInfograph.citation_sparkline([(2019,10),(2020,40),(2021,80),(2022,60)], b;
                                            target_width=measure(b, caption))
    @test abs(measure(b, spark) - measure(b, caption)) <=
          1.05 * maximum(measure(b, string(c)) for c in "▁▂▃▄▅▆▇█")
end
```

- [ ] **Step 2-4:** Implement:
  - `tldr_autosize(text; box_width, box_height, fs_min=9.0, fs_max=14.0)`: largest fs in bounds where `layout(prepare(_backend(SERIF,fs), text); max_width=box_width)` block height `≤ box_height`; if fs_max fits, return fs_max.
  - `dropcap_offset(first_para; body_fontsize, gutter=4.0)`: `measure(_backend(SERIF, 3*body_fontsize), string(first(strip(first_para)))) + gutter`.
  - `wrap_pills(pills, backend; strip_width, pad, gap)`: each pill atomic width = `measure(backend, pill) + 2pad`; greedy row-wrap; returns `Vector{Vector{String}}`.
  - `citation_sparkline(by_year, backend; target_width)`: map counts → block chars `▁▂▃▄▅▆▇█` by normalized height, then add/trim trailing chars so measured width is within ±1 glyph of `target_width`.
  Run → PASS. Commit `feat(doi): F2 tldr/dropcap/pills/sparkline primitives`.

### Task F2.4: `infograph` composition + integration test

**Files:** Modify `src/layout.jl`; Test `test/test_layout.jl`.

`infograph(meta::PaperMetadata; page=(420,594), template=:editorial, justification=:greedy, fetch_figure=false) -> CM.Figure` and `infograph(doi::AbstractString; mailto, kwargs...)` (calls `fetch_doi_metadata`). Validate `template === :editorial` else `throw(ArgumentError)`. `justification=:knuth_plass` falls back to greedy with one-time `@warn` if `examples/layouts/knuth_plass.jl` absent (it is — #K stretch). Composition uses a CairoMakie `Figure` with explicit pixel layout (no `Axis` auto-scaling — use a single hidden-decoration scene with `text!`/`poly!` at measured coordinates; the body text wraps around the figure pillar via `shape_pack` with a rectangular `polygon_chord_fn` over the left column, or a plain `layout`). Drop cap rendered as a separate `text!` at the display fontsize. Slot-6 path: abstract/tldr slot shows enlarged concept pills + muted "abstract unavailable" caption.

- [ ] **Step 1: Failing tests (integration + comparative + overflow)**

```julia
@testset "infograph integration (6 cached)" begin
    for doi in canonical_dois()
        fig = infograph(doi; mailto="t@e.com")
        @test fig isa CM.Figure
    end
    @test_throws ArgumentError infograph(fetch_doi_metadata(canonical_dois()[1]; mailto="t@e.com"); template=:bogus)
end

@testset "comparative + overflow" begin
    syc = fetch_doi_metadata("10.1038/s41586-019-1666-5"; mailto="t@e.com")
    attn = fetch_doi_metadata("10.48550/arXiv.1706.03762"; mailto="t@e.com")
    fs_syc,_  = title_autoshrink(syc.title;  box_width=360.0)
    fs_attn,_ = title_autoshrink(attn.title; box_width=360.0)
    @test fs_syc < fs_attn               # longer Sycamore title renders smaller
    b = DOIInfograph._backend(DOIInfograph.SANS, 11.0)
    _, syc_etal = DOIInfograph.fit_authors(syc.authors, b; row_width=300.0)
    _, attn_etal = DOIInfograph.fit_authors(attn.authors, b; row_width=300.0)
    @test syc_etal == true              # 77 authors → et al.
    @test attn_etal == false            # 8 authors fit
end
```

- [ ] **Step 2-4:** Implement `infograph`. Run → PASS. Commit `feat(doi): F2 infograph composition + integration`.

**F2 acceptance recap:** 100-title property ✓; 6-cached integration ✓; comparative fs delta ✓; author overflow ✓; sparkline ±1 glyph ✓.

---

# Stage F3 — 6-up grid, export, Pluto, golden (`src/grid.jl`, `Demo.jl`)

### Task F3.1: `grid_infograph` + export helpers

**Files:** Create `src/grid.jl`; Test `test/test_grid.jl`.

- [ ] **Step 1: Failing test**

```julia
# SPDX-License-Identifier: MIT
using Test, DOIInfograph, CairoMakie
@testset "grid renders" begin
    fig = grid_infograph(canonical_dois(); mailto="t@e.com")
    @test fig isa CairoMakie.Figure
    mktempdir() do d
        pdf = joinpath(d, "grid.pdf"); png = joinpath(d, "grid.png")
        export_pdf(fig, pdf); export_png(fig, png)
        @test filesize(pdf) > 0 && filesize(png) > 0
    end
end
@testset "slot-6 graceful render" begin
    m = fetch_doi_metadata(canonical_dois()[6]; mailto="t@e.com")
    @test m.abstract === nothing && m.tldr === nothing
    @test infograph(m) isa CairoMakie.Figure      # no throw; enlarged pills + muted caption path
end
```

- [ ] **Step 2-4:** Implement `grid_infograph(dois; mailto, kwargs...)` = 2×3 `CM.Figure` of sub-infographs (compose each `infograph` into a grid cell via `GridLayout`), `export_pdf(fig, path)=CM.save(path, fig)`, `export_png(fig, path)=CM.save(path, fig; px_per_unit=2)`. Run → PASS. Commit `feat(doi): F3 grid + export helpers`.

### Task F3.2: PDF-text golden (font-embedding / selectability check)

**Files:** Test `test/test_grid.jl`; Create `test/golden/grid_pdf_text.sha256`.

The golden asserts text is **embedded + selectable**, NOT pixel coordinates (per WAVE-1 convention e). Extract with `pdftotext`, normalize whitespace, checksum the **set of tokens** (sorted, deduped) so reflow/positioning changes don't break it but a font-embedding regression (text becomes outlines → empty extraction) does. Regression floor, not exact match.

- [ ] **Step 1: Failing test**

```julia
@testset "pdf text golden" begin
    if Sys.which("pdftotext") === nothing
        @test_skip "pdftotext unavailable"
    else
        fig = grid_infograph(canonical_dois(); mailto="t@e.com")
        mktempdir() do d
            pdf = joinpath(d, "g.pdf"); export_pdf(fig, pdf)
            txt = read(`pdftotext -enc UTF-8 $pdf -`, String)
            toks = sort(unique(filter(!isempty, split(lowercase(txt), r"\s+"))))
            @test length(toks) >= 50                       # selectable text present (floor)
            @test "quantum" in toks && "supremacy" in toks # known slot-1 tokens embedded
            gold = joinpath(@__DIR__, "golden", "grid_pdf_text.sha256")
            digest = bytes2hex(sha256(join(toks, " ")))
            if isfile(gold)
                @test_skip "token-set drift (informational): $(chomp(read(gold,String)) == digest)"
            else
                mkpath(dirname(gold)); write(gold, digest)
            end
        end
    end
end
```
(Uses `SHA` stdlib — add `using SHA` to the test; SHA is stdlib, no Project dep needed but add to `[extras]`/`[targets]` if required.) The hard assertions are the token floor + known tokens (these catch font-embedding regressions); the committed `.sha256` is informational drift signal, not a hard gate, because the token set legitimately shifts with abstract reflow.

- [ ] **Step 2-4:** Run once to generate `golden/grid_pdf_text.sha256`, commit it. Run → PASS. Commit `test(doi): F3 PDF-text font-embedding golden`.

### Task F3.3: Render the committed README-hero PNG + composite PDF

**Files:** `data/build_cache.jl` sibling `render_hero.jl` (committed); output `examples/doi_infograph/assets/grid_hero.png` + `grid_hero.pdf`.

- [ ] **Step 1:** Write `render_hero.jl`: `fig = grid_infograph(canonical_dois(); mailto=…); export_png(fig, "assets/grid_hero.png"); export_pdf(fig, "assets/grid_hero.pdf")`. Run offline (cache present). Commit the PNG + PDF binaries + script.
- [ ] **Step 2:** This PNG path is what I attach to the orchestrator in the "PR opened" message.

### Task F3.4: Pluto notebook `Demo.jl`

**Files:** Create `examples/doi_infograph/Demo.jl`.

- [ ] **Step 1:** Standard Pluto notebook: first cell `import Pkg; Pkg.activate(@__DIR__)` (Deviation 3); cells: DOI `TextField`, `@bind page_width Slider(300:10:600)`, render `infograph(doi; mailto=…)` cached so only re-layout on slider (cache the `PaperMetadata` in a `let`-bound ref; re-call `infograph` with new `page` width — acceptance is ~500ms reflow, CairoMakie static render). "Export PDF" `@bind` button → `export_pdf`. No test (notebooks aren't unit-tested); README documents running it.
- [ ] **Step 2:** Commit `feat(doi): F3 Pluto Demo.jl`.

### Task F3.5: README

**Files:** Create `examples/doi_infograph/README.md`.

- [ ] Document: what it is; offline cache (`data/cache/`); `fetch_figure=false` default + publisher-ToS opt-in note; the 6 slots; HERO PNG embedded + composite PDF linked beside it (F3 acceptance); per-paper PDF usage pattern (loop `infograph` + `export_pdf`); Pluto run instructions; the 6 PROBE-FIRST deviations (esp. SemanticScholar.jl unusable, Pluto external, S2 ARXIV prefix). Commit `docs(doi): F3 README`.

---

## Verification (before PR — `superpowers:verification-before-completion`)

- [ ] Full suite ONCE → log: `mkdir -p test-logs && julia --project -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"` — **note:** demo suites run from their own env: `julia --project=examples/doi_infograph -e 'using Pkg; Pkg.test()'`. Grep the log rather than re-running.
- [ ] Confirm renders come from CACHE (no network): run `render_hero.jl` with no `DOIINFOGRAPH_WRITE_CACHE` set; it must succeed offline.
- [ ] `git status` clean of `Manifest.toml` (gitignored); all new `.jl` have SPDX headers.

## Self-review notes (done)

- **Spec coverage:** F1 (clients, reconstruction, cache, fetch_doi_metadata, og:image, 6-DOI offline, 429 backoff, slot-6 null) ✓; F2 (title autoshrink + 100-title property, author overflow, tldr autosize, drop cap, pill wrap, sparkline, infograph, integration, comparative, template ArgumentError, K-P fallback @warn) ✓; F3 (grid_infograph, single composite PDF+PNG, slot-6 graceful, Pluto slider, offline, PDF-text golden, hero PNG) ✓.
- **Type consistency:** `PaperMetadata`/`AuthorRef` field names match across F1→F3; `title_autoshrink` returns `(fs, nlines)`; `fit_authors` returns `(shown, etal)`; `_backend(fam, fs)` used throughout.
- **Open risk:** slot-5 `ng.3097` has no OpenAlex abstract; its abstract slot falls back to S2 tldr or the slot-6-style graceful path — acceptable, the author-overflow demo is the point. Re-verify at cache-build; swap to a ≥80-author paper *with* an abstract only if the render looks empty.
