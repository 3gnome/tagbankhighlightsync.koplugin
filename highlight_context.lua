-- Best-effort visible-page context for local tag suggestions.

local HighlightContext = {}

HighlightContext.DEFAULT_MAX_WORDS = 120
HighlightContext.DEFAULT_MAX_CHARS = 4000

local function trim(text)
    return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function HighlightContext.normalize_space(text)
    if type(text) ~= "string" then
        return ""
    end
    return trim(text:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("%s+", " "))
end

local function collect_selection_text(value, out, seen)
    if type(value) == "string" then
        out[#out + 1] = value
        return
    end
    if type(value) ~= "table" or seen[value] then
        return
    end
    seen[value] = true
    for _, key in ipairs({ "text", "t", "s", "str", "value" }) do
        if type(value[key]) == "string" then
            out[#out + 1] = value[key]
        end
    end
    for _, key in ipairs({ "spans", "segments", "lines" }) do
        if type(value[key]) == "table" then
            collect_selection_text(value[key], out, seen)
        end
    end
    for _, child in ipairs(value) do
        collect_selection_text(child, out, seen)
    end
end

--- Normalize backend-specific getTextFromPositions results to a string.
function HighlightContext.selection_to_text(selection)
    if type(selection) == "string" then
        return selection
    end
    local out = {}
    collect_selection_text(selection, out, {})
    return table.concat(out, "")
end

local function words(text)
    local out = {}
    for word in (text or ""):gmatch("%S+") do
        out[#out + 1] = word
    end
    return out
end

--- Keep a bounded window around selection while retaining the selected text.
function HighlightContext.bound_around(text, selection, max_words, max_chars)
    text = HighlightContext.normalize_space(text)
    selection = HighlightContext.normalize_space(selection)
    max_words = math.max(1, max_words or HighlightContext.DEFAULT_MAX_WORDS)
    max_chars = math.max(64, max_chars or HighlightContext.DEFAULT_MAX_CHARS)
    if text == "" then
        return ""
    end

    local start_pos, end_pos
    if selection ~= "" then
        start_pos, end_pos = text:find(selection, 1, true)
    end
    if not start_pos then
        local all = words(text)
        local finish = math.min(#all, max_words)
        text = table.concat(all, " ", 1, finish)
        return text:sub(1, max_chars)
    end

    local before = words(text:sub(1, start_pos - 1))
    local selected = words(text:sub(start_pos, end_pos))
    local after = words(text:sub(end_pos + 1))
    if #selected >= max_words then
        return trim(table.concat(selected, " ", 1, max_words):sub(1, max_chars))
    end
    local remaining = math.max(0, max_words - #selected)
    local before_count = math.min(#before, math.floor(remaining / 2))
    local after_count = math.min(#after, remaining - before_count)
    if before_count < math.floor(remaining / 2) then
        after_count = math.min(#after, remaining - before_count)
    elseif after_count < remaining - before_count then
        before_count = math.min(#before, remaining - after_count)
    end

    local out = {}
    for i = #before - before_count + 1, #before do
        if i >= 1 then out[#out + 1] = before[i] end
    end
    for _, word in ipairs(selected) do out[#out + 1] = word end
    for i = 1, after_count do out[#out + 1] = after[i] end
    local bounded = table.concat(out, " ")
    if #bounded <= max_chars then
        return bounded
    end

    -- A character cap is a final safety bound. Center it on the selection.
    local selected_at = bounded:find(selection, 1, true)
    if not selected_at then
        return trim(bounded:sub(1, max_chars))
    end
    local left = math.max(1, selected_at - math.floor((max_chars - #selection) / 2))
    local right = math.min(#bounded, left + max_chars - 1)
    left = math.max(1, right - max_chars + 1)
    return trim(bounded:sub(left, right))
end

--- Extract the blank-line paragraph containing selection, or a bounded page window.
function HighlightContext.extract_paragraph(page_text, selection, opts)
    opts = opts or {}
    if type(page_text) ~= "string" or type(selection) ~= "string" then
        return nil
    end
    selection = HighlightContext.normalize_space(selection)
    if selection == "" then
        return nil
    end

    local normalized_page = page_text:gsub("\r\n", "\n"):gsub("\r", "\n")
    for block in (normalized_page .. "\n\n"):gmatch("(.-)\n%s*\n") do
        local paragraph = HighlightContext.normalize_space(block)
        if paragraph ~= "" and paragraph:find(selection, 1, true) then
            return HighlightContext.bound_around(
                paragraph, selection, opts.max_words, opts.max_chars)
        end
    end

    local page = HighlightContext.normalize_space(normalized_page)
    if not page:find(selection, 1, true) then
        return nil
    end
    return HighlightContext.bound_around(page, selection, opts.max_words, opts.max_chars)
end

--- Read visible screen text through KOReader's document API. Never raises.
function HighlightContext.get_visible_page_text(document, screen)
    if not document or not document.getTextFromPositions or not screen then
        return nil
    end
    local ok, text = pcall(function()
        local width = screen:getWidth()
        local height = screen:getHeight()
        return document:getTextFromPositions(
            { x = 0, y = 0 },
            { x = width, y = height },
            true)
    end)
    if not ok then
        return nil
    end
    text = HighlightContext.selection_to_text(text)
    if HighlightContext.normalize_space(text) == "" then
        return nil
    end
    return text
end

local function resolve_screen(opts)
    if opts and opts.screen then
        return opts.screen
    end
    local ok, Device = pcall(require, "device")
    if ok and Device then
        return Device.screen
    end
end

--- Return context and source ("page" or "annotation"), falling back to ann.text.
function HighlightContext.get(hl, ann, opts)
    opts = opts or {}
    ann = ann or {}
    local fallback = HighlightContext.bound_around(
        ann.text or "", ann.text or "", opts.max_words, opts.max_chars)
    local document = opts.document
        or (hl and hl.ui and hl.ui.document)
    local page_text = HighlightContext.get_visible_page_text(
        document, resolve_screen(opts))
    if page_text then
        local paragraph = HighlightContext.extract_paragraph(page_text, ann.text or "", opts)
        if paragraph and paragraph ~= "" then
            return paragraph, "page"
        end
    end
    return fallback, "annotation"
end

return HighlightContext
