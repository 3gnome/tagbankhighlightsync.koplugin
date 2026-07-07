-- Discover books in reading history that have syncable highlight sidecars.

local OutputSettings = require("output_settings")
local Merge = require("merge")

local SyncAllBooks = {}

local function file_exists(path)
    local lfs = _G.lfs
    if not lfs then
        local ok, mod = pcall(require, "libs/libkoreader-lfs")
        if ok then
            lfs = mod
        end
    end
    return path and lfs and lfs.attributes(path, "mode") == "file"
end

function SyncAllBooks.read_sidecar_annotations(doc_path)
    if not doc_path or doc_path == "" then
        return {}
    end
    local DocSettings = require("docsettings")
    local ok, doc_settings = pcall(DocSettings.open, DocSettings, doc_path)
    if not ok or not doc_settings then
        return {}
    end
    return doc_settings:readSetting("annotations") or {}
end

function SyncAllBooks.is_sync_disabled_for_path(doc_path)
    local DocSettings = require("docsettings")
    local ok, doc_settings = pcall(DocSettings.open, DocSettings, doc_path)
    if ok and doc_settings and doc_settings.isTrue then
        return doc_settings:isTrue("highlight_sync_disabled")
    end
    return false
end

function SyncAllBooks.count_syncable(annotations, settings)
    return #OutputSettings.filter_annotations(
        Merge.normalize_to_list(annotations or {}), settings)
end

function SyncAllBooks.title_for_path(doc_path, fallback)
    fallback = fallback or (doc_path or ""):gsub("^.*[/\\]", "")
    local DocSettings = require("docsettings")
    local ok, doc_settings = pcall(DocSettings.open, DocSettings, doc_path)
    if ok and doc_settings then
        local props = doc_settings:readSetting("doc_props")
        if props and props.title and props.title ~= "" then
            return props.title
        end
    end
    return fallback
end

--- @return table[] { path, title, count }
function SyncAllBooks.discover_books_with_syncable_highlights(current_doc_path, settings)
    settings = OutputSettings.merge_defaults(settings or {})
    local ReadHistory = require("readhistory")
    ReadHistory:reload(true)

    local seen = {}
    local books = {}

    local function add_book(path, title_hint, is_current)
        if not path or seen[path] then
            return
        end
        if SyncAllBooks.is_sync_disabled_for_path(path) then
            return
        end
        if not is_current and not file_exists(path) then
            return
        end
        local count = SyncAllBooks.count_syncable(
            SyncAllBooks.read_sidecar_annotations(path), settings)
        if count == 0 then
            return
        end
        seen[path] = true
        books[#books + 1] = {
            path = path,
            title = SyncAllBooks.title_for_path(path, title_hint or path:gsub("^.*[/\\]", "")),
            count = count,
            is_current = is_current == true,
        }
    end

    for _, entry in ipairs(ReadHistory.hist or {}) do
        if entry.select_enabled ~= false and entry.file then
            add_book(entry.file, entry.text, entry.file == current_doc_path)
        end
    end

    if current_doc_path and not seen[current_doc_path] then
        add_book(current_doc_path, current_doc_path:gsub("^.*[/\\]", ""), true)
    end

    for _, book in ipairs(books) do
        book.is_current = (book.path == current_doc_path)
    end

    table.sort(books, function(a, b)
        if a.is_current ~= b.is_current then
            return a.is_current
        end
        return a.title:lower() < b.title:lower()
    end)

    return books
end

return SyncAllBooks
