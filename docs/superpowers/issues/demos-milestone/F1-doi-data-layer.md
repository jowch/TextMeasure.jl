# F1 — DOIInfograph data layer (`examples/doi_infograph/data/`)

> Wave 2 demo · first of the #F1 → #F2 → #F3 serial chain.

## Scope

API clients for OpenAlex, CrossRef, Semantic Scholar; abstract reconstruction from OpenAlex's inverted index; opt-in `og:image` scraping; offline-cached responses for the acceptance DOIs.

- `OpenAlexClient(; mailto::String)` — `HTTP.jl` + `JSON3.jl`. Reconstruct abstract from `abstract_inverted_index`: emit one `(word, position)` pair per occurrence (handles multi-position words like `"of" → [2, 34, 49, …]`), sort globally by position, join with single spaces. Edge cases: **duplicate positions** (rare but observed) are resolved by stable sort with word order; **position gaps** (rare) are tolerated as missing words and yield extra inter-word spacing.
- `CrossRefClient(; mailto)` — fallback metadata and references.
- `SemanticScholarClient()` — for the `tldr` field.
- `fetch_doi_metadata(doi; fetch_figure=false)` returns a `PaperMetadata` struct with fields:
  - `title::String`
  - `authors::Vector{AuthorRef}` (`AuthorRef` is a small struct with `given`, `family`, optional `affiliation`)
  - `abstract::Union{String,Nothing}`
  - `tldr::Union{String,Nothing}`
  - `citation_count::Int`
  - `citations_by_year::Vector{Tuple{Int,Int}}` (year, count)
  - `concepts::Vector{Tuple{String,Float64}}` (name, score)
  - `oa_status::Symbol` (∈ `:gold, :green, :hybrid, :closed, :unknown`)
  - `oa_url::Union{String,Nothing}`
  - `figure_url::Union{String,Nothing}` (`nothing` when `fetch_figure=false` or scrape failed)
  - `pp::Union{String,Nothing}` (printed page range as a string, e.g., `"505–510"`; `nothing` if unavailable)
  - `journal::Union{String,Nothing}`
  - `year::Union{Int,Nothing}`
  - `doi::String`
- `fetch_figure=false` by default — to respect publisher ToS. When opt-in, scrapes `og:image` from publisher page with explicit `User-Agent: TextMeasure.jl/<version> mailto=<user>` header.
- All six acceptance DOIs (see #F3) have their JSON responses **cached to `examples/doi_infograph/data/cache/`** for offline + reproducible CI.

## Acceptance

- All six acceptance DOIs round-trip via offline cache.
- Abstract reconstruction from OpenAlex inverted index matches the canonical published text on the three DOIs that have abstracts.
- `fetch_figure=false` is the default; opt-in path documented in the demo README with publisher-ToS note.
- Rate-limit handling: 429 → exponential backoff with `Retry-After` honored.

## Depends on / Blocks

- **Depends on:** nothing.
- **Blocks:** #F2.

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#F1 — DOIInfograph data layer."
- **External APIs (verify endpoints + fields at impl time):**
  - OpenAlex: `https://api.openalex.org/works/doi:{DOI}?mailto=…`
  - CrossRef: `https://api.crossref.org/works/{DOI}` (with `mailto=` polite pool)
  - Semantic Scholar: `https://api.semanticscholar.org/graph/v1/paper/DOI:{DOI}?fields=tldr,…`
- **External Julia deps:** `HTTP.jl`, `JSON3.jl`. (No `OpenAlex.jl` or `CrossRef.jl` exists in the Julia ecosystem — greenfield.)
- **Conventions:** `CLAUDE.md`.

## Suggested labels

`demos-milestone` · `wave-2` · `examples` · `demo`
