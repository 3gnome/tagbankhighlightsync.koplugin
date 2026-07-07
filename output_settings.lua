local Merge = require("merge")
local util = require("util")

local OutputSettings = {}

OutputSettings.defaults = {
    include_highlights = true,
    include_notes = true,
    include_page_bookmarks = false,
    filename_mode = "sidecar",
    filename_template = "{sidecar}",
    json_pretty = false,
    json_wrapper = false,
    json_strip_pboxes = false,
    json_strip_ext = false,
    json_strip_pageref = false,
    json_strip_color = false,
    export_enabled = false,
    export_formats = { "markdown" },
    mirror_enabled = false,
    mirror_path = "",
    remote_layout = "flat",
    remote_prefix = "highlights",
    backup_before_sync = false,
    tag_presets = { "love", "grief", "leadership", "quotes", "ideas" },
    tag_bank = nil,
    tag_bank_migrated = false,
    tag_bank_layout_version = 0,
    tagged_library_enabled = false,
    library_subpath = "library",
    master_doc_filename = "master-quotes.md",
    library_include_untagged = true,
    library_use_callouts = true,
    library_preserve_verse_layout = true,
    library_metadata_style = "inline",
    library_exclude_orange_highlights = true,
    library_exclude_green_highlights = false,
    library_tag_index_style = "embed",
    library_include_screenshots = true,
    library_export_version = 2,
    library_force_reupload = false,
    library_templates_version = 0,
}

OutputSettings.LIBRARY_EXPORT_VERSION = 2

function OutputSettings.migrate_library_export(settings)
    settings = settings or {}
    if (settings.library_export_version or 1) < OutputSettings.LIBRARY_EXPORT_VERSION then
        settings.library_export_version = OutputSettings.LIBRARY_EXPORT_VERSION
        settings.library_force_reupload = true
        return true
    end
    return false
end

function OutputSettings.merge_defaults(settings)
    settings = settings or {}
    for k, v in pairs(OutputSettings.defaults) do
        if settings[k] == nil then
            if type(v) == "table" then
                settings[k] = {}
                for i, val in ipairs(v) do
                    settings[k][i] = val
                end
            else
                settings[k] = v
            end
        end
    end
    local TagBank = require("tag_bank")
    TagBank.ensure_bank(settings)
    OutputSettings.migrate_library_export(settings)
    return settings
end

local function sanitize_filename(str)
    if not str then return "" end
    return str:gsub("[^%w%.%-%_]", "_")
end

function OutputSettings.get_doc_hash(doc_path)
    if not doc_path then return "" end
    return util.partialMD5(doc_path) or ""
end

function OutputSettings.get_sidecar_name(sidecar_dir)
    return sidecar_dir and sidecar_dir:match("([^/]+)/*$") or "book"
end

function OutputSettings.get_book_title(document)
    if not document then return "book" end
    local name = document.file and document.file:gsub(".*/", "") or "book"
    return name:gsub("%.[^%.]+$", "") or name
end

function OutputSettings.extract_doc_metadata(document, ui)
    local meta = {}
    local props
    if document and document.getProps then
        local ok, p = pcall(function()
            return document:getProps()
        end)
        if ok and type(p) == "table" then
            props = p
        end
    end
    if not props and ui and ui.doc_settings then
        props = ui.doc_settings:readSetting("doc_props")
    end
    if type(props) == "table" then
        meta.doc_title = props.title or props.display_title
        meta.author = props.authors or props.author or ""
        meta.series = props.series
        meta.language = props.language
    end
    meta.book_title = OutputSettings.get_book_title(document)
    if not meta.doc_title or meta.doc_title == "" then
        meta.doc_title = meta.book_title
    end
    if ui and ui.doc_settings and document and document.file then
        local sidecar_dir = ui.doc_settings:getSidecarDir(document.file)
        meta.sidecar_name = OutputSettings.get_sidecar_name(sidecar_dir)
    end
    return meta
end

