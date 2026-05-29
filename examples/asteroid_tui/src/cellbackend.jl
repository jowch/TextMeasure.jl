# SPDX-License-Identifier: MIT
import TextMeasure
import Unicode

"""
    CellBackend()

A zero-config measurement backend where every grapheme cluster is exactly one
terminal cell wide and a line advances exactly one row. This makes `shape_pack`
output land on integer cell coordinates, which is what the cell-grid silhouette
packing needs. (A fourth instance of CLAUDE.md's "subtype + two methods" pattern.)
"""
struct CellBackend <: TextMeasure.AbstractMeasurementBackend end

# length(graphemes(text)) directly — no collect (avoids an allocation and a known
# ZWJ-emoji stdlib edge case in collecting the iterator; mirrors MonospaceBackend).
TextMeasure.measure(::CellBackend, text::AbstractString) =
    Float64(length(Unicode.graphemes(text)))

TextMeasure.font_metrics(::CellBackend) = TextMeasure.FontMetrics(1.0, 0.0, 1.0)
