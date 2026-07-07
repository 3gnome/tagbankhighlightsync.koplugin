local Dispatcher = require("dispatcher")  -- luacheck:ignore
local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local FFIUtil = require("ffi/util")
local util = require("util")
local T = FFIUtil.template
local InfoMessage = require("ui/widget/infomessage")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Merge = require("merge")
local Export = require("export")
local OutputSettings = require("output_settings")
local SettingsMenu = require("settings_menu")
local BatchSync = require("batch_sync")
local TagDialog = require("tag_dialog")
local TagMenu = require("tag_menu")
local TagBank = require("tag_bank")
local LibraryExport = require("library_export")
local LibraryUpload = require("library_upload")
local CloudStorageCompat = require("cloudstorage_compat")
local SyncBackground = require("sync_background")
local SyncPostWrite = require("sync_post_write")
local SyncAllBooks = require("sync_all_books")
local Tags = require("tags")
local rapidjson = require("rapidjson")
local NetworkMgr = require("ui/network/manager")
local Device = require("device")
local logger = require("logger")

local is_reloading_due_to_sync = false

local SETTINGS_KEY = "tag_bank_highlight_sync"
local LEGACY_SETTINGS_KEY = "highlight_sync"

local TagBankHighlightSync = WidgetContainer:extend{
    name = "TagBankHighlightSync",
    is_doc_only = false,
}

TagBankHighlightSync.default_settings = {
    is_enabled = true,
    sync_on_open = false,
    sync_on_close = false,
    sync_on_resume = false,
    pending_sync = false,
    last_sync_time = nil,
}

function TagBankHighlightSync:loadSettings()
    local settings = G_reader_settings:readSetting(SETTINGS_KEY)
    if not settings then
        settings = G_reader_settings:readSetting(LEGACY_SETTINGS_KEY, self.default_settings)
        if settings then
            G_reader_settings:saveSetting(SETTINGS_KEY, settings)
        end
    end
    settings = settings or self.default_settings
    if settings.sync_server then
        CloudStorageCompat.normalizeSyncServer(settings.sync_server)
    end
    return settings
end

function TagBankHighlightSync:init()
    if self.document and self.document.is_pic then
        return
    end

    self.is_syncing = false
    self._sync_generation = 0
    self.settings = self:loadSettings()
    local layout_before = self.settings.tag_bank_layout_version or 0
    local export_before = self.settings.library_export_version or 1
    OutputSettings.merge_defaults(self.settings)
    if (self.settings.tag_bank_layout_version or 0) > layout_before
        or (self.settings.library_export_version or 1) > export_before then
        self:saveSettings()
    end
    CloudStorageCompat.applyPatches()
    UIManager:nextTick(function()
        CloudStorageCompat.ensureCloudSyncPatch(self.ui and self.ui.cloudstorage)
    end)
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self:registerSyncEvents()
end

function TagBankHighlightSync:registerSyncEvents()
    if not self.settings.is_enabled then
        self.onResume = nil
        self.onNetworkConnected = nil
        return
    end
    self.onResume = function()
        self:_onResume()
    end
    self.onNetworkConnected = function()
        self:_onNetworkConnected()
    end
end

function TagBankHighlightSync:shouldDeferResumeSync()
    return Device:hasWifiRestore()
        and NetworkMgr.wifi_was_on
        and G_reader_settings:isTrue("auto_restore_wifi")
end

function TagBankHighlightSync:runPendingAutoSyncIfReady()
    if self:canSync(true) and (self.settings.pending_sync or self.settings.sync_on_resume) then
        self:SyncBookHighlights(true, false, { background = true })
    end
end

--- Needed so PDF ext sub-table integer keys encode in JSON.
local function with_stringified_ext_keys(data)
    local function fix_annotation(annotation)
        if not annotation or type(annotation) ~= "table" then
            return annotation
        end
        if not annotation.ext then
            return annotation
        end
        local new_annotation = {}
        for k, v in pairs(annotation) do
            new_annotation[k] = v
        end
        local new_ext = {}
        for k, v in pairs(annotation.ext) do
            new_ext[tostring(k)] = v
        end
        new_annotation.ext = new_ext
        return new_annotation
    end

    if data.annotations and type(data.annotations) == "table" then
        local wrapped = {}
        for k, v in pairs(data) do
            wrapped[k] = v
        end
        wrapped.annotations = {}
        for i, ann in ipairs(data.annotations) do
            wrapped.annotations[i] = fix_annotation(ann)
        end
        return wrapped
    end

    local new_annotations = {}
    for i, annotation in ipairs(Merge.normalize_to_list(data)) do
        new_annotations[i] = fix_annotation(annotation)
    end
    return new_annotations
end

local function destringify_ext_keys(data)
    local function fix_item(annotation)
        if annotation and annotation.ext then
            local new_ext = {}
            for k, v in pairs(annotation.ext) do
                new_ext[tonumber(k) or k] = v
            end
            annotation.ext = new_ext
        end
    end

    if data.annotations then
        for _, ann in ipairs(Merge.normalize_to_list(data.annotations)) do
            fix_item(ann)
        end
        return
    end
    for _, ann in ipairs(Merge.normalize_to_list(data)) do
        fix_item(ann)
    end
end

local function read_json_file(path)
    local file = io.open(path, "r")
    if not file then
        return {}, true
    end
    local content = file:read("*a")
    file:close()
    if not content or content == "" then
        return {}, true
    end
    local ok, data = pcall(rapidjson.decode, content)
    if not ok or type(data) ~= "table" then
        logger.warn("TagBankHighlightSync: invalid JSON in", path)
        return {}, false
    end
    destringify_ext_keys(data)
    return data, true
end

local function encode_json(data, pretty)
    local payload = with_stringified_ext_keys(data)
    if pretty then
        return rapidjson.encode(payload, { pretty = true })
    end
    return rapidjson.encode(payload)
end

local function write_json_file(path, data, pretty)
    local encoded = encode_json(data, pretty)
    local tmp = path .. ".tmp"
    local file = io.open(tmp, "w")
    if not file then
        return false
    end
    file:write(encoded)
    file:close()
    if os.rename(tmp, path) then
        return true
    end
    file = io.open(path, "w")
    if not file then
        os.remove(tmp)
        return false
    end
    file:write(encoded)
    file:close()
    os.remove(tmp)
    return true
end

local function ensure_dir_exists(path)
    if path and path ~= "" then
        util.makePath(path)
    end
end

local function copy_file(src, dest)
    return BatchSync.copy_file(src, dest)
end

function TagBankHighlightSync:saveSettings()
    G_reader_settings:saveSetting(SETTINGS_KEY, self.settings)
    self:registerSyncEvents()
end

function TagBankHighlightSync:is_doc()
    return self.document ~= nil
end

function TagBankHighlightSync:isSyncDisabledForDoc()
    if not self.ui or not self.ui.doc_settings then
        return false
    end
    return self.ui.doc_settings:isTrue("highlight_sync_disabled")
end

