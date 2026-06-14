import HouseStyle
using HouseStyle: RAMP

# Two found poems woven through the LICENSE, each an ordered list of phrases. A phrase is
# (tokens, size, weight): `tokens` are CONSECUTIVE license words (lowercase, letters-only
# match); `size` is a RAMP tier; `weight` is a Fraunces weight name. The whole poem renders
# in Fraunces serif (pivots + body); Hanken sans is the chrome only (masthead/footer).
#
# RED poem — "Without Limitation" — lights through the grant clause.
# BLACK poem — "As Is" — lights from the notice paragraph down through the warranty.
# The two pivots (FREE / AS IS) render uppercase.

const RED_PHRASES = [
    (["free"],                                  RAMP.title,   "Black"),
    (["to","any","person","obtaining","a","copy"], RAMP.body, "Regular"),
    (["to","deal"],                             RAMP.subhead, "SemiBold"),
    (["without","restriction"],                 RAMP.body,    "Regular"),
    (["without","limitation"],                  RAMP.title,   "Black"),
    (["to","use"],                              RAMP.body,    "Regular"),
    (["modify","merge","publish","distribute"], RAMP.subhead, "SemiBold"),
]

const BLACK_PHRASES = [
    (["this"],               RAMP.body,    "Regular"),
    (["software"],           RAMP.body,    "Regular"),
    (["as","is"],            RAMP.title,   "Black"),
    (["without","warranty"], RAMP.subhead, "SemiBold"),
    (["of","any","kind"],    RAMP.body,    "Regular"),
    (["the","authors"],      RAMP.subhead, "SemiBold"),
    (["liable"],             RAMP.subhead, "Black"),
    (["for","any","claim"],  RAMP.body,    "Regular"),
    (["arising"],            RAMP.subhead, "SemiBold"),
    (["out","of"],           RAMP.body,    "Regular"),
    (["the","software"],     RAMP.subhead, "SemiBold"),
]

const CAPS_PHRASES = (["free"], ["as","is"])   # rendered uppercase (the two pivots)

const BODY_PT = RAMP.body

"Body column measure, in 'M' advances of the Plex body face (the wrap width feeding KP)."
const MEASURE_CH = 66

"Lowercased, letters-only form of a license token, for phrase matching (drops punctuation)."
strip_word(w) = lowercase(filter(isletter, w))

"""
    fweight(weight) -> String

Fraunces 9pt static path for a poem weight name (`"Regular"`/`"SemiBold"`/`"Black"`).
The whole poem is Fraunces serif. Uses `HouseStyle.fraunces`.
"""
fweight(weight) = HouseStyle.fraunces("9pt-$(weight)")

"""
    WStyle(font, size, color, lit, caps)

Per-word style: which face/size/colour a license word renders at. `lit` marks a poem word
(`false` ⇒ the faded Plex Mono ghost source); `caps` marks a pivot rendered uppercase.
"""
struct WStyle
    font  :: String
    size  :: Int
    color :: Any
    lit   :: Bool
    caps  :: Bool
end

# --- tokenise the LICENSE into words + paragraph-start indices ----------------

"""
    license_words(text=LICENSE_TEXT) -> (words, para_start)

Split `text` into whitespace-delimited `words` and the set `para_start` of 1-based word
indices that begin a NEW paragraph (i.e. follow a `\\n`). Mirrors the engine's `:word`
tokenisation and marks where the forced `:newline` breaks fall.
"""
function license_words(text = LICENSE_TEXT)
    words = String[]
    para_start = Set{Int}()
    for (pi, para) in enumerate(split(text, "\n"))
        for (wi, w) in enumerate(split(para))
            push!(words, String(w))
            (wi == 1 && pi > 1) && push!(para_start, length(words))
        end
    end
    return words, para_start
end

# --- per-word style assignment (ghost by default; lit where a phrase matches) -

"""
    assign!(styles, words, phrases, color, start_ptr) -> ptr

Forward-match each phrase of `phrases` against `words` (letters-only, in order), starting at
`start_ptr`, and overwrite the matched words' `styles` entries with the lit Fraunces style
(uppercase pivots flagged via `caps`). Returns the pointer past the last match, so the RED
poem and the BLACK poem are assigned in two sequential passes and never collide.
"""
function assign!(styles, words, phrases, color, start_ptr)
    N = length(words)
    ptr = start_ptr
    for (tokens, sz, wt) in phrases
        L = length(tokens)
        found = nothing
        for k in ptr:(N - L + 1)
            if all(strip_word(words[k + t - 1]) == tokens[t] for t in 1:L)
                found = k
                break
            end
        end
        found === nothing && error("poem phrase not found in LICENSE: $(tokens)")
        caps = tokens in CAPS_PHRASES
        font = fweight(wt)
        for t in 1:L
            styles[found + t - 1] = WStyle(font, sz, color, true, caps)
        end
        ptr = found + L
    end
    return ptr
end

"""
    styled_words(; ghost_color, red_color, black_color) -> (words, styles, para_start)

The full styled word stream for the hero/golden: tokenise `LICENSE_TEXT`, default every
word to the faded Plex Mono `ghost_color`, then light the RED poem and the BLACK poem in
place. The three colours are passed in so the palette stays local to the caller.
"""
function styled_words(; ghost_color, red_color, black_color)
    words, para_start = license_words()
    N = length(words)
    plex = HouseStyle.plexmono("Regular")
    styles = [WStyle(plex, BODY_PT, ghost_color, false, false) for _ in 1:N]
    ptr = assign!(styles, words, RED_PHRASES, red_color, 1)
    assign!(styles, words, BLACK_PHRASES, black_color, ptr)
    return words, styles, para_start
end

"""
    display_str(words, styles, para_start, i) -> String

Sentence-cased display form of word `i`: lowercase the token, capitalise the first letter
when it starts a sentence (document start, paragraph start, or follows a word ending in
`.`). The two pivots (`caps`) render uppercase, with any trailing sentence punctuation
stripped (quotes kept) so e.g. the `"AS` + `IS",` tokens read as `"AS IS"`.
"""
function display_str(words, styles, para_start, i)
    styles[i].caps && return rstrip(c -> c in (',', ';', '.'), uppercase(words[i]))
    base = lowercase(words[i])
    is_start = i == 1 || i in para_start || (i > 1 && endswith(words[i - 1], "."))
    return is_start ? uppercasefirst(base) : base
end
