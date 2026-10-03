-- Background vs foreground sync paths (open/resume vs manual Sync now).

local Device = require("device")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local CloudStorageCompat = require("cloudstorage_compat")
local OutputSettings = require("output_settings")
local LibraryExport = require("library_export")
local LibraryUpload = require("library_upload")
local TagBank = require("tag_bank")
local Tags = require("tags")
local Merge = require("merge")
local SyncProgress = require("sync_progress")
local SyncStatus = require("sync_status")
local logger = require("logger")
local _ = require("gettext")

local lfs = _G.lfs
if not lfs then
    local ok, mod = pcall(require, "libs/libkoreader-lfs")
    if ok then
        lfs = mod
    end
end

local SETTINGS_KEY = "tag_bank_highlight_sync"

local SyncBackground = {}

SyncBackground.OPEN_SYNC_DEFER_SEC = 3
SyncBackground.CLOSE_SYNC_DEFER_SEC = 1
SyncBackground.RESUME_SYNC_RETRY_SEC = 2
SyncBackground.RESUME_SYNC_INITIAL_DEFER_SEC = 2
SyncBackground.NETWORK_CONNECTED_DEFER_SEC = 0.5
SyncBackground.RESUME_SYNC_MAX_ATTEMPTS = 8

function SyncBackground.should_defer_library(opts)
    return type(opts) == "table" and opts.background == true
end

function SyncBackground.is_push_only(opts)
    return type(opts) == "table" and opts.push_only == true
end

--- Automatic sync while offline: queue pending_sync instead of WiFi prompt.
function SyncBackground.should_queue_offline(silent, opts)
    return silent == true or SyncBackground.should_defer_library(opts)
end

--- Merge sync (cloudstorage provider) needs a live route — not just radio on.
function SyncBackground.network_ready_for_merge_sync()
    return NetworkMgr:isConnected()
end

--- Raw HTTP push (close JSON / library PUT) can work on LAN when Wi-Fi is on but WAN is not up.
function SyncBackground.network_ready_for_raw_push()
    if NetworkMgr:isConnected() then
        return true
    end
    if Device:hasWifiToggle() and NetworkMgr:isWifiOn() then
        return true
    end
    return false
end

--- @deprecated use network_ready_for_merge_sync or network_ready_for_raw_push
function SyncBackground.network_ready_for_sync()
    return SyncBackground.network_ready_for_raw_push()
end

local function set_sync_status(status)
    local settings = G_reader_settings:readSetting(SETTINGS_KEY)
    if settings then
        SyncStatus.apply(settings, status, os.date("%Y-%m-%d %H:%M:%S"))
        G_reader_settings:saveSetting(SETTINGS_KEY, settings)
    end
end

