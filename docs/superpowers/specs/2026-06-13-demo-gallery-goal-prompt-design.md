# `/goal` prompt — demo gallery, impeccable finish

**Date:** 2026-06-13 · **Status:** design approved (knobs locked)

## Purpose

Design a `/goal` condition that drives Claude to elevate the 5-demo gallery
(#E #F #G #H #K) to an "impeccable finish" bar — grading each demo, redesigning or
replacing the weak ones, and iterating each as a **web mockup first** before porting to
its final medium (PDF / PNG / ANSI TUI).

## The governing constraint

`/goal`'s evaluator is a **fast model that only reads the conversation transcript**. It
never runs commands or opens files. "Better finish" is a *subjective visual* bar and the
evaluator **cannot see a PNG/PDF/terminal**. Therefore the entire design problem is:
**translate "impeccable" into checkpoints that Claude's own transcript output demonstrates.**

This is the "green test ≠ visual sign-off" trap, sharpened — the judge here can't even see
the test. The answer is three independent, transcript-visible confirmations per artifact
(re-open-and-match, independent-reviewer PASS, green golden), plus a deliberate human gate.

## Locked decisions

| Decision | Choice |
|---|---|
| Scope | **Grade then redesign/replace.** Keep strong demos; licensed to replace any that can't reach the bar (asteroid TUI flagged test-gamed). |
| Mockup loop | **Mandatory for every demo**, TUI included (rendered as a styled fixed-pitch HTML grid), then ported. |
| Done bar | **Independent design-reviewer subagent sign-off, *then* human gate.** Subagents grade unattended; goal stops and hands the final aesthetic call to the user rather than auto-clearing. |
| Pass threshold | **≥ 8/10 on EVERY rubric axis.** One axis < 8 forces another iteration. |
| Turn bound | **~40 turns**, then stop and report progress. |

## Deliverable shape — 3 coupled artifacts

A 4,000-char condition can't carry the rigor alone, so it stays thin and *points at* files:

1. **`DESIGN.md` + `PRODUCT.md`** (repo root) — authored as the goal's step 0 if absent;
   treated as authoritative if present. These are the anchor the reviewer scores against.
   - **`PRODUCT.md`** — what the gallery proves about TextMeasure.jl, who reads it, and the
     one claim each demo must make tangible.
   - **`DESIGN.md`** — the craft rubric. Axes: **TYPE, PALETTE, COMPOSITION,
     RESTRAINT/HIERARCHY, FINISH.** Extends `docs/superpowers/demos-house-style.md` and the
     `frontend-design` skill. House-style values stay authoritative unless `DESIGN.md`
     deliberately supersedes a specific value *and states why*.
2. **Design-reviewer subagent brief** — "you have no stake in this work; score this
   screenshot against each `DESIGN.md` axis; PASS requires ≥ 8 on every axis." Lives inside
   the goal text (dispatched fresh per artifact).
3. **The `/goal` condition string** (below) — the ≤ 4,000-char paste-able driver.

## Per-demo pipeline (every stage leaves transcript evidence)

```
0. Author DESIGN.md + PRODUCT.md  (once, if absent)
1. GRADE existing demo vs DESIGN.md → keep | refine | replace
2. MOCKUP: HTML/CSS (TUI = styled monospace grid), iterate via Playwright screenshots
3. PORT: render real media (Julia/Makie PDF/PNG, or captured ANSI frames)
4. RE-OPEN final media + screenshot → confirm in writing it matches the mockup
5. REVIEW: fresh design-reviewer subagent scores FINAL screenshot → PASS ≥ 8 every axis
6. Golden test green; regenerated goldens visually verified before commit; no Manifest committed
```

Stages 4–6 are the three independent confirmations that make a transcript-only evaluator
trustworthy.

## The paste-able `/goal` condition

> Paste everything below after `/goal ` (it is under 4,000 characters).

```
GOAL — Demo gallery (#E #F #G #H #K), impeccable finish.

SETUP: Read docs/superpowers/demos-house-style.md and, if present, DESIGN.md + PRODUCT.md at repo root. If either is missing, author it BEFORE any demo work. PRODUCT.md = what the gallery proves about TextMeasure.jl, who reads it, and the one claim each demo must make tangible. DESIGN.md = the craft rubric with axes TYPE, PALETTE, COMPOSITION, RESTRAINT/HIERARCHY, FINISH, extending demos-house-style.md and the frontend-design skill; house-style values stay authoritative unless DESIGN.md deliberately supersedes a specific value and says why. Invoke the frontend-design skill when authoring DESIGN.md and every mockup. FONTS: if Fraunces or IBM Plex Mono are not yet pinned as static TTFs in examples/fonts/, source them (OFL) before any port; expect to regenerate every golden against the new faces and visually verify each before commit.

PER DEMO, run this pipeline and surface the evidence in THIS transcript:
1. GRADE the current demo vs DESIGN.md -> verdict keep | refine | replace. You MAY replace any demo that can't reach the bar; the asteroid TUI (#E) is a known test-gamed candidate.
2. MOCKUP FIRST: build an HTML/CSS mockup (TUI = styled fixed-pitch monospace grid), iterate with Playwright screenshots until it clears DESIGN.md.
3. PORT to the real medium (Julia/Makie PDF/PNG, or captured ANSI frames for the TUI).
4. RE-OPEN the rendered final media, screenshot it, and confirm IN WRITING it matches the signed-off mockup; name any geometry the medium couldn't hit.
5. REVIEW: dispatch a FRESH design-reviewer subagent that has no stake in the work; it scores the FINAL artifact's screenshot against EVERY DESIGN.md axis and must return PASS with >=8/10 on every axis. Any axis <8 = another iteration. Paste its verdict.
6. The demo's golden test passes; any regenerated golden is visually verified before commit; no demo Manifest.toml is committed.

MET WHEN, for all 5 demos, this transcript contains: a grade verdict, a final-media-matches-mockup confirmation, an independent reviewer PASS (>=8 every axis), and a green golden — AND you have posted a final summary table (demo · verdict · per-axis scores · media path) and explicitly handed off for the user's final visual sign-off. Do NOT self-clear past that hand-off.

Stop and report progress if not met after 40 turns.
```

## House-style redesign (2026-06-13, post-approval)

After the prompt was designed, `demos-house-style.md` was redesigned under Impeccable +
frontend-design into the **"editorial instrument"** spine, and `DESIGN.md` / `PRODUCT.md`
updated to match:

- **Type:** Fraunces (display/text optical sizes) × IBM Plex Mono — pinned as **static**
  TTFs in `examples/fonts/` for golden determinism. Ramp re-founded on √2 (the paper ratio):
  9 / 11 / 16 / 22 / 31 / 44 pt.
- **Palette:** two layers — identity (PAPER `#FBFAF7` off-white, INK `#1E1C1A`, BRASS
  signature `#B5793C`) + data-encoding-only (blue/green/red/gray). Pure white retired.
- **#G** subject is **California** (not Vermont).

**Prerequisite the goal must handle first:** source + pin Fraunces and IBM Plex Mono before
any mockup→port, then expect to **regenerate every golden** against the new faces (visually
verified before commit, per house style). This is the largest single cost of the redesign.

## Notes / open follow-ups

- **DESIGN.md quality is load-bearing** — the reviewer's bar is only as good as this doc. If
  authored unattended in turn 0 it may be weak. Recommended precursor: co-author
  `DESIGN.md` + `PRODUCT.md` with the user *before* running the goal, so the bar is
  trustworthy and the goal just executes against it. The prompt works either way.
- Pair the goal with **auto mode** so each turn runs unattended (per `/goal` docs).
- The "human gate" is encoded as the terminal hand-off: the condition is met at
  *posted-and-awaiting-sign-off*, not at *user-approved* — the goal stops there by design.
```
