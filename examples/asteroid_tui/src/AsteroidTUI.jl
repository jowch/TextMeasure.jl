# SPDX-License-Identifier: MIT
"""
    AsteroidTUI

Tachikoma ASCII Asteroid Blaster (#E, demos milestone) — the headline demo for
TextMeasure.jl's *measure-once-layout-many* primitive in terminal space.

This module is a SKELETON during the planning gate: it declares the dependency
surface so the package precompiles and the FIGlet weakdep extension activates.
The renderer-agnostic game core (CellBuffer, game state, tick loop) and the
Tachikoma renderer are filled in during the implementation phase.
"""
module AsteroidTUI

using TextMeasure
using TextMeasureLayouts
using Silhouettes
using FIGlet                  # activates TextMeasureFigletExt
import GeometryBasics as GB
using Random

# Smoke check that the FIGlet extension loaded (cell-space measurement available).
function _ext_loaded()
    return Base.get_extension(TextMeasure, :TextMeasureFigletExt) !== nothing
end

end # module
