-- On-the-spot highlight region screenshot (capture now, sync later).

local DataStorage = require("datastorage")
local _ = require("gettext")
local Tags = require("tags")
local LibraryExport = require("library_export")

local HighlightCapture = {}

HighlightCapture.FIELD = Tags.CAPTURE_FIELD
HighlightCapture.AT_FIELD = Tags.CAPTURE_AT_FIELD

local function padding_size()
    local ok, Size = pcall(require, "ui/size")
    if ok and Size and Size.padding then
        return Size.padding.small
    end
    return 8
end

--- Union of screen rects with padding, clamped to screen bounds.
function HighlightCapture.union_rect(boxes, padding, max_w, max_h)
    if not boxes or #boxes == 0 then
        return nil
    end
    padding = padding or 0
    max_w = max_w or 99999
    max_h = max_h or 99999
    local x0, y0, x1, y1
    for _, box in ipairs(boxes) do
        local bx = box.x or 0
        local by = box.y or 0
        local bw = box.w or 0
        local bh = box.h or 0
        local rx0, ry0 = bx, by
        local rx1, ry1 = bx + bw, by + bh
        if not x0 then
            x0, y0, x1, y1 = rx0, ry0, rx1, ry1
        else
            x0 = math.min(x0, rx0)
            y0 = math.min(y0, ry0)
            x1 = math.max(x1, rx1)
            y1 = math.max(y1, ry1)
        end
    end
    x0 = math.max(0, math.floor(x0 - padding))
    y0 = math.max(0, math.floor(y0 - padding))
    x1 = math.min(max_w, math.ceil(x1 + padding))
    y1 = math.min(max_h, math.ceil(y1 + padding))
    local w = x1 - x0
    local h = y1 - y0
    if w <= 0 or h <= 0 then
        return nil
    end
    return { x = x0, y = y0, w = w, h = h }
end

--- True when rect fits inside screen dimensions (for crop validation).
function HighlightCapture.rect_in_bounds(rect, screen_w, screen_h)
    if not rect or not screen_w or not screen_h then
        return false, "rect_oob"
    end
    if rect.w <= 0 or rect.h <= 0 then
        return false, "rect_oob"
    end
    if rect.x < 0 or rect.y < 0 then
        return false, "rect_oob"
    end
    if rect.x + rect.w > screen_w or rect.y + rect.h > screen_h then
        return false, "rect_oob"
    end
    return true
end

local function capture_context(hl, ann)
    local ctx = {
        ann_pageno = ann and ann.pageno,
    }
    if hl and hl.ui and hl.ui.document then
        local doc = hl.ui.document
        if doc.getCurrentPage then
            ctx.current_page = doc:getCurrentPage()
        end
        if doc.getCurrentPos then
            ctx.current_pos = doc:getCurrentPos()
        end
    end
    return ctx
end

function HighlightCapture.get_visible_boxes(hl, index)
    if not hl or not index or not hl.getHighlightVisibleBoxes then
        return nil
    end
    return hl:getHighlightVisibleBoxes(index)
end

