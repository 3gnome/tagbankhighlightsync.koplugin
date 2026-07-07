-- Highlight dialog entry: Tag & sync hub.

local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local FFIUtil = require("ffi/util")
local T = FFIUtil.template
local _ = require("gettext")
local TagMenu = require("tag_menu")
local VerseLayout = require("verse_layout")
local HighlightCapture = require("highlight_capture")
local Tags = require("tags")

local TagDialog = {}

local HIGHLIGHT_DIALOG_ID = "99_highlightsync_tag"

function TagDialog.get_dialog_id()
    return HIGHLIGHT_DIALOG_ID
end

--- Resolve annotation index from the highlight dialog (nil index = new unsaved selection).
function TagDialog.resolve_highlight_index(hl, index)
    if not hl or not hl.ui or not hl.ui.annotation then
        return nil, nil
    end
    local annotations = hl.ui.annotation.annotations
    if index and annotations[index] then
        return index, annotations[index]
    end
    if hl.selected_text and hl.selected_text.pos0 and hl.saveHighlight then
        local new_index = hl:saveHighlight(true)
        if new_index and annotations[new_index] then
            return new_index, annotations[new_index]
        end
    end
    return nil, nil
end

local function persist_quote_layout(hl, ann, mode)
    VerseLayout.set_quote_layout(ann, mode)
    if hl and hl.ui and hl.ui.doc_settings then
        hl.ui.doc_settings:saveSetting("annotations", hl.ui.annotation.annotations)
    end
    if hl and hl.ui and hl.ui.annotation then
        hl.ui.annotation:updateAnnotations(true, true)
    end
end

local function quote_layout_subtitle(ann)
    return T(_("Quote layout: %1"), VerseLayout.layout_label(VerseLayout.get_quote_layout(ann)))
end

local function screenshot_subtitle(hl, index, ann)
    local ok, boxes_or_reason = HighlightCapture.preflight(hl, index, ann)
    local box_count = ok and type(boxes_or_reason) == "table" and #boxes_or_reason or 0
    local partial = ok and HighlightCapture.is_partial_capture(ann, box_count)
    local reason = ok and nil or boxes_or_reason
    return HighlightCapture.status_label(ann, ok, reason, partial)
end

local function capture_enabled(hl, index, ann)
    local ok = HighlightCapture.preflight(hl, index, ann)
    return ok
end

function TagDialog.show_quote_layout_chooser(plugin, hl, index, ann)
    local chooser
    local function pick(mode)
        UIManager:close(chooser)
        persist_quote_layout(hl, ann, mode)
        TagDialog.show_hub(plugin, hl, index)
    end

    chooser = ButtonDialog:new{
        title = _("Quote layout"),
        buttons = {
            {
                {
                    text = _("Auto"),
                    callback = function() pick("auto") end,
                },
                {
                    text = _("Verse"),
                    callback = function() pick("verse") end,
                },
            },
            {
                {
                    text = _("Prose"),
                    callback = function() pick("prose") end,
                },
                {
                    text = _("Back"),
                    callback = function()
                        UIManager:close(chooser)
                        TagDialog.show_hub(plugin, hl, index)
                    end,
                },
            },
        },
    }
    UIManager:show(chooser)
end

function TagDialog.show_hub(plugin, hl, index)
    local resolved_index, ann = TagDialog.resolve_highlight_index(hl, index)
    if not ann then
        UIManager:show(InfoMessage:new{
            text = _("Could not find this highlight."),
            timeout = 2,
        })
        return
    end

    if hl and hl.dialog then
        UIManager:setDirty(hl.dialog, "ui")
    end

    local hub
    hub = ButtonDialog:new{
        title = _("Tag & sync"),
        title_align_center = true,
        buttons = {
            {
                {
                    text = _("Tag highlight"),
                    callback = function()
                        UIManager:close(hub)
                        TagMenu.show_apply(plugin, hl, resolved_index, ann, {
                            on_back = function()
                                TagDialog.show_hub(plugin, hl, resolved_index)
                            end,
                        })
                    end,
                },
            },
            {
                {
                    text = _("Quote layout"),
                    callback = function()
                        UIManager:close(hub)
                        TagDialog.show_quote_layout_chooser(plugin, hl, resolved_index, ann)
                    end,
                },
            },
            {
                {
                    text = quote_layout_subtitle(ann),
                    align = "left",
                    enabled = false,
                },
            },
            {
                {
                    text = _("Capture with screenshot"),
                    enabled = capture_enabled(hl, resolved_index, ann),
                    callback = function()
                        HighlightCapture.capture_from_hub(plugin, hl, resolved_index, ann, function()
                            TagDialog.show_hub(plugin, hl, resolved_index)
                        end)
                    end,
                },
            },
            {
                {
                    text = screenshot_subtitle(hl, resolved_index, ann),
                    align = "left",
                    enabled = false,
                },
            },
            {
                {
                    text = _("Sync now"),
                    callback = function()
                        UIManager:close(hub)
                        if hl.highlight_dialog then
                            UIManager:close(hl.highlight_dialog)
                            hl.highlight_dialog = nil
                        end
                        plugin:syncNow(hl, resolved_index, ann)
                    end,
                },
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(hub)
                    end,
                },
            },
        },
    }
    hl._tagbank_hub = hub
    UIManager:show(hub)
end

function TagDialog.register_highlight_dialog(plugin)
    if not plugin.ui or not plugin.ui.highlight then
        return
    end
    plugin.ui.highlight:addToHighlightDialog(HIGHLIGHT_DIALOG_ID, function(hl, index)
        return {
            text = _("Tag & sync…"),
            enabled = true,
            callback = function()
                TagDialog.show_hub(plugin, hl, index)
            end,
        }
    end)
end

return TagDialog
