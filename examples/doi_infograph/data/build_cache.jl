# SPDX-License-Identifier: MIT
# One-time cache builder (NOT run in CI). Populates data/cache/*.json from the live APIs.
#
#   DOIINFOGRAPH_WRITE_CACHE=1 julia --project=examples/doi_infograph \
#       examples/doi_infograph/data/build_cache.jl
#
# Tests + renders then run fully offline from the committed cache.
using DOIInfograph

const MAILTO = get(ENV, "DOIINFOGRAPH_MAILTO", "jjmaomi@gmail.com")

for doi in canonical_dois()
    DOIInfograph.fetch(OpenAlexClient(; mailto=MAILTO), doi)
    DOIInfograph.fetch(CrossRefClient(; mailto=MAILTO), doi)
    DOIInfograph.fetch(SemanticScholarClient(; mailto=MAILTO), doi)
    sleep(3)                       # polite to S2's unauthenticated rate limit
    @info "cached" doi
end
@info "cache build complete"
