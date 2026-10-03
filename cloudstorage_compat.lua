-- Runtime fixes for stock cloudstorage.koplugin on device.
-- The dev emulator applies equivalent patches on disk (patch-cloudstorage-emulator.sh);
-- Kindle/stable KOReader builds ship the unpatched plugin, where WebDAV root folder
-- choose passes url=nil and breaks TagBank's Cloud folder picker.

local CloudStorageCompat = {}

--- Sync callback return: merge threw or UI already shown; skip duplicate toast.
CloudStorageCompat.SYNC_ABORT = "tagbank_sync_abort"

function CloudStorageCompat.normalizeUrl(url)
    if url == nil or url == "" then
        return "/"
    end
    return url
end

function CloudStorageCompat.normalizeSyncServer(server)
    if not server then
        return server
    end
    server.url = CloudStorageCompat.normalizeUrl(server.url)
    return server
end

function CloudStorageCompat.applyPatches()
    local logger = require("logger")
    local BD = require("ui/bidi")
    local ButtonDialog = require("ui/widget/buttondialog")
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")

    local ok, CloudStorage = pcall(require, "cloudstorage")
    if not ok or type(CloudStorage) ~= "table" then
        logger.warn("TagBankHighlightSync: cloudstorage module not available for compat patches:", CloudStorage)
        return false
    end
    if CloudStorage._tagbank_compat_patched then
        return true
    end
    CloudStorage._tagbank_compat_patched = true

    local orig_sort = CloudStorage.sortItemTable
    if orig_sort then
        function CloudStorage:sortItemTable(tbl, url)
            return orig_sort(self, tbl, CloudStorageCompat.normalizeUrl(url))
        end
    end

    function CloudStorage:showFolderChooseDialog(item)
        local url = CloudStorageCompat.normalizeUrl(item and item.url)
        local folder_dialog
        folder_dialog = ButtonDialog:new{
            title = _("Choose this folder?") .. "\n\n" .. BD.dirpath(url) .. "\n",
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        callback = function()
                            UIManager:close(folder_dialog)
                        end,
                    },
                    {
                        text = _("Choose"),
                        callback = function()
                            UIManager:close(folder_dialog)
                            if self.caller_choose_folder_callback then
                                self:onClose()
                                local server = self.servers[self.server_idx]
                                self.caller_choose_folder_callback({
                                    name     = server.name,
                                    type     = server.type,
                                    address  = server.address,
                                    username = server.username,
                                    password = server.password,
                                    url      = url,
                                })
                            else
                                self.choose_folder_callback(url)
                                self:init(true)
                            end
                        end,
                    },
                },
            },
        }
        UIManager:show(folder_dialog)
    end

    logger.info("TagBankHighlightSync: applied cloudstorage compat patches")
    return true
end

