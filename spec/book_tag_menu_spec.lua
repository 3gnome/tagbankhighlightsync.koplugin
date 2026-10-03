return function(assert_eq, assert_true, BookTagMenu, TagMenu, Tags)
    local merged = BookTagMenu.merge_existing_tags(
        { "love", "themes" },
        { leadership = true, love = false, compassion = true })
    assert_eq(table.concat(merged, ","), "compassion,leadership,love,themes",
        "review additions merge without removing existing tags")

    merged = BookTagMenu.merge_existing_tags({ "love" }, { "themes", "love" })
    assert_eq(table.concat(merged, ","), "love,themes",
        "list selections merge and dedupe deterministically")

    local ann = { text = "quote", highlight_sync_tags = { "love" } }
    local annotations = { ann }
    local saved, updated
    local saved_value
    local hl = {
        ui = {
            annotation = {
                annotations = annotations,
                updateAnnotations = function(_, sidecar, redraw)
                    updated = sidecar and redraw
                end,
            },
            doc_settings = {
                saveSetting = function(_, key, value)
                    saved = key == "annotations"
                    saved_value = value
                end,
            },
        },
    }
    local bank = {
        {
            kind = "folder", id = "themes", name = "Themes", children = {
                { kind = "tag", id = "love", name = "Love" },
                { kind = "tag", id = "leadership", name = "Leadership" },
            },
        },
    }
    TagMenu.persist_applied_tags(hl, ann, { "love", "leadership" }, bank)
    assert_eq(table.concat(Tags.get_tags(ann), ","), "leadership,love",
        "review uses normalized tag persistence")
    assert_true(saved, "review persistence saves annotation sidecar")
    assert_true(saved_value == hl.ui.annotation.annotations and saved_value[1] == ann,
        "review persistence saves deduped live annotations")
    assert_true(updated, "review persistence refreshes KOReader annotations")
    assert_eq(table.concat(ann.highlight_sync_tags_prev_expanded, ","), "love,themes",
        "review persistence keeps prior expanded tags for library cleanup")
end
