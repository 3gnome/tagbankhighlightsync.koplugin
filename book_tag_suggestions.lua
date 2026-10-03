-- Pure, local tag suggestions from other annotations in the current book.

local TagBank = require("tag_bank")
local Tags = require("tags")

local BookTagSuggestions = {}

BookTagSuggestions.MAX_SUGGESTIONS = 5
BookTagSuggestions.MAX_RECENT = 12
BookTagSuggestions.MIN_SCORE = 0.18
BookTagSuggestions.EXACT_BOOST = 0.50

local STOP_WORDS = {}
for word in ([[
    a about after again against all am an and any are as at be because been
    before being below between both but by can did do does doing down during
    each few for from further had has have having he her here hers herself him
    himself his how i if in into is it its itself just me more most my myself
    no nor not now of off on once only or other our ours ourselves out over own
    same she should so some such than that the their theirs them themselves then
    there these they this those through to too under until up very was we were
    what when where which while who whom why will with would you your yours
    yourself yourselves
]]):gmatch("%S+") do
    STOP_WORDS[word] = true
end

local function canonical_text(text)
    text = tostring(text or ""):lower()
    text = text:gsub("’", "'"):gsub("‘", "'")
    text = text:gsub("[_%-]+", " ")
    text = text:gsub("'s([^%a%d])", "%1")
    text = text:gsub("[^%a%d]+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
end

function BookTagSuggestions.tokenize(text)
    local tokens = {}
    for token in canonical_text(text):gmatch("[%a%d]+") do
        if #token >= 2 and not STOP_WORDS[token] then
            tokens[#tokens + 1] = token
        end
    end
    return tokens
end

local function token_counts(text)
    local counts = {}
    for _, token in ipairs(BookTagSuggestions.tokenize(text)) do
        counts[token] = (counts[token] or 0) + 1
    end
    return counts
end

local function serialize_position(pos)
    if type(pos) ~= "table" then
        return tostring(pos or "")
    end
    local fields = { "page", "x", "y", "zoom", "rotation", "offset" }
    local parts = {}
    for _, field in ipairs(fields) do
        parts[#parts + 1] = tostring(pos[field] or "")
    end
    return table.concat(parts, ",")
end

local function same_position(a, b)
    if not a or not b or a.pos0 == nil or a.pos1 == nil
        or b.pos0 == nil or b.pos1 == nil then
        return false
    end
    if serialize_position(a.pos0) ~= serialize_position(b.pos0)
        or serialize_position(a.pos1) ~= serialize_position(b.pos1) then
        return false
    end
    local a_page = a.pageno or a.page
    local b_page = b.pageno or b.page
    return a_page == nil or b_page == nil or tostring(a_page) == tostring(b_page)
end

--- Exclude current annotation by table identity, index, persistent id, or position.
function BookTagSuggestions.is_current_annotation(ann, index, current_ann, current_index)
    if not ann then
        return false
    end
    if current_ann and ann == current_ann then
        return true
    end
    if current_index ~= nil and index ~= nil
        and tostring(current_index) == tostring(index) then
        return true
    end
    if current_ann then
        for _, field in ipairs({ "id", "uid", "uuid", "annotation_id" }) do
            if ann[field] ~= nil and current_ann[field] ~= nil
                and tostring(ann[field]) == tostring(current_ann[field]) then
                return true
            end
        end
        if same_position(ann, current_ann) then
            return true
        end
    end
    return false
end

local function timestamp_value(ann)
    local value = tostring((ann and (ann.datetime_updated or ann.datetime)) or "")
    local digits = value:gsub("%D", ""):sub(1, 14)
    return tonumber(digits) or 0
end

local function add_counts(dest, src)
    for token, count in pairs(src) do
        dest[token] = (dest[token] or 0) + count
    end
end

local function weighted_vector(counts, document_frequency, document_count)
    local vector = {}
    for token, count in pairs(counts) do
        local frequency = document_frequency[token] or 0
        local idf = math.log((document_count + 1) / (frequency + 1)) + 1
        vector[token] = count * idf
    end
    return vector
end

function BookTagSuggestions.cosine_similarity(a, b)
    local dot, norm_a, norm_b = 0, 0, 0
    for token, value in pairs(a or {}) do
        norm_a = norm_a + value * value
        dot = dot + value * ((b and b[token]) or 0)
    end
    for _, value in pairs(b or {}) do
        norm_b = norm_b + value * value
    end
    if norm_a == 0 or norm_b == 0 then
        return 0
    end
    return dot / math.sqrt(norm_a * norm_b)
end

local function shared_token_count(a, b)
    local count = 0
    for token in pairs(a or {}) do
        if b and b[token] then
            count = count + 1
        end
    end
    return count
end

local function phrase_occurs(query, phrase)
    phrase = canonical_text(phrase)
    if phrase == "" then
        return false
    end
    return (" " .. query .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

local function capped(value, default_value, hard_max)
    value = tonumber(value)
    if value == nil then value = default_value end
    return math.max(0, math.min(math.floor(value), hard_max))
end

local function excluded_ids(opts)
    local excluded = {}
    for _, id in ipairs((opts and opts.existing_tags) or {}) do
        excluded[id] = true
    end
    return excluded
end

--- Return { suggestions = {...}, recent = {...} } for one book's annotation list.
function BookTagSuggestions.suggest(query_text, annotations, bank, opts)
    opts = opts or {}
    annotations = annotations or {}
    bank = bank or {}
    local bank_ids = TagBank.collect_ids(bank)
    local excluded = excluded_ids(opts)
    local candidates = {}
    local document_frequency = {}
    local document_count = 0

    for index, ann in ipairs(annotations) do
        if not BookTagSuggestions.is_current_annotation(
            ann, index, opts.current_annotation, opts.current_index) then
            local counts = token_counts((ann.text or "") .. " " .. (ann.note or ""))
            for token in pairs(counts) do
                document_frequency[token] = (document_frequency[token] or 0) + 1
            end
            document_count = document_count + 1

            for _, id in ipairs(Tags.get_tags(ann)) do
                if bank_ids[id] then
                    local candidate = candidates[id]
                    if not candidate then
                        candidate = {
                            id = id,
                            name = TagBank.get_display_name(bank, id),
                            counts = {},
                            frequency = 0,
                            last_used = 0,
                        }
                        candidates[id] = candidate
                    end
                    candidate.frequency = candidate.frequency + 1
                    candidate.last_used = math.max(candidate.last_used, timestamp_value(ann))
                    add_counts(candidate.counts, counts)
                end
            end
        end
    end

    local query_counts = token_counts(query_text)
    local query_canonical = canonical_text(query_text)
    local query_vector = weighted_vector(query_counts, document_frequency, document_count)
    local suggestions = {}
    local min_score = tonumber(opts.min_score) or BookTagSuggestions.MIN_SCORE

    for id, candidate in pairs(candidates) do
        if not excluded[id] then
            local candidate_vector = weighted_vector(
                candidate.counts, document_frequency, document_count)
            local similarity = BookTagSuggestions.cosine_similarity(
                query_vector, candidate_vector)
            local exact = phrase_occurs(query_canonical, candidate.name)
                or phrase_occurs(query_canonical, candidate.id)
            local score = similarity + (exact and BookTagSuggestions.EXACT_BOOST or 0)
            local shared = shared_token_count(query_counts, candidate.counts)
            if exact or (shared >= 2 and score >= min_score) then
                suggestions[#suggestions + 1] = {
                    id = id,
                    name = candidate.name,
                    score = score,
                    exact_match = exact,
                    frequency = candidate.frequency,
                    last_used = candidate.last_used,
                }
            end
        end
    end

    table.sort(suggestions, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.frequency ~= b.frequency then return a.frequency > b.frequency end
        if a.last_used ~= b.last_used then return a.last_used > b.last_used end
        return a.id < b.id
    end)
    local suggestion_cap = capped(
        opts.max_suggestions, BookTagSuggestions.MAX_SUGGESTIONS,
        BookTagSuggestions.MAX_SUGGESTIONS)
    while #suggestions > suggestion_cap do table.remove(suggestions) end

    local suggestion_ids = {}
    for _, candidate in ipairs(suggestions) do
        suggestion_ids[candidate.id] = true
    end
    local recent = {}
    for id, candidate in pairs(candidates) do
        if not excluded[id] and not suggestion_ids[id] then
            recent[#recent + 1] = {
                id = id,
                name = candidate.name,
                frequency = candidate.frequency,
                last_used = candidate.last_used,
            }
        end
    end
    table.sort(recent, function(a, b)
        if a.last_used ~= b.last_used then return a.last_used > b.last_used end
        if a.frequency ~= b.frequency then return a.frequency > b.frequency end
        return a.id < b.id
    end)
    local recent_cap = capped(
        opts.max_recent, BookTagSuggestions.MAX_RECENT,
        BookTagSuggestions.MAX_RECENT)
    while #recent > recent_cap do table.remove(recent) end

    return {
        suggestions = suggestions,
        recent = recent,
    }
end

return BookTagSuggestions
