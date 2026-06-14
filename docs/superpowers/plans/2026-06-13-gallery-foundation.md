# Gallery Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the shared `HouseStyle` Julia package (pinned palette/ramp/font/footer constants + a deterministic golden-digest helper) and pin the gallery fonts, so all four gallery pieces import one canonical spine instead of re-typing values.

**Architecture:** A tiny in-repo unregistered package at `examples/_housestyle/` exporting plain constants and two pure helpers. It is the runtime mirror of `docs/superpowers/demos-house-style.md` — pieces depend on it by `[sources]` path. No rendering, no Makie dep; just `Colors` + stdlib `SHA`. The gallery fonts (Fraunces + IBM Plex Mono OFL statics) are pinned under `examples/fonts/` by copying them from the `demos-E-asteroid-tui` branch (they are absent on `main`).

**Tech Stack:** Julia 1.11+, `Colors.jl`, stdlib `SHA`, `Test`. Path-dependency via the Julia 1.11 `[sources]` feature (mirrors `examples/layouts/Project.toml`).

---

### Task 1: Pin the gallery fonts

**Files:**
- Create (from branch): `examples/fonts/Fraunces/*.ttf`, `examples/fonts/Fraunces/OFL.txt`, `examples/fonts/IBMPlexMono/*.ttf`, `examples/fonts/IBMPlexMono/OFL.txt`

- [ ] **Step 1: Bring the pinned fonts from the demo branch into the worktree**

Run (from the worktree root `/home/jonathanchen/projects/TextMeasure.jl-gallery`):
```bash
git checkout demos-E-asteroid-tui -- examples/fonts/Fraunces examples/fonts/IBMPlexMono
```

- [ ] **Step 2: Verify the expected static faces are present**

Run:
```bash
ls examples/fonts/Fraunces/*.ttf examples/fonts/IBMPlexMono/*.ttf
```
Expected: includes `Fraunces9pt-Regular.ttf`, `Fraunces9pt-SemiBold.ttf`, `Fraunces9pt-Black.ttf`, `Fraunces144pt-{Light,Regular,Black}.ttf`, `Fraunces72pt-{Regular,Black}.ttf`, and `IBMPlexMono-{Regular,Medium,SemiBold,Bold,Italic,Text}.ttf`, plus an `OFL.txt` in each dir.

(NOTE for the Glyph Wave plan: the 6-weight ramp needs Fraunces 9pt **Light**, **Medium**, **Bold**, which are NOT in this set — adding those three OFL statics is a task in the Glyph Wave plan, not here.)

- [ ] **Step 3: Commit**

```bash
git add examples/fonts
git commit -m "chore(gallery): pin Fraunces + IBM Plex Mono OFL statics under examples/fonts"
```

---

### Task 2: Scaffold the `HouseStyle` package

**Files:**
- Create: `examples/_housestyle/Project.toml`
- Create: `examples/_housestyle/src/HouseStyle.jl`
- Create: `examples/_housestyle/test/runtests.jl`

- [ ] **Step 1: Write the failing test**

Create `examples/_housestyle/test/runtests.jl`:
```julia
using HouseStyle, Test

@testset "HouseStyle loads" begin
    @test isdefined(HouseStyle, :PAPER)
end
```

- [ ] **Step 2: Write the Project.toml**

Create `examples/_housestyle/Project.toml` (mirrors the `examples/layouts` pattern; `SHA`/`Test` are stdlibs):
```toml
name = "HouseStyle"
uuid = "f1a9b3c2-0d4e-4a6b-9c8d-7e2f1a0b3c4d"
version = "0.1.0"
authors = ["TextMeasure.jl contributors"]

[deps]
Colors = "5ae59095-9a9b-59fe-a467-6f913c188581"
SHA = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[compat]
Colors = "0.12, 0.13"
julia = "1.11"

[extras]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["Test"]
```

- [ ] **Step 3: Write the minimal module**

Create `examples/_housestyle/src/HouseStyle.jl`:
```julia
module HouseStyle
using Colors

const PAPER = colorant"#F4EFE6"

end # module
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
julia --project=examples/_housestyle -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```
Expected: `Test Summary: | Pass 1` — "HouseStyle loads" passes.

- [ ] **Step 5: Commit**

```bash
git add examples/_housestyle
git commit -m "feat(housestyle): scaffold shared HouseStyle package"
```