--- Stock cloudstorage.koplugin shows a success toast even when is_silent is true.
--- TagBank uploads many files per sync (JSON, exports, library/) — without this,
--- opening a book with sync-on-open spams "Successfully synchronized."
function CloudStorageCompat.ensureCloudSyncPatch(cloud)
    if not cloud then
        return false
    end
    local mt = getmetatable(cloud)
    local cls = mt and mt.__index
    if not cls then
        return false
    end
    if cls._tagbank_sync_completion_v2 then
        return true
    end
    if type(cls.sync) ~= "function" then
        return false
    end

    local ffiUtil = require("ffi/util")
    local T = ffiUtil.template
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local Notification = require("ui/widget/notification")
    local NetworkMgr = require("ui/network/manager")
    local logger = require("logger")
    local _ = require("gettext")

    local function abort_sync(sync_cb)
        if sync_cb then
            pcall(sync_cb, nil, nil, nil)
        end
    end

    function cls:sync(server, file_path, sync_cb, is_silent, caller_pre_callback, completion_cb)
        local socketutil = require("socketutil")
        local completed = false
        local function complete(outcome)
            if completed then
                return
            end
            completed = true
            if completion_cb then
                local ok_complete, complete_err = pcall(completion_cb, outcome)
                if not ok_complete then
                    logger.err("TagBankHighlightSync: sync completion callback error:", complete_err)
                end
            end
        end

        local provider = server and server.type and self.providers[server.type]
        if not provider then
            abort_sync(sync_cb)
            complete{
                success = false,
                phase = "provider",
                reason = "missing_provider",
            }
            return
        end
        provider.base = server
        local function run_sync_work()
            if caller_pre_callback then
                local ok_pre, pre_err = pcall(caller_pre_callback)
                if not ok_pre then
                    logger.err("TagBankHighlightSync: sync pre-callback error:", pre_err)
                    complete{
                        success = false,
                        phase = "setup",
                        reason = "pre_callback_exception",
                        error = tostring(pre_err),
                    }
                    return
                end
            end
            UIManager:nextTick(function()
                local file_name = ffiUtil.basename(file_path)
                local income_file_path = file_path .. ".temp"
                local cached_file_path = file_path .. ".sync"
                local fail_msg = _("Something went wrong when syncing, please check your network connection and try again later.")
                local download_fail_msg = _("Could not download highlight sync file. Check Cloud folder and network.")
                local merge_fail_msg = _("Highlight sync failed (could not write sidecar JSON).")
                local upload_fail_msg = _("Could not upload highlight sync file. Check Cloud folder and network.")
                local show_msg = function(msg)
                    if is_silent then
                        return
                    end
                    UIManager:show(InfoMessage:new{
                        text = msg or fail_msg,
                        timeout = 3,
                    })
                end
                local function finish(outcome)
                    socketutil:reset_timeout()
                    os.remove(income_file_path)
                    complete(outcome)
                end
                local phase = "download"
                local ok_work, work_err = pcall(function()
                    socketutil:set_timeout(
                        socketutil.FILE_BLOCK_TIMEOUT,
                        socketutil.FILE_TOTAL_TIMEOUT)
                    local etag
                    local code_response = 412
                    local conflict_retries = 0
                    local MAX_CONFLICT_RETRIES = 3
                    while code_response == 412 do
                        if conflict_retries >= MAX_CONFLICT_RETRIES then
                            logger.warn("TagBankHighlightSync: sync conflict retries exhausted:",
                                conflict_retries)
                            abort_sync(sync_cb)
                            finish{
                                success = false,
                                phase = "conflict",
                                reason = "conflict_retries_exhausted",
                                response_code = code_response,
                            }
                            show_msg(T(_("Highlight sync failed: too many server conflicts. Try again later.")))
                            return
                        end
                        conflict_retries = conflict_retries + 1
                        os.remove(income_file_path)
                        phase = "download"
                        code_response, etag = provider.downloadFile(
                            server.url .. "/" .. file_name, income_file_path)
                        if code_response ~= 200 and code_response ~= 404
                            and not (server.type == "dropbox" and code_response == 409)
                            and not (server.type == "ftp" and code_response == 550)
                        then
                            logger.warn("TagBankHighlightSync: sync download failed:",
                                code_response, server.url .. "/" .. file_name)
                            abort_sync(sync_cb)
                            finish{
                                success = false,
                                phase = "download",
                                reason = "download_failed",
                                response_code = code_response,
                            }
                            show_msg(download_fail_msg)
                            return
                        end
                        -- 404/409/550: no remote file; WebDAV may still write an error body to .temp.
                        if code_response ~= 200 then
                            os.remove(income_file_path)
                        end
                        phase = "merge"
                        local ok, cb_return = pcall(
                            sync_cb, file_path, cached_file_path, income_file_path)
                        if not ok then
                            logger.err("TagBankHighlightSync: sync callback error:", cb_return)
                            local err_text = tostring(cb_return or "")
                            if #err_text > 80 then
                                err_text = err_text:sub(1, 77) .. "..."
                            end
                            finish{
                                success = false,
                                phase = "merge",
                                reason = "callback_exception",
                                error = tostring(cb_return),
                            }
                            show_msg(T(_("Highlight sync failed: %1"), err_text))
                            return
                        end
                        if cb_return == CloudStorageCompat.SYNC_ABORT then
                            finish{
                                success = false,
                                phase = "merge",
                                reason = "callback_abort",
                            }
                            return
                        end
                        if not cb_return then
                            finish{
                                success = false,
                                phase = "merge",
                                reason = "callback_false",
                            }
                            show_msg(merge_fail_msg)
                            return
                        end
                        phase = "upload"
                        code_response = provider.uploadFile(
                            server.url, file_path, etag, true)
                    end
                    if type(code_response) == "number"
                        and code_response >= 200 and code_response < 300
                    then
                        os.remove(cached_file_path)
                        ffiUtil.copyFile(file_path, cached_file_path)
                        finish{
                            success = true,
                            phase = "complete",
                            reason = "success",
                            response_code = code_response,
                        }
                        if not is_silent then
                            UIManager:show(Notification:new{
                                text = _("Successfully synchronized."),
                                timeout = 2,
                            })
                        end
                    else
                        logger.warn("TagBankHighlightSync: sync upload failed:",
                            code_response, server.url)
                        finish{
                            success = false,
                            phase = "upload",
                            reason = "upload_failed",
                            response_code = code_response,
                        }
                        show_msg(upload_fail_msg)
                    end
                end)
                if not ok_work then
                    logger.err("TagBankHighlightSync: sync provider error:", work_err)
                    finish{
                        success = false,
                        phase = phase,
                        reason = "exception",
                        error = tostring(work_err),
                    }
                    show_msg(fail_msg)
                end
            end)
        end
        local ok_run, run_err
        if (not is_silent or NetworkMgr:isConnected()) and provider.run then
            ok_run, run_err = pcall(provider.run, run_sync_work)
        else
            ok_run, run_err = pcall(run_sync_work)
        end
        if not ok_run then
            logger.err("TagBankHighlightSync: sync provider runner error:", run_err)
            complete{
                success = false,
                phase = "provider",
                reason = "run_exception",
                error = tostring(run_err),
            }
        end
    end

    cls._tagbank_sync_silent_fixed = true
    cls._tagbank_sync_completion_v2 = true
    logger.info("TagBankHighlightSync: cloudstorage sync respects is_silent")
    return true
