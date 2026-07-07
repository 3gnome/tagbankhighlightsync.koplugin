#!/usr/bin/env luajit
-- Rebuild library/ Markdown from all sidecar JSON files in a WebDAV folder (except alice).
-- Usage:
--   luajit spec/regen_library_from_json.lua "/path/to/KOReader Highlights" "/path/to/library"

local script_path = arg[0]:match("(.*/)") or "./"
local plugin_root = script_path .. ".."
local ko = (os.getenv("KOREADER_DIR") or (os.getenv("HOME") .. "/koreader-dev/emulator/usr/lib/koreader"))
package.path = package.path .. ";" .. plugin_root .. "/?.lua;" .. ko .. "/?.lua"
package.cpath = package.cpath .. ";" .. ko .. "/common/?.so"

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

local webdav_root = arg[1]
local out_root = arg[2]
if not webdav_root then
    io.stderr:write("Usage: luajit spec/regen_library_from_json.lua <webdav-root> [library/dir]\n")
    os.exit(1)
end
out_root = out_root or (webdav_root .. "/library")

local _test_data_dir = os.tmpname():gsub("%..*", "") .. "_hs_regen"
package.loaded["datastorage"] = {
    getDataDir = function() return _test_data_dir end,
}
-- Same fallback as library_export.quote_filename_from_key when partialMD5 is unavailable.
local function fallback_quote_hash(key)
    key = key or "quote"
    local h = 5381
    for i = 1, #key do
        h = (h * 33 + key:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end
package.loaded["util"] = {
    makePath = function(path)
        os.execute('mkdir -p "' .. path .. '" 2>/dev/null')
    end,
    partialMD5 = function(key)
        return fallback_quote_hash(key or "")
    end,
}

local Merge = require("merge")
local Tags = require("tags")
local TagBank = require("tag_bank")
local LibraryExport = require("library_export")

local BOOK_META = {
    ["Feeding_Your_Demons__Ancient_Wisdom_for_Resolving_Inner_Conflict_-_Tsultrim_Allione.sdr"] = {
        book_title = "Feeding Your Demons: Ancient Wisdom for Resolving Inner Conflict",
        doc_title = "Feeding Your Demons: Ancient Wisdom for Resolving Inner Conflict",
        author = "Tsultrim Allione",
    },
    ["Llewellyn_s_Complete_Book_of_Lucid_Dreaming_-_Clare_R._Johnson.sdr"] = {
        book_title = "Llewellyn's Complete Book of Lucid Dreaming",
        doc_title = "Llewellyn's Complete Book of Lucid Dreaming",
        author = "Clare R. Johnson",
    },
    ["Meditations__With_Selected_Correspondence__Oxford_World_s_Classics__-_Robin_Hard___Christopher_Gill.sdr"] = {
        book_title = "Meditations: With Selected Correspondence (Oxford World's Classics)",
        doc_title = "Meditations: With Selected Correspondence (Oxford World's Classics)",
        author = "Robin Hard Christopher Gill",
    },
}

local function read_json(path)
    local f = io.open(path, "r")
    if not f then
        error("Cannot read: " .. path)
    end
    local raw = f:read("*a")
    f:close()
    local rapidjson = require("rapidjson")
    return rapidjson.decode(raw)
end

local function copy_file(src, dst)
    local inf = io.open(src, "r")
    if not inf then
        return false
    end
    local content = inf:read("*a")
    inf:close()
    local dir = dst:match("^(.*)/[^/]+$")
    if dir then
        os.execute('mkdir -p "' .. dir .. '"')
    end
    local outf = io.open(dst, "w")
    if not outf then
        return false
    end
    outf:write(content)
    outf:close()
    return true
end

local function list_json_sidecars(root)
    local names = {}
    local pipe = io.popen('find "' .. root .. '" -maxdepth 1 -name "*.sdr.json" -printf "%f\\n" 2>/dev/null')
    if not pipe then
        return names
    end
    for name in pipe:lines() do
        if name ~= "alice.sdr.json" then
            names[#names + 1] = name
        end
    end
    pipe:close()
    table.sort(names)
    return names
end

local function list_md(dir)
    local names = {}
    local pipe = io.popen('find "' .. dir .. '" -maxdepth 1 -name "*.md" -printf "%f\\n" 2>/dev/null')
    if not pipe then
        return names
    end
    for name in pipe:lines() do
        names[#names + 1] = name
    end
    pipe:close()
    return names
end

local function rm_rf(path)
    os.execute('rm -rf "' .. path .. '" 2>/dev/null')
end

local settings = {
    tagged_library_enabled = true,
    library_include_untagged = true,
    library_use_callouts = true,
    library_metadata_style = "both",
    master_doc_filename = "master-quotes.md",
    tag_bank = TagBank.default_bank(),
}
TagBank.ensure_bank(settings)

LibraryExport.ensure_local_dirs()
LibraryExport.ensure_library_assets(settings)
rm_rf(LibraryExport.get_quotes_dir())
rm_rf(LibraryExport.get_images_dir())
rm_rf(LibraryExport.get_tags_dir())
rm_rf(LibraryExport.get_books_dir())
LibraryExport.ensure_local_dirs()

local master_path = LibraryExport.get_master_path(settings)
LibraryExport.write_file(master_path, "# Tagged quotes index\n\n")

local json_files = list_json_sidecars(webdav_root)
if #json_files == 0 then
    print("No sidecar JSON files found in " .. webdav_root)
    os.exit(1)
end

for _, json_name in ipairs(json_files) do
    local json_path = webdav_root .. "/" .. json_name
    local sidecar_name = json_name:gsub("%.json$", "")
    local filename = sidecar_name
    local meta = BOOK_META[sidecar_name] or {
        book_title = sidecar_name,
        doc_title = sidecar_name,
        author = "",
    }
    print("Processing " .. json_name)
    local annotations = read_json(json_path)
    local metadata = {
        book_title = meta.book_title,
        doc_title = meta.doc_title,
        author = meta.author,
        sidecar_name = sidecar_name,
        sync_datetime = os.date("%Y-%m-%d"),
        tag_bank = settings.tag_bank,
    }
    local lib_ctx = {
        book_title = metadata.book_title,
        doc_title = metadata.doc_title,
        author = metadata.author,
        sidecar_name = sidecar_name,
        filename = filename,
        tag_bank = settings.tag_bank,
        sync_datetime = metadata.sync_datetime,
    }
    local book_path = LibraryExport.get_book_path(filename)
    LibraryExport.update_book_file(book_path, annotations, settings, metadata)
    local master_content = LibraryExport.read_file(master_path)
    for _, item in ipairs(LibraryExport.collect_tagged(annotations, settings)) do
        master_content = LibraryExport.upsert_library_entry(master_content, item, lib_ctx, settings)
        LibraryExport.update_tag_indexes_for_annotation(item, lib_ctx, false, settings)
    end
    LibraryExport.write_file(master_path, master_content)
end

-- Replace deploy targets so stale Alice (or other removed book) files do not linger.
rm_rf(out_root .. "/quotes")
rm_rf(out_root .. "/tags")
rm_rf(out_root .. "/books")
os.execute('mkdir -p "' .. out_root .. '/books" "' .. out_root .. '/tags" "' .. out_root .. '/quotes" "' .. out_root .. '/templates"')

local ok = 0
local function deploy(local_path, rel)
    local dest = out_root .. "/" .. rel
    if copy_file(local_path, dest) then
        ok = ok + 1
        print("OK", dest)
    else
        print("MISSING", local_path)
    end
end

for _, json_name in ipairs(json_files) do
    local sidecar_name = json_name:gsub("%.json$", "")
    deploy(LibraryExport.get_book_path(sidecar_name), "books/" .. sidecar_name .. ".md")
end
deploy(master_path, "master-quotes.md")
deploy(LibraryExport.get_readme_path(), "README.md")
for _, name in ipairs(list_md(LibraryExport.get_templates_dir())) do
    deploy(LibraryExport.get_templates_dir() .. "/" .. name, "templates/" .. name)
end
local css_path = LibraryExport.get_templates_dir() .. "/obsidian-snippets/scholarly-quotes.css"
if copy_file(css_path, out_root .. "/templates/obsidian-snippets/scholarly-quotes.css") then
    ok = ok + 1
    print("OK", out_root .. "/templates/obsidian-snippets/scholarly-quotes.css")
end
for _, name in ipairs(list_md(LibraryExport.get_tags_dir())) do
    deploy(LibraryExport.get_tags_dir() .. "/" .. name, "tags/" .. name)
end
for _, name in ipairs(list_md(LibraryExport.get_quotes_dir())) do
    deploy(LibraryExport.get_quotes_dir() .. "/" .. name, "quotes/" .. name)
end

print(string.format("\nRegenerated %d file(s) into %s from %d JSON sidecar(s)", ok, out_root, #json_files))