---

### Task 3: Pin the palette and ramp constants

**Files:**
- Modify: `examples/_housestyle/src/HouseStyle.jl`
- Modify: `examples/_housestyle/test/runtests.jl`

- [ ] **Step 1: Write the failing test**

Append to `examples/_housestyle/test/runtests.jl`:
```julia
@testset "palette + ramp (exact, from demos-house-style.md)" begin
    @test HouseStyle.PAPER     == colorant"#F4EFE6"
    @test HouseStyle.INK       == colorant"#1A1714"
    @test HouseStyle.BRASS     == colorant"#9A7B4F"
    @test HouseStyle.BRASS_INK == colorant"#6E5226"
    @test HouseStyle.BLUE      == colorant"#2E5E8C"
    @test HouseStyle.GREEN     == colorant"#3E7A54"
    @test HouseStyle.RED       == colorant"#A33A2A"
    @test HouseStyle.GRAY      == colorant"#6B7280"
    @test HouseStyle.RAMP == (caption=9, body=11, subhead=16, title=22, deck=31, display=44)
end
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
julia --project=examples/_housestyle -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `INK` (and others) not defined.

- [ ] **Step 3: Add the constants**

Replace the body of `examples/_housestyle/src/HouseStyle.jl` between `using Colors` and `end # module` with:
```julia
# Identity layer (carries every piece)
const PAPER     = colorant"#F4EFE6"
const INK       = colorant"#1A1714"
const BRASS     = colorant"#9A7B4F"
const BRASS_INK = colorant"#6E5226"
# Data layer (encode ONLY — never identity)
const BLUE  = colorant"#2E5E8C"
const GREEN = colorant"#3E7A54"
const RED   = colorant"#A33A2A"
const GRAY  = colorant"#6B7280"
# √2 type ramp (pt) — pick the tier by role, never an in-between value
const RAMP = (caption=9, body=11, subhead=16, title=22, deck=31, display=44)
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
julia --project=examples/_housestyle -e 'using Pkg; Pkg.test()'
```
Expected: PASS — palette + ramp testset green.

- [ ] **Step 5: Commit**

```bash
git add examples/_housestyle
git commit -m "feat(housestyle): pin palette + √2 ramp constants"
```

---

### Task 4: Font-path helpers and footer

**Files:**
- Modify: `examples/_housestyle/src/HouseStyle.jl`
- Modify: `examples/_housestyle/test/runtests.jl`

- [ ] **Step 1: Write the failing test**

