local lfs = require("libs/libkoreader-lfs")

local BatchSync = {}

function BatchSync.find_sync_json_files(root_path)
    local files = {}
    if not root_path or lfs.attributes(root_path, "mode") ~= "directory" then
        return files
    end
    for entry in lfs.dir(root_path) do
        if entry ~= "." and entry ~= ".." then
            local full = root_path .. "/" .. entry
            local mode = lfs.attributes(full, "mode")
            if mode == "directory" and entry:match("%.sdr$") then
                for sidecar_entry in lfs.dir(full) do
                    if sidecar_entry:match("%.json$")
                        and not sidecar_entry:match("%.json%.")
                    then
                        files[#files + 1] = full .. "/" .. sidecar_entry
                    end
                end
            end
        end
    end
    return files
end

function BatchSync.copy_file(src, dest)
    local in_f = io.open(src, "rb")
    if not in_f then return false end
    local data = in_f:read("*a")
    in_f:close()
    local out_f = io.open(dest, "wb")
    if not out_f then return false end
    out_f:write(data)
    out_f:close()
    return true
end

return BatchSync
