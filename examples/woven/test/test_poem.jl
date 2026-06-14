using Woven: LICENSE_TEXT, RED_PHRASES, BLACK_PHRASES, CAPS_PHRASES,
               license_words, strip_word, styled_words, display_str
using Test

# Forward-match an ordered phrase list against the letters-only license tokens, starting at
# `start`. Returns the pointer past the last match (errors loudly if any phrase is missing),
# mirroring the assign! matcher — this is the in-order-subsequence guarantee under test.
function _match_phrases(toks, phrases, start)
    N = length(toks)
    ptr = start
    for (tokens, _, _) in phrases
        L = length(tokens)
        found = nothing
        for k in ptr:(N - L + 1)
            if all(toks[k + t - 1] == tokens[t] for t in 1:L)
                found = k
                break
            end
        end
        @test found !== nothing            # phrase IS present, in order, after ptr
        ptr = found + L
    end
    return ptr
end

@testset "poem" begin
    words, _ = license_words()
    toks = [strip_word(w) for w in words]

    @testset "RED poem is an in-order subsequence of the LICENSE" begin
        ptr = _match_phrases(toks, RED_PHRASES, 1)
        @test ptr > 1

        @testset "BLACK poem follows, also in order, no collision" begin
            ptr2 = _match_phrases(toks, BLACK_PHRASES, ptr)
            @test ptr2 >= ptr            # black poem assigned strictly after the red poem
        end
    end

    @testset "FREE / AS IS are the caps pivots" begin
        @test (["free"] in CAPS_PHRASES)
        @test (["as", "is"] in CAPS_PHRASES)
        # the two pivots are caps-flagged in the styled stream (letters-only match, since the
        # raw license tokens carry punctuation, e.g. `"AS` / `IS",`).
        _, styles, para_start = styled_words(; ghost_color = :g, red_color = :r, black_color = :b)
        caps_letters = [strip_word(words[i]) for i in eachindex(words) if styles[i].caps]
        @test "free" in caps_letters
        @test "as" in caps_letters && "is" in caps_letters
        # ... and they DISPLAY uppercase, with trailing sentence punctuation stripped (quotes kept).
        for i in eachindex(words)
            styles[i].caps || continue
            @test display_str(words, styles, para_start, i) ==
                  rstrip(c -> c in (',', ';', '.'), uppercase(words[i]))
        end
    end
end