--- Prefer live annotations; fall back to doc_settings when UI list not hydrated yet.
function TagBankHighlightSync:getAnnotationsForSync()
    local live = self.ui and self.ui.annotation and self.ui.annotation.annotations
    local live_list = Merge.normalize_to_list(live or {})
    if #live_list > 0 then
        return live
    end
    local stored = self.ui and self.ui.doc_settings
        and self.ui.doc_settings:readSetting("annotations")
    local stored_list = Merge.normalize_to_list(stored or {})
    if #stored_list > 0 then
        return stored
    end
    return live or stored or {}
end

function TagBankHighlightSync:invalidateInFlightSync(reason)
    self._sync_generation = (self._sync_generation or 0) + 1
end

function TagBankHighlightSync:isSyncGenerationCurrent(generation)
    return generation == (self._sync_generation or 0)
end

function TagBankHighlightSync:canSync(require_enabled)
    if require_enabled and not self.settings.is_enabled then
        return false
    end
    if not self:is_doc() then
        return false
    end
    if self:isSyncDisabledForDoc() then
        return false
    end
    return self.settings.sync_server ~= nil and self.ui.cloudstorage ~= nil
end

function TagBankHighlightSync:buildSyncContext()
    local doc_path = self.document and self.document.file
    local doc_settings = self.ui and self.ui.doc_settings
    if not doc_settings or not doc_path then
        return nil
    end
    local sidecar_dir = doc_settings:getSidecarDir(doc_path)
    local sidecar_name = OutputSettings.get_sidecar_name(sidecar_dir)
    local book_title = OutputSettings.get_book_title(self.document)
    local doc_meta = OutputSettings.extract_doc_metadata(self.document, self.ui)
    local doc_hash = OutputSettings.get_doc_hash(doc_path)
    local filename = OutputSettings.resolve_filename(self.settings, {
        sidecar_name = sidecar_name,
        book_title = book_title,
        doc_hash = doc_hash,
    })
    return {
        doc_path = doc_path,
        doc_settings = doc_settings,
        sidecar_dir = sidecar_dir,
        sidecar_name = sidecar_name,
        book_title = book_title,
        doc_hash = doc_hash,
        filename = filename,
        sync_path = sidecar_dir .. "/" .. filename .. ".json",
        metadata = {
            book_title = book_title,
            doc_title = doc_meta.doc_title or book_title,
            author = doc_meta.author or "",
            series = doc_meta.series,
            language = doc_meta.language,
            sidecar_name = sidecar_name,
            device_id = G_reader_settings:readSetting("device_id"),
            sync_datetime = os.date("%Y-%m-%d %H:%M:%S"),
            tag_bank = TagBank.ensure_bank(self.settings),
        },
    }
end

function TagBankHighlightSync:buildSyncContextForPath(doc_path)
    if not doc_path then
        return nil
    end
    local DocSettings = require("docsettings")
    local ok, doc_settings = pcall(DocSettings.open, DocSettings, doc_path)
    if not ok or not doc_settings then
        return nil
    end
    local sidecar_dir = doc_settings:getSidecarDir(doc_path)
    local sidecar_name = OutputSettings.get_sidecar_name(sidecar_dir)
    local props = doc_settings:readSetting("doc_props") or {}
    local book_title = props.title and props.title ~= "" and props.title
        or doc_path:gsub(".*/", ""):gsub("%.[^%.]+$", "")
    local doc_hash = OutputSettings.get_doc_hash(doc_path)
    local filename = OutputSettings.resolve_filename(self.settings, {
        sidecar_name = sidecar_name,
        book_title = book_title,
        doc_hash = doc_hash,
    })
    local author = props.authors
    if type(author) == "table" then
        author = table.concat(author, ", ")
    end
    return {
        doc_path = doc_path,
        doc_settings = doc_settings,
        sidecar_dir = sidecar_dir,
        sidecar_name = sidecar_name,
        book_title = book_title,
        doc_hash = doc_hash,
        filename = filename,
        sync_path = sidecar_dir .. "/" .. filename .. ".json",
        metadata = {
            book_title = book_title,
            doc_title = props.title or book_title,
            author = author or "",
            series = props.series,
            language = props.language,
            sidecar_name = sidecar_name,
            device_id = G_reader_settings:readSetting("device_id"),
            sync_datetime = os.date("%Y-%m-%d %H:%M:%S"),
            tag_bank = TagBank.ensure_bank(self.settings),
        },
    }
end

function TagBankHighlightSync:getAnnotationsForPath(doc_path)
    if self:is_doc() and self.document and self.document.file == doc_path then
        return self:getAnnotationsForSync()
    end
    local DocSettings = require("docsettings")
    local ok, doc_settings = pcall(DocSettings.open, DocSettings, doc_path)
    if ok and doc_settings then
        return doc_settings:readSetting("annotations") or {}
    end
    return {}
end

function TagBankHighlightSync:persistMergedToDocSettings(doc_settings, full_annotations, merged_syncable)
    if not doc_settings then
        return
    end
    local is_syncable = function(item)
        return OutputSettings.is_syncable_annotation(item, self.settings)
    end
    local persisted = Merge.merge_back_into_full(full_annotations, merged_syncable, is_syncable)
    doc_settings:saveSetting("annotations", persisted)
    doc_settings:saveSetting("annotations_externally_modified", true)
    doc_settings:flush()
end

--- Merge + persist for a book that may not be the open document.
function TagBankHighlightSync:onSyncForPath(ctx, local_path, cached_path, income_path, reload, defer_library)
    local full_annotations = Merge.normalize_to_list(self:getAnnotationsForPath(ctx.doc_path))
    local local_highlights = OutputSettings.filter_annotations(full_annotations, self.settings)

    local cached_raw, cached_ok = read_json_file(cached_path)
    if not cached_ok then
        logger.warn("TagBankHighlightSync: cached sync snapshot unreadable:", cached_path)
    end
    local cached_highlights = OutputSettings.unwrap_payload(cached_raw)
    local income_highlights = OutputSettings.unwrap_payload(select(1, read_json_file(income_path)))

    if self.settings.backup_before_sync and lfs.attributes(local_path, "mode") == "file" then
        if not copy_file(local_path, local_path .. ".bak") then
            logger.warn("TagBankHighlightSync: backup failed:", local_path)
        end
    end

    local merged = Merge.Merge_highlights(local_highlights, income_highlights, cached_highlights)
    local payload = OutputSettings.prepare_for_write(merged, self.settings, ctx.metadata)

    if not write_json_file(ctx.sync_path, payload, self.settings.json_pretty) then
        logger.err("TagBankHighlightSync: failed to write sync file:", ctx.sync_path)
        return false
    end

    if not defer_library then
        local base = ctx.sync_path:gsub("%.json$", "")
        SyncPostWrite.safe_step("export", function()
            Export.write_exports(base, merged, self.settings, ctx.metadata)
        end)
        SyncPostWrite.safe_step("mirror", function()
            self:mirrorSyncFiles(ctx, merged)
        end)
    end

    if self:is_doc() and self.document and self.document.file == ctx.doc_path then
        self:persistMergedAnnotations(full_annotations, merged, reload, defer_library)
    else
        self:persistMergedToDocSettings(ctx.doc_settings, full_annotations, merged)
    end

    if not defer_library then
        SyncPostWrite.safe_step("library refresh", function()
            self:refreshLibraryFiles(ctx, full_annotations)
        end)
    end

    self.settings.last_sync_time = os.date("%Y-%m-%d %H:%M:%S")
    self:saveSettings()
    return true, merged
