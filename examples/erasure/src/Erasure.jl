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

include("wordgeom.jl")
export WordBox, word_boxes

include("poem.jl")
export KEPT_WORDS, kept_seg_indices

include("redact.jl")
export RedactRect, redaction_rects

end # module
