return function(assert_eq, assert_true, Merge)
    local arr = { { page = "a", pos0 = "a", pos1 = "b" } }
    assert_eq(#Merge.normalize_to_list(arr), 1, "array normalize")

    local map = { abc = { page = "a", pos0 = "a", pos1 = "b" } }
    assert_eq(#Merge.normalize_to_list(map), 1, "map normalize")

    local pdf_h = {
        page = 5,
        pos0 = { page = 5, x = 100, y = 200 },
        pos1 = { page = 5, x = 150, y = 250 },
    }
    local key1 = Merge.generate_key(pdf_h)
    local key2 = Merge.generate_key(pdf_h)
    assert_eq(key1, key2, "PDF key stable")
    assert_true(not key1:match("^table:"), "PDF key not table pointer")

    local older = { page = "p", pos0 = "p", pos1 = "q", datetime = "2020-01-01 10:00:00" }
    local newer = { page = "p", pos0 = "p", pos1 = "q", datetime = "2024-01-01 10:00:00", text = "updated" }
    local merged = Merge.Merge_highlights({ older }, { newer }, { older })
    assert_eq(merged[1].text, "updated", "newer wins")

    local cached = { { page = "x", pos0 = "x", pos1 = "y", datetime = "2020-01-01 10:00:00" } }
    local remote = { { page = "x", pos0 = "x", pos1 = "y", datetime = "2024-01-01 10:00:00" } }
    local after_delete = Merge.Merge_highlights({}, remote, cached)
    assert_eq(#after_delete, 0, "deleted locally stays deleted")

    local local_tagged = {
        page = "p", pos0 = "a", pos1 = "b",
        datetime = "2024-06-01 10:00:00",
        highlight_sync_tags = { "love" },
    }
    local remote_tagged = {
        page = "p", pos0 = "a", pos1 = "b",
        datetime = "2024-01-01 10:00:00",
        highlight_sync_tags = { "grief" },
    }
    local tag_merge = Merge.Merge_highlights({ local_tagged }, { remote_tagged }, { local_tagged })
    assert_eq(#tag_merge, 1, "tag merge one item")
    local tags = tag_merge[1].highlight_sync_tags or {}
    table.sort(tags)
    assert_eq(tags[1], "grief", "tag union grief")
    assert_eq(tags[2], "love", "tag union love")

    local bookmark = {
        page = "b", pos0 = "bm0", pos1 = "bm1", text = "bookmark only",
    }
    local highlight = {
        page = "p", pos0 = "a", pos1 = "b", text = "sync me",
        datetime = "2024-06-01 10:00:00",
    }
    local full = { bookmark, highlight }
    local merged_syncable = { highlight }
    local is_syncable = function(item)
        return item.pos0 == "a"
    end
    local persisted = Merge.merge_back_into_full(full, merged_syncable, is_syncable)
    assert_eq(#persisted, 2, "merge_back keeps non-syncable")
    assert_eq(persisted[1].text, "bookmark only", "bookmark preserved")
    assert_eq(persisted[2].text, "sync me", "syncable updated")

    local after_delete = Merge.merge_back_into_full(
        { highlight, bookmark }, {}, is_syncable)
    assert_eq(#after_delete, 1, "merge_back drops deleted syncable only")
    assert_eq(after_delete[1].text, "bookmark only", "bookmark still present")

    local local_cap = {
        page = "p", pos0 = "a", pos1 = "b",
        datetime = "2024-06-01 10:00:00",
        highlight_sync_tags = { "love" },
        highlight_sync_capture = "quotes/images/abc.png",
        highlight_sync_capture_at = "2024-06-01 11:00:00",
    }
    local remote_newer = {
        page = "p", pos0 = "a", pos1 = "b",
        datetime = "2024-06-02 10:00:00",
        text = "edited on server",
        highlight_sync_tags = { "grief" },
    }
    local cap_merge = Merge.Merge_highlights({ local_cap }, { remote_newer }, { local_cap })
    assert_eq(cap_merge[1].text, "edited on server", "newer text wins")
    assert_eq(cap_merge[1].highlight_sync_capture, "quotes/images/abc.png", "capture preserved on merge")
end