end

function TagBankHighlightSync:canSyncAll()
    if not self.settings.is_enabled then
        return false
    end
    if not self.settings.sync_server then
        return false
    end
    return self.ui and self.ui.cloudstorage ~= nil
end

function TagBankHighlightSync:syncBookAtPath(doc_path, silent, on_done)
    local ctx = self:buildSyncContextForPath(doc_path)
    if not ctx then
        if on_done then on_done(false) end
        return
    end
    local filtered = OutputSettings.filter_annotations(
        Merge.normalize_to_list(self:getAnnotationsForPath(doc_path)), self.settings)
    if #filtered == 0 then
        if on_done then on_done(true) end
        return
    end

    ensure_dir_exists(ctx.sidecar_dir)
    ctx.metadata.sync_datetime = os.date("%Y-%m-%d %H:%M:%S")
    local payload = OutputSettings.prepare_for_write(filtered, self.settings, ctx.metadata)
    if not write_json_file(ctx.sync_path, payload, self.settings.json_pretty) then
        if on_done then on_done(false) end
        return
    end

    local cs = self.ui.cloudstorage
    local server = OutputSettings.build_sync_server(self.settings.sync_server, self.settings, ctx)
    cs:sync(server, ctx.sync_path, function(local_path, cached_path, income_path)
        if not local_path then
            if on_done then on_done(false) end
            return CloudStorageCompat.SYNC_ABORT
        end
        local ok, success = pcall(function()
            return self:onSyncForPath(ctx, local_path, cached_path, income_path, false, false)
        end)
        if not ok then
            logger.err("TagBankHighlightSync: sync at path failed:", success)
            if on_done then on_done(false) end
            return CloudStorageCompat.SYNC_ABORT
        end
        if on_done then on_done(success) end
        return success
    end, silent)
end

function TagBankHighlightSync:syncAllBooksFromHistory(opts)
    opts = opts or {}
    if not self:canSyncAll() then
        if not opts.silent then
            UIManager:show(InfoMessage:new{
                text = _("Configure Cloud folder in Tag Bank Highlight Sync first."),
                timeout = 3,
            })
        end
        return
    end
    if self.is_syncing or self._sync_all_in_progress then
        if not opts.silent then
            UIManager:show(InfoMessage:new{
                text = _("Highlight sync already in progress."),
                timeout = 2,
            })
        end
        return
    end

    local current = self.document and self.document.file
    local books = SyncAllBooks.discover_books_with_syncable_highlights(current, self.settings)
    if #books == 0 then
        if not opts.silent then
            UIManager:show(InfoMessage:new{
                text = _("No highlights to sync in reading history."),
                timeout = 3,
            })
        end
        return
    end

    CloudStorageCompat.ensureCloudSyncPatch(self.ui.cloudstorage)

    local function start_batch()
        self._sync_all_in_progress = true
        self.is_syncing = true
        local idx = 1
        local failures = 0
        local total = #books
        local prog_notif

        local function show_progress(label)
            if prog_notif then UIManager:close(prog_notif) end
            prog_notif = InfoMessage:new{
                text = label,
                timeout = 120,
            }
            UIManager:show(prog_notif)
        end

        local function finish_batch()
            self.is_syncing = false
            self._sync_all_in_progress = false
            if prog_notif then UIManager:close(prog_notif) end
            if not opts.silent then
                local msg
                if failures == 0 then
                    msg = T(_("Synced highlights from %1 book(s)."), total)
                else
                    msg = T(_("Synced %1 book(s); %2 failed."),
                        total - failures, failures)
                end
                UIManager:show(InfoMessage:new{
                    text = msg,
                    timeout = 4,
                })
            end
            if opts.on_done then
                opts.on_done(failures == 0, total, failures)
            end
        end

        local function sync_next()
            if idx > total then
                finish_batch()
                return
            end
            local book = books[idx]
            local n = idx
            idx = idx + 1
            show_progress(T(_("Syncing %1 (%2/%3)…"), book.title, n, total))
            self:syncBookAtPath(book.path, true, function(ok)
                if not ok then
                    failures = failures + 1
                end
                sync_next()
            end)
        end

        sync_next()
    end

    if not SyncBackground.network_ready_for_merge_sync() then
        if NetworkMgr:willRerunWhenConnected(start_batch) then
            return
        end
        if not opts.silent then
            UIManager:show(InfoMessage:new{
                text = _("Network is not available for highlight sync."),
                timeout = 3,
            })
        end
        return
    end

    NetworkMgr:runWhenOnline(start_batch)
end

--- Write sidecar JSON from current annotations (no network, no merge).
function TagBankHighlightSync:flushLocalSyncJson(ctx, opts)
    opts = opts or {}
    if not ctx or not self.ui or not self.ui.annotation then
        return false
    end
    ensure_dir_exists(ctx.sidecar_dir)
    ctx.metadata.sync_datetime = os.date("%Y-%m-%d %H:%M:%S")
    local filtered = OutputSettings.filter_annotations(
        self:getAnnotationsForSync(), self.settings)
    local pretty = not opts.compact and self.settings.json_pretty
    local payload = OutputSettings.prepare_for_write(filtered, self.settings, ctx.metadata)
    if not write_json_file(ctx.sync_path, payload, pretty) then
        return false
    end
    if not opts.skip_exports and self.settings.export_enabled then
        Export.write_exports(ctx.sync_path:gsub("%.json$", ""), filtered, self.settings, ctx.metadata)
    end
    return true
end

function TagBankHighlightSync:buildClosePushSnapshot(ctx, filtered_annotations)
    if not ctx or not self.settings.sync_server then
        return nil
    end
    local base_server = {}
    for k, v in pairs(self.settings.sync_server) do
        base_server[k] = v
    end
    CloudStorageCompat.normalizeSyncServer(base_server)
    local snapshot = {
        sync_path = ctx.sync_path,
        base_server = base_server,
        server = OutputSettings.build_sync_server(base_server, self.settings, ctx),
    }
    if self.settings.tagged_library_enabled and filtered_annotations then
        snapshot.library_refresh = {
            filename = ctx.filename,
            sidecar_name = ctx.sidecar_name,
            metadata = ctx.metadata,
            annotations = filtered_annotations,
        }
    end
    return snapshot
end

function TagBankHighlightSync:releaseSyncLock()
    self.is_syncing = false
end

--- CreDocument keeps _document=false until the engine is loaded; avoid touching it mid-reload.
function TagBankHighlightSync:isDocumentEngineReady()
    local doc = self.document
    if not doc then
        return false
    end
    local inner = doc._document
    if inner == false or inner == nil then
        return false
    end
    if self.ui and (self.ui.tearing_down or self.ui.reloading) then
        return false
    end
    return true
end