Append to `examples/_housestyle/test/runtests.jl`:
```julia
@testset "font paths + footer" begin
    @test isdir(HouseStyle.FONTS_DIR)
    @test isfile(HouseStyle.fraunces("9pt-Regular"))
    @test isfile(HouseStyle.fraunces("144pt-Black"))
    @test isfile(HouseStyle.plexmono())            # default Regular
    @test isfile(HouseStyle.plexmono("Medium"))
    @test endswith(HouseStyle.fraunces("9pt-Regular"), "Fraunces9pt-Regular.ttf")
    @test HouseStyle.footer("Erasure") == "TextMeasure.jl · Erasure"
end
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
julia --project=examples/_housestyle -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `FONTS_DIR`/`fraunces` not defined.

- [ ] **Step 3: Add the helpers**

Append inside the module (before `end # module`) in `examples/_housestyle/src/HouseStyle.jl`:
```julia
# examples/fonts lives two dirs up from this src file: _housestyle/src -> _housestyle -> examples
const FONTS_DIR = normpath(joinpath(@__DIR__, "..", "..", "fonts"))

"Absolute path to a pinned Fraunces static, e.g. `fraunces(\"9pt-Regular\")`."
fraunces(name::AbstractString) = joinpath(FONTS_DIR, "Fraunces", "Fraunces$(name).ttf")

"Absolute path to a pinned IBM Plex Mono static, e.g. `plexmono(\"Medium\")` (default Regular)."
plexmono(name::AbstractString="Regular") = joinpath(FONTS_DIR, "IBMPlexMono", "IBMPlexMono-$(name).ttf")

"The shared footer string: `TextMeasure.jl · <piece>` (middot U+00B7)."
footer(piece::AbstractString) = "TextMeasure.jl · $(piece)"
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
julia --project=examples/_housestyle -e 'using Pkg; Pkg.test()'
```
Expected: PASS — font-path + footer testset green (depends on Task 1 fonts being present).

- [ ] **Step 5: Commit**

```bash
git add examples/_housestyle
git commit -m "feat(housestyle): font-path helpers + footer string"
```

---

### Task 5: Deterministic golden-digest helper

**Files:**
- Modify: `examples/_housestyle/src/HouseStyle.jl`
- Modify: `examples/_housestyle/test/runtests.jl`

Rationale: every piece's golden test hashes a *computed layout/placement table* (never rendered pixels — Cairo/ffmpeg are not byte-stable). Each piece formats its own rows as strings; `digest_rows` canonicalizes (sort) and hashes them so the digest is order-independent and machine-independent.

- [ ] **Step 1: Write the failing test**

Append to `examples/_housestyle/test/runtests.jl`:
```julia
@testset "digest_rows" begin
    a = ["w1|0.00|12.50", "w2|40.00|12.50"]
    @test HouseStyle.digest_rows(a) isa String
    @test length(HouseStyle.digest_rows(a)) == 64          # sha256 hex
    @test HouseStyle.digest_rows(a) == HouseStyle.digest_rows(reverse(a))  # order-independent
    @test HouseStyle.digest_rows(a) != HouseStyle.digest_rows(["w1|0.01|12.50", "w2|40.00|12.50"])
end
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
julia --project=examples/_housestyle -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `digest_rows` not defined.

- [ ] **Step 3: Add the helper**

Add `using SHA` to the top of the module (next to `using Colors`), and append before `end # module`:
```julia
"""
    digest_rows(rows) -> String

SHA-256 hex of a canonicalized placement/layout table. `rows` is a vector of
pre-formatted strings (each piece builds its own row format, rounding floats to a
fixed precision before formatting). Rows are sorted so the digest is independent of
emission order. This is the gallery's golden invariant — hash the computed table,
never the rendered pixels.
"""
function digest_rows(rows::AbstractVector{<:AbstractString})
    bytes2hex(sha2_256(join(sort(collect(rows)), "\n")))
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
julia --project=examples/_housestyle -e 'using Pkg; Pkg.test()'
```
Expected: PASS — all four testsets green.

- [ ] **Step 5: Commit**

```bash
git add examples/_housestyle
git commit -m "feat(housestyle): deterministic golden digest_rows helper"
```

---

### Task 6: Document the dependency pattern for pieces

**Files:**
- Create: `examples/_housestyle/README.md`

- [ ] **Step 1: Write the README**

Create `examples/_housestyle/README.md`:
```markdown
# HouseStyle — shared gallery spine

Runtime mirror of `docs/superpowers/demos-house-style.md`. Each gallery piece depends on
this package by path so colours/ramp/fonts/footer come from ONE source.

In a piece's `Project.toml`:

    [deps]
    HouseStyle = "f1a9b3c2-0d4e-4a6b-9c8d-7e2f1a0b3c4d"

    [sources]
    HouseStyle = { path = "../_housestyle" }

Then `using HouseStyle` and reference `HouseStyle.PAPER`, `HouseStyle.RAMP.body`,
`HouseStyle.fraunces("9pt-Regular")`, `HouseStyle.plexmono()`, `HouseStyle.footer("Erasure")`,
`HouseStyle.digest_rows(rows)`. If a value here and `demos-house-style.md` disagree, that is a bug.
```

- [ ] **Step 2: Commit**

```bash
git add examples/_housestyle/README.md
git commit -m "docs(housestyle): document the path-dependency pattern"
```

---

## Self-review notes

- **Spec coverage:** covers the design-doc §4 shared-infra items — house-style module (Tasks 2–5), the golden-digest discipline (Task 5), and font pinning (Task 1). The "render harness" is intentionally NOT here: rendering is Makie-specific and is built with its first consumer (the Erasure plan), per the vertical-slice approach.
- **Type consistency:** `fraunces`/`plexmono`/`footer`/`digest_rows`/`RAMP`/colour names are the exact identifiers every piece plan must reference. The `HouseStyle` uuid `f1a9b3c2-…` is fixed here and reused in every piece's `[sources]`.
- **Deferred:** the three missing Fraunces 9pt weights (Light/Medium/Bold) are pinned in the Glyph Wave plan (only it needs the 6-weight ramp).
