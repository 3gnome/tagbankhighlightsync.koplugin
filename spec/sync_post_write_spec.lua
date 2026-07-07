return function(assert_eq, assert_true, SyncPostWrite)
    local logged = {}
    package.loaded["logger"] = {
        err = function(...)
            logged[#logged + 1] = table.concat({ ... }, " ")
        end,
        warn = function() end,
        info = function() end,
    }

    local ok = SyncPostWrite.safe_step("test step", function()
        error("boom")
    end)
    assert_true(not ok, "safe_step returns false on error")
    assert_true(#logged > 0, "safe_step logs error")

    local handled
    logged = {}
    local invoke_ok = SyncPostWrite.safe_invoke("upload follow-up", function()
        local function later(cb)
            cb(true)
        end
        later(function()
            error("upload boom")
        end)
    end, function(err)
        handled = err
    end)
    assert_true(not invoke_ok, "safe_invoke catches callback-style throw")
    assert_true(handled ~= nil and handled:find("upload boom", 1, true) ~= nil,
        "safe_invoke forwards follow-up error")
    assert_eq(SyncPostWrite.truncate_error(string.rep("x", 100), 10), "xxxxxxx...",
        "truncate_error shortens long messages")

    local refresh_annotations
    local host_full = {
        settings = { tagged_library_enabled = true },
        mirrorSyncFiles = function() end,
        persistMergedAnnotations = function() end,
        refreshLibraryFiles = function(self, ctx, annotations)
            refresh_annotations = annotations
        end,
    }
    package.loaded["export"] = {
        write_exports = function() end,
    }
    local full = { { text = "full ann", pos0 = "f0", pos1 = "f1" } }
    local merged = { { text = "merged only", pos0 = "m0", pos1 = "m1" } }
    SyncPostWrite.run(host_full, {
        sync_path = "/tmp/book.json",
        metadata = {},
    }, merged, full, false, false)
    assert_true(refresh_annotations == full, "library refresh uses full_annotations not merged")
    assert_eq(refresh_annotations[1].text, "full ann", "full annotation content preserved")

    local export_called = false
    local host_deferred = {
        settings = { tagged_library_enabled = true },
        mirrorSyncFiles = function() end,
        persistMergedAnnotations = function() end,
        refreshLibraryFiles = function()
            error("library refresh boom")
        end,
    }
    package.loaded["export"] = {
        write_exports = function()
            export_called = true
        end,
    }
    SyncPostWrite.run(host_deferred, {
        sync_path = "/tmp/book.json",
        metadata = {},
    }, {}, {}, false, true)
    assert_true(not export_called, "background defers export writes")

    logged = {}
    local host = {
        settings = { tagged_library_enabled = true },
        mirrorSyncFiles = function() end,
        persistMergedAnnotations = function() end,
        refreshLibraryFiles = function()
            error("library refresh boom")
        end,
    }
    package.loaded["export"] = {
        write_exports = function() end,
    }

    logged = {}
    local ran = SyncPostWrite.run(host, {
        sync_path = "/tmp/book.json",
        metadata = {},
    }, {}, {}, false, false)
    assert_true(ran, "run returns true when library refresh throws")
    assert_true(#logged > 0, "run logs library refresh failure")
end
