-- Verse layout detection and normalization for library quote export.

local VerseLayout = {}

VerseLayout.FIELD = "highlight_sync_quote_layout"

local NBSP = "\194\160"
local CURLY_OPEN = "\226\128\156"
local CURLY_CLOSE = "\226\128\157"
local CURLY_APOSTROPHE = "\226\128\153"
local EM_DASH = "\226\128\148"

local LAYOUT_AUTO = "auto"
local LAYOUT_VERSE = "verse"
local LAYOUT_PROSE = "prose"

function VerseLayout.get_quote_layout(item)
    if not item or type(item) ~= "table" then
        return LAYOUT_AUTO
    end
    local mode = item[VerseLayout.FIELD]
    if mode == LAYOUT_VERSE or mode == LAYOUT_PROSE then
        return mode
    end
    return LAYOUT_AUTO
end

function VerseLayout.set_quote_layout(item, mode)
    if not item or type(item) ~= "table" then
        return
    end
    if mode == LAYOUT_VERSE or mode == LAYOUT_PROSE then
        item[VerseLayout.FIELD] = mode
    else
        item[VerseLayout.FIELD] = nil
    end
end

function VerseLayout.layout_label(mode)
    if mode == LAYOUT_VERSE then
        return "Verse"
    end
    if mode == LAYOUT_PROSE then
        return "Prose"
    end
    return "Auto"
end

function VerseLayout.has_verse_nbsp(text)
    text = text or ""
    return text:find(NBSP .. NBSP, 1, true) ~= nil
end

