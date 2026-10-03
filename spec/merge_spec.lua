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

    local same_start_a = {
        page = "p", pos0 = "/body/p[1].0", pos1 = "/body/p[1].5", text = "short",
    }
    local same_start_b = {
        page = "p", pos0 = "/body/p[1].0", pos1 = "/body/p[1].12", text = "longer",
    }
    local same_start_merge = Merge.Merge_highlights(
        { same_start_a }, { same_start_b }, {})
    assert_eq(#same_start_merge, 2,
        "same pos0 with different pos1 remains separate highlights")

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

    local local_duplicate_merge = Merge.Merge_highlights({
        {
            page = "p", pos0 = "split", pos1 = "end",
            datetime = "2024-01-01 10:00:00",
            highlight_sync_tags = { "love" },
            highlight_sync_capture = "quotes/images/local.png",
        },
        {
            page = "p", pos0 = "split", pos1 = "end",
            datetime_updated = "2024-06-01 10:00:00",
            highlight_sync_tags = { "grief" },
        },
    }, {}, {})
    assert_eq(#local_duplicate_merge, 1,
        "merge input dedupes same-position local annotations")
    local split_tags = local_duplicate_merge[1].highlight_sync_tags or {}
    table.sort(split_tags)
    assert_eq(table.concat(split_tags, ","), "grief,love",
        "merge input dedupe preserves split local tags")
    assert_eq(local_duplicate_merge[1].highlight_sync_capture, "quotes/images/local.png",
        "merge input dedupe preserves split local capture")

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

    local duplicate_full = {
        bookmark,
        {
            page = "p", pos0 = "dup", pos1 = "end", text = "old copy",
            datetime = "2024-01-01 10:00:00",
        },
        {
            page = "p", pos0 = "dup", pos1 = "end", text = "new copy",
            datetime_updated = "2024-06-01 10:00:00",
        },
    }
    local duplicate_merged = {
        {
            page = "p", pos0 = "dup", pos1 = "end", text = "merged copy",
            datetime_updated = "2024-06-02 10:00:00",
        },
    }
    local deduped = Merge.merge_back_into_full(
        duplicate_full, duplicate_merged,
        function(item) return item.pos0 == "dup" end)
    assert_eq(#deduped, 2,
        "merge_back emits one syncable annotation for duplicate positions")
    assert_eq(deduped[2].text, "merged copy",
        "merge_back keeps merged duplicate winner")

    local duplicate_non_syncable = Merge.merge_back_into_full(
        {
            { page = "p", pos0 = "ns", pos1 = "end", text = "note one" },
            { page = "p", pos0 = "ns", pos1 = "end", text = "note two" },
        },
        {},
        function() return false end)
    assert_eq(#duplicate_non_syncable, 2,
        "merge_back preserves same-position non-syncable annotations")

    local deduped_annotations = Merge.dedupe_annotations({
        {
            page = "p", pos0 = "m", pos1 = "n",
            datetime = "2024-01-01 10:00:00",
            highlight_sync_tags = { "love" },
            highlight_sync_capture = "quotes/images/a.png",
        },
        {
            page = "p", pos0 = "m", pos1 = "n",
            datetime_updated = "2024-06-01 10:00:00",
            highlight_sync_tags = { "grief" },
        },
    }, function() return true end)
    assert_eq(#deduped_annotations, 1,
        "dedupe collapses same-position syncable annotations")
    local deduped_tags = deduped_annotations[1].highlight_sync_tags
    table.sort(deduped_tags)
    assert_eq(table.concat(deduped_tags, ","), "grief,love",
        "dedupe unions duplicate tags")
    assert_eq(deduped_annotations[1].highlight_sync_capture, "quotes/images/a.png",
        "dedupe preserves duplicate capture metadata")

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

    -- Tag deletion propagates: a tag removed on the newer side must not be
    -- re-added from the older side (which still carries it).
    local base_two_tags = {
        page = "p", pos0 = "rm", pos1 = "end",
        datetime = "2024-01-01 10:00:00",
        highlight_sync_tags = { "love", "grief" },
    }
    local local_removed = {
        page = "p", pos0 = "rm", pos1 = "end",
        datetime = "2024-06-01 10:00:00",
        highlight_sync_tags = { "love" },
    }
    local server_stale = {
        page = "p", pos0 = "rm", pos1 = "end",
        datetime = "2024-01-01 10:00:00",
        highlight_sync_tags = { "love", "grief" },
    }
    local removal_merge = Merge.Merge_highlights(
        { local_removed }, { server_stale }, { base_two_tags })
    local removal_tags = removal_merge[1].highlight_sync_tags or {}
    table.sort(removal_tags)
    assert_eq(table.concat(removal_tags, ","), "love",
        "tag removed on newer side propagates to stale side")
end