function OutputSettings.resolve_filename(settings, ctx)
    local mode = settings.filename_mode or "sidecar"
    local sidecar = ctx.sidecar_name or "book"
    local title = ctx.book_title or "book"
    local hash = ctx.doc_hash or ""
    local date = os.date("%Y-%m-%d")

    local base
    if mode == "title" then
        base = title
    elseif mode == "hash" then
        base = hash ~= "" and hash or sidecar
    elseif mode == "template" then
        base = (settings.filename_template or "{sidecar}")
            :gsub("{title}", title)
            :gsub("{hash}", hash)
            :gsub("{sidecar}", sidecar)
            :gsub("{date}", date)
    else
        base = sidecar
    end
    return sanitize_filename(base)
end

function OutputSettings.is_syncable_annotation(item, settings)
    if not item or type(item) ~= "table" then
        return false
    end
    local is_bookmark = not item.drawer
    local has_note = item.note and item.note ~= ""
    if is_bookmark then
        return settings.include_page_bookmarks == true
    elseif has_note then
        return settings.include_notes == true
    end
    return settings.include_highlights == true
end

function OutputSettings.filter_annotations(annotations, settings)
    local list = Merge.normalize_to_list(annotations)
    local filtered = {}
    for _, item in ipairs(list) do
        if OutputSettings.is_syncable_annotation(item, settings) then
            filtered[#filtered + 1] = item
        end
    end
    return filtered
end

function OutputSettings.strip_annotation_fields(item, settings)
    local copy = {}
    for k, v in pairs(item) do
        copy[k] = v
    end
    if settings.json_strip_pboxes then copy.pboxes = nil end
    if settings.json_strip_ext then copy.ext = nil end
    if settings.json_strip_pageref then copy.pageref = nil end
    if settings.json_strip_color then
        copy.color = nil
    end
    return copy
end

function OutputSettings.prepare_for_write(annotations, settings, metadata)
    local list = OutputSettings.filter_annotations(annotations, settings)
    if settings.json_strip_pboxes or settings.json_strip_ext
        or settings.json_strip_pageref or settings.json_strip_color then
        local stripped = {}
        for i, item in ipairs(list) do
            stripped[i] = OutputSettings.strip_annotation_fields(item, settings)
        end
        list = stripped
    end
    if settings.json_wrapper then
        return {
            book_title = metadata.book_title,
            device_id = metadata.device_id,
            sync_datetime = metadata.sync_datetime,
            annotations = list,
        }
    end
    return list
end

function OutputSettings.unwrap_payload(data)
    if type(data) ~= "table" then
        return {}
    end
    if data.annotations and type(data.annotations) == "table" then
        return Merge.normalize_to_list(data.annotations)
    end
    return Merge.normalize_to_list(data)
end

function OutputSettings.get_remote_subpath(settings, ctx)
    local layout = settings.remote_layout or "flat"
    local base = ctx.filename or "book"
    if layout == "flat" then
        return ""
    elseif layout == "by_title" then
        return sanitize_filename(ctx.book_title or base)
    elseif layout == "by_date" then
        return os.date("%Y-%m-%d")
    elseif layout == "prefix" then
        local prefix = settings.remote_prefix or "highlights"
        return sanitize_filename(prefix)
    end
    return ""
end

function OutputSettings.build_sync_server(base_server, settings, ctx)
    local server = {}
    for k, v in pairs(base_server) do
        server[k] = v
    end
    local sub = OutputSettings.get_remote_subpath(settings, ctx)
    local url = server.url or "/"
    if sub ~= "" then
        url = url:gsub("/+$", "") .. "/" .. sub
        if not url:match("^/") then
            url = "/" .. url
        end
    end
    server.url = url
    return server
end

function OutputSettings.build_library_sync_server(base_server, settings, relative_dir)
    local LibraryExport = require("library_export")
    return LibraryExport.build_sync_server(base_server, settings, relative_dir)
end

return OutputSettings
