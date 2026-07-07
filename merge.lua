local Tags = require("tags")

local function parse_datetime_cached()
    local cache = {}
    return function(str)
        if not str then return 0 end
        if cache[str] then return cache[str] end
        local y, m, d, h, min, s = str:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
        if not y then return 0 end
        local t = os.time{
            year = tonumber(y), month = tonumber(m), day = tonumber(d),
            hour = tonumber(h), min = tonumber(min), sec = tonumber(s),
        }
        cache[str] = t
        return t
    end
end
local parse_datetime = parse_datetime_cached()

local function get_datetime(item)
    return item.datetime_updated or item.datetime
end

local function get_newer(item1, item2)
    local t1 = parse_datetime(get_datetime(item1))
    local t2 = parse_datetime(get_datetime(item2))
    return t1 >= t2 and item1 or item2
end

--- Serialize a PDF position table into a stable string key.
local function serialize_pdf_pos(pos)
    if type(pos) ~= "table" then
        return tostring(pos)
    end
    return string.format("%s,%s,%s,%s,%s,%s",
        pos.page or "",
        pos.x or "",
        pos.y or "",
        pos.zoom or "",
        pos.rotation or "",
        pos.offset or "")
end

--- Generate a stable key using pos0+pos1 (XPath or PDF coordinates).
local function generate_key(highlight)
    if highlight.pos0 and highlight.pos1 then
        if type(highlight.pos0) == "table" or type(highlight.pos1) == "table" then
            return string.format("%s|%s|%s",
                highlight.page or "",
                serialize_pdf_pos(highlight.pos0),
                serialize_pdf_pos(highlight.pos1))
        end
        return string.format("%s|%s", highlight.pos0, highlight.pos1)
    end
    local text = highlight.text or ""
    local hash = tostring(#text) .. ":" .. (text:sub(1, 20) or "")
    return string.format("%s|%s", highlight.page or "?", hash)
end

--- Normalize annotations from array or hash-map (legacy sidecar) into a list.
local function normalize_to_list(highlights)
    if not highlights or type(highlights) ~= "table" then
        return {}
    end
    local list = {}
    local n = #highlights
    if n > 0 then
        for i = 1, n do
            if highlights[i] then
                list[#list + 1] = highlights[i]
            end
        end
        return list
    end
    for _, h in pairs(highlights) do
        if type(h) == "table" then
            list[#list + 1] = h
        end
    end
    return list
end

local function convert_to_map(highlights)
    local map = {}
    for _, h in ipairs(normalize_to_list(highlights)) do
        map[generate_key(h)] = h
    end
    return map
end

local function merge_highlights(local_annotations, server_annotations, last_sync_annotations)
    local local_map = convert_to_map(local_annotations or {})
    local server_map = convert_to_map(server_annotations or {})
    local last_sync_map = convert_to_map(last_sync_annotations or {})

    local merged = {}

    for key, local_highlight in pairs(local_map) do
        local server_highlight = server_map[key]
        local last_sync_highlight = last_sync_map[key]
        if not (server_highlight == nil and last_sync_highlight ~= nil) then
            merged[key] = local_highlight
        end
    end

    for key, server_highlight in pairs(server_map) do
        if last_sync_map[key] ~= nil and local_map[key] == nil then
            -- deleted locally, ignore remote copy
        else
            if not local_map[key] then
                merged[key] = server_highlight
            else
                local winner = get_newer(server_highlight, local_map[key])
                merged[key] = Tags.merge_annotation_tags(
                    winner, local_map[key], server_highlight)
                Tags.merge_capture_metadata(
                    merged[key], local_map[key], server_highlight)
            end
        end
    end

    local merged_annotations = {}
    for _, h in pairs(merged) do
        merged_annotations[#merged_annotations + 1] = h
    end

    table.sort(merged_annotations, function(a, b)
        if a.pageno ~= b.pageno then
            return (a.pageno or 0) < (b.pageno or 0)
        end
        if not a.pos0 then return true end
        if not b.pos0 then return false end

        if type(a.pos0) == "table" then
            if type(b.pos0) == "table" then
                local ay, ax = a.pos0.y or 0, a.pos0.x or 0
                local by, bx = b.pos0.y or 0, b.pos0.x or 0
                return ay < by or (ay == by and ax < bx)
            end
            return false
        elseif type(b.pos0) == "table" then
            return true
        end

        return a.pos0 < b.pos0
    end)

    return merged_annotations
end

--- Merge syncable highlights back into the full on-device list.
--- Non-syncable annotations (per is_syncable) are left unchanged.
--- Syncable items deleted during merge are removed from the full list.
function merge_back_into_full(full_annotations, merged_syncable, is_syncable)
    local full_list = normalize_to_list(full_annotations)
    local merged_map = convert_to_map(merged_syncable or {})
    local result = {}
    local seen_merged = {}

    for _, ann in ipairs(full_list) do
        local key = generate_key(ann)
        if is_syncable(ann) then
            if merged_map[key] then
                result[#result + 1] = merged_map[key]
                seen_merged[key] = true
            end
        else
            result[#result + 1] = ann
        end
    end

    for key, ann in pairs(merged_map) do
        if not seen_merged[key] then
            result[#result + 1] = ann
        end
    end

    return result
end

local M = {}

M.Merge_highlights = merge_highlights
M.merge_back_into_full = merge_back_into_full
M.generate_key = generate_key
M.normalize_to_list = normalize_to_list
M.serialize_pdf_pos = serialize_pdf_pos

return M