function TagBankHighlightSync:scheduleReloadAfterSync()
    local attempts = 0
    local max_attempts = 60
    local function try_reload()
        attempts = attempts + 1
        if not self.ui or not self.document then
            is_reloading_due_to_sync = false
            return
        end
        if not self:isDocumentEngineReady() then
            if attempts >= max_attempts then
                is_reloading_due_to_sync = false
                logger.warn("TagBankHighlightSync: reload after sync skipped (document not ready)")
                return
            end
            UIManager:tickAfterNext(try_reload)
            return
        end
        local ok, err = pcall(function()
            self.ui:reloadDocument()
        end)
        if not ok then
            is_reloading_due_to_sync = false
            logger.warn("TagBankHighlightSync: reload after sync failed:", err)
        end
    end
    is_reloading_due_to_sync = true
    UIManager:tickAfterNext(try_reload)
end

function TagBankHighlightSync:persistMergedAnnotations(full_annotations, merged_syncable, reload, lightweight)
    if not self.ui or not self.ui.annotation then
        return
    end
    local is_syncable = function(item)
        return OutputSettings.is_syncable_annotation(item, self.settings)
    end
    local persisted = Merge.merge_back_into_full(full_annotations, merged_syncable, is_syncable)
    self.ui.annotation.annotations = persisted
    if self.ui.doc_settings then
        self.ui.doc_settings:saveSetting("annotations", persisted)
        self.ui.doc_settings:saveSetting("annotations_externally_modified", true)
        if lightweight then
            self.ui.annotation.needs_update = true
        elseif not reload and self:is_doc() and self:isDocumentEngineReady() then
            local ok, err = pcall(function()
                self.ui.annotation:updateAnnotations(true, true)
            end)
            if not ok then
                logger.warn("TagBankHighlightSync: updateAnnotations failed:", err)
                self.ui.annotation.needs_update = true
            end
        elseif not reload then
            self.ui.annotation.needs_update = true
        end
    end
    if reload then
        self:scheduleReloadAfterSync()
    end
end

function TagBankHighlightSync:mirrorSyncFiles(ctx, annotations)
    local mirror_path = self.settings.mirror_path or ""
    if not self.settings.mirror_enabled or mirror_path:match("^%s*$") then
        return
    end
    ensure_dir_exists(mirror_path)
    local base = mirror_path .. "/" .. ctx.filename
    copy_file(ctx.sync_path, base .. ".json")
    Export.write_exports(base, annotations, self.settings, ctx.metadata)
end

function TagBankHighlightSync:onSync(ctx, local_path, cached_path, income_path, reload)
    local full_annotations = Merge.normalize_to_list(self:getAnnotationsForSync())
    local local_highlights = OutputSettings.filter_annotations(full_annotations, self.settings)

    local cached_raw, cached_ok = read_json_file(cached_path)
    if not cached_ok then
        logger.warn("TagBankHighlightSync: cached sync snapshot unreadable:", cached_path)
    end
    local cached_highlights = OutputSettings.unwrap_payload(cached_raw)
    local income_highlights = OutputSettings.unwrap_payload(select(1, read_json_file(income_path)))

    if self.settings.backup_before_sync and lfs.attributes(local_path, "mode") == "file" then
        if not copy_file(local_path, local_path .. ".bak") then
            logger.warn("TagBankHighlightSync: backup failed:", local_path)
        end
    end

    local merged = Merge.Merge_highlights(local_highlights, income_highlights, cached_highlights)
    local payload = OutputSettings.prepare_for_write(merged, self.settings, ctx.metadata)

    if not write_json_file(ctx.sync_path, payload, self.settings.json_pretty) then
        logger.err("TagBankHighlightSync: failed to write sync file:", ctx.sync_path)
        return false
    end

    local defer_library = SyncBackground.should_defer_library(self._sync_opts)
    SyncPostWrite.run(self, ctx, merged, full_annotations, reload, defer_library)

    self.settings.last_sync_time = os.date("%Y-%m-%d %H:%M:%S")
    self:saveSettings()
    return true, merged
end

function TagBankHighlightSync:scheduleBackgroundLibraryWork(ctx, annotations, server)
    UIManager:scheduleIn(1, function()
        if not self.ui then
            return
        end
        self:refreshLibraryFiles(ctx, annotations)
        local function after_exports(exports_ok)
            if self.settings.tagged_library_enabled then
                self:uploadLibraryFiles(ctx, nil, function() end, {
                    background = true,
                    annotations = annotations,
                })
            end
        end
        if self.settings.export_enabled and server then
            self:uploadExportFiles(ctx, server, after_exports)
        elseif self.settings.tagged_library_enabled then
            self:uploadLibraryFiles(ctx, nil, function() end, {
                background = true,
                annotations = annotations,
            })
        end
    end)
end

local EXPORT_EXTENSIONS = {
    markdown = "md",
    md = "md",
    txt = "txt",
    csv = "csv",
}

function TagBankHighlightSync:ensureRemoteLibrarySubdir(base_server, settings, parent_relative, folder_name, on_done)
    local cs = self.ui and self.ui.cloudstorage
    if not cs or not base_server then
        if on_done then on_done() end
        return
    end
    local parent = OutputSettings.build_library_sync_server(base_server, settings, parent_relative)
    local provider = parent.type and cs.providers[parent.type]
    if not provider or not provider.createFolder then
        if on_done then on_done() end
        return
    end
    provider.base = parent
    local finish = function()
        provider.createFolder(parent.url, folder_name)
        if on_done then on_done() end
    end
    if provider.run then
        provider.run(finish)
    else
        finish()
    end
end

function TagBankHighlightSync:uploadScreenshotFile(job, on_done)
    local ok = CloudStorageCompat.uploadBinaryFile(
        self.settings.sync_server, job.server.url, job.path)
    if ok then
        FFIUtil.copyFile(job.path, job.path .. ".sync")
    else
        logger.warn("TagBankHighlightSync: screenshot upload failed:", job.path)
    end
    if on_done then on_done(ok) end
end

function TagBankHighlightSync:runCloudUploadQueue(queue, on_done)
    local cs = self.ui and self.ui.cloudstorage
    if not cs or #queue == 0 then
        if on_done then on_done(true) end
        return
    end
    local idx = 1
    local all_ok = true
    local function upload_next()
        if idx > #queue then
            if on_done then on_done(all_ok) end
            return
        end
        local job = queue[idx]
        idx = idx + 1
        if job.kind == "screenshot" then
            self:uploadScreenshotFile(job, function(ok)
                if not ok then
                    all_ok = false
                end
                upload_next()
            end)
            return
        end
        cs:sync(job.server, job.path, function()
            if job.on_result then
                all_ok = job.on_result(all_ok) and all_ok
            end
            upload_next()
            return true
        end, true)
    end
    upload_next()
end

