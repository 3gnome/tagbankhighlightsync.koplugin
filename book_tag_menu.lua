-- Review UI for local, same-book tag suggestions.

local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local FFIUtil = require("ffi/util")
local T = FFIUtil.template
local _ = require("gettext")
local BookTagSuggestions = require("book_tag_suggestions")
local HighlightContext = require("highlight_context")
local TagBank = require("tag_bank")
local TagMenu = require("tag_menu")
local Tags = require("tags")

local BookTagMenu = {}

local CHECKMARK = "✓"

local function selected_ids(selected)
    local ids = {}
    for id, enabled in pairs(selected or {}) do
        if enabled then ids[#ids + 1] = id end
    end
    return Tags.normalize_list(ids)
end

--- Merge reviewed additions without ever removing current annotation tags.
function BookTagMenu.merge_existing_tags(existing, selected)
    local combined = {}
    for _, id in ipairs(existing or {}) do combined[#combined + 1] = id end
    if type(selected) == "table" then
        if #selected > 0 then
            for _, id in ipairs(selected) do combined[#combined + 1] = id end
        else
            for id, enabled in pairs(selected) do
                if enabled then combined[#combined + 1] = id end
            end
        end
    end
    return Tags.normalize_list(combined)
end

local function count_selected(selected)
    local count = 0
    for _, enabled in pairs(selected) do
        if enabled then count = count + 1 end
    end
    return count
end

function BookTagMenu.show(plugin, hl, current_index, ann, opts)
    opts = opts or {}
    local bank = TagBank.ensure_bank(plugin.settings)
    local annotations = hl and hl.ui and hl.ui.annotation
        and hl.ui.annotation.annotations or {}
    local context = HighlightContext.get(hl, ann)
    local query = context
    if ann.note and ann.note ~= "" then
        query = query .. " " .. ann.note
    end
    local existing = Tags.get_tags(ann)
    local result = BookTagSuggestions.suggest(query, annotations, bank, {
        current_annotation = ann,
        current_index = current_index,
        existing_tags = existing,
    })
    local selected = {}
    for _, candidate in ipairs(result.suggestions) do
        selected[candidate.id] = true
    end

    local menu
    local function close_and_return()
        UIManager:close(menu)
        if opts.on_back then opts.on_back() end
    end

    local function refresh()
        if menu then menu:updateItems() end
    end

    local function toggle(id)
        selected[id] = not selected[id]
        refresh()
    end

    local items = {
        {
            text = "← " .. _("Back"),
            keep_menu_open = true,
            callback = close_and_return,
        },
    }

    if #result.suggestions == 0 and #result.recent == 0 then
        items[#items + 1] = {
            text = _("No suggestions yet. Tag more highlights in this book first."),
            dim = true,
            enabled = false,
            keep_menu_open = true,
        }
    else
        items[#items + 1] = {
            text = _("Apply selected"),
            mandatory_func = function()
                return tostring(count_selected(selected))
            end,
            keep_menu_open = true,
            callback = function()
                local merged = BookTagMenu.merge_existing_tags(
                    existing, selected_ids(selected))
                TagMenu.persist_applied_tags(hl, ann, merged, bank)
                close_and_return()
            end,
        }

        if #result.suggestions > 0 then
            items[#items + 1] = {
                text = _("Suggested (preselected)"),
                dim = true,
                enabled = false,
                keep_menu_open = true,
            }
            for _, candidate in ipairs(result.suggestions) do
                local id = candidate.id
                items[#items + 1] = {
                    text = candidate.name,
                    mandatory_func = function()
                        return selected[id] and CHECKMARK or ""
                    end,
                    keep_menu_open = true,
                    callback = function() toggle(id) end,
                }
            end
        end

        if #result.recent > 0 then
            items[#items + 1] = {
                text = _("Recent in this book"),
                dim = true,
                enabled = false,
                keep_menu_open = true,
            }
            for _, candidate in ipairs(result.recent) do
                local id = candidate.id
                items[#items + 1] = {
                    text = candidate.name,
                    mandatory_func = function()
                        return selected[id] and CHECKMARK or ""
                    end,
                    keep_menu_open = true,
                    callback = function() toggle(id) end,
                }
            end
        end
    end

    menu = Menu:new{
        title = _("Suggest tags from this book"),
        subtitle = T(_("Uses %1 other highlights"), tostring(math.max(0, #annotations - 1))),
        item_table = items,
    }
    UIManager:show(menu)
end

return BookTagMenu
