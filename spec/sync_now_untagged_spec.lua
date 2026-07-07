return function(assert_eq, assert_true, LibraryExport, LibraryUpload, Tags)
    local include_settings = { library_include_untagged = true }
    local strict_settings = { library_include_untagged = false }
    local util_mod = package.loaded["util"]
    local orig_md5 = util_mod.partialMD5
    util_mod.partialMD5 = function(s)
        if s:find("/pos/u0", 1, true) then
            return "syncnow1"
        end
        return orig_md5(s)
    end
    local ann = {
        pos0 = "/pos/u0",
        pos1 = "/pos/u1",
        text = "untagged verse for sync now",
    }

    assert_true(LibraryExport.is_untagged_library_export(ann, include_settings),
        "untagged exportable when include_untagged on")
    assert_true(not LibraryExport.is_untagged_library_export(ann, strict_settings),
        "untagged export blocked when include_untagged off")
    assert_true(not LibraryExport.is_untagged_library_export(
        { pos0 = "t", pos1 = "u", text = "x", highlight_sync_tags = { "love" } },
        include_settings), "tagged item is not untagged export")

    Tags.set_library_sync_state(ann, Tags.compute_library_hash(ann, {}))
    assert_true(not Tags.needs_library_sync(ann, {}), "hash matches after set")
    assert_true(LibraryUpload.target_needs_library_work(ann, {}, include_settings),
        "missing local quote still needs library work")

    LibraryExport.ensure_local_dirs()
    LibraryExport.write_atomic_quote(ann, {
        book_title = "Book",
        sidecar_name = "book.sdr",
        filename = "book.sdr",
    }, include_settings)
    assert_true(not LibraryUpload.target_needs_library_work(ann, {}, include_settings),
        "skip when hash matches and quote file exists")
    LibraryExport.remove_atomic_quote(ann)
    util_mod.partialMD5 = orig_md5
end
