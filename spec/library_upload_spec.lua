return function(assert_eq, assert_true, LibraryUpload, LibraryExport, Tags, TagBank)
    local settings = { library_include_screenshots = true }
    local bank = {}
    local util_mod = package.loaded["util"]
    local orig_md5 = util_mod.partialMD5
    util_mod.partialMD5 = function(s)
        if s:find("/pos/a", 1, true) then
            return "aaa111"
        end
        if s:find("/pos/c", 1, true) then
            return "ccc333"
        end
        if s:find("/pos/z", 1, true) then
            return "zzz999"
        end
        return orig_md5(s)
    end

    local synced_tagged = {
        pos0 = "/pos/a",
        pos1 = "/pos/b",
        text = "tagged",
        highlight_sync_tags = { "love" },
    }
    local untagged_item = {
        pos0 = "/pos/c",
        pos1 = "/pos/d",
        text = "untagged",
        highlight_sync_capture = "quotes/images/def456.png",
    }
    local synced_path = LibraryExport.get_quote_path(synced_tagged)
    local untagged_path = LibraryExport.get_quote_path(untagged_item)
    local untagged_png = LibraryExport.get_quote_image_path(untagged_item)

    LibraryExport.ensure_local_dirs()
    local png_f = io.open(untagged_png, "wb")
    if png_f then
        png_f:write("fakepng")
        png_f:close()
    end

    local build_server = function(relative_dir)
        return { url = "/library/" .. relative_dir .. "/", type = "webdav" }
    end
    local jobs = LibraryUpload.collectScreenshotJobs(
        { synced_tagged, untagged_item }, settings, build_server)
    assert_true(#jobs >= 1, "screenshot job when local png exists")
    assert_eq(jobs[1].kind, "screenshot", "screenshot kind")
    assert_true(jobs[1].path:find("images/", 1, true) ~= nil, "png path")

    local synced_png_f = io.open(untagged_png .. ".sync", "wb")
    if synced_png_f then
        synced_png_f:write("synced")
        synced_png_f:close()
    end
    local synced_jobs = LibraryUpload.collectScreenshotJobs(
        { untagged_item }, settings, build_server)
    assert_eq(#synced_jobs, 0, "skip screenshot job when png.sync exists")
    os.remove(untagged_png .. ".sync")

    os.remove(untagged_png)

    local full_queue = {
        { path = "/library/master-quotes.md" },
        { path = untagged_png, kind = "screenshot" },
        { path = synced_path },
        { path = untagged_path },
    }
    Tags.set_library_sync_state(synced_tagged, Tags.compute_library_hash(synced_tagged,
        Tags.expand_for_export(Tags.get_tags(synced_tagged), bank)))
    local changed = LibraryUpload.collectChangedLibraryUploadQueue(
        full_queue, { synced_tagged, untagged_item }, bank, settings)
    local kinds = {}
    for _, job in ipairs(changed) do
        if job.kind == "screenshot" then
            kinds.screenshot = true
        end
        if job.path == untagged_path then
            kinds.untagged_md = true
        end
        if job.path == synced_path then
            kinds.synced_md = true
        end
        if job.path == full_queue[1].path then
            kinds.master = true
        end
    end
    assert_true(kinds.screenshot, "background includes screenshot")
    assert_true(kinds.untagged_md, "background includes untagged captured quote md")
    assert_true(not kinds.synced_md, "background skips unchanged tagged quote md")
    assert_true(not kinds.master, "background skips master when path is outside library root")

    local book_path = LibraryExport.get_book_path("alice.sdr")
    LibraryExport.write_file(book_path, "# Alice\n\nquote line\n")
    local book_queue = { { path = book_path } }
    local book_changed = LibraryUpload.collectChangedLibraryUploadQueue(
        book_queue, {}, bank, settings)
    assert_eq(#book_changed, 1, "background includes pending book md")
    local book_sync = io.open(book_path .. ".sync", "wb")
    if book_sync then
        book_sync:write("x")
        book_sync:close()
    end
    book_changed = LibraryUpload.collectChangedLibraryUploadQueue(
        book_queue, {}, bank, settings)
    assert_eq(#book_changed, 0, "background skips book md when .sync exists")
    os.remove(book_path .. ".sync")
    os.remove(book_path)

    local text_only = {
        pos0 = "/pos/t",
        pos1 = "/pos/u",
        text = "text only untagged",
    }
    local text_path = LibraryExport.get_quote_path(text_only)
    assert_true(LibraryUpload.target_needs_library_work(text_only, bank, settings),
        "untagged text needs library work when hash missing")
    Tags.set_library_sync_state(text_only, Tags.compute_library_hash(text_only, {}))
    assert_true(not LibraryUpload.target_needs_library_work(text_only, bank, settings),
        "untagged text skip when library hash matches")
    local util_mod = package.loaded["util"]
    local orig_md5 = util_mod.partialMD5
    util_mod.partialMD5 = function(s)
        if s:find("/pos/t", 1, true) then
            return "txtonly1"
        end
        return orig_md5(s)
    end
    text_only.pos0 = "/pos/t"
    Tags.set_library_sync_state(text_only, Tags.compute_library_hash(text_only, {}))
    assert_true(LibraryUpload.target_needs_library_work(text_only, bank, settings),
        "untagged missing quote file needs work even when hash matches")
    util_mod.partialMD5 = orig_md5
    Tags.set_library_sync_state(text_only, nil)
    text_only.highlight_sync_capture = "quotes/images/def456.png"
    local text_png = LibraryExport.get_quote_image_path(text_only)
    local text_png_f = io.open(text_png, "wb")
    if text_png_f then
        text_png_f:write("x")
        text_png_f:close()
    end
    assert_true(LibraryUpload.target_needs_library_work(text_only, bank, settings),
        "pending screenshot counts as library work")
    os.remove(text_png)

    local text_queue = {
        { path = "/library/master-quotes.md" },
        { path = text_path },
    }
    local text_changed = LibraryUpload.collectChangedLibraryUploadQueue(
        text_queue, { text_only }, bank, settings)
    local text_md_included = false
    for _, job in ipairs(text_changed) do
        if job.path == text_path then
            text_md_included = true
        end
    end
    assert_true(text_md_included, "background includes untagged text-only quote md")

    local mixed = {
        { path = "/z.md" },
        { path = untagged_png, kind = "screenshot" },
        { path = untagged_path },
    }
    local prioritized = LibraryUpload.prioritizeLibraryUploadQueue(mixed, untagged_item, function(item)
        return LibraryExport.get_quote_path(item)
    end)
    assert_eq(prioritized[1].kind, "screenshot", "screenshot first")
    assert_eq(prioritized[2].path, untagged_path, "target quote md second")

    LibraryExport.ensure_local_dirs()
    local cap_item = {
        pos0 = "/pos/z",
        pos1 = "/pos/w",
        highlight_sync_capture = "quotes/images/zzz.png",
    }
    local cap_png = LibraryExport.get_quote_image_path(cap_item)
    local cap_f = io.open(cap_png, "wb")
    if cap_f then
        cap_f:write("x")
        cap_f:close()
        assert_true(not LibraryUpload.verifyScreenshotUploads(cap_item),
            "verify fails without sync sidecar")
        os.remove(cap_png)
    end
    util_mod.partialMD5 = orig_md5
end
