return function(assert_eq, assert_true, SyncAllBooks)
    SyncAllBooks = SyncAllBooks or require("sync_all_books")

    package.loaded["readhistory"] = {
        hist = {
            { file = "/books/alice.epub", text = "alice.epub", select_enabled = true },
            { file = "/books/empty.epub", text = "empty.epub", select_enabled = true },
            { file = "/books/disabled.epub", text = "disabled.epub", select_enabled = true },
        },
        reload = function() end,
    }

    local sidecars = {
        ["/books/alice.epub"] = {
            { drawer = "lighten", text = "quote one" },
            { drawer = "lighten", text = "quote two" },
        },
        ["/books/empty.epub"] = {},
        ["/books/disabled.epub"] = {
            { drawer = "lighten", text = "hidden" },
        },
    }

    local disabled = {
        ["/books/disabled.epub"] = true,
    }

    package.loaded["docsettings"] = {
        open = function(_, path)
            return {
                readSetting = function(self, key)
                    if key == "annotations" then
                        return sidecars[path] or {}
                    end
                    if key == "doc_props" and path == "/books/alice.epub" then
                        return { title = "Alice" }
                    end
                    return nil
                end,
                isTrue = function(self, key)
                    return key == "highlight_sync_disabled" and disabled[path] == true
                end,
            }
        end,
    }

    _G.lfs = {
        attributes = function(path, attr)
            if attr == "mode" and path and path:match("%.epub$") then
                return "file"
            end
            return nil
        end,
    }

    local settings = { include_highlights = true, include_notes = true }

    assert_eq(SyncAllBooks.count_syncable(sidecars["/books/alice.epub"], settings), 2,
        "counts syncable highlights")
    assert_true(SyncAllBooks.is_sync_disabled_for_path("/books/disabled.epub"),
        "disabled flag read from sidecar")

    local books = SyncAllBooks.discover_books_with_syncable_highlights("/books/current.epub", settings)
    assert_eq(#books, 1, "only alice has syncable highlights")
    assert_eq(books[1].path, "/books/alice.epub", "alice path")
    assert_eq(books[1].title, "Alice", "alice title from doc_props")
end
