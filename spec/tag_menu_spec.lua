return function(assert_eq, assert_true, TagMenu)
    assert_eq(TagMenu.custom_tag_dest_path({ "buddhism" })[1], "buddhism",
        "dest path preserves folder")
    assert_eq(#TagMenu.custom_tag_dest_path({}), 0,
        "empty path is bank root")
    assert_eq(#TagMenu.custom_tag_dest_path(nil), 0,
        "nil path is bank root")

    assert_eq(TagMenu.folder_picker_mode(nil), TagMenu.FOLDER_PICKER_BROWSE,
        "default browse mode")
    assert_eq(TagMenu.folder_picker_mode({}), TagMenu.FOLDER_PICKER_BROWSE,
        "empty opts browse")
    assert_eq(TagMenu.folder_picker_mode({ mode = "browse" }), TagMenu.FOLDER_PICKER_BROWSE,
        "explicit browse")
    assert_eq(TagMenu.folder_picker_mode({ mode = "move" }), TagMenu.FOLDER_PICKER_MOVE,
        "move mode")
    assert_eq(TagMenu.folder_picker_mode({ mode = "other" }), TagMenu.FOLDER_PICKER_BROWSE,
        "unknown mode falls back to browse")

    assert_eq(TagMenu.add_tag_dest_picker_mode(), TagMenu.FOLDER_PICKER_MOVE,
        "Add to bank uses move picker tap-to-select")

    assert_true(TagMenu.should_pick_add_tag_folder({}), "picker at root")
    assert_true(TagMenu.should_pick_add_tag_folder(nil), "picker when path nil")
    assert_true(not TagMenu.should_pick_add_tag_folder({ "buddhism" }),
        "no picker inside folder")

    assert_true(TagMenu.skip_add_tag_actions({ "buddhism" }),
        "inside folder skips action dialog")
    assert_true(not TagMenu.skip_add_tag_actions({}), "at root shows action dialog")
    assert_true(not TagMenu.skip_add_tag_actions(nil), "nil path shows action dialog")

    local saved_annotations
    local updated = 0
    local target = {
        text = "same",
        pos0 = "/body/p[1].0",
        pos1 = "/body/p[1].4",
        datetime = "2024-01-01 10:00:00",
    }
    local stale_duplicate = {
        text = "same",
        pos0 = "/body/p[1].0",
        pos1 = "/body/p[1].4",
        datetime = "2024-01-01 09:00:00",
    }
    local hl = {
        ui = {
            annotation = {
                annotations = { stale_duplicate, target },
                updateAnnotations = function()
                    updated = updated + 1
                end,
            },
            doc_settings = {
                saveSetting = function(_, key, value)
                    if key == "annotations" then saved_annotations = value end
                end,
            },
        },
    }
    TagMenu.persist_applied_tags(hl, target, { "love" }, {})
    assert_eq(#hl.ui.annotation.annotations, 1,
        "tag persist dedupes same-position highlight stack")
    assert_eq(hl.ui.annotation.annotations[1].highlight_sync_tags[1], "love",
        "tag persist keeps edited annotation")
    assert_true(hl.ui.annotation.annotations[1].datetime_updated ~= nil,
        "tag persist marks annotation updated")
    assert_true(saved_annotations == hl.ui.annotation.annotations,
        "tag persist saves deduped annotations")
    assert_eq(updated, 1, "tag persist redraws annotations once")
end
