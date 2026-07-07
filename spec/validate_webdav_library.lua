#!/usr/bin/env luajit
-- Dev validation: build library/ Markdown from a sidecar JSON (Phase A checklist).
-- Usage (from anywhere in WSL):
--   luajit /mnt/c/Users/small/tagbankhighlightsync.koplugin/spec/validate_webdav_library.lua \
--     [path/to/alice.sdr.json] [output/library/dir]

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

local json_path = arg[1] or "/mnt/c/Users/small/Desktop/KOReader Highlights/alice.sdr.json"
local out_root = arg[2] or "/mnt/c/Users/small/Desktop/KOReader Highlights/library"
local sidecar_name = json_path:match("([^/]+)%.json$") or "alice.sdr"
local filename = sidecar_name

local _test_data_dir = os.tmpname():gsub("%..*", "") .. "_hs_validate"
package.loaded["datastorage"] = {
    getDataDir = function() return _test_data_dir end,
}
package.loaded["util"] = {
    makePath = function(path)
        os.execute('mkdir -p "' .. path .. '" 2>/dev/null')
    end,
    partialMD5 = function() return "validate" end,
}

local Merge = require("merge")
local Export = require("export")
local Tags = require("tags")
local TagBank = require("tag_bank")
local LibraryExport = require("library_export")

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

local annotations = read_json(json_path)
local settings = {
    tagged_library_enabled = true,
    library_include_untagged = true,
    library_use_callouts = true,
    library_metadata_style = "both",
    master_doc_filename = "master-quotes.md",
    tag_bank = TagBank.default_bank(),
}
TagBank.ensure_bank(settings)

local metadata = {
    book_title = "Alice's Adventures in Wonderland",
    doc_title = "Alice's Adventures in Wonderland",
    author = "Lewis Carroll",
    sidecar_name = sidecar_name,
    sync_datetime = os.date("%Y-%m-%d"),
    tag_bank = settings.tag_bank,
}

LibraryExport.ensure_local_dirs()
LibraryExport.ensure_library_assets(settings)
local book_path = LibraryExport.get_book_path(filename)
LibraryExport.update_book_file(book_path, annotations, settings, metadata)

local master_path = LibraryExport.get_master_path(settings)
local content = "# Tagged quotes index\n\n"
local lib_ctx = {
    book_title = metadata.book_title,
    doc_title = metadata.doc_title,
    author = metadata.author,
    sidecar_name = sidecar_name,
    filename = filename,
    tag_bank = settings.tag_bank,
    sync_datetime = metadata.sync_datetime,
}
for _, item in ipairs(LibraryExport.collect_tagged(annotations)) do
    content = LibraryExport.upsert_library_entry(content, item, lib_ctx, settings)
    LibraryExport.update_tag_indexes_for_annotation(item, lib_ctx, false, settings)
end
LibraryExport.write_file(master_path, content)

os.execute('mkdir -p "' .. out_root .. '/books" "' .. out_root .. '/tags" "' .. out_root .. '/quotes" "' .. out_root .. '/templates"')

local function list_md(dir)
    local names = {}
    local pipe = io.popen('find "' .. dir .. '" -maxdepth 1 -name "*.md" -printf "%f\\n" 2>/dev/null')
        or io.popen('ls "' .. dir .. '" 2>/dev/null')
    if not pipe then
        return names
    end
    for name in pipe:lines() do
        if name:match("%.md$") then
            names[#names + 1] = name
        end
    end
    pipe:close()
    return names
end

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

deploy(book_path, "books/" .. filename .. ".md")
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

local tags_dir = LibraryExport.get_tags_dir()
for _, name in ipairs(list_md(tags_dir)) do
    deploy(tags_dir .. "/" .. name, "tags/" .. name)
end

local quotes_dir = LibraryExport.get_quotes_dir()
for _, name in ipairs(list_md(quotes_dir)) do
    deploy(quotes_dir .. "/" .. name, "quotes/" .. name)
end

local master_body = LibraryExport.read_file(master_path)
local sample_quote = ""
for _, item in ipairs(LibraryExport.collect_tagged(annotations)) do
    sample_quote = item.text or ""
    if sample_quote ~= "" then
        break
    end
end
if sample_quote ~= "" and master_body:find(sample_quote, 1, true) then
    print("WARN: master-quotes.md still contains full quote text (expected link index only)")
end
local tag_sample = LibraryExport.read_file(LibraryExport.get_tag_index_path("love"))
if tag_sample ~= "" and sample_quote ~= "" and tag_sample:find(sample_quote, 1, true) then
    print("WARN: tags/love.md still contains full quote text (expected link index only)")
end
if master_body:find("[[quotes/", 1, true) then
    print("OK hybrid master index links")
end

print(string.format("\nDeployed %d file(s) to %s (layout: hybrid)", ok, out_root))
print("Obsidian: open library/ as vault; open templates/Writing Dashboard.md (Dataview)")
print("Writer workflow: tag on device → Sync now → query quotes by tag/book in Obsidian")
