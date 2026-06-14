module Woven

# The project's own LICENSE, verbatim — the FULL body of /LICENSE: the grant paragraph,
# the notice paragraph ("...included in all copies or substantial portions..."), and the
# warranty paragraph. Internal newlines are collapsed to spaces; the three paragraphs are
# joined by a single '\n' (a forced paragraph break). EVERY lit poem word (poem.jl) is a
# real word of this text, in this order — the two found poems are WOVEN through the exact
# text governing the software, so do not paraphrase.
const LICENSE_TEXT =
    "Permission is hereby granted, free of charge, to any person obtaining a copy " *
    "of this software and associated documentation files (the \"Software\"), to deal " *
    "in the Software without restriction, including without limitation the rights " *
    "to use, copy, modify, merge, publish, distribute, sublicense, and/or sell " *
    "copies of the Software, and to permit persons to whom the Software is " *
    "furnished to do so, subject to the following conditions:\n" *
    "The above copyright notice and this permission notice shall be included in all " *
    "copies or substantial portions of the Software.\n" *
    "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR " *
    "IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, " *
    "FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE " *
    "AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER " *
    "LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, " *
    "OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE " *
    "SOFTWARE."

include("poem.jl")
export RED_PHRASES, BLACK_PHRASES, CAPS_PHRASES, WStyle, MEASURE_CH
export styled_words, strip_word, display_str, license_words

include("layout.jl")
export Placement, placement_table

include("render.jl")
export save_png

include("golden.jl")
export geometry_rows, hero_digest

include("hero.jl")
export hero

end # module Woven
