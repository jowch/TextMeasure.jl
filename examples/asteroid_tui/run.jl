# SPDX-License-Identifier: MIT
using AsteroidTUI
AsteroidTUI.run_game(; seed = parse(Int, get(ENV, "SEED", "0")))
