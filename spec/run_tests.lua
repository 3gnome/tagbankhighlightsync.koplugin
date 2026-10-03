#!/usr/bin/env luajit
-- Run: lua spec/run_tests.lua (from plugin root or spec/)

local root = arg[0]:match("(.*)[/\\]") or "."
if root:match("spec$") then
    package.path = package.path .. ";" .. root .. "/?.lua;" .. root .. "/../?.lua"
else
    package.path = package.path .. ";" .. root .. "/?.lua;" .. root .. "/spec/?.lua"
end

local function mock_gettext(_, fmt, ...)
    if select("#", ...) > 0 then
        local lua_fmt = fmt:gsub("%%(%d+)", "%%s")
        return string.format(lua_fmt, ...)
    end
    return setmetatable({ fmt = fmt }, {
        __index = {
            format = function(self, ...)
                local lua_fmt = self.fmt:gsub("%%(%d+)", "%%s")
                return string.format(lua_fmt, ...)
            end,
        },
    })
end
package.loaded["gettext"] = setmetatable({}, {
    __index = function(t, s) return s end,
    __call = mock_gettext,
})
_G._ = package.loaded["gettext"]

local _test_data_dir
local _test_data_dir_owned = false
package.loaded["datastorage"] = {
    getDataDir = function()
        if not _test_data_dir then
            _test_data_dir = os.getenv("HIGHLIGHTSYNC_TEST_DIR")
            if not _test_data_dir then
                _test_data_dir = os.tmpname():gsub("%..*", "") .. "_hs_test"
                _test_data_dir_owned = true
            end
        end
        return _test_data_dir
    end,
}
package.loaded["util"] = {
    makePath = function(path)
        if package.config:sub(1, 1) == "\\" then
            os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
        else
            os.execute('mkdir -p "' .. path .. '" 2>/dev/null')
        end
    end,
    partialMD5 = function() return "abc123" end,
    urlEncode = function(path, keep)
        return path
    end,
}
if not _G.lfs then
    local ok, mod = pcall(require, "libs/libkoreader-lfs")
    if ok then
        _G.lfs = mod
    end
end

local passed, failed = 0, 0

local function assert_eq(a, e, msg)
    if a ~= e then failed = failed + 1; print("FAIL:", msg, e, a); return end
    passed = passed + 1
end

local function assert_true(c, msg)
    if not c then failed = failed + 1; print("FAIL:", msg); return end
    passed = passed + 1
end

local Merge = require("merge")
local Export = require("export")
local OutputSettings = require("output_settings")
local Tags = require("tags")
local TagBank = require("tag_bank")
local LibraryExport = require("library_export")
local LibraryUpload = require("library_upload")
local CloudStorageCompat = require("cloudstorage_compat")
local FromHighlight = require("from_highlight")
local VerseLayout = require("verse_layout")
local HighlightCapture = require("highlight_capture")
local HighlightContext = require("highlight_context")
local BookTagSuggestions = require("book_tag_suggestions")
local BatchSync = require("batch_sync")
local SyncStatus = require("sync_status")
package.loaded["device"] = {
    hasWifiToggle = function() return true end,
    hasWifiRestore = function() return false end,
}
package.loaded["ui/network/manager"] = {
    isConnected = function() return false end,
    isWifiOn = function() return false end,
}
package.loaded["ui/uimanager"] = {
    nextTick = function(_, fn) if fn then fn() end end,
    scheduleIn = function(_, _, fn) if fn then fn() end end,
    show = function() end,
    close = function() end,
    forceRePaint = function() end,
}
package.loaded["ui/widget/infomessage"] = {
    new = function(_, args)
        return { text = args.text, timeout = args.timeout }
    end,
}
package.loaded["logger"] = package.loaded["logger"] or {
    err = function() end,
    warn = function() end,
    info = function() end,
}
_G.G_reader_settings = {
    _store = {},
    readSetting = function(_, key, default)
        return G_reader_settings._store[key] or default
    end,
    saveSetting = function(_, key, value)
        G_reader_settings._store[key] = value
    end,
}
local SyncBackground = require("sync_background")
package.loaded["logger"] = package.loaded["logger"] or {
    err = function() end,
    warn = function() end,
    info = function() end,
}
local SyncPostWrite = require("sync_post_write")
local PluginPeers = require("plugin_peers")
package.loaded["ui/widget/buttondialog"] = package.loaded["ui/widget/buttondialog"] or {}
package.loaded["ui/widget/confirmbox"] = package.loaded["ui/widget/confirmbox"] or {}
package.loaded["ui/widget/inputdialog"] = package.loaded["ui/widget/inputdialog"] or {}
package.loaded["ui/widget/menu"] = package.loaded["ui/widget/menu"] or {}
package.loaded["ffi/util"] = package.loaded["ffi/util"] or { template = function(s) return s end }
local TagMenu = require("tag_menu")
local BookTagMenu = require("book_tag_menu")
local SyncAllBooks = require("sync_all_books")

require("merge_spec")(assert_eq, assert_true, Merge)
require("export_spec")(assert_eq, assert_true, Export, OutputSettings)
require("verse_layout_spec")(assert_eq, assert_true, VerseLayout)
require("highlight_capture_spec")(assert_eq, assert_true, HighlightCapture, Tags)
require("highlight_context_spec")(assert_eq, assert_true, HighlightContext)
require("book_tag_suggestions_spec")(assert_eq, assert_true, BookTagSuggestions)
require("output_settings_spec")(assert_eq, assert_true, OutputSettings, Merge)
require("tags_spec")(assert_eq, assert_true, Tags)
require("tag_bank_spec")(assert_eq, assert_true, TagBank, Tags)
require("from_highlight_spec")(assert_eq, assert_true, FromHighlight, TagBank)
require("library_export_spec")(assert_eq, assert_true, LibraryExport, Merge, Tags)
require("library_upload_spec")(assert_eq, assert_true, LibraryUpload, LibraryExport, Tags, TagBank)
require("sync_now_untagged_spec")(assert_eq, assert_true, LibraryExport, LibraryUpload, Tags)
require("sync_background_spec")(assert_eq, assert_true, SyncBackground)
require("sync_post_write_spec")(assert_eq, assert_true, SyncPostWrite)
require("cloudstorage_compat_spec")(assert_eq, assert_true, CloudStorageCompat)
require("sync_progress_spec")(assert_eq, assert_true, require("sync_progress"))
require("sync_status_spec")(assert_eq, assert_true, SyncStatus)
require("batch_sync_spec")(assert_eq, assert_true, BatchSync)
require("plugin_peers_spec")(assert_eq, assert_true, PluginPeers)
require("tag_menu_spec")(assert_eq, assert_true, TagMenu)
require("book_tag_menu_spec")(assert_eq, assert_true, BookTagMenu, TagMenu, Tags)
require("sync_all_books_spec")(assert_eq, assert_true, SyncAllBooks)

print(string.format("Results: %d passed, %d failed", passed, failed))
if _test_data_dir_owned and _test_data_dir then
    if package.config:sub(1, 1) == "\\" then
        os.execute('rmdir /s /q "' .. _test_data_dir:gsub("/", "\\") .. '" 2>nul')
    else
        os.execute('rm -rf -- "' .. _test_data_dir .. '"')
    end
end
os.exit(failed > 0 and 1 or 0)