local function append_boxes(dest, src)
    if not src then
        return
    end
    for _, box in ipairs(src) do
        if box and (box.h or 0) ~= 0 then
            dest[#dest + 1] = box
        end
    end
end

--- Page boxes to screen coords when paging; rolling boxes are already screen coords.
function HighlightCapture.to_screen_boxes(hl, page, boxes)
    if not boxes or #boxes == 0 or not hl or not hl.view then
        return nil
    end
    if not hl.ui or not hl.ui.paging then
        return boxes
    end
    local view = hl.view
    local screen = {}
    for _, box in ipairs(boxes) do
        local s = view:pageToScreenTransform(page, box)
        if s then
            screen[#screen + 1] = s
        end
    end
    if #screen == 0 then
        return nil
    end
    return screen
end

function HighlightCapture.is_on_current_view(hl, ann)
    if not hl or not hl.ui or not ann then
        return false
    end
    local ui = hl.ui
    local doc = ui.document
    if not doc then
        return false
    end
    local view = hl.view
    if ui.paging then
        local pages = view and view.getCurrentPageList and view:getCurrentPageList() or {}
        if #pages == 0 and doc.getCurrentPage then
            pages = { doc:getCurrentPage() }
        end
        if ann.pageno then
            for _, page in ipairs(pages) do
                if ann.pageno == page then
                    return true
                end
            end
        end
        if ann.pos0 and ann.pos1 and ann.pos0.page and ann.pos1.page then
            for _, page in ipairs(pages) do
                if ann.pos0.page <= page and page <= ann.pos1.page then
                    return true
                end
            end
        end
        return false
    end
    if not ann.pos0 or not ann.pos1 then
        return ann.pageno ~= nil and doc.getCurrentPage and ann.pageno == doc:getCurrentPage()
    end
    if not doc.getCurrentPos or not doc.getPosFromXPointer then
        return true
    end
    local cur_top = doc:getCurrentPos()
    local dimen_h = ui.dimen and ui.dimen.h or 800
    local cur_bottom = cur_top + dimen_h
    if view and view.view_mode == "page" and doc.getVisiblePageCount
        and doc:getVisiblePageCount() > 1 then
        cur_bottom = cur_top + 2 * dimen_h
    end
    local start_pos = doc:getPosFromXPointer(ann.pos0)
    local end_pos = doc:getPosFromXPointer(ann.pos1)
    return end_pos >= cur_top and start_pos <= cur_bottom
end

local function copy_boxes(boxes)
    if not boxes or #boxes == 0 then
        return nil
    end
    local copy = {}
    for i, box in ipairs(boxes) do
        copy[i] = {
            x = box.x or 0,
            y = box.y or 0,
            w = box.w or 0,
            h = box.h or 0,
        }
    end
    return copy
end

local function boxes_from_visible_cache(hl, index)
    local raw = HighlightCapture.get_visible_boxes(hl, index)
    if not raw or #raw == 0 then
        return nil
    end
    if hl.ui and hl.ui.paging and hl.view and hl.view.getCurrentPageList then
        for _, page in ipairs(hl.view:getCurrentPageList()) do
            local screen = HighlightCapture.to_screen_boxes(hl, page, raw)
            if screen and #screen > 0 then
                return screen
            end
        end
        return nil
    end
    return raw
end

local function geometry_boxes_at_capture(hl, ann)
    if not hl or not hl.ui or not hl.ui.document or not ann then
        return nil
    end
    local doc = hl.ui.document
    local view = hl.view
    local boxes = {}

    if hl.ui.paging and view and view.getCurrentPageList and doc.getPageBoxesFromPositions then
        for _, page in ipairs(view:getCurrentPageList()) do
            local pos0, pos1 = ann.pos0, ann.pos1
            if type(ann.ext) == "table" and ann.ext[page] then
                pos0 = ann.ext[page].pos0 or pos0
                pos1 = ann.ext[page].pos1 or pos1
            end
            if pos0 and pos1 then
                local page_boxes = doc:getPageBoxesFromPositions(page, pos0, pos1)
                append_boxes(boxes, HighlightCapture.to_screen_boxes(hl, page, page_boxes))
            end
        end
    elseif doc.getScreenBoxesFromPositions and ann.pos0 and ann.pos1 then
        append_boxes(boxes, doc:getScreenBoxesFromPositions(ann.pos0, ann.pos1, true))
    end

    if #boxes > 0 then
        return boxes
    end
    return nil
end

--- Freeze painted highlight boxes while the user still sees them (before dialog close).
function HighlightCapture.snapshot_capture_boxes(hl, index, ann)
    if not hl or not ann then
        return nil
    end
    local boxes = boxes_from_visible_cache(hl, index)
    local source = "visible_snapshot"
    if not boxes or #boxes == 0 then
        boxes = geometry_boxes_at_capture(hl, ann)
        source = "geometry_snapshot"
    end
    boxes = copy_boxes(boxes)
    if not boxes then
        hl._tagbank_capture_boxes = nil
        hl._tagbank_capture_source = nil
        return nil
    end
    hl._tagbank_capture_boxes = boxes
    hl._tagbank_capture_source = source
    return boxes
end

--- Resolve screen-space boxes for capture (visible cache, then document geometry).
function HighlightCapture.resolve_capture_boxes(hl, index, ann)
    if not ann then
        return nil, "missing"
    end

    local boxes = boxes_from_visible_cache(hl, index)
    if boxes and #boxes > 0 then
        return boxes
    end

    if not hl or not hl.ui or not hl.ui.document then
        return nil, "no_geometry"
    end

    local doc = hl.ui.document
    local view = hl.view
    boxes = {}

    if hl.ui.paging and view and view.getCurrentPageList and doc.getPageBoxesFromPositions then
        for _, page in ipairs(view:getCurrentPageList()) do
            local pos0, pos1 = ann.pos0, ann.pos1
            if type(ann.ext) == "table" and ann.ext[page] then
                pos0 = ann.ext[page].pos0 or pos0
                pos1 = ann.ext[page].pos1 or pos1
            end
            if pos0 and pos1 then
                local page_boxes = doc:getPageBoxesFromPositions(page, pos0, pos1)
                append_boxes(boxes, HighlightCapture.to_screen_boxes(hl, page, page_boxes))
            end
        end
    elseif doc.getScreenBoxesFromPositions and ann.pos0 and ann.pos1 then
        append_boxes(boxes, doc:getScreenBoxesFromPositions(ann.pos0, ann.pos1, true))
    end

    if #boxes == 0 and hl.ui.paging and view and view.getCurrentPageList then
        for _, page in ipairs(view:getCurrentPageList()) do
            local pboxes = ann.pboxes
            if type(ann.ext) == "table" and ann.ext[page] and ann.ext[page].pboxes then
                pboxes = ann.ext[page].pboxes
            end
            append_boxes(boxes, HighlightCapture.to_screen_boxes(hl, page, pboxes))
        end
    elseif #boxes == 0 and hl.ui and hl.ui.paging then
        append_boxes(boxes, ann.pboxes)
    end

    if #boxes > 0 then
        return boxes
    end
    return nil, "no_geometry"
end

--- Invalidate KOReader's per-page highlight box cache (stale after scroll in rolling mode).
function HighlightCapture.invalidate_highlight_box_cache(hl)
    local view = hl and hl.view
    if view and view.resetHighlightBoxesCache then
        view:resetHighlightBoxesCache()
    end
end

--- Live geometry for capture: painted visible boxes first, then document geometry.
function HighlightCapture.resolve_shot_boxes(hl, index, ann)
    if not ann then
        return nil, "missing"
    end
    if not hl or not hl.ui or not hl.ui.document then
        return nil, "no_geometry"
    end

    local boxes = boxes_from_visible_cache(hl, index)
    if boxes and #boxes > 0 then
        return boxes
    end

    local doc = hl.ui.document
    local view = hl.view
    boxes = {}

    if hl.ui.paging and view and view.getCurrentPageList and doc.getPageBoxesFromPositions then
        for _, page in ipairs(view:getCurrentPageList()) do
            local pos0, pos1 = ann.pos0, ann.pos1
            if type(ann.ext) == "table" and ann.ext[page] then
                pos0 = ann.ext[page].pos0 or pos0
                pos1 = ann.ext[page].pos1 or pos1
            end
            if pos0 and pos1 then
                local page_boxes = doc:getPageBoxesFromPositions(page, pos0, pos1)
                append_boxes(boxes, HighlightCapture.to_screen_boxes(hl, page, page_boxes))
            end
        end
    elseif doc.getScreenBoxesFromPositions and ann.pos0 and ann.pos1 then
        append_boxes(boxes, doc:getScreenBoxesFromPositions(ann.pos0, ann.pos1, true))
    end

    if #boxes > 0 then
        return boxes
    end

    return nil, "no_geometry"
end

function HighlightCapture.is_partial_capture(ann, visible_count)
    if not ann or not visible_count or visible_count < 1 then
        return false
    end
    local pboxes = ann.pboxes
    if type(pboxes) == "table" and #pboxes > visible_count then
        return true
    end
    if type(ann.ext) == "table" then
        local page_count = 0
        for _ in pairs(ann.ext) do
            page_count = page_count + 1
        end
        if page_count > 1 then
            return true
        end
    end
    return false
end

function HighlightCapture.preflight(hl, index, ann)
    if not ann then
        return false, "missing"
    end
    local boxes = HighlightCapture.resolve_capture_boxes(hl, index, ann)
    if boxes and #boxes > 0 then
        return true, boxes
    end
    if not HighlightCapture.is_on_current_view(hl, ann) then
        return false, "wrong_page"
    end
    return false, "no_geometry"
end

function HighlightCapture.status_label(ann, preflight_ok, preflight_reason, partial)
    if not preflight_ok and preflight_reason == "wrong_page" then
        return _("Screenshot: open this page first")
    end
    if not preflight_ok and preflight_reason == "no_geometry" then
        return _("Screenshot: could not locate highlight")
    end
    if Tags.has_capture(ann) then
        if partial then
            return _("Screenshot: saved (partial)")
        end
        return _("Screenshot: saved")
    end
    return _("Screenshot: not captured")
end

local function is_nonblack(bb, x, y)
    local ok_px, color = pcall(function()
        return bb:getPixel(x, y)
    end)
    if not ok_px or not color then
        return false
    end
    if type(color) == "number" then
        return color ~= 0
    end
    return true
end

--- True when a Gray8 pixel looks like paper background, not text ink.
function HighlightCapture.should_whiten_gray8(v, threshold)
    threshold = threshold or 176
    v = v or 0
    return v >= threshold
end

--- True when a pixel looks like background (light gray / off-white), not text ink.
function HighlightCapture.should_whiten_rgb(r, g, b, threshold)
    threshold = threshold or 176
    r = r or 0
    g = g or 0
    b = b or 0
    return r >= threshold and g >= threshold and b >= threshold
end

local function pixel_gray8_value(color)
    if type(color) == "number" then
        return color
    end
    if color and color.getColor8 then
        local ok, c8 = pcall(function()
            return color:getColor8()
        end)
        if ok and c8 then
            if type(c8) == "number" then
                return c8
            end
            local a_ok, a_val = pcall(function()
                return c8.a
            end)
            if a_ok and a_val then
                return a_val
            end
        end
    end
    return nil
end

function HighlightCapture.normalize_light_background(bb, threshold)
    if not bb then
        return
    end
    threshold = threshold or 176
    local ok, Blitbuffer = pcall(require, "ffi/blitbuffer")
    if not ok or not Blitbuffer then
        return
    end
    local white_rgb = Blitbuffer.ColorRGB24 and Blitbuffer.ColorRGB24(0xFF, 0xFF, 0xFF)
    local white8 = Blitbuffer.Color8 and Blitbuffer.Color8(0xFF)
    local w = bb:getWidth()
    local h = bb:getHeight()
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local px_ok, color = pcall(function()
                return bb:getPixel(x, y)
            end)
            if not px_ok or not color then
                -- skip
            else
                local gray_v = pixel_gray8_value(color)
                if gray_v then
                    if HighlightCapture.should_whiten_gray8(gray_v, threshold) then
                        pcall(function()
                            if white8 then
                                bb:setPixel(x, y, white8)
                            elseif white_rgb then
                                bb:setPixel(x, y, white_rgb)
                            end
                        end)
                    end
                else
                    local rgb_ok, rgb = pcall(function()
                        return color:getColorRGB24()
                    end)
                    if rgb_ok and rgb
                        and HighlightCapture.should_whiten_rgb(rgb.r, rgb.g, rgb.b, threshold)
                        and white_rgb then
                        pcall(function()
                            bb:setPixel(x, y, white_rgb)
                        end)
                    end
                end
            end
        end
    end
end

local function detect_nonblack_bounds(bb)
    local max_w = bb:getWidth()
    local max_h = bb:getHeight()
    local first_x, last_x
    local nonblack_count = 0
    local sample_step_x = math.max(1, math.floor(max_w / 80))
    local sample_step_y = math.max(1, math.floor(max_h / 80))
    for x = 0, max_w - 1, sample_step_x do
        local found
        for y = 0, max_h - 1, sample_step_y do
            if is_nonblack(bb, x, y) then
                nonblack_count = nonblack_count + 1
                found = true
                break
            end
        end
        if found then
            first_x = first_x or x
            last_x = x
        end
    end
    return first_x, last_x, nonblack_count
end

local function crop_framebuffer(rect, final_path, debug_full_path)
    local Device = require("device")
    local Blitbuffer = require("ffi/blitbuffer")
    local Screen = Device.screen
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local in_bounds, bounds_err = HighlightCapture.rect_in_bounds(rect, screen_w, screen_h)
    if not in_bounds then
        return false, bounds_err
    end
    local bgr = Device:hasBGRFrameBuffer()
    if debug_full_path then
        Screen.bb:writePNG(debug_full_path, bgr)
    end
    local crop_bb = Blitbuffer.new(rect.w, rect.h, Screen.bb:getType())
    crop_bb:blitFrom(Screen.bb, 0, 0, rect.x, rect.y, rect.w, rect.h)
    pcall(function()
        detect_nonblack_bounds(crop_bb)
    end)
    HighlightCapture.normalize_light_background(crop_bb)
    crop_bb:writePNG(final_path, bgr)
    crop_bb:free()
    return true
end

local function persist_capture(hl, ann, relative_path)
    LibraryExport.invalidate_capture_upload_state(ann)
    ann[Tags.CAPTURE_FIELD] = relative_path
    ann[Tags.CAPTURE_AT_FIELD] = os.date("%Y-%m-%d %H:%M:%S")
    if hl and hl.ui and hl.ui.doc_settings then
        hl.ui.doc_settings:saveSetting("annotations", hl.ui.annotation.annotations)
    end
end

--- Capture highlight region to PNG; returns ok, err_key, partial.
function HighlightCapture.capture(hl, index, ann, opts)
    opts = opts or {}
    local partial = false
    LibraryExport.ensure_local_dirs()
    local final_path = LibraryExport.get_quote_image_path(ann)
    local relative_path = LibraryExport.get_capture_relative_path(ann)
    local debug_full_path = DataStorage:getDataDir() .. "/highlight_sync_capture_debug_full.png"

    local ok, err = pcall(function()
        local UIManager = require("ui/uimanager")
        if not opts.skip_invalidate then
            HighlightCapture.invalidate_highlight_box_cache(hl)
        end
        if not opts.skip_repaint then
            UIManager:forceRePaint()
        end

        local boxes = hl._tagbank_capture_boxes
        local box_source = hl._tagbank_capture_source or "snapshot"
        hl._tagbank_capture_boxes = nil
        hl._tagbank_capture_source = nil
        if not boxes or #boxes == 0 then
            boxes = HighlightCapture.resolve_shot_boxes(hl, index, ann)
            box_source = "live_fallback"
        end
        if not boxes or #boxes == 0 then
            if not HighlightCapture.is_on_current_view(hl, ann) then
                error("wrong_page")
            end
            error("no_geometry")
        end
        partial = HighlightCapture.is_partial_capture(ann, #boxes)

        local Device = require("device")
        local Screen = Device.screen
        local screen_w = Screen:getWidth()
        local screen_h = Screen:getHeight()
        local rect = HighlightCapture.union_rect(boxes, padding_size(), screen_w, screen_h)
        if not rect then
            error("bad_rect")
        end

        local crop_ok, crop_err = crop_framebuffer(rect, final_path, debug_full_path)
        if not crop_ok then
            error(crop_err or "crop_failed")
        end
    end)

    if not ok then
        local err_key = tostring(err)
        if err_key == "wrong_page" or err_key == "no_geometry" or err_key == "bad_rect" then
            return false, err_key, partial
        end
        return false, err_key, partial
    end

    persist_capture(hl, ann, relative_path)
    return true, nil, partial
end

--- Close hub/dialog, capture on next tick, toast, reopen hub.
function HighlightCapture.capture_from_hub(plugin, hl, index, ann, reopen_hub)
    local UIManager = require("ui/uimanager")
    -- Snapshot while the highlight is still painted (before any close/invalidate/repaint).
    HighlightCapture.snapshot_capture_boxes(hl, index, ann)

    local hub = hl and hl._tagbank_hub
    if hub then
        UIManager:close(hub)
        hl._tagbank_hub = nil
    end
    if hl and hl.highlight_dialog then
        UIManager:close(hl.highlight_dialog)
        hl.highlight_dialog = nil
    end

    -- Hide saved highlights so the crop is plain text (yellow is painted after page content).
    local view = hl and hl.view
    local prev_highlight_visible = view and view.highlight_visible
    if view then
        view.highlight_visible = false
    end

    local function restore_highlights()
        if view and prev_highlight_visible ~= nil then
            view.highlight_visible = prev_highlight_visible
        end
        UIManager:setDirty(nil, "full")
        UIManager:forceRePaint()
    end

    UIManager:setDirty(nil, "full")
    UIManager:forceRePaint()
    UIManager:nextTick(function()
        UIManager:nextTick(function()
            local ok, err_key, partial = HighlightCapture.capture(hl, index, ann, {
                skip_repaint = true,
                skip_invalidate = true,
            })
            restore_highlights()
            if ok then
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = partial and _("Screenshot saved (partial) — sync later")
                        or _("Screenshot saved — sync later"),
                    timeout = 2,
                })
            else
                local InfoMessage = require("ui/widget/infomessage")
                local msg
                if err_key == "wrong_page" then
                    msg = _("Open the page with this highlight, then try again.")
                elseif err_key == "no_geometry" then
                    msg = _("Could not locate highlight on screen.")
                else
                    msg = _("Could not save screenshot.")
                end
                UIManager:show(InfoMessage:new{
                    text = msg,
                    timeout = 3,
                })
            end
            if reopen_hub then
                reopen_hub()
            end
        end)
    end)
end

return HighlightCapture
