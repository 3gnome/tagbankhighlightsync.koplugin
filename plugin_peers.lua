-- Optional peer-plugin detection (no hard dependencies).

local PluginPeers = {}

--- True when AnkiKOAi is installed and loaded in this KOReader session.
function PluginPeers.is_ankikooai_available(ui)
    local ok, PluginLoader = pcall(require, "pluginloader")
    if ok and PluginLoader then
        if PluginLoader.isPluginLoaded and PluginLoader:isPluginLoaded("ankikooai") then
            return true
        end
        if PluginLoader.getPluginInstance and PluginLoader:getPluginInstance("ankikooai") then
            return true
        end
    end
    return ui and ui.ankikooai ~= nil
end

return PluginPeers
