-- Markdown quote library (master + per-book) for WebDAV export.

local DataStorage = require("datastorage")
local Export = require("export")
local Merge = require("merge")
local Tags = require("tags")

local LibraryExport = {}

local function yaml_quote(str)
    return Export.yaml_quote(str)
end

function LibraryExport.is_library_exportable(item, settings)
    if not item then
        return false
    end
    settings = settings or {}
    if settings.library_exclude_orange_highlights ~= false then
        if item.color == "orange" then
            return false
        end
    end
    if settings.library_exclude_green_highlights == true then
        if item.color == "green" then
            return false
        end
    end
    return true
end

function LibraryExport.is_hybrid_layout(_settings)
    return true
end

local function escape_pattern(text)
    return (text or ""):gsub("([%-%.%+%*%?%^%$%(%)%[%]|%%])", "%%%1")
end

local function split_lines(content)
    local lines = {}
    content = content or ""
    if content == "" then
        return lines
    end
    content = content:gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in (content .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

local function join_lines(lines)
    if #lines == 0 then
        return ""
    end
    return table.concat(lines, "\n") .. "\n"
end

local function is_legacy_marker_line(line)
    if not line or line == "" then
        return false
    end
    return line:match("^%% highlight_sync:")
        or line:match("^%% /highlight_sync")
        or line:match("^<!-- highlight_sync:")
        or line:match("^<!-- /highlight_sync")
end

local function is_quote_heading_line(line)
    return line and line:match("^### ") ~= nil
end

function LibraryExport.block_heading(item, ctx)
    return Export.format_quote_heading(item, LibraryExport.make_quote_metadata(ctx, item))
end

function LibraryExport.legacy_block_heading(item, ctx)
    return Export.format_quote_heading_legacy(item, LibraryExport.make_quote_metadata(ctx, item))
end

function LibraryExport.quote_block_key(item)
    return Merge.generate_key(item)
end

function LibraryExport.format_block_anchor(key)
    key = (key or ""):gsub("--", "")
    return "<!-- hs:key=" .. key .. " -->"
end

function LibraryExport.find_block_span(lines, heading, block_key)
    if block_key and block_key ~= "" then
        local anchor = LibraryExport.format_block_anchor(block_key)
        for i, line in ipairs(lines) do
            if line == anchor then
                local start_idx = i
                local end_idx = i + 1
                local saw_heading = false
                while end_idx <= #lines do
                    local next_line = lines[end_idx]
                    if next_line == anchor then
                        break
                    end
                    if next_line:match("^<!-- hs:key=") and next_line ~= anchor then
                        break
                    end
                    if is_quote_heading_line(next_line) then
                        if saw_heading then
                            break
                        end
                        saw_heading = true
                    end
                    end_idx = end_idx + 1
                end
                while end_idx <= #lines and (lines[end_idx] == "" or is_legacy_marker_line(lines[end_idx])) do
                    end_idx = end_idx + 1
                end
                return start_idx, end_idx - 1
            end
        end
    end
    if not heading or heading == "" then
        return nil, nil
    end
    for i, line in ipairs(lines) do
        if line == heading then
            local start_idx = i
            while start_idx > 1 and (lines[start_idx - 1] == "" or is_legacy_marker_line(lines[start_idx - 1])) do
                start_idx = start_idx - 1
            end
            local end_idx = i + 1
            while end_idx <= #lines and not is_quote_heading_line(lines[end_idx]) do
                end_idx = end_idx + 1
            end
            while end_idx <= #lines and (lines[end_idx] == "" or is_legacy_marker_line(lines[end_idx])) do
                end_idx = end_idx + 1
            end
            return start_idx, end_idx - 1
        end
    end
    return nil, nil
end

function LibraryExport.strip_legacy_wrappers(content)
    content = content or ""
    local html_start = "<!-- highlight_sync:"
    local html_end = "<!-- /highlight_sync -->"
    local html_pattern = escape_pattern(html_start)
        .. "[^>]-%->[%s%S]-" .. escape_pattern(html_end)
    content = content:gsub("\n?" .. html_pattern .. "\n?", "\n")

    local obs_start = "%% highlight_sync:"
    local obs_end = "%% /highlight_sync %%"
    local obs_pattern = escape_pattern(obs_start)
        .. "[^%]-%% [%s%S]-" .. escape_pattern(obs_end)
    content = content:gsub("\n?" .. obs_pattern .. "\n?", "\n")

    content = content:gsub("\n?%% highlight_sync:[^\n]*\n", "\n")
    content = content:gsub("\n?%% /highlight_sync %% ?\n", "\n")
    content = content:gsub("\n?<!-- highlight_sync:[^>]-%->\n", "\n")
    content = content:gsub("\n?<!-- /highlight_sync -->\n", "\n")
    return content:gsub("\n\n\n+", "\n\n")
end

function LibraryExport.upsert_block_by_heading(content, heading, block, legacy_heading, block_key)
    content = LibraryExport.strip_legacy_wrappers(content or "")
    block = (block or ""):gsub("\n+$", "")
    local lines = split_lines(content)
    local start_idx, end_idx = LibraryExport.find_block_span(lines, heading, block_key)
    if not start_idx and legacy_heading and legacy_heading ~= heading then
        start_idx, end_idx = LibraryExport.find_block_span(lines, legacy_heading, block_key)
    end
    local block_lines = split_lines(block)
    if start_idx then
        local new_lines = {}
        for i = 1, start_idx - 1 do
            new_lines[#new_lines + 1] = lines[i]
        end
        for i = 1, #block_lines do
            new_lines[#new_lines + 1] = block_lines[i]
        end
        for i = end_idx + 1, #lines do
            new_lines[#new_lines + 1] = lines[i]
        end
        return join_lines(new_lines)
    end
    if content ~= "" and not content:match("\n$") then
        content = content .. "\n"
    end
    if content ~= "" and not content:match("\n\n$") then
        content = content .. "\n"
    end
    return content .. block .. "\n"
end

function LibraryExport.remove_block_by_heading(content, heading, legacy_heading, block_key)
    content = content or ""
    local lines = split_lines(content)
    local start_idx, end_idx = LibraryExport.find_block_span(lines, heading, block_key)
    if not start_idx and legacy_heading and legacy_heading ~= heading then
        start_idx, end_idx = LibraryExport.find_block_span(lines, legacy_heading, block_key)
    end
    if not start_idx then
        return LibraryExport.strip_legacy_wrappers(content)
    end
    local new_lines = {}
    for i = 1, start_idx - 1 do
        new_lines[#new_lines + 1] = lines[i]
    end
    for i = end_idx + 1, #lines do
        new_lines[#new_lines + 1] = lines[i]
    end
    return LibraryExport.strip_legacy_wrappers(join_lines(new_lines))
end

function LibraryExport.upsert_quote_block(content, item, ctx, settings)
    settings = settings or {}
    local meta = LibraryExport.make_quote_metadata(ctx, item)
    local block_key = LibraryExport.quote_block_key(item)
    local anchor = LibraryExport.format_block_anchor(block_key)
    local block = Export.format_quote_block(item, meta, settings)
    if not block:match("^<!-- hs:key=") then
        block = anchor .. "\n" .. block
    end
    local heading = Export.format_quote_heading(item, meta)
    local legacy = Export.format_quote_heading_legacy(item, meta)
    return LibraryExport.upsert_block_by_heading(content, heading, block, legacy, block_key)
end

function LibraryExport.remove_quote_block(content, item, ctx)
    local meta = LibraryExport.make_quote_metadata(ctx, item)
    local block_key = LibraryExport.quote_block_key(item)
    local heading = Export.format_quote_heading(item, meta)
    local legacy = Export.format_quote_heading_legacy(item, meta)
    return LibraryExport.remove_block_by_heading(content, heading, legacy, block_key)
end

local function fallback_quote_hash(key)
    key = key or "quote"
    local h = 5381
    for i = 1, #key do
        h = (h * 33 + key:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

function LibraryExport.quote_filename_from_key(key)
    local util = require("util")
    local hash = util.partialMD5(key or "")
    if hash and hash ~= "" then
        return hash .. ".md"
    end
    return fallback_quote_hash(key) .. ".md"
end

function LibraryExport.get_quote_link_basename(item)
    local name = LibraryExport.quote_filename_from_key(LibraryExport.quote_block_key(item))
    return "quotes/" .. name:gsub("%.md$", "")
end

function LibraryExport.get_quotes_dir()
    return LibraryExport.get_local_root() .. "/quotes"
end

function LibraryExport.get_images_dir()
    return LibraryExport.get_quotes_dir() .. "/images"
end

function LibraryExport.quote_image_filename(item)
    return LibraryExport.quote_filename_from_key(LibraryExport.quote_block_key(item))
        :gsub("%.md$", ".png")
end

function LibraryExport.get_quote_image_path(item)
    return LibraryExport.get_images_dir() .. "/" .. LibraryExport.quote_image_filename(item)
end

function LibraryExport.get_capture_relative_path(item)
    return "quotes/images/" .. LibraryExport.quote_image_filename(item)
end

function LibraryExport.capture_image_exists(item)
    if not Tags.has_capture(item) then
        return false
    end
    local path = LibraryExport.get_quote_image_path(item)
    if lfs and lfs.attributes(path, "mode") == "file" then
        return true
    end
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

--- Drop WebDAV .sync sidecars so re-capture and quote refresh re-upload PNG/MD.
function LibraryExport.invalidate_capture_upload_state(item)
    if not item then
        return
    end
    local png_path = LibraryExport.get_quote_image_path(item)
    if png_path and png_path ~= "" then
        os.remove(png_path .. ".sync")
    end
    local quote_path = LibraryExport.get_quote_path(item)
    if quote_path and quote_path ~= "" then
        os.remove(quote_path .. ".sync")
    end
end

function LibraryExport.remove_quote_image(item)
    local path = LibraryExport.get_quote_image_path(item)
    if path and path ~= "" and lfs and lfs.attributes(path, "mode") == "file" then
        os.remove(path)
    end
end

function LibraryExport.get_quote_path(item)
    return LibraryExport.get_quotes_dir() .. "/"
        .. LibraryExport.quote_filename_from_key(LibraryExport.quote_block_key(item))
end

function LibraryExport.build_index_line(item, ctx, settings)
    settings = settings or {}
    local block_key = LibraryExport.quote_block_key(item)
    local anchor = LibraryExport.format_block_anchor(block_key)
    local link = LibraryExport.get_quote_link_basename(item)
    local meta = LibraryExport.make_quote_metadata(ctx, item)
    local heading = Export.format_quote_heading(item, meta)
    local summary = heading:gsub("^###%s*", "")
    local bank = ctx.tag_bank or {}
    local tag_line = Tags.format_hashtag_line_for_export(Tags.get_tags(item), bank)
    local line = "- [[" .. link .. "]] · " .. summary
    if tag_line ~= "" then
        line = line .. " · " .. tag_line
    end
    local block = anchor .. "\n" .. line
    local index_style = settings.library_tag_index_style or "embed"
    if index_style == "embed" then
        block = block .. "\n\n![[" .. link .. "]]\n"
    end
    return block
end

function LibraryExport.build_atomic_quote_document(item, ctx, settings)
    settings = settings or {}
    local meta = LibraryExport.make_quote_metadata(ctx, item)
    local block_key = LibraryExport.quote_block_key(item)
    local leaf = Tags.get_tags(item)
    local expanded = Tags.expand_for_export(leaf, ctx.tag_bank or {})
    local sidecar = ctx.sidecar_name or ctx.filename or "book"
    local book_file = ctx.filename or sidecar
    local raw_when = item.datetime_updated or item.datetime or ctx.sync_datetime or ""

    local fm = {
        "---",
        "type: quote",
        "book: " .. yaml_quote(meta.doc_title or meta.book_title or book_file),
        "sidecar: " .. yaml_quote(sidecar),
    }
    if meta.author and meta.author ~= "" then
        fm[#fm + 1] = "author: " .. yaml_quote(meta.author)
    end
    if #expanded > 0 then
        fm[#fm + 1] = "tags: [" .. table.concat(expanded, ", ") .. "]"
    end
    if raw_when ~= "" then
        fm[#fm + 1] = "captured_at: " .. yaml_quote(raw_when)
    end
    if settings.library_include_screenshots ~= false then
        local capture_path = item[Tags.CAPTURE_FIELD]
        if capture_path and capture_path ~= ""
            and LibraryExport.capture_image_exists(item) then
            fm[#fm + 1] = "screenshot: \"[[" .. capture_path .. "]]\""
        end
    end
    fm[#fm + 1] = 'source: "[[books/' .. book_file .. ']]"'
    fm[#fm + 1] = "---"
    fm[#fm + 1] = ""

    local body_settings = {}
    for k, v in pairs(settings) do
        body_settings[k] = v
    end
    -- Frontmatter carries metadata; body keeps hashtags + quote callout only.
    body_settings.library_metadata_style = "hashtags_only"
    body_settings.library_embed_screenshot = settings.library_include_screenshots ~= false

    local body = Export.format_quote_block(item, meta, body_settings)
    local anchor = LibraryExport.format_block_anchor(block_key)
    if not body:match("^<!-- hs:key=") then
        body = anchor .. "\n" .. body
    end
    body = body .. "\nSource: [[books/" .. book_file .. "]]\n"
    return table.concat(fm, "\n") .. body
end

function LibraryExport.write_atomic_quote(item, ctx, settings)
    local path = LibraryExport.get_quote_path(item)
    local content = LibraryExport.build_atomic_quote_document(item, ctx, settings)
    LibraryExport.ensure_local_dirs()
    return LibraryExport.write_file(path, content)
end

function LibraryExport.remove_atomic_quote(item)
    local path = LibraryExport.get_quote_path(item)
    if not path or path == "" then
        return
    end
    if lfs and lfs.attributes(path, "mode") ~= "file" then
        return
    end
    local content = LibraryExport.read_file(path)
    if content ~= "" then
        local file_key = LibraryExport.extract_quote_key_from_content(content)
        local item_key = LibraryExport.quote_block_key(item)
        if file_key and file_key ~= item_key then
            return
        end
    end
    os.remove(path)
    LibraryExport.remove_quote_image(item)
end

function LibraryExport.upsert_index_line(content, item, ctx, settings)
    settings = settings or {}
    local block_key = LibraryExport.quote_block_key(item)
    local block = LibraryExport.build_index_line(item, ctx, settings)
    local meta = LibraryExport.make_quote_metadata(ctx, item)
    local heading = Export.format_quote_heading(item, meta)
    local legacy = Export.format_quote_heading_legacy(item, meta)
    return LibraryExport.upsert_block_by_heading(content, heading, block, legacy, block_key)
end

function LibraryExport.remove_index_line(content, item, ctx)
    return LibraryExport.remove_quote_block(content, item, ctx)
end

function LibraryExport.upsert_library_entry(content, item, ctx, settings)
    if LibraryExport.is_hybrid_layout(settings) then
        LibraryExport.write_atomic_quote(item, ctx, settings)
        return LibraryExport.upsert_index_line(content, item, ctx, settings)
    end
    return LibraryExport.upsert_quote_block(content, item, ctx, settings)
end

function LibraryExport.remove_library_entry(content, item, ctx, settings)
    if LibraryExport.is_hybrid_layout(settings) then
        LibraryExport.remove_atomic_quote(item)
        return LibraryExport.remove_index_line(content, item, ctx)
    end
    return LibraryExport.remove_quote_block(content, item, ctx)
end

function LibraryExport.extract_quote_key_from_content(content)
    return content and content:match("<!%-%- hs:key=(.-) %-%->")
end

function LibraryExport.prune_book_quotes(ctx, active_tagged_keys)
    if not lfs then
        return
    end
    local quotes_dir = LibraryExport.get_quotes_dir()
    if lfs.attributes(quotes_dir, "mode") ~= "directory" then
        return
    end
    active_tagged_keys = active_tagged_keys or {}
    local sidecar = ctx.filename or ctx.sidecar_name or ""
    if sidecar == "" then
        return
    end
    local sidecar_pat = "sidecar: " .. escape_pattern(sidecar)
    for name in lfs.dir(quotes_dir) do
        if name ~= "." and name ~= ".." and name:match("%.md$") then
            local path = quotes_dir .. "/" .. name
            if lfs.attributes(path, "mode") == "file" then
                local content = LibraryExport.read_file(path)
                if content:find(sidecar_pat) then
                    local key = LibraryExport.extract_quote_key_from_content(content)
                    if key and not active_tagged_keys[key] then
                        os.remove(path)
                        local png_name = name:gsub("%.md$", ".png")
                        local png_path = LibraryExport.get_images_dir() .. "/" .. png_name
                        if lfs.attributes(png_path, "mode") == "file" then
                            os.remove(png_path)
                        end
                    end
                end
            end
        end
    end
end

function LibraryExport.get_local_root()
    return DataStorage:getDataDir() .. "/highlight_sync_library"
end

function LibraryExport.get_books_dir()
    return LibraryExport.get_local_root() .. "/books"
end

function LibraryExport.get_tags_dir()
    return LibraryExport.get_local_root() .. "/tags"
end

function LibraryExport.get_templates_dir()
    return LibraryExport.get_local_root() .. "/templates"
end

function LibraryExport.get_tag_index_path(tag_id)
    return LibraryExport.get_tags_dir() .. "/" .. tag_id .. ".md"
end

function LibraryExport.get_book_path(filename)
    return LibraryExport.get_books_dir() .. "/" .. filename .. ".md"
end

function LibraryExport.get_master_path(settings)
    local name = settings.master_doc_filename or "master-quotes.md"
    return LibraryExport.get_local_root() .. "/" .. name
end

function LibraryExport.get_readme_path()
    return LibraryExport.get_local_root() .. "/README.md"
end

function LibraryExport.ensure_local_dirs()
    local util = require("util")
    util.makePath(LibraryExport.get_books_dir())
    util.makePath(LibraryExport.get_tags_dir())
    util.makePath(LibraryExport.get_quotes_dir())
    util.makePath(LibraryExport.get_images_dir())
    util.makePath(LibraryExport.get_templates_dir())
end

function LibraryExport.build_sync_server(base_server, settings, relative_dir)
    local server = {}
    for k, v in pairs(base_server) do
        server[k] = v
    end
    local sub = settings.library_subpath or "library"
    local url = (server.url or "/"):gsub("/+$", "") .. "/" .. sub
    if relative_dir and relative_dir ~= "" then
        url = url:gsub("/+$", "") .. "/" .. relative_dir:gsub("^/+", "")
    end
    if not url:match("^/") then
        url = "/" .. url
    end
    if not url:match("/$") then
        url = url .. "/"
    end
    server.url = url
    return server
end

function LibraryExport.read_file(path)
    local f = io.open(path, "r")
    if not f then
        return ""
    end
    local content = f:read("*a")
    f:close()
    return content or ""
end

function LibraryExport.write_file(path, content)
    local dir = path:match("^(.*)/[^/]+$")
    if dir and dir ~= "" then
        local util = require("util")
        util.makePath(dir)
    end
    local f = io.open(path, "w")
    if not f then
        return false
    end
    f:write(content)
    f:close()
    os.remove(path .. ".sync")
    return true
end

function LibraryExport.collect_tagged(annotations, settings)
    settings = settings or {}
    local tagged = {}
    for _, item in ipairs(Merge.normalize_to_list(annotations or {})) do
        if #Tags.get_tags(item) > 0 and LibraryExport.is_library_exportable(item, settings) then
            tagged[#tagged + 1] = item
        end
    end
    return tagged
end

function LibraryExport.is_untagged_library_export(item, settings)
    settings = settings or {}
    return item
        and settings.library_include_untagged ~= false
        and #Tags.get_tags(item) == 0
        and LibraryExport.is_library_exportable(item, settings)
end

--- Block keys for quotes/*.md to keep during hybrid prune (tagged + optional untagged).
function LibraryExport.collect_preserved_quote_keys(annotations, settings)
    settings = settings or {}
    local keys = {}
    for _, item in ipairs(LibraryExport.collect_tagged(annotations, settings)) do
        keys[LibraryExport.quote_block_key(item)] = true
    end
    if settings.library_include_untagged ~= false then
        for _, item in ipairs(Merge.normalize_to_list(annotations or {})) do
            if #Tags.get_tags(item) == 0 and LibraryExport.is_library_exportable(item, settings) then
                keys[LibraryExport.quote_block_key(item)] = true
            end
        end
    end
    return keys
end

--- Master index + atomic quotes refresh (tagged master entries; untagged atomics when enabled).
function LibraryExport.sync_library_quotes(annotations, ctx, settings)
    settings = settings or {}
    ctx = ctx or {}
    local master_path = LibraryExport.get_master_path(settings)
    local content = LibraryExport.read_file(master_path)
    if content:match("^%s*$") then
        content = "# Tagged quotes index\n\n"
    elseif not content:match("^#") then
        content = "# Tagged quotes index\n\n" .. content
    end
    for _, item in ipairs(LibraryExport.collect_tagged(annotations, settings)) do
        content = LibraryExport.upsert_library_entry(content, item, ctx, settings)
        LibraryExport.update_tag_indexes_for_annotation(item, ctx, false, settings)
    end
    if settings.library_include_untagged ~= false then
        for _, item in ipairs(Merge.normalize_to_list(annotations or {})) do
            if #Tags.get_tags(item) == 0 and LibraryExport.is_library_exportable(item, settings) then
                LibraryExport.write_atomic_quote(item, ctx, settings)
            end
        end
    end
    for _, item in ipairs(Merge.normalize_to_list(annotations or {})) do
        if #Tags.get_tags(item) == 0 and settings.library_include_untagged == false then
            content = LibraryExport.remove_library_entry(content, item, ctx, settings)
            LibraryExport.update_tag_indexes_for_annotation(item, ctx, true, settings)
        end
    end
    if LibraryExport.is_hybrid_layout(settings) then
        LibraryExport.prune_book_quotes(
            ctx, LibraryExport.collect_preserved_quote_keys(annotations, settings))
    end
    return LibraryExport.write_file(master_path, content)
end

function LibraryExport.build_library_context(ctx)
    if not ctx or not ctx.metadata then
        return nil
    end
    return {
        book_title = ctx.metadata.book_title,
        doc_title = ctx.metadata.doc_title,
        author = ctx.metadata.author,
        series = ctx.metadata.series,
        sidecar_name = ctx.sidecar_name,
        filename = ctx.filename,
        tag_bank = ctx.metadata.tag_bank,
        sync_datetime = ctx.metadata.sync_datetime,
    }
end

--- Regenerate per-book + master/tag quote library files (local only).
function LibraryExport.refresh_book_library(ctx, annotations, settings)
    if not ctx or not ctx.metadata then
        return false
    end
    settings = settings or {}
    LibraryExport.ensure_local_dirs()
    LibraryExport.ensure_library_assets(settings)
    local book_path = LibraryExport.get_book_path(ctx.filename)
    LibraryExport.update_book_file(book_path, annotations, settings, ctx.metadata)
    local lib_ctx = LibraryExport.build_library_context(ctx)
    if not lib_ctx then
        return false
    end
    return LibraryExport.sync_library_quotes(annotations, lib_ctx, settings)
end

function LibraryExport.collect_captured(annotations, settings)
    settings = settings or {}
    local captured = {}
    for _, item in ipairs(Merge.normalize_to_list(annotations or {})) do
        if Tags.has_capture(item) and LibraryExport.is_library_exportable(item, settings) then
            captured[#captured + 1] = item
        end
    end
    return captured
end

function LibraryExport.refresh_captured_quote(item, ctx, settings)
    if not item or not Tags.has_capture(item) then
        return
    end
    LibraryExport.write_atomic_quote(item, ctx, settings)
end

--- Refresh local library files for one highlight (untagged Sync now path).
function LibraryExport.refresh_target_for_sync(ann, ctx, annotations, settings)
    if not ann or not ctx or not LibraryExport.is_library_exportable(ann, settings) then
        return
    end
    settings = settings or {}
    local metadata = ctx.metadata or ctx
    LibraryExport.ensure_local_dirs()
    if #Tags.get_tags(ann) == 0 and settings.library_include_untagged == false then
        local book_path = LibraryExport.get_book_path(ctx.filename or ctx.sidecar_name or metadata.sidecar_name)
        LibraryExport.update_book_file(book_path, annotations, settings, metadata)
        return
    end
    LibraryExport.write_atomic_quote(ann, ctx, settings)
    local book_path = LibraryExport.get_book_path(ctx.filename or ctx.sidecar_name or metadata.sidecar_name)
    LibraryExport.update_book_file(book_path, annotations, settings, metadata)
    if #Tags.get_tags(ann) > 0 then
        local master_path = LibraryExport.get_master_path(settings)
        LibraryExport.update_master_for_annotation(master_path, ann, ctx, false, settings)
    end
end

function LibraryExport.ensure_tag_index_header(tag_id, display_name, content)
    local title = display_name or tag_id
    if content:match("^%s*$") then
        return "# " .. title .. "\n\n"
    end
    if not content:match("^#") then
        return "# " .. title .. "\n\n" .. content
    end
    return content
end

function LibraryExport.build_library_readme(_settings)
    return table.concat({
        "# KOReader quote library",
        "",
        "Markdown files here are generated by **TagBankHighlightSync** on **Sync now**.",
        "JSON sync (`*.sdr.json` in the parent folder) is the source of truth for devices.",
        "",
        "## Layout",
        "",
        "| Path | Use when writing |",
        "|------|------------------|",
        "| `books/` | One literature note per book (all highlights); Apple Notes import |",
        "| `quotes/` | One atomic note per tagged highlight — link with `[[quotes/…]]` |",
        "| `master-quotes.md` | Cross-book index linking to `quotes/` |",
        "| `tags/` | Browse one theme at a time (e.g. `tags/buddhism.md`) |",
        "| `templates/` | Obsidian dashboards — copy or open as-is |",
        "",
        "## Writer workflow",
        "",
        "1. **Read** on KOReader → tag highlights by theme → **Sync now**.",
        "2. **Collect** — open `templates/Writing Dashboard.md` in Obsidian (needs Dataview).",
        "3. **Synthesize** — link `[[quotes/…]]` from manuscripts; browse themes via `tags/` indexes.",
        "4. **Draft** — tag quotes `#used` or `status:: used` in separate Obsidian notes (not overwritten on re-sync).",
        "",
        "Re-sync refreshes quote blocks matched by a stable highlight key (HTML comment anchor).",
        "",
    }, "\n")
end

function LibraryExport.build_writing_dashboard(_settings)
    return table.concat({
        "# Writing Dashboard",
        "",
        "Open this note in Obsidian with the **Dataview** plugin enabled.",
        "Vault root should be the `library/` folder (paths below are relative to that).",
        "",
        "## Theme index",
        "",
        "```dataview",
        "TABLE WITHOUT ID",
        "  file.link as Theme,",
        "  length(filter(file.tags, (t) => t != \"quotes\")) as Tags",
        "FROM \"tags\"",
        "SORT file.name asc",
        "```",
        "",
        "## Recently synced books",
        "",
        "```dataview",
        "TABLE author, synced",
        "FROM \"books\"",
        "WHERE type = \"literature\"",
        "SORT synced desc",
        "LIMIT 10",
        "```",
        "",
        "## Recent atomic quotes",
        "",
        "```dataview",
        "TABLE author, book, file.tags",
        "FROM \"quotes\"",
        "SORT file.mtime desc",
        "LIMIT 20",
        "```",
        "",
        "## Quotes with your notes",
        "",
        "```query",
        "path:quotes [!note]",
        "```",
        "",
        "## Manuscript tags (draft / used / cut)",
        "",
        "```query",
        "path:quotes #draft OR #used OR #cut",
        "```",
        "",
        "## Master quote index",
        "",
        "See [[../master-quotes]] for links to `quotes/`; browse `tags/` for themes.",
        "",
        "### Optional typography",
        "",
        "Copy `templates/obsidian-snippets/scholarly-quotes.css` into your vault `.obsidian/snippets/` for softer quote styling.",
        "",
    }, "\n")
end

function LibraryExport.build_scholarly_quotes_css()
    return table.concat({
        "/* TagBankHighlightSync — scholarly quote styling for Obsidian */",
        ".markdown-preview-view .callout[data-callout=\"quote\"] {",
        "  --callout-color: 120, 120, 120;",
        "  font-family: Georgia, 'Iowan Old Style', 'Palatino Linotype', serif;",
        "  line-height: 1.65;",
        "}",
        ".markdown-preview-view .callout[data-callout=\"quote\"] .callout-content,",
        ".markdown-source-view.is-live-preview .callout[data-callout=\"quote\"] .callout-content {",
        "  white-space: pre-wrap;",
        "}",
        ".markdown-preview-view .callout[data-callout=\"note\"] {",
        "  --callout-color: 90, 130, 160;",
        "  font-size: 0.95em;",
        "}",
        ".markdown-preview-view h3 {",
        "  font-weight: 600;",
        "  letter-spacing: 0.01em;",
        "}",
        ".markdown-preview-view .dataview-inline-field-name {",
        "  font-variant: small-caps;",
        "  opacity: 0.75;",
        "}",
    }, "\n")
end

function LibraryExport.build_manuscript_moc()
    return table.concat({
        "# Manuscript MOC",
        "",
        "Map of content for your book-in-progress. Add chapter headings and link permanent notes.",
        "",
        "## Chapter 1 — (title)",
        "",
        "- Permanent note: `[[]]`",
        "- Quotes: browse `quotes/` or `tags/` theme indexes",
        "",
        "## Chapter 2 — (title)",
        "",
        "- ",
        "",
        "### Editorial tags on device",
        "",
        "Use **Manuscript → draft / used / cut** in the tag bank for quotes you are actively placing in the manuscript.",
        "",
    }, "\n")
end

function LibraryExport.ensure_library_assets(settings)
    settings = settings or {}
    LibraryExport.ensure_local_dirs()
    local readme_path = LibraryExport.get_readme_path()
    local readme_body = LibraryExport.build_library_readme(settings)
    local template_version = settings.library_templates_version or 0
    local shipped_version = 4
    local needs_refresh = template_version < shipped_version
    local force_refresh = settings.library_force_reupload == true
    if needs_refresh or force_refresh or LibraryExport.read_file(readme_path) == "" then
        LibraryExport.write_file(readme_path, readme_body)
    end
    local dashboard_path = LibraryExport.get_templates_dir() .. "/Writing Dashboard.md"
    if needs_refresh or force_refresh or LibraryExport.read_file(dashboard_path) == "" then
        LibraryExport.write_file(dashboard_path, LibraryExport.build_writing_dashboard(settings))
    end
    local moc_path = LibraryExport.get_templates_dir() .. "/Manuscript MOC.md"
    local moc_body = LibraryExport.build_manuscript_moc()
    if needs_refresh or force_refresh or LibraryExport.read_file(moc_path) == "" then
        LibraryExport.write_file(moc_path, moc_body)
    end
    local css_path = LibraryExport.get_templates_dir() .. "/obsidian-snippets/scholarly-quotes.css"
    if LibraryExport.read_file(css_path) == "" then
        LibraryExport.write_file(css_path, LibraryExport.build_scholarly_quotes_css())
    end
    if template_version < shipped_version then
        settings.library_templates_version = shipped_version
    end
end

function LibraryExport.make_quote_metadata(ctx, item)
    return {
        book_title = ctx.book_title,
        doc_title = ctx.doc_title or ctx.book_title,
        author = ctx.author,
        series = ctx.series,
        sidecar_name = ctx.sidecar_name or ctx.filename,
        sync_datetime = item.datetime_updated or item.datetime or ctx.sync_datetime,
        tag_bank = ctx.tag_bank,
    }
end

function LibraryExport.update_tag_indexes_for_annotation(item, ctx, remove, settings)
    if not item then
        return
    end
    settings = settings or {}
    local TagBank = require("tag_bank")
    local bank = ctx.tag_bank or {}
    local leaf = Tags.get_tags(item)
    local expanded = Tags.expand_for_export(leaf, bank)
    local previous = Tags.take_previous_expanded_tags(item)
    LibraryExport.ensure_local_dirs()

    local tags_to_update = {}
    local tags_to_strip = {}
    for _, tag_id in ipairs(expanded) do
        tags_to_update[tag_id] = true
    end
    if remove or #leaf == 0 then
        for _, tag_id in ipairs(previous) do
            tags_to_strip[tag_id] = true
        end
        for _, tag_id in ipairs(expanded) do
            tags_to_strip[tag_id] = true
        end
    else
        for _, tag_id in ipairs(previous) do
            if not tags_to_update[tag_id] then
                tags_to_strip[tag_id] = true
            end
        end
    end

    for tag_id in pairs(tags_to_strip) do
        local path = LibraryExport.get_tag_index_path(tag_id)
        local content = LibraryExport.read_file(path)
        if LibraryExport.is_hybrid_layout(settings) then
            content = LibraryExport.remove_index_line(content, item, ctx)
        else
            content = LibraryExport.remove_quote_block(content, item, ctx)
        end
        local display = TagBank.get_display_name(bank, tag_id)
        content = LibraryExport.ensure_tag_index_header(tag_id, display, content)
        LibraryExport.write_file(path, content)
    end

    if not remove and #leaf > 0 then
        for tag_id in pairs(tags_to_update) do
            local path = LibraryExport.get_tag_index_path(tag_id)
            local content = LibraryExport.read_file(path)
            if LibraryExport.is_hybrid_layout(settings) then
                content = LibraryExport.upsert_index_line(content, item, ctx, settings)
            else
                content = LibraryExport.upsert_quote_block(content, item, ctx, settings)
            end
            local display = TagBank.get_display_name(bank, tag_id)
            content = LibraryExport.ensure_tag_index_header(tag_id, display, content)
            LibraryExport.write_file(path, content)
        end
    end
end

function LibraryExport.rebuild_book_document(annotations, settings, metadata)
    settings = settings or {}
    local include_untagged = settings.library_include_untagged ~= false
    local list = {}
    for _, item in ipairs(Merge.normalize_to_list(annotations or {})) do
        if LibraryExport.is_library_exportable(item, settings) then
            if include_untagged or #Tags.get_tags(item) > 0 then
                list[#list + 1] = item
            end
        end
    end
    return Export.to_markdown(list, metadata, settings)
end

function LibraryExport.update_book_file(path, annotations, settings, metadata)
    LibraryExport.ensure_local_dirs()
    local content = LibraryExport.rebuild_book_document(annotations, settings, metadata)
    return LibraryExport.write_file(path, content)
end

function LibraryExport.update_master_for_annotation(path, item, ctx, remove, settings)
    settings = settings or {}
    local content = LibraryExport.read_file(path)
    if remove or #Tags.get_tags(item) == 0 then
        content = LibraryExport.remove_library_entry(content, item, ctx, settings)
    else
        content = LibraryExport.upsert_library_entry(content, item, ctx, settings)
    end
    LibraryExport.ensure_local_dirs()
    if content:match("^%s*$") then
        content = "# Tagged quotes index\n\n"
    elseif not content:match("^#") then
        content = "# Tagged quotes index\n\n" .. content
    end
    LibraryExport.update_tag_indexes_for_annotation(item, ctx, remove or #Tags.get_tags(item) == 0, settings)
    return LibraryExport.write_file(path, content)
end

return LibraryExport