local function build_close_library_jobs(snapshot)
    if not snapshot or not snapshot.library_refresh or not snapshot.base_server then
        return {}
    end
    local settings = G_reader_settings:readSetting(SETTINGS_KEY)
    if not settings or not settings.tagged_library_enabled or not settings.sync_server then
        return {}
    end
    OutputSettings.merge_defaults(settings)
    local refresh = snapshot.library_refresh
    local ctx = {
        filename = refresh.filename,
        sidecar_name = refresh.sidecar_name,
        metadata = refresh.metadata,
    }
    LibraryExport.refresh_book_library(ctx, refresh.annotations, settings)
    local book_local = LibraryExport.get_book_path(ctx.filename)
    local master_local = LibraryExport.get_master_path(settings)
    local queue = {}
    local function add_job(relative_dir, path)
        if path and lfs.attributes(path, "mode") == "file" then
            queue[#queue + 1] = {
                server = OutputSettings.build_library_sync_server(
                    snapshot.base_server, settings, relative_dir),
                path = path,
            }
        end
    end
    add_job("books", book_local)
    add_job("", master_local)
    local quotes_dir = LibraryExport.get_quotes_dir()
    for _, item in ipairs(Merge.normalize_to_list(refresh.annotations or {})) do
        if LibraryExport.is_library_exportable(item, settings) then
            local quote_path = LibraryExport.get_quote_path(item)
            if quote_path:find(quotes_dir, 1, true) and lfs.attributes(quote_path, "mode") == "file" then
                add_job("quotes", quote_path)
            end
        end
    end
    local tags_dir = LibraryExport.get_tags_dir()
    local bank = TagBank.ensure_bank(settings)
    local seen_tags = {}
    for _, item in ipairs(Merge.normalize_to_list(refresh.annotations or {})) do
        for _, tag_id in ipairs(Tags.expand_for_export(Tags.get_tags(item), bank)) do
            if not seen_tags[tag_id] then
                seen_tags[tag_id] = true
                local tag_path = LibraryExport.get_tag_index_path(tag_id)
                if lfs.attributes(tag_path, "mode") == "file" then
                    add_job("tags", tag_path)
                end
            end
        end
    end
    if settings.library_include_screenshots ~= false then
        local build_server = function(relative_dir)
            return OutputSettings.build_library_sync_server(
                snapshot.base_server, settings, relative_dir)
        end
        local shot_jobs = LibraryUpload.collectScreenshotJobs(
            refresh.annotations, settings, build_server)
        for _, job in ipairs(shot_jobs) do
            queue[#queue + 1] = job
        end
    end
    return LibraryUpload.collectChangedLibraryUploadQueue(
        queue, refresh.annotations, bank, settings)
end

local function finish_close_push(progress_token, status, deferred_msg)
    set_sync_status(status)
    SyncProgress.close(progress_token)
    if deferred_msg then
        SyncProgress.toast(deferred_msg, 4)
    end
end

--- Deferred push-only upload after book close (no plugin instance required).
function SyncBackground.schedule_close_push(snapshot)
    if not snapshot or not snapshot.sync_path or not snapshot.base_server then
        return
    end
    UIManager:scheduleIn(SyncBackground.CLOSE_SYNC_DEFER_SEC, function()
        if not SyncBackground.network_ready_for_raw_push() then
            set_sync_status(SyncStatus.DEFERRED)
            return
        end
        local progress_token = SyncProgress.show(_("Uploading highlights on close…"))
        local ok, err = pcall(function()
            local library_jobs = snapshot.library_jobs
            if not library_jobs and snapshot.library_refresh then
                library_jobs = build_close_library_jobs(snapshot)
            end
            local result = CloudStorageCompat.pushSyncFile(
                snapshot.base_server, snapshot.server, snapshot.sync_path)
            if result.conflict then
                logger.info("TagBankHighlightSync: close push conflict; full merge on next open")
                finish_close_push(progress_token, SyncStatus.DEFERRED, _(
                    "Highlight sync deferred — cloud copy changed. Will merge on next open."))
                return
            end
            if not result.ok then
                logger.warn("TagBankHighlightSync: close push upload failed")
                finish_close_push(progress_token, SyncStatus.FAILED, _(
                    "Highlight sync deferred — could not reach cloud server. Will retry on next open."))
                return
            end
            local library_ok = true
            if library_jobs and #library_jobs > 0 then
                library_ok = CloudStorageCompat.pushFileQueue(
                    snapshot.base_server, library_jobs)
            end
            if not library_ok then
                logger.warn("TagBankHighlightSync: close library upload failed")
                finish_close_push(progress_token, SyncStatus.FAILED, _(
                    "Highlight sync deferred — could not reach cloud server. Will retry on next open."))
                return
            end
            finish_close_push(progress_token, SyncStatus.SUCCESS)
        end)
        if not ok then
            logger.err("TagBankHighlightSync: close push error:", err)
            finish_close_push(progress_token, SyncStatus.FAILED, _(
                "Highlight sync deferred — could not reach cloud server. Will retry on next open."))
        end
    end)
end

--- Retry auto-sync after wake while Wi-Fi reconnects (NetworkListener restores async).
function SyncBackground.schedule_auto_sync_retry(plugin, try_fn)
    local attempts = 0
    local function try_once()
        attempts = attempts + 1
        if not plugin or not plugin.ui or not plugin:is_doc() then
            return
        end
        if SyncBackground.network_ready_for_merge_sync() then
            try_fn(plugin)
            return
        end
        if attempts < SyncBackground.RESUME_SYNC_MAX_ATTEMPTS then
            UIManager:scheduleIn(SyncBackground.RESUME_SYNC_RETRY_SEC, try_once)
        elseif plugin.settings then
            SyncStatus.apply(plugin.settings, SyncStatus.DEFERRED,
                os.date("%Y-%m-%d %H:%M:%S"))
            plugin:saveSettings()
        end
    end
    UIManager:scheduleIn(SyncBackground.RESUME_SYNC_INITIAL_DEFER_SEC, try_once)
end

return SyncBackground
