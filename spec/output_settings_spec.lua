return function(assert_eq, assert_true, OutputSettings, Merge)
    local settings = OutputSettings.merge_defaults({
        include_highlights = true,
        include_notes = true,
        include_page_bookmarks = false,
    })
    local highlight = { drawer = "lighten", text = "hi", pos0 = "a", pos1 = "b" }
    local note = { drawer = "lighten", text = "hi", note = "n", pos0 = "c", pos1 = "d" }
    local bookmark = { text = "bm", pos0 = "e", pos1 = "f" }
    local filtered = OutputSettings.filter_annotations({ highlight, note, bookmark }, settings)
    assert_eq(#filtered, 2, "filter excludes bookmarks by default")
    assert_true(OutputSettings.is_syncable_annotation(highlight, settings), "highlight syncable")
    assert_true(not OutputSettings.is_syncable_annotation(bookmark, settings), "bookmark not syncable")

    local payload = OutputSettings.prepare_for_write({ highlight, bookmark }, settings, {
        book_title = "Book",
        device_id = "dev",
        sync_datetime = "2026-01-01 10:00:00",
    })
    assert_eq(#Merge.normalize_to_list(payload), 1, "prepare_for_write filters payload")

    local legacy = { library_export_version = 1 }
    OutputSettings.merge_defaults(legacy)
    assert_eq(legacy.library_export_version, 2, "export version migrated")
    assert_true(legacy.library_force_reupload, "force reupload on migration")
end