function TagBankHighlightSync:uploadExportFiles(ctx, server, on_done)
    if not self.settings.export_enabled then
        if on_done then on_done(true) end
        return
    end
    local cs = self.ui.cloudstorage
    if not cs then
        if on_done then on_done(false) end
        return
    end

    local queue = {}
    local base = ctx.sync_path:gsub("%.json$", "")
    for _, fmt in ipairs(self.settings.export_formats or {}) do
        local ext = EXPORT_EXTENSIONS[fmt]
        if ext then
            local local_export = base .. "." .. ext
            if lfs.attributes(local_export, "mode") == "file" then
                queue[#queue + 1] = { server = server, path = local_export }
            end
        end
    end
    self:runCloudUploadQueue(queue, on_done)
end

function TagBankHighlightSync:refreshLibraryFiles(ctx, annotations)
    if not self.settings.tagged_library_enabled then
        return
    end
    if not ctx or not ctx.metadata then
        logger.warn("TagBankHighlightSync: refreshLibraryFiles missing context")
        return
    end
    LibraryExport.refresh_book_library(ctx, annotations, self.settings)
    self:saveSettings()
end

function TagBankHighlightSync:markLibrarySynced(ann)
    if not ann then
        return
    end
    local bank = TagBank.ensure_bank(self.settings)
    local expanded = Tags.expand_for_export(Tags.get_tags(ann), bank)
    Tags.set_library_sync_state(ann, Tags.compute_library_hash(ann, expanded))
    if self.ui and self.ui.doc_settings then
        self.ui.doc_settings:saveSetting("annotations", self.ui.annotation.annotations)
    end
end

function TagBankHighlightSync:refreshLibraryForBook(ctx, annotations)
    if not self.settings.tagged_library_enabled then
        return
    end
    self:refreshLibraryFiles(ctx, annotations)
end

function TagBankHighlightSync:collectLibraryUploadQueue(ctx, annotations, upload_opts)
    upload_opts = upload_opts or {}
    local background = upload_opts.background == true
    local queue = {}
    if not self.settings.tagged_library_enabled then
        return queue
    end
    annotations = annotations or (self.ui and self.ui.annotation and self.ui.annotation.annotations) or {}
    LibraryExport.ensure_library_assets(self.settings)
    local book_local = LibraryExport.get_book_path(ctx.filename)
    local master_local = LibraryExport.get_master_path(self.settings)

    if lfs.attributes(book_local, "mode") == "file" then
        queue[#queue + 1] = {
            server = OutputSettings.build_library_sync_server(
                self.settings.sync_server, self.settings, "books"),
            path = book_local,
        }
    end
    if lfs.attributes(master_local, "mode") == "file" then
        queue[#queue + 1] = {
            server = OutputSettings.build_library_sync_server(
                self.settings.sync_server, self.settings, ""),
            path = master_local,
        }
    end
    if not background then
        local readme_local = LibraryExport.get_readme_path()
        if lfs.attributes(readme_local, "mode") == "file" then
            queue[#queue + 1] = {
                server = OutputSettings.build_library_sync_server(
                    self.settings.sync_server, self.settings, ""),
                path = readme_local,
            }
        end
        local templates_dir = LibraryExport.get_templates_dir()
        if lfs.attributes(templates_dir, "mode") == "directory" then
            for name in lfs.dir(templates_dir) do
                if name ~= "." and name ~= ".." and name:match("%.md$") then
                    queue[#queue + 1] = {
                        server = OutputSettings.build_library_sync_server(
                            self.settings.sync_server, self.settings, "templates"),
                        path = templates_dir .. "/" .. name,
                    }
                end
            end
            local snippets_dir = templates_dir .. "/obsidian-snippets"
            if lfs.attributes(snippets_dir, "mode") == "directory" then
                for name in lfs.dir(snippets_dir) do
                    if name ~= "." and name ~= ".." then
                        local snippet_local = snippets_dir .. "/" .. name
                        if lfs.attributes(snippet_local, "mode") == "file" then
                            queue[#queue + 1] = {
                                server = OutputSettings.build_library_sync_server(
                                    self.settings.sync_server, self.settings, "templates/obsidian-snippets"),
                                path = snippet_local,
                            }
                        end
                    end
                end
            end
        end
    end
    if background then
        local bank = TagBank.ensure_bank(self.settings)
        local seen_tags = {}
        for _, item in ipairs(Merge.normalize_to_list(annotations)) do
            for _, tag_id in ipairs(Tags.expand_for_export(Tags.get_tags(item), bank)) do
                if not seen_tags[tag_id] then
                    seen_tags[tag_id] = true
                    local tag_path = LibraryExport.get_tag_index_path(tag_id)
                    if lfs.attributes(tag_path, "mode") == "file" then
                        queue[#queue + 1] = {
                            server = OutputSettings.build_library_sync_server(
                                self.settings.sync_server, self.settings, "tags"),
                            path = tag_path,
                        }
                    end
                end
            end
        end
        for _, item in ipairs(Merge.normalize_to_list(annotations)) do
            if LibraryExport.is_library_exportable(item, self.settings) then
                local quote_path = LibraryExport.get_quote_path(item)
                if lfs.attributes(quote_path, "mode") == "file" then
                    queue[#queue + 1] = {
                        server = OutputSettings.build_library_sync_server(
                            self.settings.sync_server, self.settings, "quotes"),
                        path = quote_path,
                    }
                end
            end
        end
    else
        local tags_dir = LibraryExport.get_tags_dir()
        if lfs.attributes(tags_dir, "mode") == "directory" then
            for name in lfs.dir(tags_dir) do
                if name ~= "." and name ~= ".." and name:match("%.md$") then
                    queue[#queue + 1] = {
                        server = OutputSettings.build_library_sync_server(
                            self.settings.sync_server, self.settings, "tags"),
                        path = tags_dir .. "/" .. name,
                    }
                end
            end
        end
        local quotes_dir = LibraryExport.get_quotes_dir()
        if lfs.attributes(quotes_dir, "mode") == "directory" then
            for name in lfs.dir(quotes_dir) do
                if name ~= "." and name ~= ".." and name:match("%.md$") then
                    queue[#queue + 1] = {
                        server = OutputSettings.build_library_sync_server(
                            self.settings.sync_server, self.settings, "quotes"),
                        path = quotes_dir .. "/" .. name,
                    }
                end
            end
        end
    end
    if self.settings.library_include_screenshots ~= false then
        local build_server = function(relative_dir)
            return OutputSettings.build_library_sync_server(
                self.settings.sync_server, self.settings, relative_dir)
        end
        local shot_jobs = LibraryUpload.collectScreenshotJobs(
            annotations, self.settings, build_server)
        for _, job in ipairs(shot_jobs) do
            queue[#queue + 1] = job
        end
    end
    return queue
end

function TagBankHighlightSync:prepareLibraryUploadQueue(ctx, annotations, target_ann, upload_opts)
    upload_opts = upload_opts or {}
    local queue = self:collectLibraryUploadQueue(ctx, annotations, upload_opts)
    if upload_opts.background then
        local bank = TagBank.ensure_bank(self.settings)
        queue = LibraryUpload.collectChangedLibraryUploadQueue(
            queue, annotations, bank, self.settings)
    end
    queue = LibraryUpload.prioritizeLibraryUploadQueue(queue, target_ann, function(item)
        return LibraryExport.get_quote_path(item)
    end)
    return queue
end

function TagBankHighlightSync:buildLibraryContext(ctx)
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

function TagBankHighlightSync:uploadLibraryFiles(ctx, target_ann, on_done, upload_opts)
    if not self.settings.tagged_library_enabled then
        if on_done then on_done(true) end
        return true
    end
    if not self.settings.sync_server or not self.ui.cloudstorage then
        if on_done then on_done(false) end
        return false
    end
    local bank = TagBank.ensure_bank(self.settings)
    local target_needs_work = target_ann
        and LibraryExport.is_library_exportable(target_ann, self.settings)
        and LibraryUpload.target_needs_library_work(target_ann, bank, self.settings)
    if target_ann and LibraryExport.is_library_exportable(target_ann, self.settings) then
        if not target_needs_work then
            if on_done then on_done(true) end
            return true
        end
    end
    self:saveSettings()
    local upload_annotations = (upload_opts and upload_opts.annotations)
        or (self.ui and self.ui.annotation and self.ui.annotation.annotations)
    if target_needs_work and target_ann and ctx then
        local quote_path = LibraryExport.get_quote_path(target_ann)
        if lfs.attributes(quote_path, "mode") ~= "file" then
            local lib_ctx = self:buildLibraryContext(ctx)
            if lib_ctx then
                LibraryExport.refresh_target_for_sync(
                    target_ann, lib_ctx, upload_annotations, self.settings)
            end
        end
    end
    local queue = self:prepareLibraryUploadQueue(ctx, upload_annotations, target_ann, upload_opts)
    local has_screenshots = false
    for _, job in ipairs(queue) do
        if job.kind == "screenshot" then
            has_screenshots = true
            break
        end
    end
    local background = upload_opts and upload_opts.background
    local function finish_upload(all_ok)
        if all_ok and target_ann and not LibraryUpload.verifyScreenshotUploads(target_ann) then
            all_ok = false
            if not background then
                logger.warn("TagBankHighlightSync: screenshot missing .sync after upload:",
                    LibraryExport.get_quote_image_path(target_ann))
            end
        end
        if all_ok and target_needs_work and target_ann then
            local quote_path = LibraryExport.get_quote_path(target_ann)
            if lfs.attributes(quote_path, "mode") ~= "file" then
                all_ok = false
                if not background then
                    logger.warn("TagBankHighlightSync: quote file missing after library upload:",
                        quote_path)
                end
            end
        end
        if all_ok then
            if self.settings.library_force_reupload then
                self.settings.library_force_reupload = false
                self:saveSettings()
            end
            if target_ann then
                self:markLibrarySynced(target_ann)
            end
        elseif background and target_ann and Tags.has_capture(target_ann) then
            logger.warn("TagBankHighlightSync: background library upload incomplete for capture")
        end
        if on_done then on_done(all_ok) end
    end
    local function start_uploads()
        self:runCloudUploadQueue(queue, finish_upload)
    end
    if has_screenshots and not background then
        self:ensureRemoteLibrarySubdir(
            self.settings.sync_server, self.settings, "quotes", "images", start_uploads)
    else
        start_uploads()
    end
    return nil
end

function TagBankHighlightSync:syncNow(hl, resolved_index, ann)
    if not self:is_doc() then
        return
    end
    ann = ann or (hl and hl.ui and hl.ui.annotation.annotations[resolved_index])
    if not ann then
        UIManager:show(InfoMessage:new{
            text = _("Could not find this highlight."),
            timeout = 2,
        })
        return
    end

    TagBank.ensure_bank(self.settings)
    local has_tags = #Tags.get_tags(ann) > 0
    local has_capture = Tags.has_capture(ann)
    local force_reupload = self.settings.library_force_reupload == true
    local needs_lib = Tags.needs_library_sync(ann, self.settings.tag_bank)
    local untagged_lib = LibraryExport.is_untagged_library_export(ann, self.settings)
    local needs_library = force_reupload or needs_lib or has_capture or untagged_lib
    local library_unchanged = self.settings.tagged_library_enabled
        and not LibraryUpload.target_needs_library_work(ann, self.settings.tag_bank, self.settings)

    if self.settings.tagged_library_enabled and needs_library then
        local ctx = self:buildSyncContext()
        if ctx then
            local lib_ctx = self:buildLibraryContext(ctx)
            if has_tags and (force_reupload or needs_lib) then
                if lib_ctx then
                    LibraryExport.refresh_target_for_sync(
                        ann, lib_ctx, self.ui.annotation.annotations, self.settings)
                end
            elseif lib_ctx and (force_reupload or needs_lib or has_capture or untagged_lib) then
                LibraryExport.refresh_target_for_sync(
                    ann, lib_ctx, self.ui.annotation.annotations, self.settings)
            end
        end
    end

    if self:canSync(true) then
        UIManager:show(InfoMessage:new{
            text = _("Syncing…"),
            timeout = 1,
        })
        self._sync_now_target_ann = ann
        self:SyncBookHighlights(false, false)
        return
    end

    if self.settings.tagged_library_enabled and needs_library then
        if library_unchanged then
            UIManager:show(InfoMessage:new{
                text = _("Already synced."),
                timeout = 2,
            })
            return
        end
        local ctx = self:buildSyncContext()
        if not ctx then
            UIManager:show(InfoMessage:new{
                text = _("Configure Cloud folder to upload library files."),
                timeout = 3,
            })
            return
        end
        self:uploadLibraryFiles(ctx, ann, function(all_ok)
            if all_ok then
                UIManager:show(InfoMessage:new{
                    text = _("Library synced."),
                    timeout = 2,
                })
            else
                UIManager:show(InfoMessage:new{
                    text = _("Library upload failed."),
                    timeout = 3,
                })
            end
        end)
        return
    end

    UIManager:show(InfoMessage:new{
        text = _("Configure Cloud folder or enable quote library."),
        timeout = 3,
    })
end

function TagBankHighlightSync:SyncBookHighlights(silent, reload, opts)
    opts = opts or {}
    if not self:canSync(true) then
        return
    end

    CloudStorageCompat.ensureCloudSyncPatch(self.ui and self.ui.cloudstorage)

    if self.is_syncing then
        logger.warn("TagBankHighlightSync: Duplicate sync attempt ignored.")
        return
    end

    self._sync_opts = opts
    local background = SyncBackground.should_defer_library(opts)

    local cs = self.ui.cloudstorage
    if not cs then
        if not silent then
            UIManager:show(InfoMessage:new{
                text = _("Cloud storage plugin is required for highlight sync."),
                timeout = 3,
            })
        end
        return
    end

    local do_sync = function()
        self.is_syncing = true
        local ctx = self:buildSyncContext()
        if not ctx then
            self._sync_opts = nil
            self:releaseSyncLock()
            return
        end
        ensure_dir_exists(ctx.sidecar_dir)

        ctx.filtered_annotations = OutputSettings.filter_annotations(
            self:getAnnotationsForSync(), self.settings)
        local payload = OutputSettings.prepare_for_write(
            ctx.filtered_annotations, self.settings, ctx.metadata)

        if not write_json_file(ctx.sync_path, payload, not background and self.settings.json_pretty) then
            self._sync_opts = nil
            self:releaseSyncLock()
            if not silent then
                UIManager:show(InfoMessage:new{
                    text = _("Failed to write highlight sync file."),
                    timeout = 3,
                })
            end
            return
        end

        if not background and self.settings.export_enabled then
            Export.write_exports(ctx.sync_path:gsub("%.json$", ""), ctx.filtered_annotations,
                self.settings, ctx.metadata)
        end

        local server = OutputSettings.build_sync_server(self.settings.sync_server, self.settings, ctx)
        local caller_pre = nil
        if not silent then
            caller_pre = function()
                UIManager:show(InfoMessage:new{
                    text = _("Syncing highlights…"),
                    timeout = 1,
                })
            end
        end

        local sync_generation = self._sync_generation or 0
        cs:sync(server, ctx.sync_path, function(local_path, cached_path, income_path)
            if not self:isSyncGenerationCurrent(sync_generation) then
                self:releaseSyncLock()
                self._sync_opts = nil
                return CloudStorageCompat.SYNC_ABORT
            end
            if not local_path then
                self:releaseSyncLock()
                self._sync_opts = nil
                return CloudStorageCompat.SYNC_ABORT
            end
            local ok, success, merged = pcall(function()
                return self:onSync(ctx, local_path, cached_path, income_path, reload)
            end)
            self:releaseSyncLock()
            self._sync_opts = nil
            local function show_followup_error(err)
                self._sync_now_target_ann = nil
                if not silent then
                    UIManager:show(InfoMessage:new{
                        text = T(_("Sync finished with upload errors: %1"),
                            SyncPostWrite.truncate_error(err)),
                        timeout = 4,
                    })
                end
            end
            local function safe_followup(name, fn)
                return SyncPostWrite.safe_invoke(name, fn, show_followup_error)
            end
            if not ok then
                logger.err("TagBankHighlightSync: merge failed:", success)
                if not silent then
                    UIManager:show(InfoMessage:new{
                        text = T(_("Highlight sync failed: %1"),
                            SyncPostWrite.truncate_error(success)),
                        timeout = 4,
                    })
                end
                return CloudStorageCompat.SYNC_ABORT
            end
            if not success then
                return false
            end
            if success then
                if self.settings.pending_sync then
                    self.settings.pending_sync = false
                    self:saveSettings()
                end
                if background and self:isSyncGenerationCurrent(sync_generation) then
                    self:scheduleBackgroundLibraryWork(ctx, merged, server)
                    return success
                end
                if background then
                    return success
                end
                safe_followup("sync follow-up", function()
                    self:uploadExportFiles(ctx, server, function(exports_ok)
                        safe_followup("sync follow-up callback", function()
                            local target = self._sync_now_target_ann
                            self._sync_now_target_ann = nil
                            local function finish_library(library_ok)
                                safe_followup("finish library", function()
                                    local all_ok = exports_ok and library_ok
                                    if target and self.settings.tagged_library_enabled then
                                        if all_ok then
                                            UIManager:show(InfoMessage:new{
                                                text = _("Sync complete."),
                                                timeout = 2,
                                            })
                                        else
                                            UIManager:show(InfoMessage:new{
                                                text = _("Sync finished with upload errors."),
                                                timeout = 3,
                                            })
                                        end
                                    elseif not silent and not all_ok then
                                        UIManager:show(InfoMessage:new{
                                            text = _("Sync finished with upload errors."),
                                            timeout = 3,
                                        })
                                    end
                                end)
                            end
                            if self.settings.tagged_library_enabled then
                                safe_followup("upload library", function()
                                    self:uploadLibraryFiles(ctx, target, finish_library)
                                end)
                            else
                                finish_library(true)
                            end
                        end)
                    end)
                end)
            end
            return success
        end, silent, caller_pre)
    end

    if not SyncBackground.network_ready_for_merge_sync() then
        if SyncBackground.should_queue_offline(silent, opts) then
            self.settings.pending_sync = true
            self:saveSettings()
            return
        end
        if NetworkMgr:willRerunWhenConnected(do_sync) then
            self.settings.pending_sync = true
            self:saveSettings()
        end
        return
    end
    do_sync()
end

function TagBankHighlightSync:onSyncBookHighlights()
    self:SyncBookHighlights(false, false)
end

function TagBankHighlightSync:onDispatcherRegisterActions()
    Dispatcher:registerAction("highlightsync_action", {
        category = "none",
        event = "SyncBookHighlights",
        title = _("Sync Highlights Now"),
        help = _("Synchronize highlights with the cloud."),
        reader = true,
    })
end

function TagBankHighlightSync:onReaderReady()
    TagDialog.register_highlight_dialog(self)
    if is_reloading_due_to_sync then
        is_reloading_due_to_sync = false
        return
    end
    if not self.settings.sync_on_open and not self.settings.pending_sync then
        return
    end
    local function try_open_sync(attempt)
        attempt = attempt or 0
        if is_reloading_due_to_sync then
            return
        end
        local live = self.ui and self.ui.annotation and self.ui.annotation.annotations
        local stored = self.ui and self.ui.doc_settings
            and self.ui.doc_settings:readSetting("annotations")
        local live_n = #OutputSettings.filter_annotations(live or {}, self.settings)
        local stored_n = #OutputSettings.filter_annotations(stored or {}, self.settings)
        if live_n == 0 and stored_n > 0 and attempt < 5 then
            UIManager:scheduleIn(1, function()
                try_open_sync(attempt + 1)
            end)
            return
        end
        if self:canSync(true) then
            self:SyncBookHighlights(true, false, { background = true })
        end
    end
    UIManager:scheduleIn(SyncBackground.OPEN_SYNC_DEFER_SEC, function()
        try_open_sync(0)
    end)
end

function TagBankHighlightSync:onCloseDocument()
    if is_reloading_due_to_sync then
        return
    end
    if not self.settings.sync_on_close then
        return
    end
    if not self:canSync(true) then
        return
    end
    self:invalidateInFlightSync("close document")
    local ctx = self:buildSyncContext()
    if not ctx then
        return
    end
    if not self:flushLocalSyncJson(ctx, { compact = true, skip_exports = true }) then
        logger.warn("TagBankHighlightSync: close sync local write failed:", ctx.sync_path)
        return
    end
    local filtered = OutputSettings.filter_annotations(
        self:getAnnotationsForSync(), self.settings)
    local snapshot = self:buildClosePushSnapshot(ctx, filtered)
    if not snapshot then
        return
    end
    if SyncBackground.network_ready_for_raw_push() then
        SyncBackground.schedule_close_push(snapshot)
    else
        self.settings.pending_sync = true
        self:saveSettings()
    end
end

function TagBankHighlightSync:_onResume()
    if not self.settings.sync_on_resume and not self.settings.pending_sync then
        return
    end
    if self:shouldDeferResumeSync() then
        return
    end
    SyncBackground.schedule_auto_sync_retry(self, function(plugin)
        plugin:runPendingAutoSyncIfReady()
    end)
end

function TagBankHighlightSync:_onNetworkConnected()
    if not self.settings.sync_on_resume and not self.settings.pending_sync then
        return
    end
    UIManager:scheduleIn(SyncBackground.NETWORK_CONNECTED_DEFER_SEC, function()
        if not self.ui then
            return
        end
        self:runPendingAutoSyncIfReady()
    end)
end

function TagBankHighlightSync:toggleSetting(key)
    self.settings[key] = not self.settings[key]
    self:saveSettings()
end

function TagBankHighlightSync:genSettingsMenu()
    return SettingsMenu.genSettingsMenu(self)
end

function TagBankHighlightSync:openCloudFolderPicker(touchmenu_instance, after_pick)
    CloudStorageCompat.applyPatches()
    local cs = self.ui.cloudstorage
    if not cs then
        UIManager:show(InfoMessage:new{
            text = _("Cloud storage plugin is required for highlight sync."),
            timeout = 3,
        })
        return
    end
    local bs_ok = pcall(require, "ui/widget/buttonselector")
    if not bs_ok then
        UIManager:show(InfoMessage:new{
            text = _("Cloud storage+ needs frontend/ui/widget/buttonselector.lua on KOReader v2026.03. Copy it from upstream KOReader into koreader/frontend/ui/widget/, then restart."),
            timeout = 6,
        })
        return
    end
    -- Same direct call as Tools → Cloud Storage menu (no deferred nextTick).
    local ok, err = pcall(function()
        cs:onShowCloudStorageList(function(sv)
            if after_pick then
                after_pick(CloudStorageCompat.normalizeSyncServer(sv))
            end
        end)
    end)
    if not ok then
        logger.err("TagBankHighlightSync openCloudFolderPicker failed:", err)
        UIManager:show(InfoMessage:new{
            text = T(_("Cloud storage failed to open: %1"), tostring(err)),
            timeout = 5,
        })
    end
end

function TagBankHighlightSync:setSyncRemoteFolder(touchmenu_instance)
    local cs = self.ui.cloudstorage
    if not cs then
        UIManager:show(InfoMessage:new{
            text = _("Cloud storage plugin is required for highlight sync."),
            timeout = 3,
        })
        return
    end
    local server = self.settings.sync_server
    if not server then
        self:openCloudFolderPicker(touchmenu_instance, function(sv)
            self.settings.sync_server = sv
            self:saveSettings()
            UIManager:show(InfoMessage:new{
                text = _("Cloud folder set."),
                timeout = 2,
            })
        end)
        return
    end
    local dialogue
    local buttons = {
        {
            {
                text = _("Delete"),
                enabled = server and true or false,
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Delete server info?"),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            UIManager:close(dialogue)
                            self.settings.sync_server = nil
                            self:saveSettings()
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    })
                end,
            },
            {
                text = _("Change folder…"),
                callback = function()
                    UIManager:close(dialogue)
                    self:openCloudFolderPicker(touchmenu_instance, function(sv)
                        local old = self.settings.sync_server
                        self.settings.sync_server = sv
                        if old and sv and (old.url ~= sv.url or old.address ~= sv.address) then
                            UIManager:show(InfoMessage:new{
                                text = _("Cloud folder changed. Move existing JSON files manually if needed."),
                                timeout = 4,
                            })
                        end
                        self:saveSettings()
                        if touchmenu_instance then
                            touchmenu_instance:updateItems()
                        end
                        UIManager:nextTick(function()
                            self:setSyncRemoteFolder(touchmenu_instance)
                        end)
                    end)
                end,
            },
            {
                text = _("Close"),
                callback = function()
                    UIManager:close(dialogue)
                end,
            },
        },
    }
    local text = cs:getServerNameType(server) or _("not set")
    if server then
        text = text .. "\n\n" .. T(_("Folder path:\n%1"), cs.getReadablePath(server))
            .. "\n\n" .. _("Set up the same cloud folder on each device to sync across your devices.")
            .. "\n\n" .. _("To change folder: tap Change folder…, tap your WebDAV server, open / (root), then long-press the bold row \"Long-press here to choose current folder\" and tap Choose.")
    end
    if self.settings.last_sync_time then
        text = text .. "\n\n" .. T(_("Last sync: %1"), self.settings.last_sync_time)
    end
    dialogue = ButtonDialog:new{
        title = T(_("Cloud storage: %1"), text),
        buttons = buttons,
    }
    UIManager:show(dialogue)
