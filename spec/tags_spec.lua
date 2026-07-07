return function(assert_eq, assert_true, Tags)
    local list = Tags.normalize_list({ "Love", "#love", "love", "Grief" })
    assert_eq(#list, 2, "dedupe tags")
    assert_eq(list[1], "grief", "sorted grief")
    assert_eq(list[2], "love", "sorted love")

    local parsed = Tags.parse_input(" #love, grief ,love ")
    assert_eq(#parsed, 2, "parse input count")

    local ann = { text = "hi" }
    Tags.set_tags(ann, { "love" })
    assert_eq(#Tags.get_tags(ann), 1, "set tags")
    assert_eq(Tags.get_tags(ann)[1], "love", "get tag value")

    local merged = Tags.merge_annotation_tags(
        { text = "a", highlight_sync_tags = { "love" }, datetime = "2024-01-01 10:00:00" },
        { highlight_sync_tags = { "grief" } },
        { highlight_sync_tags = { "ideas" } }
    )
    assert_eq(#Tags.get_tags(merged), 3, "union count")

    local line = Tags.format_hashtag_line({ "love", "quotes" })
    assert_true(line:find("#love") ~= nil, "hashtag line")

    local bank = {
        { kind = "folder", id = "buddhism", name = "Buddhism", children = {
            { kind = "tag", id = "aversion", name = "aversion" },
        }},
    }
    local tagged = { highlight_sync_tags = { "aversion" } }
    Tags.stash_expanded_tags_for_library(tagged, bank)
    local prev = Tags.take_previous_expanded_tags(tagged)
    assert_eq(#prev, 2, "stashed expanded tags")
    assert_true(not tagged[Tags.PREV_EXPANDED_FIELD], "prev field cleared after take")

    tagged.text = "hello"
    tagged.highlight_sync_tags = { "aversion" }
    assert_true(Tags.needs_library_sync(tagged, bank), "needs library sync when hash missing")
    Tags.set_library_sync_state(tagged, Tags.compute_library_hash(tagged, prev))
    assert_true(not Tags.needs_library_sync(tagged, bank), "library sync skip when unchanged")

    local merged = { text = "newer", datetime = "2024-06-02 10:00:00" }
    Tags.merge_capture_metadata(merged, {
        highlight_sync_capture = "quotes/images/x.png",
        highlight_sync_capture_at = "2024-06-01 10:00:00",
    })
    assert_eq(merged.highlight_sync_capture, "quotes/images/x.png", "merge keeps capture from other copy")

    local util_mod = package.loaded["util"]
    local stub_md5 = util_mod.partialMD5
    util_mod.partialMD5 = function(s) return s end
    local capture_only = {
        text = "poem",
        highlight_sync_capture = "quotes/images/poem.png",
        highlight_sync_capture_at = "2024-06-01 10:00:00",
    }
    assert_true(Tags.needs_library_sync(capture_only, bank), "capture-only needs sync when hash missing")
    Tags.set_library_sync_state(capture_only, Tags.compute_library_hash(capture_only, {}))
    assert_true(not Tags.needs_library_sync(capture_only, bank), "capture-only skip when unchanged")
    capture_only.highlight_sync_capture_at = "2024-06-02 11:00:00"
    assert_true(Tags.needs_library_sync(capture_only, bank), "capture-only resync after re-capture")
    util_mod.partialMD5 = stub_md5
end
