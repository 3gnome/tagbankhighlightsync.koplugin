-- Library WebDAV upload queue helpers (pure logic for unit tests).

local LibraryExport = require("library_export")
local Merge = require("merge")
local Tags = require("tags")

local lfs = _G.lfs
if not lfs then
    local ok, mod = pcall(require, "libs/libkoreader-lfs")
    if ok then
        lfs = mod
    end
end

local function local_file_exists(path)
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

local LibraryUpload = {}

function LibraryUpload.target_needs_library_work(ann, bank, settings)
    if not ann then
        return false
    end
    settings = settings or {}
    if settings.library_force_reupload then
        return true
    end
    if Tags.needs_library_sync(ann, bank) then
        return true
    end
    if LibraryUpload.hasPendingScreenshotUpload(ann) then
        return true
    end
    if LibraryExport.is_untagged_library_export(ann, settings) then
        local quote_path = LibraryExport.get_quote_path(ann)
        if not local_file_exists(quote_path) then
            return true
        end
    end
    return false
end

function LibraryUpload.collectScreenshotJobs(annotations, settings, build_server_fn)
    local jobs = {}
    if settings.library_include_screenshots == false then
        return jobs
    end
    for _, item in ipairs(LibraryExport.collect_captured(annotations, settings)) do
        local png_path = LibraryExport.get_quote_image_path(item)
        if local_file_exists(png_path)
            and LibraryUpload.hasPendingScreenshotUpload(item) then
            jobs[#jobs + 1] = {
                server = build_server_fn("quotes/images"),
                path = png_path,
                kind = "screenshot",
            }
        end
    end
    return jobs
end

function LibraryUpload.hasPendingFileUpload(path)
    if not path or path == "" then
        return false
    end
    if not local_file_exists(path) then
        return false
    end
    return not local_file_exists(path .. ".sync")
end

function LibraryUpload.is_background_library_path(path, settings)
    settings = settings or {}
    if not path or path == "" then
        return false
    end
    if path == LibraryExport.get_master_path(settings)
        or path == LibraryExport.get_readme_path() then
        return true
    end
    local books_dir = LibraryExport.get_books_dir()
    local tags_dir = LibraryExport.get_tags_dir()
    local quotes_dir = LibraryExport.get_quotes_dir()
    return path:find(books_dir, 1, true) ~= nil
        or path:find(tags_dir, 1, true) ~= nil
        or path:find(quotes_dir, 1, true) ~= nil
end

function LibraryUpload.shouldIncludeBackgroundJob(job, annotations, bank, settings)
    if job.kind == "screenshot" then
        return true
    end
    if LibraryUpload.hasPendingFileUpload(job.path)
        and LibraryUpload.is_background_library_path(job.path, settings) then
        return true
    end
    local quotes_dir = LibraryExport.get_quotes_dir()
    if not job.path or not job.path:match("%.md$") then
        return false
    end
    if not job.path:find(quotes_dir, 1, true) then
        return false
    end
    for _, item in ipairs(LibraryExport.collect_captured(annotations, settings)) do
        if LibraryExport.get_quote_path(item) == job.path then
            return true
        end
    end
    for _, item in ipairs(Merge.normalize_to_list(annotations or {})) do
        if LibraryExport.is_library_exportable(item, settings)
            and LibraryExport.get_quote_path(item) == job.path
            and LibraryUpload.target_needs_library_work(item, bank, settings) then
            return true
        end
    end
    return false
end

function LibraryUpload.collectChangedLibraryUploadQueue(full_queue, annotations, bank, settings)
    local out = {}
    for _, job in ipairs(full_queue or {}) do
        if LibraryUpload.shouldIncludeBackgroundJob(job, annotations, bank, settings) then
            out[#out + 1] = job
        end
    end
    return out
end

function LibraryUpload.prioritizeLibraryUploadQueue(queue, target_ann, get_quote_path_fn)
    local shots, target_md, rest = {}, {}, {}
    local target_path = target_ann and get_quote_path_fn and get_quote_path_fn(target_ann) or nil
    for _, job in ipairs(queue or {}) do
        if job.kind == "screenshot" then
            shots[#shots + 1] = job
        elseif target_path and job.path == target_path then
            target_md[#target_md + 1] = job
        else
            rest[#rest + 1] = job
        end
    end
    local out = {}
    for _, job in ipairs(shots) do
        out[#out + 1] = job
    end
    for _, job in ipairs(target_md) do
        out[#out + 1] = job
    end
    for _, job in ipairs(rest) do
        out[#out + 1] = job
    end
    return out
end

function LibraryUpload.verifyScreenshotUploads(target_ann)
    if not target_ann or not Tags.has_capture(target_ann) then
        return true
    end
    local png_path = LibraryExport.get_quote_image_path(target_ann)
    if not local_file_exists(png_path) then
        return true
    end
    return local_file_exists(png_path .. ".sync")
end

function LibraryUpload.hasPendingScreenshotUpload(target_ann)
    if not target_ann or not Tags.has_capture(target_ann) then
        return false
    end
    local png_path = LibraryExport.get_quote_image_path(target_ann)
    if not local_file_exists(png_path) then
        return false
    end
    return not local_file_exists(png_path .. ".sync")
end

return LibraryUpload
