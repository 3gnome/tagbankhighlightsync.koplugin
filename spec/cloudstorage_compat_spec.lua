return function(assert_eq, assert_true, CloudStorageCompat)
    assert_eq(CloudStorageCompat.normalizeUrl(nil), "/", "nil url → /")
    assert_eq(CloudStorageCompat.normalizeUrl(""), "/", "empty url → /")
    assert_eq(CloudStorageCompat.normalizeUrl("/books"), "/books", "path unchanged")

    local server = { name = "webdav", url = nil }
    CloudStorageCompat.normalizeSyncServer(server)
    assert_eq(server.url, "/", "sync_server url normalized")

    assert_eq(
        CloudStorageCompat.joinUploadUrl("http://example.com/", "/library/quotes/images/"),
        "http://example.com/library/quotes/images",
        "join upload url"
    )
    assert_eq(
        CloudStorageCompat.joinUploadUrl("http://example.com/library/quotes/images", "abc.png"),
        "http://example.com/library/quotes/images/abc.png",
        "join filename"
    )
    assert_eq(CloudStorageCompat.SYNC_ABORT, "tagbank_sync_abort", "sync abort sentinel")

    local push_nil = CloudStorageCompat.pushSyncFile(nil, nil, nil)
    assert_true(not push_nil.ok and not push_nil.conflict, "pushSyncFile nil args fails safely")

    local saved_modules = {}
    local saved_names = {}
    local NIL = {}
    local function save_module(name)
        saved_names[#saved_names + 1] = name
        saved_modules[name] = package.loaded[name] == nil and NIL
            or package.loaded[name]
    end
    local function restore_modules()
        for _, name in ipairs(saved_names) do
            local value = saved_modules[name]
            package.loaded[name] = value == NIL and nil or value
        end
    end
    for _, name in ipairs({
        "ffi/util", "libs/libkoreader-lfs", "socket.http",
        "ltn12", "socketutil", "socket", "logger",
    }) do
        save_module(name)
    end

    local function write_file(path, content)
        local file = assert(io.open(path, "wb"))
        assert(file:write(content))
        assert(file:close())
    end
    local function read_file(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end
    local function run_push_case(remote_code, remote_body, remote_headers, put_code, cached_body)
        local local_path = os.tmpname()
        write_file(local_path, "local-new")
        if cached_body ~= nil then
            write_file(local_path .. ".sync", cached_body)
        else
            os.remove(local_path .. ".sync")
        end
        local puts = {}
        package.loaded["ffi/util"] = {
            basename = function(path) return path:match("([^/\\]+)$") end,
            copyFile = function(src, dst)
                write_file(dst, read_file(src))
                return true
            end,
            template = function(fmt) return tostring(fmt) end,
        }
        package.loaded["libs/libkoreader-lfs"] = {
            attributes = function(path, attr)
                if attr ~= "size" then return nil end
                local file = io.open(path, "rb")
                if not file then return nil end
                local content = file:read("*a")
                file:close()
                return #content
            end,
        }
        package.loaded["ltn12"] = {
            sink = {
                table = function(target)
                    return function(chunk)
                        if chunk then target[#target + 1] = chunk end
                        return 1
                    end
                end,
            },
            source = {
                file = function(file)
                    return function()
                        return file:read(8192)
                    end
                end,
            },
        }
        package.loaded["socket"] = {
            skip = function(n, ...)
                local values = { ... }
                table.remove(values, n)
                return unpack(values)
            end,
        }
        package.loaded["socketutil"] = {
            FILE_BLOCK_TIMEOUT = 1,
            FILE_TOTAL_TIMEOUT = 1,
            set_timeout = function() end,
            reset_timeout = function() end,
        }
        package.loaded["logger"] = {
            info = function() end,
            warn = function() end,
            err = function() end,
        }
        package.loaded["socket.http"] = {
            request = function(req)
                if req.method == "GET" then
                    if req.sink and remote_body then req.sink(remote_body) end
                    return true, remote_code, remote_headers or {}
                end
                if req.method == "PUT" then
                    puts[#puts + 1] = req
                    return true, put_code or 201, {}
                end
                return nil, 500, {}
            end,
        }
        local result = CloudStorageCompat.pushSyncFile(
            { address = "http://example.com/root/" },
            { url = "/book" },
            local_path)
        local cached_after
        local cached_file = io.open(local_path .. ".sync", "rb")
        if cached_file then
            cached_after = cached_file:read("*a")
            cached_file:close()
        end
        os.remove(local_path)
        os.remove(local_path .. ".sync")
        return result, puts, cached_after
    end

    local result, puts = run_push_case(
        200, "remote-new", { etag = "remote-tag" }, 201, "baseline")
    assert_true(not result.ok and result.conflict,
        "close push defers when remote differs from baseline")
    assert_eq(#puts, 0, "changed remote is not overwritten")

    result, puts = run_push_case(
        200, "baseline", { etag = "same-tag" }, 201, "baseline")
    assert_true(result.ok and not result.conflict,
        "close push succeeds when remote matches baseline")
    assert_eq(puts[1].headers["If-Match"], "same-tag",
        "matching remote uses its current etag")

    result, puts = run_push_case(200, "baseline", {}, 201, "baseline")
    assert_true(not result.ok and result.conflict,
        "existing remote without etag is not overwritten")
    assert_eq(#puts, 0, "no-etag remote skips PUT")

    result, puts = run_push_case(404, nil, {}, 201, nil)
    assert_true(result.ok and not result.conflict,
        "new close push can create absent remote")
    assert_eq(puts[1].headers["If-None-Match"], "*",
        "new close push uses create-only header")

    result, puts = run_push_case(404, nil, {}, 201, "baseline")
    assert_true(not result.ok and result.conflict,
        "missing remote after prior baseline defers to merge")
    assert_eq(#puts, 0, "missing changed remote skips PUT")

    restore_modules()

    local orig_push = CloudStorageCompat.pushSyncFile
    local base_server = { address = "http://example.com/" }
    local function make_jobs(n)
        local jobs = {}
        for i = 1, n do
            jobs[i] = { server = { url = "/library/" }, path = "/tmp/job" .. i .. ".md" }
        end
        return jobs
    end

    local calls = 0
    CloudStorageCompat.pushSyncFile = function()
        calls = calls + 1
        return { ok = false, conflict = false }
    end
    assert_true(not CloudStorageCompat.pushFileQueue(base_server, make_jobs(5)),
        "queue aborts on first failure")
    assert_eq(calls, 1, "only one push attempt when first fails")

    calls = 0
    CloudStorageCompat.pushSyncFile = function()
        calls = calls + 1
        return { ok = calls < 2, conflict = false }
    end
    assert_true(not CloudStorageCompat.pushFileQueue(base_server, make_jobs(5)),
        "queue stops after first failing job")
    assert_eq(calls, 2, "second job attempted after first succeeded")

    calls = 0
    CloudStorageCompat.pushSyncFile = function()
        calls = calls + 1
        return { ok = true, conflict = false }
    end
    assert_true(CloudStorageCompat.pushFileQueue(base_server, make_jobs(3)),
        "happy path uploads all jobs")
    assert_eq(calls, 3, "all jobs pushed on success")

    CloudStorageCompat.pushSyncFile = orig_push

    local original_ffi = package.loaded["ffi/util"]
    package.loaded["ffi/util"] = {
        basename = function(path) return path:match("([^/\\]+)$") end,
        copyFile = function() return true end,
        template = function(fmt, ...)
            if type(fmt) == "table" and fmt.format then
                return fmt:format(...)
            end
            return tostring(fmt)
        end,
    }
    package.loaded["ui/uimanager"] = {
        nextTick = function(_, fn) fn() end,
        show = function() end,
    }
    package.loaded["ui/widget/infomessage"] = {
        new = function(_, args) return args end,
    }
    package.loaded["ui/widget/notification"] = {
        new = function(_, args) return args end,
    }
    package.loaded["socketutil"] = {
        FILE_BLOCK_TIMEOUT = 1,
        FILE_TOTAL_TIMEOUT = 1,
        set_timeout = function() end,
        reset_timeout = function() end,
    }

    local SyncClass = {
        sync = function() end,
        _tagbank_sync_silent_fixed = true,
    }
    local provider = {}
    local cloud = setmetatable({
        providers = { webdav = provider },
    }, {
        __index = SyncClass,
    })
    assert_true(CloudStorageCompat.ensureCloudSyncPatch(cloud),
        "completion patch upgrades an earlier silent-only patch")
    assert_true(SyncClass._tagbank_sync_completion_v2,
        "completion patch version is recorded")

    local test_server = { type = "webdav", url = "/highlights" }
    local function run_completion_case(sync_cb, download_code, upload_code, server_override)
        local completion_count = 0
        local final_outcome
        provider.downloadFile = function()
            return download_code, "etag"
        end
        provider.uploadFile = function()
            return upload_code
        end
        cloud:sync(server_override or test_server, "/tmp/book.sdr.json", sync_cb,
            true, nil, function(outcome)
                completion_count = completion_count + 1
                final_outcome = outcome
            end)
        assert_eq(completion_count, 1, "completion callback called exactly once")
        return final_outcome
    end

    local outcome = run_completion_case(function() return true end, 404, 201)
    assert_true(outcome.success, "successful upload outcome")
    assert_eq(outcome.phase, "complete", "success completion phase")
    assert_eq(outcome.reason, "success", "success completion reason")
    assert_eq(outcome.response_code, 201, "success response code")

    outcome = run_completion_case(function() return true end, 404, 201,
        { type = "missing", url = "/highlights" })
    assert_true(not outcome.success, "missing provider fails")
    assert_eq(outcome.reason, "missing_provider", "missing provider reason")

    outcome = run_completion_case(function() return true end, 503, 201)
    assert_eq(outcome.phase, "download", "download failure phase")
    assert_eq(outcome.reason, "download_failed", "download failure reason")
    assert_eq(outcome.response_code, 503, "download failure response code")

    outcome = run_completion_case(function() error("merge exploded") end, 404, 201)
    assert_eq(outcome.reason, "callback_exception", "callback exception outcome")

    outcome = run_completion_case(
        function() return CloudStorageCompat.SYNC_ABORT end, 404, 201)
    assert_eq(outcome.reason, "callback_abort", "callback abort outcome")

    outcome = run_completion_case(function() return false end, 404, 201)
    assert_eq(outcome.reason, "callback_false", "callback false outcome")

    outcome = run_completion_case(function() return true end, 404, 500)
    assert_eq(outcome.phase, "upload", "upload failure phase")
    assert_eq(outcome.reason, "upload_failed", "upload failure reason")
    assert_eq(outcome.response_code, 500, "upload failure response code")

    outcome = run_completion_case(function() return true end, 404, nil)
    assert_eq(outcome.reason, "upload_failed", "nil upload response fails once")

    package.loaded["ffi/util"] = original_ffi
end
