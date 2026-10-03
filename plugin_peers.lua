-- Optional peer-plugin detection (no hard dependencies).

local PluginPeers = {}

--- True when AnkiKoFlash is installed and loaded in this KOReader session.
function PluginPeers.is_ankikoflash_available(ui)
    local ok, PluginLoader = pcall(require, "pluginloader")
    if ok and PluginLoader then
        if PluginLoader.isPluginLoaded and PluginLoader:isPluginLoaded("ankikoflash") then
            return true
        end
        if PluginLoader.getPluginInstance and PluginLoader:getPluginInstance("ankikoflash") then
            return true
        end
    end
    return ui and ui.ankikoflash ~= nil
end

return PluginPeers