local function count_punct_cap_breaks(text)
    local count = 0
    local pos = 1
    while pos <= #text do
        local s, e = text:find("[%.%?!]", pos)
        if not s then
            break
        end
        local after = e + 1
        if text:sub(after, after + #CURLY_CLOSE - 1) == CURLY_CLOSE then
            after = after + #CURLY_CLOSE
        end
        if text:sub(after, after) == " " then
            after = after + 1
            local ch = text:sub(after, after)
            if ch:match("[A-Z]") or ch == "[" then
                count = count + 1
            end
        end
        pos = e + 1
    end
    return count
end

local function count_comma_cap_breaks(text)
    local count = 0
    local pos = 1
    while true do
        local s, e = text:find(", ", pos, true)
        if not s then
            break
        end
        local cap = text:sub(e + 1, e + 1)
        if cap:match("[A-Z]") then
            count = count + 1
        end
        pos = e + 1
    end
    return count
end

local function count_char(text, ch)
    local n = 0
    local pos = 1
    while true do
        local s = text:find(ch, pos, true)
        if not s then
            break
        end
        n = n + 1
        pos = s + #ch
    end
    return n
end

function VerseLayout.looks_like_verse_layout(text)
    text = text or ""
    if VerseLayout.has_verse_nbsp(text) then
        return true
    end

    local len = #text
    local punct_cap = count_punct_cap_breaks(text)
    local comma_cap = count_comma_cap_breaks(text)
    local semis = count_char(text, ";")
    local punct_count = count_char(text, ".") + count_char(text, "?") + count_char(text, "!")

    if len < 100 and punct_cap < 2 then
        return false
    end
    if len < 200 and punct_count <= 1 then
        return false
    end

    if punct_cap >= 3 then
        return true
    end
    if comma_cap >= 2 and len >= 120 and (semis >= 1 or punct_cap >= 2) then
        return true
    end
    if semis >= 1 and len >= 120 and punct_cap >= 2 then
        return true
    end
    if len >= 400 and punct_cap >= 2 then
        return true
    end
    return false
end

-- Back-compat alias
VerseLayout.looks_like_flat_verse = VerseLayout.looks_like_verse_layout

local function replace_nbsp_runs(text)
    local pos = 1
    while true do
        local s, e = text:find(NBSP .. NBSP, pos, true)
        if not s then
            break
        end
        while e + #NBSP <= #text and text:sub(e + 1, e + #NBSP) == NBSP do
            e = e + #NBSP
        end
        text = text:sub(1, s - 1) .. "\n  " .. text:sub(e + 1)
        pos = s + 3
    end
    return text
end

local function apply_punctuation_verse_breaks(text)
    text = text:gsub(
        "([%.%?!])" .. CURLY_CLOSE .. " " .. CURLY_OPEN,
        "%1" .. CURLY_CLOSE .. "\n" .. CURLY_OPEN)
    text = text:gsub(
        "([%.%?!])" .. CURLY_CLOSE .. " ([A-Z])",
        "%1" .. CURLY_CLOSE .. "\n%2")
    text = text:gsub(
        "([%.%?!]) (" .. CURLY_OPEN .. ")",
        "%1\n%2")
    text = text:gsub("([%.%?!]) ([A-Z])", "%1\n%2")
    text = text:gsub("(" .. EM_DASH .. ") ([A-Z])", "%1\n%2")
    text = text:gsub(" be (When )", " be\n%1")
    return text
end

local function apply_midline_cap_breaks(text)
    local no_break = {
        the = true, a = true, an = true, of = true, ["in"] = true, to = true,
        as = true, so = true, be = true, by = true, on = true, at = true,
    }
    return text:gsub("(%l[%l]+) ([A-Z][a-z])", function(prev, cap)
        local last_word = prev:match("(%l+)$")
        if last_word and no_break[last_word] then
            return prev .. " " .. cap
        end
        return prev .. "\n" .. cap
    end)
end

local function apply_verse_line_breaks(text)
    text = apply_punctuation_verse_breaks(text)
    text = text:gsub("; ([A-Z])", ";\n%1")
    text = text:gsub(", ([A-Z])", ",\n%1")
    text = text:gsub(", " .. CURLY_OPEN, ",\n" .. CURLY_OPEN)
    text = apply_midline_cap_breaks(text)
    text = text:gsub(" (%[)", "\n%1")
    text = text:gsub("follows ([A-Z])", "follows\n%1")
    return text
end

local function line_ends_with(line, suffix)
    return #line >= #suffix and line:sub(-#suffix) == suffix
end

local function line_ends_with_sentence(prev)
    if line_ends_with(prev, ".") or line_ends_with(prev, "?") or line_ends_with(prev, "!") then
        return true
    end
    if #prev >= #CURLY_CLOSE and prev:sub(-#CURLY_CLOSE) == CURLY_CLOSE then
        local before = prev:sub(-#CURLY_CLOSE - 1, -#CURLY_CLOSE - 1)
        if before == "." or before == "?" or before == "!" then
            return true
        end
    end
    return false
end

local function should_insert_stanza_gap(prev, next)
    if not next or next == "" then
        return false
    end
    if next:sub(1, 1) == "[" and line_ends_with_sentence(prev) then
        return true
    end
    if next:sub(1, #CURLY_OPEN) == CURLY_OPEN and line_ends_with_sentence(prev)
        and prev:sub(1, #CURLY_OPEN) ~= CURLY_OPEN then
        return true
    end
    if line_ends_with(prev, "won't you join the dance?")
        or line_ends_with(prev, "won" .. CURLY_APOSTROPHE .. "t you join the dance?") then
        return next:sub(1, #CURLY_OPEN) == CURLY_OPEN
    end
    if line_ends_with(prev, "could not join the dance.") then
        return next:sub(1, #CURLY_OPEN) == CURLY_OPEN
    end
    return false
end

local function insert_stanza_gaps(lines)
    local result = {}
    for i, line in ipairs(lines) do
        result[#result + 1] = line
        if should_insert_stanza_gap(line, lines[i + 1]) then
            result[#result + 1] = ""
        end
    end
    return result
end

function VerseLayout.normalize(text)
    text = text or ""
    if text == "" or text:find("\n") then
        return text
    end
    text = replace_nbsp_runs(text)
    text = apply_verse_line_breaks(text)
    local out_lines = {}
    for line in text:gmatch("[^\n]+") do
        out_lines[#out_lines + 1] = line:gsub("%s+$", "")
    end
    if #out_lines > 0 then
        out_lines = insert_stanza_gaps(out_lines)
        return table.concat(out_lines, "\n")
    end
    return text
end

function VerseLayout.should_normalize(text, settings, item)
    if settings and settings.library_preserve_verse_layout == false then
        return false
    end
    local mode = VerseLayout.get_quote_layout(item)
    if mode == LAYOUT_PROSE then
        return false
    end
    if mode == LAYOUT_VERSE then
        return true
    end
    if VerseLayout.has_verse_nbsp(text) then
        return true
    end
    return VerseLayout.looks_like_verse_layout(text)
end

return VerseLayout