end

local function trim_slashes(s)
    s = tostring(s or "")
    local from = s:match("^/*()")
    return from > #s and "" or s:match(".*[^/]", from)
end

function CloudStorageCompat.joinUploadUrl(address, path)
    local util = require("util")
    path = util.urlEncode(path, "/") or ""
    local sane_path = trim_slashes(path)
    local sane_address = tostring(address or ""):gsub("/+$", "")
    if sane_path == "" then
        return sane_address
    end
    return sane_address .. "/" .. sane_path
end

--- Binary-safe PUT for PNG screenshots (stock WebDAV opens files with "r").
function CloudStorageCompat.uploadBinaryFile(base_server, server_url, local_path)
    if not base_server or not local_path or local_path == "" then
        return false
    end
    local ffiUtil = require("ffi/util")
    local lfs = require("libs/libkoreader-lfs")
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socketutil = require("socketutil")
    local socket = require("socket")
    local logger = require("logger")

    local file_url = CloudStorageCompat.joinUploadUrl(base_server.address, server_url or "/")
    file_url = CloudStorageCompat.joinUploadUrl(file_url, ffiUtil.basename(local_path))

    local size = lfs.attributes(local_path, "size")
    if not size then
        logger.warn("TagBankHighlightSync: binary upload missing file:", local_path)
        return false
    end

    local f = io.open(local_path, "rb")
    if not f then
        logger.warn("TagBankHighlightSync: binary upload cannot open:", local_path)
        return false
    end

    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code = socket.skip(1, http.request{
        url = file_url,
        method = "PUT",
        source = ltn12.source.file(f),
        user = base_server.username or "",
        password = base_server.password or "",
        headers = {
            ["Content-Length"] = size,
        },
    })

    local close_ok, close_err = pcall(function() f:close() end)

    socketutil:reset_timeout()

    if not close_ok and not tostring(close_err or ""):find("closed file", 1, true) then
        error(close_err)
    end

    local ok = type(code) == "number" and code >= 200 and code <= 299
    if not ok then
        logger.warn("TagBankHighlightSync: binary upload failed:", file_url, code)
    end
    return ok
end

