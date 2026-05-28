# F1 — DOIInfograph data layer (`examples/doi_infograph/data/`)

> Wave 2 demo · first of the #F1 → #F2 → #F3 serial chain.

## Scope

API clients for OpenAlex, CrossRef, Semantic Scholar; abstract reconstruction from OpenAlex's inverted index; opt-in `og:image` scraping; offline-cached responses for the acceptance DOIs.

**Existing packages we depend on (verified on JuliaRegistries / GitHub):**

- **`SemanticScholar.jl`** (tmthyln, registered, UUID `f2f2c3a1-78ca-4323-b152-8442c77f9dcc`, v1.0.0, Julia 1.6+) ships both low-level direct-API bindings and a high-level struct layer. **Use this directly for the `tldr` field; do not reimplement.** See https://github.com/tmthyln/SemanticScholar.jl.
- **`Pitaya`** (naustica, unregistered GitHub-only, UUID `0b12f483-aaff-4a42-bf4f-5a3345f2360f`, last commit 2021) is the only existing Julia CrossRef client. It is stale (HTTP 0.9 compat) and unregistered, so we cite it as prior art but write our own thin `CrossRefClient` with current HTTP.jl. The Pitaya `works(doi="…")` signature is a useful API shape to mirror. URL: https://github.com/naustica/Pitaya.
- **No `OpenAlex.jl` exists** — searched `juliahub.com/ui/Packages?q=openalex` (0 hits) and GitHub `language:Julia openalex` (0 hits). Greenfield, justified.

### Clients to write

- `OpenAlexClient(; mailto::String)` — `HTTP.jl` + `JSON3.jl`. Reconstruct abstract from `abstract_inverted_index`: emit one `(word, position)` pair per occurrence (handles multi-position words like `"of" → [2, 34, 49, …]`), sort globally by position, join with single spaces. Edge cases: **duplicate positions** (rare but observed) are resolved by stable sort with word order; **position gaps** (rare) are tolerated as missing words and yield extra inter-word spacing.
- `CrossRefClient(; mailto)` — fallback metadata and references. Thin wrapper over `HTTP.jl`; mirrors Pitaya's `works(doi="…")` shape but on current HTTP.jl.
- **`SemanticScholarClient` is NOT a new wrapper** — `fetch_doi_metadata` calls `SemanticScholar.jl`'s `Paper`/`fetch` API directly. The PaperMetadata adapter (extract `tldr` from S2's response struct) is a tiny adapter, not a client.
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
- **Abstract reconstruction from OpenAlex inverted index is content-equivalent (not byte-equivalent) to the canonical published text** on the three DOIs that have abstracts. The OpenAlex inverted index drops case-folding info, mangles HTML entities, and removes some punctuation — exact byte-for-byte match is not achievable and not required. Acceptance criterion: every content token (non-stop-word) in the published abstract appears in the reconstructed string in the same order. Stop-word drops and whitespace differences are tolerated.
- `fetch_figure=false` is the default; opt-in path documented in the demo README with publisher-ToS note.
- Rate-limit handling: 429 → exponential backoff with `Retry-After` honored.
- **Slot-6 DOI (no abstract, no TLDR) does not crash any client** — null/missing-field handling is exercised by the offline cache.

## Depends on / Blocks

- **Depends on:** nothing.
- **Blocks:** #F2.

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#F1 — DOIInfograph data layer."
- **External APIs (verify endpoints + fields at impl time):**
  - OpenAlex: `https://api.openalex.org/works/doi:{DOI}?mailto=…`
  - CrossRef: `https://api.crossref.org/works/{DOI}` (with `mailto=` polite pool)
  - Semantic Scholar: `https://api.semanticscholar.org/graph/v1/paper/DOI:{DOI}?fields=tldr,…`
- **External Julia deps:** `HTTP.jl`, `JSON3.jl`, **`SemanticScholar.jl`** (registered). Prior art for CrossRef: `Pitaya` (GitHub-only, stale). No `OpenAlex.jl` exists.
- **Semantic Scholar `tldr` coverage caveat:** the S2 product docs note TLDRs are "currently limited to computer science and biomedical domains." Slot-3 (PLOS ONE general OA) and slot-6 (no-abstract slot) may legitimately lack a `tldr`; the data layer surfaces this as `tldr::Nothing` and #F2 handles the absence gracefully.
- **Conventions:** `CLAUDE.md`.

## Suggested labels

`demos-milestone` · `wave-2` · `examples` · `demo`