end

function TagBankHighlightSync:batchSyncCurrentFolder(touchmenu_instance)
    if not self.settings.sync_server or not self.ui.cloudstorage then
        UIManager:show(InfoMessage:new{
            text = _("Configure cloud sync before batch sync."),
            timeout = 3,
        })
        return
    end
    local root = self.ui.file_chooser and self.ui.file_chooser.path
    if not root then
        return
    end
    local files = BatchSync.find_sync_json_files(root)
    if #files == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No highlight sync JSON files found in this folder."),
            timeout = 3,
        })
        return
    end
    UIManager:show(InfoMessage:new{
        text = T(_("Batch syncing %1 files…"), #files),
        timeout = 2,
    })
    local cs = self.ui.cloudstorage
    local idx = 1
    local function sync_next()
        if idx > #files then
            if touchmenu_instance then touchmenu_instance:updateItems() end
            UIManager:show(InfoMessage:new{
                text = _("Batch sync complete."),
                timeout = 2,
            })
            return
        end
        local path = files[idx]
        idx = idx + 1
        local server = OutputSettings.build_sync_server(self.settings.sync_server, self.settings, {
            filename = path:match("([^/]+)%.json$") or "book",
            book_title = path:match("([^/]+)%.json$") or "book",
        })
        cs:sync(server, path, function()
            sync_next()
            return true
        end, true)
    end
    sync_next()
end

function TagBankHighlightSync:addToMainMenu(menu_items)
    local in_reader = self:is_doc()
    menu_items.tag_bank_highlight_sync = {
        text = _("Tag Bank Highlight Sync"),
        sub_item_table = {
            {
                text_func = function()
                    local cs = self.ui.cloudstorage
                    local text = cs and cs:getServerNameType(self.settings.sync_server)
                    return T(_("Cloud folder: %1"), text or _("not set"))
                end,
                callback = function(touchmenu_instance)
                    if not self.ui.cloudstorage then
                        UIManager:show(InfoMessage:new{
                            text = _("Cloud storage plugin is required for highlight sync."),
                            timeout = 3,
                        })
                        return
                    end
                    self:setSyncRemoteFolder(touchmenu_instance)
                end,
                keep_menu_open = true,
            },
            {
                text = _("Sync Highlights"),
                callback = function()
                    self:SyncBookHighlights(false, true)
                end,
                enabled_func = function()
                    return self:canSync(true)
                end,
                keep_menu_open = true,
                show_in_reader = true,
            },
            {
                text = _("Batch sync folder"),
                callback = function(touchmenu_instance)
                    self:batchSyncCurrentFolder(touchmenu_instance)
                end,
                enabled_func = function()
                    return self.settings.is_enabled and self.settings.sync_server ~= nil
                        and not in_reader
                end,
                keep_menu_open = true,
                show_in_filemanager = true,
            },
            {
                text = _("Settings"),
                sub_item_table_func = function()
                    return self:genSettingsMenu()
                end,
                keep_menu_open = true,
            },
        },
    }

    if in_reader then
        local filtered = {}
        for _, item in ipairs(menu_items.tag_bank_highlight_sync.sub_item_table) do
            if item.show_in_filemanager ~= true then
                filtered[#filtered + 1] = item
            end
        end
        menu_items.tag_bank_highlight_sync.sub_item_table = filtered
    else
        local filtered = {}
        for _, item in ipairs(menu_items.tag_bank_highlight_sync.sub_item_table) do
            if item.show_in_reader ~= true then
                filtered[#filtered + 1] = item
            end
        end
        menu_items.tag_bank_highlight_sync.sub_item_table = filtered
    end
end

require("insert_menu")

return TagBankHighlightSync
