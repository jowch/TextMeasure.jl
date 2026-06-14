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
