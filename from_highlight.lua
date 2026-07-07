-- Extract distinctive words from highlight text for the Tag highlight menu.

local TagBank = require("tag_bank")

local FromHighlight = {}

local MAX_WORDS = 20
local MIN_LETTERS = 5
local EARLY_RATIO = 0.25

-- English stopwords with at least 5 letters (lowercase slugs).
local STOPWORDS = {
    about = true, above = true, after = true, again = true, along = true,
    among = true, being = true, below = true, between = true, during = true,
    every = true, having = true, itself = true, might = true, never = true,
    often = true, other = true, shall = true, since = true, still = true,
    their = true, these = true, thing = true, think = true, those = true,
    three = true, under = true, ["until"] = true, where = true, which = true,
    ["while"] = true, would = true, without = true, themselves = true,
    really = true, always = true, before = true, could = true, doing = true,
    either = true, enough = true, little = true, maybe = true, natural = true,
    nothing = true, people = true, rather = true, should = true, simply = true,
    somewhat = true, talking = true, there = true, through = true,
}

local TOKEN_PATTERN = "([%a][%a'%-]*[%a]?)"

local function letter_count(token)
    local n = 0
    for _ in token:gmatch("[%a]") do
        n = n + 1
    end
    return n
end

local function preprocess(text)
    text = text:gsub("\194\173", "")
    text = text:gsub("\226\128\156", '"'):gsub("\226\128\157", '"')
    text = text:gsub("\226\128\152", "'"):gsub("\226\128\153", "'")
    text = text:gsub("%- ", "")
    text = text:gsub("([%a]+)-%s*\n%s*([%a]+)", "%1%2")
    return text
end

local function is_proper_noun(token)
    return token:match("[A-Z]") ~= nil
end

local function is_adverb_like(token)
    return token == token:lower() and token:match("ly$") ~= nil
end

local function count_token_frequencies(text)
    local freq = {}
    local pos = 1
    while true do
        local s, e, token = text:find(TOKEN_PATTERN, pos)
        if not s then
            break
        end
        local slug = TagBank.slugify(token)
        freq[slug] = (freq[slug] or 0) + 1
        pos = e + 1
    end
    return freq
end

local function composite_score(token, slug, text_len, first_pos, freq)
    local score = letter_count(token)
    if is_proper_noun(token) then
        score = score + 4
    end
    if first_pos <= math.max(1, math.floor(text_len * EARLY_RATIO)) then
        score = score + 2
    end
    score = score + 3 * ((freq[slug] or 1) - 1)
    if is_adverb_like(token) then
        score = score - 3
    end
    return score
end

function FromHighlight.extract_words(text, bank)
    text = preprocess(text or "")
    if text == "" then
        return {}
    end

    local bank_ids = TagBank.collect_ids(bank or {})
    local freq = count_token_frequencies(text)
    local text_len = #text

    local seen = {}
    local candidates = {}
    local pos = 1
    while true do
        local s, e, token = text:find(TOKEN_PATTERN, pos)
        if not s then
            break
        end
        pos = e + 1

        if letter_count(token) >= MIN_LETTERS then
            local slug = TagBank.slugify(token)
            if not bank_ids[slug] and not STOPWORDS[slug] and not seen[slug] then
                seen[slug] = true
                local display = TagBank.format_display_name(token)
                candidates[#candidates + 1] = {
                    display = display,
                    id = TagBank.slugify(display),
                    first_pos = s,
                    score = composite_score(token, slug, text_len, s, freq),
                }
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.first_pos < b.first_pos
    end)

    local out = {}
    for i = 1, math.min(MAX_WORDS, #candidates) do
        local c = candidates[i]
        out[#out + 1] = { display = c.display, id = c.id }
    end
    return out
end

return FromHighlight
