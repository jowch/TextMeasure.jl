# Demos Milestone — issue bodies

This directory contains one Markdown file per GitHub issue planned under the **Demos** milestone, plus a `milestone.md` for the milestone description itself.

Each issue body is self-contained: scope, acceptance, dependencies, and pointers back to the design spec + relevant existing code. They're written so a planner picking up an issue weeks from now can invoke `writing-plans` against the issue body alone and produce a detailed implementation plan.

## Files

| File | Issue | Wave |
|---|---|---|
| [`milestone.md`](milestone.md) | Milestone description | — |
| [`A-prepared-slice.md`](A-prepared-slice.md) | #A — `Prepared` segment-slice helper | 1 |
| [`B-figlet-backend.md`](B-figlet-backend.md) | #B — `Figlet.jl` + `TextMeasureFigletExt` | 1 |
| [`C-shape-pack.md`](C-shape-pack.md) | #C — `examples/layouts/shape_pack.jl` | 1 |
| [`D-silhouettes.md`](D-silhouettes.md) | #D — `examples/silhouettes/` | 1 |
| [`E-asteroid-tui.md`](E-asteroid-tui.md) | #E — Tachikoma ASCII Asteroid Blaster | 2 |
| [`F1-doi-data-layer.md`](F1-doi-data-layer.md) | #F1 — DOIInfograph data layer | 2 |
| [`F2-doi-layout-engine.md`](F2-doi-layout-engine.md) | #F2 — DOIInfograph adaptive layout engine | 2 |
| [`F3-doi-grid-pluto.md`](F3-doi-grid-pluto.md) | #F3 — DOIInfograph 6-up grid + Pluto | 2 |
| [`G-map-feature.md`](G-map-feature.md) | #G — CairoMakie Map Feature Page | 2 |
| [`H-newer-yorker.md`](H-newer-yorker.md) | #H — CairoMakie "Newer Yorker" correctness exhibit | 2 |
| [`I-readme-gallery.md`](I-readme-gallery.md) | #I — README hero, gallery, release hygiene | 3 |
| [`J-demo-health-ci.md`](J-demo-health-ci.md) | #J — Demo health CI + golden snapshots | 3 |
| [`K-knuth-plass-stretch.md`](K-knuth-plass-stretch.md) | #K — Knuth–Plass justification [STRETCH] | — |

## Creating the milestone + issues with `gh`

After review, the milestone and issues can be created with the GitHub CLI. **Run these from the repo root, on a branch that has these files merged into `main` (so the URLs in issue bodies resolve).**

```bash
# 1. Create the milestone
gh api repos/:owner/:repo/milestones \
  --method POST \
  --field title="Demos" \
  --field description="$(cat docs/superpowers/issues/demos-milestone/milestone.md)" \
  --field state="open"

# Capture the milestone number from the response (or list with `gh api repos/:owner/:repo/milestones`)
MILESTONE=<number>

# 2. Create each issue, attaching to the milestone
for f in A-prepared-slice B-figlet-backend C-shape-pack D-silhouettes \
         E-asteroid-tui F1-doi-data-layer F2-doi-layout-engine F3-doi-grid-pluto \
         G-map-feature H-newer-yorker I-readme-gallery J-demo-health-ci \
         K-knuth-plass-stretch; do
  TITLE=$(head -1 "docs/superpowers/issues/demos-milestone/${f}.md" | sed 's/^# //')
  gh issue create \
    --title "$TITLE" \
    --body-file "docs/superpowers/issues/demos-milestone/${f}.md" \
    --milestone "$MILESTONE" \
    --label "demos-milestone"
done

# 3. (Optional) add wave labels — adjust each as desired
gh issue list --milestone "$MILESTONE" --json number,title \
  | jq -r '.[] | "\(.number)\t\(.title)"' \
  | while IFS=$'\t' read -r N T; do
      case "$T" in
        *"#A "*|*"#B "*|*"#C "*|*"#D "*) gh issue edit "$N" --add-label "wave-1" ;;
        *"#E "*|*"#F1 "*|*"#F2 "*|*"#F3 "*|*"#G "*|*"#H "*) gh issue edit "$N" --add-label "wave-2" ;;
        *"#I "*|*"#J "*) gh issue edit "$N" --add-label "wave-3" ;;
        *"#K "*) gh issue edit "$N" --add-label "stretch" ;;
      esac
    done
```

Adjust `--label` values to match your repo's label conventions; the script above assumes `demos-milestone`, `wave-1`, `wave-2`, `wave-3`, `stretch` exist.

## Per-issue workflow once created

For each issue picked up:

1. Read the issue body.
2. Invoke the `writing-plans` skill against the issue body to produce a detailed implementation plan.
3. Execute the plan.

The issue body's "Context" section bootstraps the planner with spec section, existing code, and conventions — no separate brief required.
