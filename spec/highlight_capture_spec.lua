return function(assert_eq, assert_true, HighlightCapture, Tags)
    local boxes = {
        { x = 10, y = 20, w = 100, h = 30 },
        { x = 10, y = 55, w = 80, h = 25 },
    }
    local rect = HighlightCapture.union_rect(boxes, 5, 600, 800)
    assert_eq(rect.x, 5, "union x with padding")
    assert_eq(rect.y, 15, "union y with padding")
    assert_eq(rect.w, 110, "union width")
    assert_eq(rect.h, 70, "union height")

    local clamped = HighlightCapture.union_rect({ { x = 590, y = 790, w = 20, h = 20 } }, 10, 600, 800)
    assert_true(clamped.x + clamped.w <= 600, "clamped to screen width")
    assert_true(clamped.y + clamped.h <= 800, "clamped to screen height")

    assert_true(not HighlightCapture.union_rect({}, 0, 100, 100), "empty boxes nil")

    local in_bounds = HighlightCapture.rect_in_bounds({ x = 10, y = 20, w = 100, h = 50 }, 600, 800)
    assert_true(in_bounds, "rect inside screen")
    local oob_ok, oob_err = HighlightCapture.rect_in_bounds({ x = 550, y = 20, w = 100, h = 50 }, 600, 800)
    assert_true(not oob_ok, "rect past right edge rejected")
    assert_eq(oob_err, "rect_oob", "rect_oob error key")
    oob_ok = HighlightCapture.rect_in_bounds({ x = 0, y = 0, w = 0, h = 10 }, 600, 800)
    assert_true(not oob_ok, "zero width rejected")

    local ann = { pboxes = { {}, {}, {} } }
    assert_true(HighlightCapture.is_partial_capture(ann, 1), "partial when fewer visible boxes")

    local full = { pboxes = { {}, {} } }
    assert_true(not HighlightCapture.is_partial_capture(full, 2), "not partial when counts match")

    assert_true(
        HighlightCapture.status_label({}, true, nil, false) ~= nil,
        "status returned for untagged highlight"
    )
    local saved_label = HighlightCapture.status_label(
        { highlight_sync_capture = "quotes/images/x.png" },
        true, nil, false)
    assert_true(saved_label ~= nil and saved_label ~= "", "saved status returned")

    local mock_hl = {
        getHighlightVisibleBoxes = function()
            return { { x = 1, y = 1, w = 10, h = 10 } }
        end,
    }
    local ok, reason = HighlightCapture.preflight(mock_hl, 1, { text = "hi" })
    assert_true(ok, "preflight ok without tags when on page")
    ok, reason = HighlightCapture.preflight(nil, 1, { text = "hi" })
    assert_true(not ok, "preflight fails without hl")
    assert_eq(reason, "wrong_page", "missing hl means wrong page")

    -- Fallback when visible_boxes cache is empty but document geometry exists.
    local fallback_ann = {
        text = "poem",
        pageno = 67,
        pos0 = { page = 67 },
        pos1 = { page = 67 },
        pboxes = { { x = 10, y = 20, w = 100, h = 30 } },
    }
    local fallback_hl = {
        ui = {
            paging = true,
            document = {
                getPageBoxesFromPositions = function(page, pos0, pos1)
                    if page == 67 then
                        return { { x = 10, y = 20, w = 100, h = 30 } }
                    end
                end,
            },
        },
        view = {
            getCurrentPageList = function() return { 67 } end,
            pageToScreenTransform = function(_, page, box)
                if page == 67 and box then
                    return { x = box.x + 5, y = box.y + 5, w = box.w, h = box.h }
                end
            end,
        },
        getHighlightVisibleBoxes = function()
            return {}
        end,
    }
    ok, reason = HighlightCapture.preflight(fallback_hl, 1, fallback_ann)
    assert_true(ok, "preflight ok via document fallback when cache empty")
    assert_true(type(reason) == "table" and #reason > 0, "returns screen boxes")
    assert_eq(reason[1].x, 15, "paging transform applied")

    local rolling_ann = {
        text = "rolling",
        pos0 = "p0",
        pos1 = "p1",
        pboxes = { { x = 300, y = 600, w = 100, h = 30 } },
    }
    local rolling_hl = {
        ui = {
            paging = false,
            dimen = { h = 800 },
            document = {
                getScreenBoxesFromPositions = function()
                    return nil
                end,
                getCurrentPos = function()
                    return 100
                end,
                getPosFromXPointer = function(pos)
                    if pos == "p0" then
                        return 200
                    end
                    return 300
                end,
            },
        },
        view = {},
        getHighlightVisibleBoxes = function()
            return {}
        end,
    }
    ok, reason = HighlightCapture.preflight(rolling_hl, 1, rolling_ann)
    assert_true(not ok, "rolling preflight rejects stale pboxes fallback")
    assert_eq(reason, "no_geometry", "rolling fallback now requires live geometry")

    local rolling_live_hl = {
        ui = {
            paging = false,
            dimen = { h = 800 },
            document = {
                getScreenBoxesFromPositions = function()
                    return { { x = 40, y = 50, w = 60, h = 20 } }
                end,
                getCurrentPos = function()
                    return 100
                end,
                getPosFromXPointer = function(pos)
                    if pos == "p0" then
                        return 200
                    end
                    return 300
                end,
            },
        },
        view = {},
        getHighlightVisibleBoxes = function()
            return {}
        end,
    }
    ok, reason = HighlightCapture.preflight(rolling_live_hl, 1, rolling_ann)
    assert_true(ok, "rolling preflight accepts live screen boxes")
    assert_eq(reason[1].x, 40, "rolling keeps live screen box coords")

    local shot_ann = { pos0 = "poem0", pos1 = "poem1" }
    local shot_hl = {
        ui = {
            paging = false,
            document = {
                getScreenBoxesFromPositions = function(_, pos0)
                    if pos0 == "poem0" then
                        return { { x = 50, y = 900, w = 800, h = 28 } }
                    end
                end,
            },
        },
        view = {
            resetHighlightBoxesCache = function() end,
        },
        getHighlightVisibleBoxes = function()
            return {}
        end,
    }
    local shot_boxes = HighlightCapture.resolve_shot_boxes(shot_hl, 1, shot_ann)
    assert_true(shot_boxes and #shot_boxes == 1, "shot geometry returns live boxes")
    assert_eq(shot_boxes[1].y, 900, "shot boxes fall back to geometry when visible empty")

    shot_hl.getHighlightVisibleBoxes = function()
        return { { x = 136, y = 648, w = 276, h = 27 } }
    end
    shot_boxes = HighlightCapture.resolve_shot_boxes(shot_hl, 1, shot_ann)
    assert_eq(shot_boxes[1].y, 648, "shot boxes prefer painted visible boxes")

    local snap_ann = { pos0 = "snap0", pos1 = "snap1" }
    local snap_hl = {
        ui = { paging = false, document = {} },
        view = {},
        getHighlightVisibleBoxes = function()
            return { { x = 120, y = 340, w = 280, h = 24 }, { x = 120, y = 370, w = 260, h = 24 } }
        end,
    }
    local visible = {
        { x = 120, y = 340, w = 280, h = 24 },
        { x = 120, y = 370, w = 260, h = 24 },
    }
    snap_hl.getHighlightVisibleBoxes = function()
        return visible
    end
    snap_boxes = HighlightCapture.snapshot_capture_boxes(snap_hl, 3, snap_ann)
    assert_true(snap_boxes and #snap_boxes == 2, "snapshot stores visible boxes")
    assert_eq(snap_hl._tagbank_capture_source, "visible_snapshot", "snapshot source visible")
    visible[1].y = 999
    assert_eq(snap_boxes[1].y, 340, "snapshot copy independent of live visible boxes")

    local wrong_page_ann = {
        pageno = 10,
        pos0 = { page = 10 },
        pos1 = { page = 10 },
    }
    local wrong_page_hl = {
        ui = {
            paging = true,
            document = { getCurrentPage = function() return 67 end },
        },
        view = {
            getCurrentPageList = function() return { 67 } end,
        },
        getHighlightVisibleBoxes = function() return {} end,
    }
    ok, reason = HighlightCapture.preflight(wrong_page_hl, 1, wrong_page_ann)
    assert_true(not ok, "preflight fails on wrong page")
    assert_eq(reason, "wrong_page", "wrong page reason")
    local wrong_label = HighlightCapture.status_label(wrong_page_ann, false, reason, false)
    assert_true(wrong_label ~= nil and wrong_label ~= "", "wrong page subtitle")

    assert_true(Tags.has_capture({ highlight_sync_capture = "quotes/images/x.png" }), "has_capture true")
    assert_true(not Tags.has_capture({ text = "hi" }), "has_capture false when unset")

    assert_true(HighlightCapture.should_whiten_rgb(240, 240, 240), "light gray whitens")
    assert_true(HighlightCapture.should_whiten_rgb(255, 255, 255), "white whitens")
    assert_true(not HighlightCapture.should_whiten_rgb(175, 240, 240), "below threshold on one channel")
    assert_true(not HighlightCapture.should_whiten_rgb(50, 50, 50), "dark text preserved")
    assert_true(not HighlightCapture.should_whiten_rgb(120, 120, 120), "mid gray preserved")

    assert_true(HighlightCapture.should_whiten_gray8(204), "paper gray 0xCC whitens")
    assert_true(HighlightCapture.should_whiten_gray8(176), "threshold gray whitens")
    assert_true(not HighlightCapture.should_whiten_gray8(96), "dark ink preserved")
    assert_true(not HighlightCapture.should_whiten_gray8(120), "mid gray ink preserved")

    local mock_pixels = {
        { 204, 204, 204, 204, 50 },
        { 204, 50, 204, 204, 204 },
    }
    local bb = {
        w = 5,
        h = 2,
        pixels = mock_pixels,
        getWidth = function(self) return self.w end,
        getHeight = function(self) return self.h end,
        getPixel = function(self, x, y)
            return self.pixels[y + 1][x + 1]
        end,
        setPixel = function(self, x, y, white)
            if white == 255 then
                self.pixels[y + 1][x + 1] = 255
            end
        end,
    }
    package.loaded["ffi/blitbuffer"] = {
        Color8 = function(v) return v end,
        ColorRGB24 = function(r, g, b) return 255 end,
    }
    HighlightCapture.normalize_light_background(bb, 176)
    assert_eq(bb.pixels[1][1], 255, "gray8 background whitened")
    assert_eq(bb.pixels[1][5], 50, "dark text preserved after normalize")
    assert_eq(bb.pixels[2][2], 50, "dark text preserved row 2")
    package.loaded["ffi/blitbuffer"] = nil
end
