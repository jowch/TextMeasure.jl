# Erasure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Build the ERASURE gallery piece: lay out the project's own MIT `LICENSE` (verbatim) with the engine, redact all-but-curated words into one continuous ink censor field, and lift ~15 Fraunces survivors — frozen at their exact measured coordinates — into a found poem on a brass reading thread. Ship a deterministic golden over the computed geometry, a Makie→PNG hero render (whose render helper the other stills reuse), and a monospace tap-to-keep toy that defaults to the curated poem.

**Architecture:** A new in-repo example package `Erasure` at `examples/erasure/`, depending on `HouseStyle` (Foundation) + `TextMeasure` + `CairoMakie`/`FreeTypeAbstraction` by `[sources]` path. The load-bearing module is `wordgeom.jl`: it re-walks `prep.segments` with the SAME greedy + whitespace-trim rule `layout` uses to recover a per-word `(segment_index, line, x0, x1, baseline)` table the public API does not expose — proven correct by a golden assertion that its per-line word grouping reconstructs `layout(prep).lines` exactly (line count + trimmed `Line.str`). On top of that: a curated kept-set (`poem.jl`), a backend-agnostic redaction-rect builder (`redact.jl`), a clean shared `render.jl` (`save_png(scene_fn, path; size, px_per_unit=1)` — the helper the gallery's other stills reuse), the `Erasure.hero()` Makie scene, the `digest_rows` golden (`test/golden/hero.sha256`), and a deterministic MonospaceBackend toy (`toy.jl`).

**Tech Stack:** Julia 1.11+, `TextMeasure` (path dep), `HouseStyle` (path dep), `Makie`/`CairoMakie`, `FreeTypeAbstraction`, stdlib `Test`. Golden discipline: hash a COMPUTED geometry table via `HouseStyle.digest_rows`, never pixels (Cairo PNG bytes are not stable). MonospaceBackend is the deterministic test + toy backend; `MakieBackend(px_per_unit=1)` drives the hero render.

---

### Task 1: Scaffold the `Erasure` package

**Files:**
- Create: `examples/erasure/Project.toml`
- Create: `examples/erasure/src/Erasure.jl`
- Create: `examples/erasure/test/runtests.jl`

- [ ] **Step 1: Write the failing smoke test**

Create `examples/erasure/test/runtests.jl`:
```julia
using Erasure, Test

@testset "Erasure" begin
    @testset "loads" begin
        @test isdefined(Erasure, :LICENSE_TEXT)
    end
end
```

- [ ] **Step 2: Write the Project.toml**

Create `examples/erasure/Project.toml` (mirrors `examples/layouts/Project.toml`; `Test` is a stdlib; per the demo memory the Manifest stays gitignored):
```toml
name = "Erasure"
uuid = "e2a5c7d1-3b9f-4e60-8a1c-2d6f0b4e91a3"
version = "0.1.0"
authors = ["TextMeasure.jl contributors"]

[deps]
CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
FreeTypeAbstraction = "663a7486-cb36-511b-a19d-cf86c1391c25"
HouseStyle = "f1a9b3c2-0d4e-4a6b-9c8d-7e2f1a0b3c4d"
Makie = "ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a"
TextMeasure = "06791c1d-2336-41e1-bd6f-a74c63395da6"

# Unregistered in-repo packages — resolve by path (Julia 1.11+ [sources]).
[sources]
HouseStyle = { path = "../_housestyle" }
TextMeasure = { path = "../.." }

[compat]
julia = "1.11"

[extras]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["Test"]
```

- [ ] **Step 3: Write the minimal module with the verbatim LICENSE**

Create `examples/erasure/src/Erasure.jl`. `LICENSE_TEXT` is the project `LICENSE` **verbatim** (the two clause paragraphs that contain every curated survivor; reproduced exactly, original line breaks collapsed to spaces inside each paragraph, paragraphs joined by a single `\n` so the engine wraps them):
```julia
module Erasure

# The project's own LICENSE, verbatim (collapsed internal newlines -> spaces; the two
# substantive paragraphs joined by one newline). EVERY curated survivor (poem.jl) is a
# real word in this text, in this order. Do not paraphrase — the gag is that the demo
# redacts the exact text governing it.
const LICENSE_TEXT =
    "Permission is hereby granted, free of charge, to any person obtaining a copy " *
    "of this software and associated documentation files (the \"Software\"), to deal " *
    "in the Software without restriction, including without limitation the rights " *
    "to use, copy, modify, merge, publish, distribute, sublicense, and/or sell " *
    "copies of the Software, and to permit persons to whom the Software is " *
    "furnished to do so, subject to the following conditions:\n" *
    "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR " *
    "IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, " *
    "FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE " *
    "AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER " *
    "LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, " *
    "OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE " *
    "SOFTWARE."

end # module
```

- [ ] **Step 4: Instantiate and run the test (expect PASS)**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```
Expected: `Test Summary: | Pass 1` — "loads" passes (`LICENSE_TEXT` is defined).

- [ ] **Step 5: Commit**

```bash
git add examples/erasure/Project.toml examples/erasure/src/Erasure.jl examples/erasure/test/runtests.jl
git commit -m "feat(erasure): scaffold Erasure package + verbatim LICENSE source"
```

---

### Task 2 (RISKIEST): `:left` per-word geometry re-walk

**Files:**
- Create: `examples/erasure/src/wordgeom.jl`
- Modify: `examples/erasure/src/Erasure.jl` (include it)
- Create: `examples/erasure/test/test_wordgeom.jl`
- Modify: `examples/erasure/test/runtests.jl` (include it)

This is the load-bearing slice: there is NO per-word x accessor, so we re-derive `(segment_index, line, x0, x1, baseline)` by re-walking `prep.segments` with the SAME greedy + whitespace-TRIM rule `layout` uses. Under `align=:left` with NO kerning, the accumulated x equals exactly layout's placement. The golden-grade test is that the re-walk's per-line word grouping reconstructs `layout(prep).lines` — same line count, same trimmed `Line.str`.

- [ ] **Step 1: Write the failing test — `WordBox` exists**

Create `examples/erasure/test/test_wordgeom.jl`:
```julia
using Erasure                                   # for Erasure.LICENSE_TEXT (Step 7 real case)
using Erasure: WordBox, word_boxes
using TextMeasure: prepare, layout, MonospaceBackend
using Test

@testset "wordgeom" begin
    @testset "WordBox shape" begin
        b = MonospaceBackend(fontsize = 11.0)
        prep = prepare(b, "alpha beta")
        boxes = word_boxes(prep; max_width = Inf)
        @test eltype(boxes) == WordBox
        @test boxes[1].seg_index isa Int
        @test boxes[1].line isa Int
        @test boxes[1].x0 isa Float64
        @test boxes[1].x1 isa Float64
        @test boxes[1].baseline isa Float64
    end
end
```

- [ ] **Step 2: Run it (expect FAIL)**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_wordgeom.jl")'
```
Expected: FAIL — `UndefVarError: WordBox not defined in Erasure` (nothing implemented yet).

- [ ] **Step 3: Implement the re-walk (minimal real Julia)**

Create `examples/erasure/src/wordgeom.jl`. The accumulator mirrors `layout`'s loop exactly — `pending` space handling, atomic over-wide word, per-line trim — but records each WORD's `(seg_index, line, x0, x1)` instead of joining strings. Baselines come from `prep.metrics` with the SAME formula `layout` uses (`ascent + (line-1)*lineheight*line_advance`):
```julia
"One word's recovered box. `x0/x1` are the left-aligned run extent in px; `baseline`
is block-top-relative (same coordinate system as `Line.baseline`). `seg_index` indexes
`prep.segments`."
struct WordBox
    seg_index :: Int
    line      :: Int
    x0        :: Float64
    x1        :: Float64
    baseline  :: Float64
end

"""
    word_boxes(prep; max_width=Inf, lineheight=1.0) -> Vector{WordBox}

Recover a per-word geometry table by re-walking `prep.segments` with the SAME greedy +
whitespace-trim rule `TextMeasure.layout` uses. Exact under `align=:left` (no kerning):
the accumulated x equals layout's placement. One WordBox per `:word` segment, in source
order. Verified against `layout(prep).lines` by the golden assertion in test_wordgeom.jl.
"""
function word_boxes(prep; max_width = Inf, lineheight = 1.0)
    m  = prep.metrics
    la = lineheight * m.line_advance
    mw = (isnan(max_width) || max_width <= 0) ? Inf : Float64(max_width)

    boxes   = WordBox[]
    line    = 1
    cur_x   = 0.0            # running right edge of committed content on this line
    has_word = false         # any word committed on this line yet?
    pending_w = 0.0          # width of a pending (not-yet-committed) space
    pending_open = false

    newline!() = (line += 1; cur_x = 0.0; has_word = false; pending_w = 0.0; pending_open = false)

    for (i, seg) in enumerate(prep.segments)
        if seg.kind === :newline
            newline!()
        elseif seg.kind === :space
            pending_w = seg.width; pending_open = true
        else  # :word
            if !has_word
                # first word on the line: no leading space, starts at x=0 (trim)
                x0 = 0.0
                push!(boxes, WordBox(i, line, x0, x0 + seg.width,
                                     m.ascent + (line - 1) * la))
                cur_x = seg.width; has_word = true; pending_open = false; pending_w = 0.0
            else
                extra = (pending_open ? pending_w : 0.0) + seg.width
                if cur_x + extra > mw
                    newline!()
                    x0 = 0.0
                    push!(boxes, WordBox(i, line, x0, x0 + seg.width,
                                         m.ascent + (line - 1) * la))
                    cur_x = seg.width; has_word = true
                else
                    x0 = cur_x + (pending_open ? pending_w : 0.0)
                    push!(boxes, WordBox(i, line, x0, x0 + seg.width,
                                         m.ascent + (line - 1) * la))
                    cur_x = x0 + seg.width; pending_open = false; pending_w = 0.0
                end
            end
        end
    end
    return boxes
end
```

Then add the include + exports to `examples/erasure/src/Erasure.jl` (immediately after the `LICENSE_TEXT` block, before `end # module`):
```julia
include("wordgeom.jl")
export WordBox, word_boxes
```

- [ ] **Step 4: Run the test (expect PASS)**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_wordgeom.jl")'
```
Expected: PASS — "WordBox shape" testset green.

- [ ] **Step 5: Write the GOLDEN-GRADE agreement test**

Append to `examples/erasure/test/test_wordgeom.jl` (inside the outer `@testset "wordgeom"`, after the "WordBox shape" block): reconstruct each line's trimmed `str` from the words the re-walk assigns to it, and assert it equals `layout`'s `Line.str` line-for-line. This is the no-drift guarantee:
```julia
    @testset "re-walk agrees with layout(prep).lines (no whitespace drift)" begin
        b = MonospaceBackend(fontsize = 11.0)
        text = "Permission is hereby granted to deal without restriction the Software"
        for mw in (Inf, 200.0, 90.0, 40.0)
            prep = prepare(b, text)
            lay  = layout(prep; max_width = mw, align = :left)
            boxes = word_boxes(prep; max_width = mw)
            # group word strings by re-walk line, in source order
            nlines = maximum(wb.line for wb in boxes)
            @test nlines == length(lay.lines)
            for ln in 1:nlines
                words = [prep.segments[wb.seg_index].str for wb in boxes if wb.line == ln]
                @test join(words, " ") == lay.lines[ln].str
            end
        end
    end
```
(Note: rejoining words with a single space reproduces layout's trimmed `Line.str` because `prepare` collapses each whitespace run to ONE `:space` segment and the trim drops line-edge spaces — so interior gaps are exactly one space. If a source ever had multi-space runs this would need the actual space widths; the LICENSE has none.)

- [ ] **Step 6: Run it (expect PASS)**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_wordgeom.jl")'
```
Expected: PASS — both testsets green; the re-walk's line grouping matches `layout` for every `max_width`.

- [ ] **Step 7: Add the REAL LICENSE agreement case (full text at the hero width)**

The toy-string loop above only exercises short strings. Add the actual production case — the full `LICENSE_TEXT` at the hero's `max_width` — so any drift at the real word count / real wrap is caught. Append inside the same `@testset "re-walk agrees with layout(prep).lines (no whitespace drift)"` block (after the `for mw in (…)` loop):
```julia
        # REAL case: the full LICENSE at the hero wrap width must reconstruct line-for-line.
        let mw = 422.0   # == HERO_MAX_WIDTH (golden.jl); the production hero width
            prep = prepare(b, Erasure.LICENSE_TEXT)
            lay  = layout(prep; max_width = mw, align = :left)
            boxes = word_boxes(prep; max_width = mw)
            nlines = maximum(wb.line for wb in boxes)
            @test nlines == length(lay.lines)            # same line count as layout
            for ln in 1:nlines
                words = [prep.segments[wb.seg_index].str for wb in boxes if wb.line == ln]
                @test join(words, " ") == lay.lines[ln].str   # same trimmed Line.str
            end
        end
```
(`Erasure.LICENSE_TEXT` is already loaded by `using Erasure`-side imports; the `b`/`prepare`/`layout`/`word_boxes` bindings are the ones at the top of test_wordgeom.jl. `422.0` is `HERO_MAX_WIDTH` from Task 5 — keep the two in sync.)

- [ ] **Step 8: Wire into runtests.jl and commit**

In `examples/erasure/test/runtests.jl`, add `include("test_wordgeom.jl")` inside the `@testset "Erasure"` block (after the "loads" testset). Then:
```bash
julia --project=examples/erasure -e 'using Pkg; Pkg.test()'
```
Expected: PASS — aggregated suite green (incl. the full-LICENSE re-walk agreement at width 422). Commit:
```bash
git add examples/erasure/src/wordgeom.jl examples/erasure/src/Erasure.jl examples/erasure/test/test_wordgeom.jl examples/erasure/test/runtests.jl
git commit -m "feat(erasure): :left per-word geometry re-walk, proven against layout"
```

---

### Task 3: Curated kept-set + the found poem

**Files:**
- Create: `examples/erasure/src/poem.jl`
- Modify: `examples/erasure/src/Erasure.jl` (include + export)
- Create: `examples/erasure/test/test_poem.jl`
- Modify: `examples/erasure/test/runtests.jl`

Curation is authoring, not engine work. The kept-set is identified by `:word`-segment index (the Nth WORD in `LICENSE_TEXT`), so it bonds directly to `WordBox.seg_index` via a word-ordinal map. The survivors (SPEC §3 Candidate A), each a real word of `LICENSE_TEXT` in order: Permission · granted · to deal · without restriction · to use · modify · merge · distribute · the Software · WITHOUT WARRANTY · OF ANY KIND · THE AUTHORS · LIABLE · ARISING FROM · THE SOFTWARE.

- [ ] **Step 1: Write the failing test**

Create `examples/erasure/test/test_poem.jl`:
```julia
using Erasure: LICENSE_TEXT, KEPT_WORDS, kept_seg_indices
using TextMeasure: prepare, MonospaceBackend
using Test

@testset "poem" begin
    @testset "every kept word is a real word of the LICENSE, in order" begin
        b = MonospaceBackend(fontsize = 11.0)
        prep = prepare(b, LICENSE_TEXT)
        words = [s.str for s in prep.segments if s.kind === :word]
        idxs  = kept_seg_indices(prep)
        @test length(idxs) == length(KEPT_WORDS)
        @test issorted(idxs)                       # reading order preserved
        @test allunique(idxs)
        for (k, segi) in zip(KEPT_WORDS, idxs)
            @test prep.segments[segi].kind === :word
            @test prep.segments[segi].str == k     # exact word at that segment
        end
    end
end
```

- [ ] **Step 2: Run it (expect FAIL)**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_poem.jl")'
```
Expected: FAIL — `UndefVarError: KEPT_WORDS not defined in Erasure`.

- [ ] **Step 3: Implement the kept-set + ordinal mapping**

Create `examples/erasure/src/poem.jl`. `KEPT_WORDS` lists survivors as `(word_string, word_ordinal)` — ordinal = which occurrence among the `:word` segments — so duplicates ("Software" appears many times) resolve to the SPEC's intended position. Ordinals are derived once below from the verbatim text:
```julia
# Survivors as (word, occurrence-ordinal-among-:word-segments). Ordinals are fixed by
# the verbatim LICENSE_TEXT word sequence; the test re-derives & verifies them, so a
# wrong ordinal fails loudly. SPEC §3 Candidate A reading order.
const KEPT_SPEC = [
    ("Permission",  1),   # word #1
    ("granted",     4),   # "...hereby granted,"
    ("to",          8), ("deal", 9),
    ("without",     14), ("restriction", 15),
    ("to",          20), ("use",  21),         # "to use,"
    ("modify",      24),
    ("merge",       25),
    ("distribute",  27),
    ("the",         53), ("Software", 54),     # "...included in all copies ... the Software"  -> resolved by test
    ("WITHOUT",     0),  ("WARRANTY", 0),
    ("OF",          0),  ("ANY",      0), ("KIND", 0),
    ("AUTHORS",     0),
    ("LIABLE",      0),
    ("ARISING",     0),  ("FROM",     0),
    ("SOFTWARE",    0),
]

# Display list (what the margin readout / caption shows), the human-readable poem words.
const KEPT_WORDS = [w for (w, _) in KEPT_SPEC]

"""
    kept_seg_indices(prep) -> Vector{Int}

Resolve each survivor to its `prep.segments` index. For entries with a nonzero ordinal
we honor it; ordinal `0` means "the next not-yet-used occurrence of this word at or
after the previously matched word" (forward scan). Returns indices in reading order.
"""
function kept_seg_indices(prep)
    word_pos = [i for (i, s) in enumerate(prep.segments) if s.kind === :word]
    # ordinal -> segment index
    nth(word_str, want) = begin
        c = 0
        for (ord, i) in enumerate(word_pos)
            if prep.segments[i].str == word_str
                c += 1
                c == want && return i
            end
        end
        error("word $(repr(word_str)) occurrence $want not found")
    end
    idxs = Int[]
    last_i = 0
    for (w, ord) in KEPT_SPEC
        i = if ord > 0
            nth(w, ord)
        else
            # next occurrence strictly after last_i
            j = findfirst(p -> p > last_i && prep.segments[p].str == w, word_pos)
            j === nothing && error("word $(repr(w)) not found after index $last_i")
            word_pos[j]
        end
        push!(idxs, i); last_i = i
    end
    return idxs
end
```

NOTE for the implementer: the literal ordinals above (1,4,8,9,…) are a *starting hint*; the failing test in Step 1 re-derives the true word sequence from `LICENSE_TEXT` and asserts `prep.segments[segi].str == k`. Run Step 4, read the assertion failures, and correct each ordinal (or switch that entry to `0` for forward-scan) until green. Do NOT guess silently — the test is the oracle. (Many entries are already safe with ordinal `0` forward-scan; prefer `0` unless a specific earlier occurrence is wanted.)

ORDINAL RESOLUTION ORDER — resolve TOP-DOWN (earliest occurrence first). The `0`/forward-scan entries anchor off `last_i` (the prior matched index), so a single wrong EARLY hint cascades: every later `0` scans from the wrong position and mis-resolves. Therefore work the list strictly top-to-bottom, fix the first wrong entry, re-run, and only then move on — never patch a late entry while an earlier one is still red. For the FIRST few survivors (where there is no earlier anchor to lean on) prefer EXPLICIT nonzero ordinals over `0`, so the forward-scan chain starts from a known-good index.

Add to `examples/erasure/src/Erasure.jl` after the `wordgeom.jl` include:
```julia
include("poem.jl")
export KEPT_WORDS, kept_seg_indices
```

- [ ] **Step 4: Run the test, correct ordinals until PASS**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_poem.jl")'
```
Expected (initially): FAIL on the words whose ordinal hint is wrong — the message prints the expected survivor vs `prep.segments[segi].str`. Adjust each `KEPT_SPEC` ordinal (or set to `0`) and re-run until: PASS — all survivors resolve to real, in-order LICENSE words.

- [ ] **Step 5: Wire into runtests.jl and commit**

Add `include("test_poem.jl")` to `examples/erasure/test/runtests.jl`. Then:
```bash
julia --project=examples/erasure -e 'using Pkg; Pkg.test()'
```
Expected: PASS — full suite green. Commit:
```bash
git add examples/erasure/src/poem.jl examples/erasure/src/Erasure.jl examples/erasure/test/test_poem.jl examples/erasure/test/runtests.jl
git commit -m "feat(erasure): curated MIT-License found-poem kept-set"
```

---

### Task 4: Redaction-rect builder (continuous censor bars)

**Files:**
- Create: `examples/erasure/src/redact.jl`
- Modify: `examples/erasure/src/Erasure.jl` (include + export)
- Create: `examples/erasure/test/test_redact.jl`
- Modify: `examples/erasure/test/runtests.jl`

Backend-agnostic geometry: from `word_boxes` + the kept set, produce (a) `Rect`s for blacked runs where adjacent bars + the inter-word space between two blacked words tile into ONE continuous bar (no paper sliver), and (b) survivor anchor boxes. SPEC §2 + §6: spaces between two blacked words are filled; spaces adjacent to a kept word stay paper; 1px ink bleed each end.

- [ ] **Step 1: Write the failing test (no paper sliver between consecutive blacked words)**

Create `examples/erasure/test/test_redact.jl`:
```julia
using Erasure: word_boxes, redaction_rects, RedactRect
using TextMeasure: prepare, MonospaceBackend
using Test

@testset "redact" begin
    @testset "consecutive blacked words tile into one continuous bar" begin
        b = MonospaceBackend(fontsize = 11.0)
        prep = prepare(b, "alpha beta gamma")     # 3 words, all blacked (kept = empty)
        boxes = word_boxes(prep; max_width = Inf)
        rects = redaction_rects(boxes, prep, Int[]; bleed = 1.0)
        # all three words on one line, no kept words -> one merged bar
        @test length(rects) == 1
        r = rects[1]
        @test r.x0 < boxes[1].x0 + 1e-9                  # bleed at/left of first word
        @test r.x1 > boxes[3].x1 - 1e-9                  # covers through last word
        # spans the full inter-word gaps (no holes): width >= last.x1 - first.x0
        @test r.x1 - r.x0 >= (boxes[3].x1 - boxes[1].x0)
    end

    @testset "a kept word splits the bar and keeps its space paper" begin
        b = MonospaceBackend(fontsize = 11.0)
        prep = prepare(b, "alpha beta gamma")
        boxes = word_boxes(prep; max_width = Inf)
        kept = [boxes[2].seg_index]                       # keep "beta"
        rects = redaction_rects(boxes, prep, kept; bleed = 1.0)
        @test length(rects) == 2                          # bar before + bar after "beta"
        # neither bar overlaps the kept word's run (its adjacent spaces are paper)
        for r in rects
            @test !(r.x0 < boxes[2].x1 && r.x1 > boxes[2].x0)
        end
    end
end
```

- [ ] **Step 2: Run it (expect FAIL)**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_redact.jl")'
```
Expected: FAIL — `UndefVarError: redaction_rects not defined`.

- [ ] **Step 3: Implement the rect builder**

Create `examples/erasure/src/redact.jl`. Walk boxes per line; a maximal run of consecutive BLACKED words (no kept word between them) becomes one rect from `first.x0 - bleed` to `last.x1 + bleed`. Because the per-line words are consecutive in source order with no kept break, the inter-word spaces between them are implicitly covered (the rect spans `x0..x1` continuously). The vertical band uses `line_top..line_top+ascent+descent`:
```julia
"A solid ink redaction rectangle in block coordinates (y down)."
struct RedactRect
    x0 :: Float64
    x1 :: Float64
    y0 :: Float64   # top
    y1 :: Float64   # bottom
end

"""
    redaction_rects(boxes, prep, kept_seg_indices; bleed=1.0) -> Vector{RedactRect}

Merge maximal runs of consecutive BLACKED words on each line into one continuous bar
(spaces between two blacked words are covered; a kept word breaks the run, leaving its
adjacent spaces paper). `bleed` px is added at each run end so adjacent bars read as one
censor line. Vertical band = the full line band (ascent+descent) from `prep.metrics`.
"""
function redaction_rects(boxes, prep, kept; bleed = 1.0)
    keptset = Set(kept)
    m = prep.metrics
    band = m.ascent + m.descent
    rects = RedactRect[]
    i = 1
    n = length(boxes)
    while i <= n
        wb = boxes[i]
        if wb.seg_index in keptset
            i += 1; continue                      # survivors are never redacted
        end
        # start a run on this line of blacked words
        run_line = wb.line
        x0 = wb.x0
        x1 = wb.x1
        top = wb.baseline - m.ascent
        j = i + 1
        while j <= n && boxes[j].line == run_line && !(boxes[j].seg_index in keptset)
            x1 = boxes[j].x1
            j += 1
        end
        push!(rects, RedactRect(x0 - bleed, x1 + bleed, top, top + band))
        i = j
    end
    return rects
end
```

Add to `examples/erasure/src/Erasure.jl` after the `poem.jl` include:
```julia
include("redact.jl")
export RedactRect, redaction_rects
```

- [ ] **Step 4: Run the test (expect PASS)**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_redact.jl")'
```
Expected: PASS — both tiling testsets green (one merged bar with no holes; kept word splits cleanly).

- [ ] **Step 5: Wire into runtests.jl and commit**

Add `include("test_redact.jl")` to `examples/erasure/test/runtests.jl`. Then:
```bash
julia --project=examples/erasure -e 'using Pkg; Pkg.test()'
```
Expected: PASS. Commit:
```bash
git add examples/erasure/src/redact.jl examples/erasure/src/Erasure.jl examples/erasure/test/test_redact.jl examples/erasure/test/runtests.jl
git commit -m "feat(erasure): continuous-censor-bar redaction rect builder"
```

---

### Task 5: Deterministic golden over the computed geometry

**Files:**
- Create: `examples/erasure/src/golden.jl`
- Modify: `examples/erasure/src/Erasure.jl` (include + export)
- Create: `examples/erasure/test/golden/hero.sha256`
- Create: `examples/erasure/test/test_golden.jl`
- Modify: `examples/erasure/test/runtests.jl`

Mirrors `examples/asteroid_tui/test/golden/` (sha file + `UPDATE_GOLDEN=1` regen). Hash a COMPUTED geometry table via `HouseStyle.digest_rows` — never pixels. The table is built with the deterministic `MonospaceBackend` at the hero's `max_width`.

- [ ] **Step 1: Implement the geometry-row builder**

Create `examples/erasure/src/golden.jl`. One row per word: kept flag, line, rounded `x0/x1/baseline` — exactly the geometry the render consumes, so a drift in the re-walk OR the kept-set changes the digest:
```julia
using HouseStyle: digest_rows
using TextMeasure: prepare, MonospaceBackend

"The deterministic monospace backend the golden + toy use (body face at RAMP.body)."
golden_backend() = MonospaceBackend(fontsize = 11.0)

"Hero wrap width in px under the golden backend (≈64ch of body 11 mono; 11*0.6*64≈422)."
const HERO_MAX_WIDTH = 422.0

"""
    geometry_rows(; max_width=HERO_MAX_WIDTH) -> Vector{String}

Build the canonical per-word geometry table for the curated hero: `kept|line|x0|x1|base`,
floats rounded to 0.01px. Deterministic (MonospaceBackend). Fed to `digest_rows`.
"""
function geometry_rows(; max_width = HERO_MAX_WIDTH)
    b = golden_backend()
    prep  = prepare(b, LICENSE_TEXT)
    boxes = word_boxes(prep; max_width = max_width)
    kept  = Set(kept_seg_indices(prep))
    rows = String[]
    for wb in boxes
        k = wb.seg_index in kept ? 1 : 0
        push!(rows, string(k, "|", wb.line, "|",
                           round(wb.x0; digits = 2), "|",
                           round(wb.x1; digits = 2), "|",
                           round(wb.baseline; digits = 2)))
    end
    return rows
end

"SHA-256 hex of the canonical hero geometry table."
hero_digest(; max_width = HERO_MAX_WIDTH) = digest_rows(geometry_rows(; max_width = max_width))
```

Add to `examples/erasure/src/Erasure.jl` after the `redact.jl` include:
```julia
include("golden.jl")
export geometry_rows, hero_digest, HERO_MAX_WIDTH
```

- [ ] **Step 2: Write the golden test (no sha file yet -> regen path)**

Create `examples/erasure/test/test_golden.jl` (mirrors asteroid's `UPDATE_GOLDEN` pattern):
```julia
using Erasure: geometry_rows, hero_digest, LICENSE_TEXT
using Test

const GOLDEN_DIR = joinpath(@__DIR__, "golden")

@testset "golden hero geometry" begin
    rows = geometry_rows()
    @test !isempty(rows)
    @test length(rows) > 100                         # the LICENSE has many words
    cs = hero_digest()
    @test length(cs) == 64                           # sha256 hex

    path = joinpath(GOLDEN_DIR, "hero.sha256")
    if get(ENV, "UPDATE_GOLDEN", "") == "1"
        mkpath(GOLDEN_DIR)
        write(path, cs)
        write(joinpath(GOLDEN_DIR, "hero.rows.txt"), join(rows, "\n"))
    end
    @test isfile(path)
    @test cs == strip(read(path, String))            # regression anchor
end
```

- [ ] **Step 3: Run WITHOUT the golden to confirm it fails closed**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_golden.jl")'
```
Expected: FAIL — `@test isfile(path)` fails (no `hero.sha256` yet). This proves the test fails closed rather than silently skipping.

- [ ] **Step 4: Generate the golden, then run clean (expect PASS)**

Run:
```bash
UPDATE_GOLDEN=1 julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_golden.jl")'
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_golden.jl")'
```
Expected: first run writes `hero.sha256` + `hero.rows.txt` and passes; second run (no env var) PASSES against the committed digest.

- [ ] **Step 5: Wire into runtests.jl and commit (including the golden file)**

Add `include("test_golden.jl")` to `examples/erasure/test/runtests.jl`. Then:
```bash
julia --project=examples/erasure -e 'using Pkg; Pkg.test()'
```
Expected: PASS. Commit:
```bash
git add examples/erasure/src/golden.jl examples/erasure/src/Erasure.jl examples/erasure/test/test_golden.jl examples/erasure/test/runtests.jl examples/erasure/test/golden/hero.sha256 examples/erasure/test/golden/hero.rows.txt
git commit -m "feat(erasure): deterministic golden over computed hero geometry"
```

---

### Task 6: Shared Makie→PNG render helper

**Files:**
- Create: `examples/erasure/src/render.jl`
- Modify: `examples/erasure/src/Erasure.jl` (include + export)
- Create: `examples/erasure/test/test_render.jl`
- Modify: `examples/erasure/test/runtests.jl`

This is the FIRST vertical slice, so it establishes the clean Makie→PNG helper the other gallery stills reuse. Keep it tiny and orthogonal: a function that takes a scene-builder closure (given a `Makie.Axis`), draws on PAPER, and saves a PNG. No erasure specifics here — purely the reusable render plumbing. `MakieBackend(px_per_unit=1)` is used by callers; the helper sets `px_per_unit` on save.

- [ ] **Step 1: Write the failing test**

Create `examples/erasure/test/test_render.jl`:
```julia
using Erasure: save_png
using CairoMakie
using Test

@testset "render helper" begin
    @testset "save_png writes a non-empty PNG on PAPER" begin
        path = joinpath(mktempdir(), "smoke.png")
        save_png(path; size = (200, 120), px_per_unit = 1) do ax
            CairoMakie.scatter!(ax, [1.0, 2.0], [1.0, 2.0])
        end
        @test isfile(path)
        @test filesize(path) > 0
        # PNG magic bytes
        @test read(path, 8) == UInt8[0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]
    end
end
```

- [ ] **Step 2: Run it (expect FAIL)**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_render.jl")'
```
Expected: FAIL — `UndefVarError: save_png not defined`.

- [ ] **Step 3: Implement the helper**

Create `examples/erasure/src/render.jl`. PAPER background, hidden decorations, y-down (block coordinates), aspect-locked; the closure receives the `Axis`:
```julia
using CairoMakie
using HouseStyle: PAPER

"""
    save_png(scene_fn, path; size=(1200, 1600), px_per_unit=1, yflip=true)

Reusable gallery render plumbing: build a PAPER-backed, decoration-free `Axis` (y down
when `yflip`, matching the engine's block coordinates), invoke `scene_fn(ax)` to draw,
and save a PNG at `px_per_unit`. The shared still-render entry point for the gallery.
"""
function save_png(scene_fn, path; size = (1200, 1600), px_per_unit = 1, yflip = true)
    fig = Figure(; size = size, backgroundcolor = PAPER)
    ax  = Axis(fig[1, 1]; backgroundcolor = PAPER, aspect = DataAspect())
    hidedecorations!(ax); hidespines!(ax)
    yflip && (ax.yreversed = true)        # block-top = 0, increasing downward
    scene_fn(ax)
    save(path, fig; px_per_unit = px_per_unit)
    return path
end
```

Add to `examples/erasure/src/Erasure.jl` after the `golden.jl` include:
```julia
include("render.jl")
export save_png
```

- [ ] **Step 4: Run the test (expect PASS)**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_render.jl")'
```
Expected: PASS — `smoke.png` written with valid PNG magic bytes.

- [ ] **Step 5: Wire into runtests.jl and commit**

Add `include("test_render.jl")` to `examples/erasure/test/runtests.jl`. Then:
```bash
julia --project=examples/erasure -e 'using Pkg; Pkg.test()'
```
Expected: PASS. Commit:
```bash
git add examples/erasure/src/render.jl examples/erasure/src/Erasure.jl examples/erasure/test/test_render.jl examples/erasure/test/runtests.jl
git commit -m "feat(erasure): shared Makie->PNG render helper (gallery still plumbing)"
```

---

### Task 7: The hero scene + PNG + visual sign-off

**Files:**
- Create: `examples/erasure/src/hero.jl`
- Modify: `examples/erasure/src/Erasure.jl` (include + export)
- Create: `examples/erasure/test/test_hero.jl`
- Modify: `examples/erasure/test/runtests.jl`

Compose the gallery image: solid INK redaction bars (Task 4) over the blacked words; Fraunces survivors at subhead 16 on a BRASS underlay; a BRASS reading thread through survivors in reading order. Uses `MakieBackend(px_per_unit=1)` for measurement so glyph extents match the render, and the `save_png` helper. Per the memory ("green ≠ sign-off"), an explicit OPEN-AND-LOOK step.

- [ ] **Step 1: Write the failing test (the hero builder returns survivor anchors + writes a PNG)**

Create `examples/erasure/test/test_hero.jl`:
```julia
using Erasure: hero, LICENSE_TEXT, KEPT_WORDS
using Test

@testset "hero" begin
    @testset "renders PNG and exposes survivor anchors in reading order" begin
        dir = mktempdir()
        path = joinpath(dir, "erasure-hero.png")
        result = hero(path)
        @test isfile(path)
        @test filesize(path) > 0
        @test read(path, 8) == UInt8[0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]
        # survivor anchors: one per kept word, strictly in reading order (line, then x)
        anchors = result.survivors            # Vector of (line, x0, x1, baseline, str)
        @test length(anchors) == length(KEPT_WORDS)
        for k in 2:length(anchors)
            a, prev = anchors[k], anchors[k-1]
            @test (a.line, a.x0) >= (prev.line, prev.x0)   # reading order monotone
        end
    end
end
```

- [ ] **Step 2: Run it (expect FAIL)**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_hero.jl")'
```
Expected: FAIL — `UndefVarError: hero not defined`.

- [ ] **Step 3: Implement the hero scene**

Create `examples/erasure/src/hero.jl`. Measure with `MakieBackend(px_per_unit=1)` at body 11 (Plex Mono) for the bar geometry; draw redaction rects in INK; draw each survivor as Fraunces 16 text on a BRASS underlay (8% fill + hairline); draw a BRASS Catmull-Rom-ish polyline through survivor anchors:
```julia
using Makie, CairoMakie
using Makie: Point2f, Rect2f
using HouseStyle: PAPER, INK, BRASS, RAMP, fraunces, plexmono, footer
using TextMeasure: prepare, layout, MakieBackend

# 8% brass underlay fill
_brass_underlay() = Makie.RGBA(Makie.RGB(BRASS), 0.08)

"""
    hero(path) -> (; survivors, png)

Render the curated MIT-License found poem: INK censor bars over blacked words, Fraunces
survivors (subhead 16) on BRASS underlays at their EXACT measured coordinates, a BRASS
reading thread through survivors in reading order. Writes `path` (PNG via `save_png`).
"""
function hero(path)
    # MakieBackend is KEYWORD-ONLY (verified against ext/TextMeasureMakieExt.jl): pass the
    # font PATH via `font=`, never positionally (positional ctor wants a resolved FTFont).
    body = MakieBackend(; font = plexmono("Regular"), fontsize = RAMP.body, px_per_unit = 1)
    prep  = prepare(body, LICENSE_TEXT)
    boxes = word_boxes(prep; max_width = HERO_MAX_WIDTH)
    kept_idx = kept_seg_indices(prep)
    keptset  = Set(kept_idx)
    rects = redaction_rects(boxes, prep, kept_idx; bleed = 1.0)

    # survivor anchors in reading order (kept_seg_indices is already ordered)
    bybox = Dict(wb.seg_index => wb for wb in boxes)
    survivors = [(line = bybox[i].line, x0 = bybox[i].x0, x1 = bybox[i].x1,
                  baseline = bybox[i].baseline, str = prep.segments[i].str)
                 for i in kept_idx]

    pad = 2.0
    save_png(path; size = (1200, 1600), px_per_unit = 1) do ax
        # 1. INK censor bars
        for r in rects
            poly!(ax, Rect2f(r.x0, r.y0, r.x1 - r.x0, r.y1 - r.y0); color = INK)
        end
        # 2. BRASS underlay + Fraunces survivor glyphs
        m = prep.metrics
        for s in survivors
            top = s.baseline - m.ascent
            poly!(ax, Rect2f(s.x0 - pad, top - pad,
                             (s.x1 - s.x0) + 2pad, (m.ascent + m.descent) + 2pad);
                  color = _brass_underlay(), strokecolor = BRASS, strokewidth = 0.75)
            text!(ax, Point2f(s.x0, s.baseline); text = s.str, color = INK,
                  font = fraunces("9pt-SemiBold"), fontsize = RAMP.subhead,
                  align = (:left, :baseline))
        end
        # 3. BRASS reading thread (trailing edge -> leading edge, reading order)
        thread = Point2f[]
        for s in survivors
            push!(thread, Point2f(s.x0, s.baseline))
            push!(thread, Point2f(s.x1, s.baseline))
        end
        lines!(ax, thread; color = BRASS, linewidth = 1.0)
        # 4. footer
        last_base = maximum(s.baseline for s in survivors)
        text!(ax, Point2f(0, last_base + 3 * m.line_advance); text = footer("Erasure"),
              color = BRASS, font = plexmono("Regular"), fontsize = RAMP.caption,
              align = (:left, :baseline))
    end
    return (; survivors = survivors, png = path)
end
```

Add to `examples/erasure/src/Erasure.jl` after the `render.jl` include:
```julia
include("hero.jl")
export hero
```

- [ ] **Step 4: Run the test (expect PASS)**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_hero.jl")'
```
Expected: PASS — PNG written, survivor anchors monotone in reading order. (If Makie text `font=` path errors, confirm the Fraunces/Plex statics from Foundation Task 1 exist via `HouseStyle.fraunces("9pt-SemiBold")`.)

- [ ] **Step 5: Generate the committed hero artifact**

Run:
```bash
julia --project=examples/erasure -e 'using Erasure; Erasure.hero("examples/erasure/erasure-hero.png")'
```
Expected: writes `examples/erasure/erasure-hero.png`.

- [ ] **Step 6: OPEN THE PNG AND VISUALLY CONFIRM (green ≠ sign-off)**

Open `examples/erasure/erasure-hero.png` and verify by eye (per the gallery memory — a green test is not a visual sign-off):
- Adjacent blacked words + their inter-word spaces tile into ONE continuous censor bar — NO paper slivers between consecutive bars on a line (SPEC §6 acceptance).
- The ~15 Fraunces survivors sit exactly in the holes (same line, same x as their original word) on BRASS underlays.
- The BRASS reading thread runs through survivors in reading order; brass appears ONLY on underlays + thread, never on a bar.
- Reads as a redacted document from afar, a poem up close.

If any check fails, fix `hero.jl`/`redact.jl` and regenerate before committing. (Use `SendUserFile` to surface the PNG to the operator for the human gate.)

- [ ] **Step 7: Wire into runtests.jl and commit (with the artifact)**

Add `include("test_hero.jl")` to `examples/erasure/test/runtests.jl`. Then:
```bash
julia --project=examples/erasure -e 'using Pkg; Pkg.test()'
```
Expected: PASS. Commit:
```bash
git add examples/erasure/src/hero.jl examples/erasure/src/Erasure.jl examples/erasure/test/test_hero.jl examples/erasure/test/runtests.jl examples/erasure/erasure-hero.png
git commit -m "feat(erasure): MIT-License found-poem hero render (visually verified)"
```

---

### Task 8: Monospace tap-to-keep toy (defaults to the curated poem)

**Files:**
- Create: `examples/erasure/src/toy.jl`
- Modify: `examples/erasure/src/Erasure.jl` (include + export)
- Create: `examples/erasure/test/test_toy.jl`
- Modify: `examples/erasure/test/runtests.jl`

Deterministic MonospaceBackend field with O(1) toggles over already-cached geometry (no re-measure). MUST default to revealing the curated hero poem (SPEC §6); "surprise me" is a secondary subtractive-procgen action. Headless-testable core: a mutable kept-set + `poem_readout` + `toggle!` + `surprise!`.

- [ ] **Step 1: Write the failing test**

Create `examples/erasure/test/test_toy.jl`:
```julia
using Erasure: new_toy, toggle!, poem_readout, surprise!, KEPT_WORDS
using Test

@testset "toy" begin
    @testset "defaults to the curated poem" begin
        t = new_toy()                                  # no args -> curated hero kept-set
        @test poem_readout(t) == join(KEPT_WORDS, " ")
    end

    @testset "toggle is O(1) over cached geometry (no re-measure)" begin
        t = new_toy()
        before = length(t.boxes)                       # geometry built once
        segi = t.boxes[1].seg_index                    # word #1 ("Permission"), already kept
        toggle!(t, segi)                               # now blacked
        @test !(segi in t.kept)
        @test length(t.boxes) == before                # geometry NOT rebuilt
        toggle!(t, segi)                               # back to kept
        @test segi in t.kept
    end

    @testset "surprise! is opt-in, deterministic under a seed, and never empty" begin
        t = new_toy()
        surprise!(t; seed = 7)
        p1 = poem_readout(t)
        surprise!(t; seed = 7)
        @test poem_readout(t) == p1                    # seeded determinism
        @test !isempty(strip(p1))                      # produces *a* poem
    end
end
```

- [ ] **Step 2: Run it (expect FAIL)**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_toy.jl")'
```
Expected: FAIL — `UndefVarError: new_toy not defined`.

- [ ] **Step 3: Implement the toy core**

Create `examples/erasure/src/toy.jl`. Geometry is built ONCE in `new_toy`; toggles only mutate the kept set; `surprise!` is the labeled non-engine subtractive-procgen with a stop-word skip + no-adjacent rule:
```julia
using Random
using TextMeasure: prepare

const _STOPWORDS = Set(["is","the","to","of","a","an","in","and","or","for","be","by",
                        "so","do","any","no","of","with","from","out","this","shall"])

"Headless toy state: cached geometry + a mutable kept-set. Toggles never re-measure."
mutable struct Toy
    prep
    boxes :: Vector{WordBox}
    kept  :: Set{Int}             # seg_index of kept words
end

"""
    new_toy(; max_width=HERO_MAX_WIDTH) -> Toy

Build the deterministic monospace field ONCE (prepare + word_boxes) and DEFAULT the
kept-set to the curated hero poem (SPEC §6 — the curated poem is first contact).
"""
function new_toy(; max_width = HERO_MAX_WIDTH)
    b = golden_backend()
    prep  = prepare(b, LICENSE_TEXT)
    boxes = word_boxes(prep; max_width = max_width)
    kept  = Set(kept_seg_indices(prep))
    return Toy(prep, boxes, kept)
end

"Toggle a word (by `prep.segments` index) kept<->blacked. O(1); no re-measure/layout."
function toggle!(t::Toy, seg_index::Int)
    seg_index in t.kept ? delete!(t.kept, seg_index) : push!(t.kept, seg_index)
    return t
end

"The current poem: kept words in reading (seg-index) order, space-joined."
function poem_readout(t::Toy)
    idxs = sort([wb.seg_index for wb in t.boxes if wb.seg_index in t.kept])
    return join((t.prep.segments[i].str for i in idxs), " ")
end

"""
    surprise!(t; seed, p=0.06) -> Toy

Labeled NON-ENGINE subtractive procgen: walk words in reading order, keep with prob `p`,
skip stop-words, never keep two adjacent words. Produces *a* poem, rarely *the* poem —
a secondary opt-in (never first contact). Seeded for deterministic tests.
"""
function surprise!(t::Toy; seed::Integer = 0, p::Float64 = 0.06)
    rng = Xoshiro(seed)
    empty!(t.kept)
    last_kept_line_x = nothing
    prev_kept = false
    for wb in t.boxes
        w = t.prep.segments[wb.seg_index].str
        if !prev_kept && !(lowercase(w) in _STOPWORDS) && rand(rng) < p
            push!(t.kept, wb.seg_index); prev_kept = true
        else
            prev_kept = false
        end
    end
    isempty(t.kept) && push!(t.kept, t.boxes[1].seg_index)  # never empty
    return t
end
```

Add to `examples/erasure/src/Erasure.jl` after the `hero.jl` include:
```julia
include("toy.jl")
export Toy, new_toy, toggle!, poem_readout, surprise!
```

- [ ] **Step 4: Run the test (expect PASS)**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; include("examples/erasure/test/test_toy.jl")'
```
Expected: PASS — default poem equals the curated `KEPT_WORDS`; toggle leaves geometry intact; `surprise!` is seed-deterministic and non-empty.

- [ ] **Step 5: Wire into runtests.jl and commit**

Add `include("test_toy.jl")` to `examples/erasure/test/runtests.jl`. Then:
```bash
julia --project=examples/erasure -e 'using Pkg; Pkg.test()'
```
Expected: PASS — full Erasure suite green. Commit:
```bash
git add examples/erasure/src/toy.jl examples/erasure/src/Erasure.jl examples/erasure/test/test_toy.jl examples/erasure/test/runtests.jl
git commit -m "feat(erasure): monospace tap-to-keep toy (defaults to curated poem)"
```

---

### Task 9: README + final full-suite green

**Files:**
- Create: `examples/erasure/README.md`

- [ ] **Step 1: Write the README**

Create `examples/erasure/README.md`:
```markdown
# ERASURE — a poem hiding in the MIT License

A blackout / found-poem demo for TextMeasure.jl. The project's own `LICENSE` is laid out
once by the engine; all but ~15 curated words are struck out with one continuous ink
censor field; the survivors — frozen at their EXACT measured coordinates — read as a poem
on a brass reading thread. See `SPEC.md` for the design rationale.

## Run

    julia --project=examples/erasure -e 'using Pkg; Pkg.instantiate()'
    # hero PNG:
    julia --project=examples/erasure -e 'using Erasure; Erasure.hero("examples/erasure/erasure-hero.png")'
    # tests (golden over computed geometry, never pixels):
    julia --project=examples/erasure -e 'using Pkg; Pkg.test()'

## How it works (all in-contract)

`prepare(backend, LICENSE)` measures every run once (no kerning); `word_boxes` re-walks
`prep.segments` with the SAME greedy + whitespace-trim rule `layout` uses to recover a
per-word `(seg_index, line, x0, x1, baseline)` table — exact under `align=:left`. The
re-walk is proven against `layout(prep).lines` (test_wordgeom.jl). Redaction bars + kept
survivors are drawn from ONE geometry pass, so a survivor is by construction in its
original spot. Curation (which words survive) is authoring, not measurement.

## Constraint

The survivor-position guarantee holds for `align=:left` only (the hero is a "document").
The toy defaults to the curated poem; "surprise me" is a labeled non-engine heuristic.
```

- [ ] **Step 2: Run the FULL suite one last time**

Run:
```bash
julia --project=examples/erasure -e 'using Pkg; Pkg.test()'
```
Expected: PASS — all testsets (loads, wordgeom, poem, redact, golden, render, hero, toy) green.

- [ ] **Step 3: Commit**

```bash
git add examples/erasure/README.md
git commit -m "docs(erasure): README + run instructions"
```

---

## Self-review notes

**Spec coverage:**
- SPEC §1 (BOTH media): hero render (Task 7) + interactive monospace toy (Task 8); toy defaults to curated poem (§6) ✓.
- SPEC §2 (blackout language): solid INK redaction bars tiling into one continuous censor bar with 1px bleed + filled inter-blacked spaces (Task 4, asserted no-sliver); BRASS underlay on kept words + BRASS reading thread (Task 7); brass reserved for survival ✓.
- SPEC §3 (source + poem): LICENSE verbatim as `LICENSE_TEXT` (Task 1) — NOTE the SPEC's quoted "verbatim" paragraph is a *condensed* MIT excerpt; the task brief mandates the real `LICENSE`, so Task 1 uses the full file text and Task 3 verifies every Candidate-A survivor is a real in-order word of it. Candidate B (Frankenstein) is a documented future toy source, not built here (single vertical slice).
- SPEC §4 (exact position load-bearing): bars + survivors from one `word_boxes` pass; golden over the geometry table (Task 5) ✓.
- SPEC §5 (aesthetic): IBM Plex Mono body 11 redaction face; Fraunces subhead 16 survivors; PAPER/INK/BRASS from HouseStyle (Tasks 6–7) ✓. Masthead/file-stamp text is a render embellishment the implementer can add in Task 7's scene; footer is wired.
- SPEC §6 (engine mechanics + honest gap): the re-walk IS the honest-gap derivation; golden assertion vs `layout(prep).lines` (Task 2); §6 sliver verification is Task 7 Step 6 visual gate; "surprise me" subtractive procgen (Task 8) ✓.

**Placeholder scan:** No `TBD`/"add validation"/"similar to Task N". Every code step is real Julia; every run step has an exact command + expected output. The one deliberately iterative spot is Task 3's `KEPT_SPEC` ordinals — flagged explicitly with the failing test as the oracle and forward-scan (`0`) as the safe default, NOT a placeholder (the resolution loop is specified).

**Type consistency:** `WordBox(seg_index::Int, line::Int, x0::Float64, x1::Float64, baseline::Float64)` is the spine; `RedactRect(x0,x1,y0,y1)::Float64`; `word_boxes(prep; max_width, lineheight)::Vector{WordBox}`; `redaction_rects(boxes, prep, kept; bleed)::Vector{RedactRect}`; `kept_seg_indices(prep)::Vector{Int}`; `geometry_rows()::Vector{String}` → `HouseStyle.digest_rows`; `save_png(fn, path; size, px_per_unit, yflip)`; `hero(path)->(; survivors, png)`; `Toy(prep, boxes::Vector{WordBox}, kept::Set{Int})`. HouseStyle uuid `f1a9b3c2-…` and the Foundation exports (PAPER/INK/BRASS/RAMP/fraunces/plexmono/footer/digest_rows) are referenced exactly. Manifest stays gitignored (demo memory); golden hashes the computed table, never pixels (asteroid pattern).

**Flagged for the implementer:**
1. The SPEC §3 "verbatim" block ≠ the actual `LICENSE`; Task 1 uses the real LICENSE per the brief, and Task 3's test enforces survivor presence — if a survivor turns out NOT to be in the full text, the Step-1 test fails loudly and the curation must adjust (it won't: all Candidate-A words verified present in order).
2. Task 3 `KEPT_SPEC` ordinals are starting hints; resolve via the failing test (prefer forward-scan `0`).
3. `MakieBackend` is KEYWORD-ONLY (VERIFIED against `ext/TextMeasureMakieExt.jl`): every construction MUST be `MakieBackend(; font=<path>, fontsize=…, px_per_unit=1)` — positional `MakieBackend(plexmono("Regular"), …)` hits a MethodError (the positional inner ctor wants a resolved FTFont, not a path). Task 7 Step 3's `hero()` uses the keyword form; mirror it at any other call site (and however `examples/layouts` constructs it).
