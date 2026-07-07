-- Post-JSON-write sync steps (exports, library refresh). Failures are logged, not fatal.

local SyncPostWrite = {}

function SyncPostWrite.truncate_error(err, max_len)
    local text = tostring(err or "")
    max_len = max_len or 80
    if #text > max_len then
        return text:sub(1, max_len - 3) .. "..."
    end
    return text
end

function SyncPostWrite.safe_invoke(name, fn, on_error)
    local ok, result = pcall(fn)
    if not ok then
        require("logger").err("TagBankHighlightSync:", name, "failed:", result)
        if on_error then
            on_error(tostring(result or ""))
        end
        return false, result
    end
    return true, result
end

function SyncPostWrite.safe_step(name, fn)
    local ok = SyncPostWrite.safe_invoke(name, fn)
    return ok
end

--- Run derived export steps after sidecar JSON is written. Returns true always.
function SyncPostWrite.run(host, ctx, merged, full_annotations, reload, defer_library)
    local Export = require("export")
    local base = ctx.sync_path:gsub("%.json$", "")

    if not defer_library then
        SyncPostWrite.safe_step("export", function()
            Export.write_exports(base, merged, host.settings, ctx.metadata)
        end)
        SyncPostWrite.safe_step("mirror", function()
            host:mirrorSyncFiles(ctx, merged)
        end)
    end
    SyncPostWrite.safe_step("persist", function()
        host:persistMergedAnnotations(full_annotations, merged, reload, defer_library)
    end)
    if not defer_library then
        SyncPostWrite.safe_step("library refresh", function()
            host:refreshLibraryFiles(ctx, full_annotations)
        end)
    end
    return true
end

return SyncPostWrite
