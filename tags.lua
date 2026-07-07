-- Tag normalization and merge helpers for highlight_sync_tags.

local TagBank = require("tag_bank")

local Tags = {}

Tags.FIELD = "highlight_sync_tags"
Tags.HASH_FIELD = "highlight_sync_library_hash"
Tags.SYNCED_AT_FIELD = "highlight_sync_library_synced_at"
Tags.PREV_EXPANDED_FIELD = "highlight_sync_tags_prev_expanded"
Tags.CAPTURE_FIELD = "highlight_sync_capture"
Tags.CAPTURE_AT_FIELD = "highlight_sync_capture_at"

local function capture_timestamp(str)
    if not str or str == "" then
        return 0
    end
    local y, m, d, h, min, s = str:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    if not y then
        return 0
    end
    return os.time{
        year = tonumber(y), month = tonumber(m), day = tonumber(d),
        hour = tonumber(h), min = tonumber(min), sec = tonumber(s),
    }
end

function Tags.has_capture(annotation)
    local path = annotation and annotation[Tags.CAPTURE_FIELD]
    return path ~= nil and path ~= ""
end

local function normalize_one(tag)
    if type(tag) ~= "string" then
        return nil
    end
    tag = tag:gsub("^#+", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if tag == "" then
        return nil
    end
    return tag:gsub("%s+", "_")
end

--- Normalize a list of tag strings (dedupe, lowercase, no # prefix).
function Tags.normalize_list(tags)
    local out = {}
    local seen = {}
    if type(tags) ~= "table" then
        return out
    end
    for _, tag in ipairs(tags) do
        local norm = normalize_one(tag)
        if norm and not seen[norm] then
            seen[norm] = true
            out[#out + 1] = norm
        end
    end
    table.sort(out)
    return out
end

--- Parse comma/space-separated custom tag input.
function Tags.parse_input(text)
    local out = {}
    if not text or text == "" then
        return out
    end
    for token in text:gmatch("[^,%s#]+") do
        out[#out + 1] = token
    end
    return Tags.normalize_list(out)
end

function Tags.get_tags(annotation)
    if not annotation or type(annotation) ~= "table" then
        return {}
    end
    return Tags.normalize_list(annotation[Tags.FIELD])
end

function Tags.set_tags(annotation, tags)
    if not annotation or type(annotation) ~= "table" then
        return
    end
    local normalized = Tags.normalize_list(tags)
    if #normalized == 0 then
        annotation[Tags.FIELD] = nil
    else
        annotation[Tags.FIELD] = normalized
    end
end

--- Remember expanded tag ids before a tag change (for library index cleanup).
function Tags.stash_expanded_tags_for_library(annotation, bank)
    if not annotation or type(annotation) ~= "table" then
        return
    end
    local expanded = Tags.expand_for_export(Tags.get_tags(annotation), bank or {})
    if #expanded == 0 then
        annotation[Tags.PREV_EXPANDED_FIELD] = nil
    else
        annotation[Tags.PREV_EXPANDED_FIELD] = expanded
    end
end

function Tags.take_previous_expanded_tags(annotation)
    if not annotation or type(annotation) ~= "table" then
        return {}
    end
    local prev = annotation[Tags.PREV_EXPANDED_FIELD]
    annotation[Tags.PREV_EXPANDED_FIELD] = nil
    if type(prev) ~= "table" then
        return {}
    end
    return prev
end

--- Union tags from multiple annotations onto a copy of primary.
function Tags.merge_annotation_tags(primary, ...)
    local copy = {}
    for k, v in pairs(primary or {}) do
        copy[k] = v
    end
    local combined = Tags.get_tags(primary)
    for i = 1, select("#", ...) do
        local other = select(i, ...)
        if other then
            for _, tag in ipairs(Tags.get_tags(other)) do
                combined[#combined + 1] = tag
            end
        end
    end
    Tags.set_tags(copy, combined)
    return copy
end

--- Preserve capture metadata from any merged annotation copy (newest capture wins).
function Tags.merge_capture_metadata(dest, ...)
    if not dest then
        return dest
    end
    local best_path, best_at, best_ts = nil, nil, -1
    local function consider(ann)
        if not ann or not Tags.has_capture(ann) then
            return
        end
        local at = ann[Tags.CAPTURE_AT_FIELD] or ann.datetime_updated or ann.datetime or ""
        local ts = capture_timestamp(at)
        if ts > best_ts or (ts == best_ts and not best_path) then
            best_ts = ts
            best_path = ann[Tags.CAPTURE_FIELD]
            best_at = ann[Tags.CAPTURE_AT_FIELD] or at
        end
    end
    consider(dest)
    for i = 1, select("#", ...) do
        consider(select(i, ...))
    end
    if best_path then
        dest[Tags.CAPTURE_FIELD] = best_path
        dest[Tags.CAPTURE_AT_FIELD] = best_at
    else
        dest[Tags.CAPTURE_FIELD] = nil
        dest[Tags.CAPTURE_AT_FIELD] = nil
    end
    return dest
end

function Tags.format_hashtag_line(tags)
    local list = Tags.normalize_list(tags)
    if #list == 0 then
        return ""
    end
    local parts = {}
    for _, tag in ipairs(list) do
        parts[#parts + 1] = "#" .. tag
    end
    return table.concat(parts, " ")
end

function Tags.format_csv(tags)
    return table.concat(Tags.normalize_list(tags), ", ")
end

function Tags.expand_for_export(leaf_ids, bank)
    return TagBank.expand_for_export(leaf_ids, bank)
end

function Tags.format_hashtag_line_for_export(leaf_ids, bank)
    return Tags.format_hashtag_line(Tags.expand_for_export(leaf_ids, bank))
end

function Tags.compute_library_hash(annotation, expanded_tag_ids)
    if not annotation then
        return ""
    end
    local util = require("util")
    local parts = {
        annotation.text or "",
        annotation.note or "",
        table.concat(expanded_tag_ids or {}, ","),
        annotation.datetime_updated or annotation.datetime or "",
        annotation.highlight_sync_quote_layout or "",
    }
    if Tags.has_capture(annotation) then
        parts[#parts + 1] = annotation[Tags.CAPTURE_FIELD]
        parts[#parts + 1] = annotation[Tags.CAPTURE_AT_FIELD] or ""
    end
    local payload = table.concat(parts, "\31")
    return util.partialMD5(payload) or payload
end

function Tags.get_library_hash(annotation)
    return annotation and annotation[Tags.HASH_FIELD] or nil
end

function Tags.set_library_sync_state(annotation, hash)
    if not annotation then
        return
    end
    annotation[Tags.HASH_FIELD] = hash
    annotation[Tags.SYNCED_AT_FIELD] = os.date("%Y-%m-%d %H:%M:%S")
end

function Tags.needs_library_sync(annotation, bank)
    if not annotation then
        return false
    end
    local leaf = Tags.get_tags(annotation)
    local expanded = Tags.expand_for_export(leaf, bank or {})
    local hash = Tags.compute_library_hash(annotation, expanded)
    return Tags.get_library_hash(annotation) ~= hash
end

return Tags