--- Push local JSON to WebDAV without download/merge (close-book sync).
--- @return table { ok = boolean, conflict = boolean }
function CloudStorageCompat.pushSyncFile(base_server, server, local_path)
    local fail = function(conflict)
        return { ok = false, conflict = conflict == true }
    end
    if not base_server or not server or not local_path or local_path == "" then
        return fail(false)
    end
    local ffiUtil = require("ffi/util")
    local lfs = require("libs/libkoreader-lfs")
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socketutil = require("socketutil")
    local socket = require("socket")
    local logger = require("logger")

    local size = lfs.attributes(local_path, "size")
    if not size then
        logger.warn("TagBankHighlightSync: close push missing file:", local_path)
        return fail(false)
    end

    local function read_file(path)
        local file = io.open(path, "rb")
        if not file then return nil end
        local content = file:read("*a")
        file:close()
        return content
    end

    local file_url = CloudStorageCompat.joinUploadUrl(base_server.address, server.url or "/")
    file_url = CloudStorageCompat.joinUploadUrl(file_url, ffiUtil.basename(local_path))

    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)

    local function finish(result)
        socketutil:reset_timeout()
        return result
    end

    local remote_chunks = {}
    local get_code, get_headers = socket.skip(1, http.request{
        url = file_url,
        method = "GET",
        sink = ltn12.sink.table(remote_chunks),
        user = base_server.username or "",
        password = base_server.password or "",
    })
    local cached_path = local_path .. ".sync"
    local cached_content = read_file(cached_path)
    local remote_exists = get_code == 200
    if remote_exists then
        local remote_content = table.concat(remote_chunks)
        if not cached_content or remote_content ~= cached_content then
            logger.info("TagBankHighlightSync: close push deferred; remote changed:", file_url)
            return finish(fail(true))
        end
        if not get_headers or not get_headers.etag or get_headers.etag == "" then
            logger.info("TagBankHighlightSync: close push deferred; remote ETag unavailable:", file_url)
            return finish(fail(true))
        end
    elseif get_code == 404 then
        if cached_content then
            logger.info("TagBankHighlightSync: close push deferred; remote missing after prior sync:", file_url)
            return finish(fail(true))
        end
    else
        logger.warn("TagBankHighlightSync: close push cannot verify remote:", file_url, get_code)
        return finish(fail(false))
    end

    local put_headers = { ["Content-Length"] = size }
    if remote_exists then
        put_headers["If-Match"] = get_headers.etag
    else
        put_headers["If-None-Match"] = "*"
    end

    local f = io.open(local_path, "rb")
    if not f then
        logger.warn("TagBankHighlightSync: close push cannot open:", local_path)
        return finish(fail(false))
    end

    local put_code = socket.skip(1, http.request{
        url = file_url,
        method = "PUT",
        source = ltn12.source.file(f),
        user = base_server.username or "",
        password = base_server.password or "",
        headers = put_headers,
    })

    pcall(function() f:close() end)

    if put_code == 412 then
        logger.warn("TagBankHighlightSync: close push conflict:", file_url)
        return finish(fail(true))
    end
    if type(put_code) == "number" and put_code >= 200 and put_code <= 299 then
        os.remove(cached_path)
        ffiUtil.copyFile(local_path, cached_path)
        return finish({ ok = true, conflict = false })
    end
    logger.warn("TagBankHighlightSync: close push failed:", file_url, put_code)
    return finish(fail(false))
end

--- Upload library/export files after close-book JSON push (no cloudstorage UI).
function CloudStorageCompat.pushFileQueue(base_server, jobs)
    if not base_server or not jobs or #jobs == 0 then
        return true
    end
    local ffiUtil = require("ffi/util")
    local all_ok = true
    for _, job in ipairs(jobs) do
        if not job.path or job.path == "" or not job.server then
            all_ok = false
            break
        elseif job.kind == "screenshot" then
            local ok = CloudStorageCompat.uploadBinaryFile(
                base_server, job.server.url, job.path)
            if ok then
                ffiUtil.copyFile(job.path, job.path .. ".sync")
            else
                all_ok = false
                break
            end
        else
            local result = CloudStorageCompat.pushSyncFile(base_server, job.server, job.path)
            if not result.ok then
                all_ok = false
                break
            end
        end
    end
    return all_ok
end

return CloudStorageCompat
