return function(assert_eq, assert_true, PluginPeers)
    local saved_loader = package.loaded["pluginloader"]

    local function restore_loader()
        package.loaded["pluginloader"] = saved_loader
    end

    assert_true(not PluginPeers.is_ankikoflash_available(nil), "nil ui, no loader → false")

    package.loaded["pluginloader"] = {
        isPluginLoaded = function(_, name)
            return name == "ankikoflash"
        end,
    }
    assert_true(PluginPeers.is_ankikoflash_available(nil), "isPluginLoaded ankikoflash")

    package.loaded["pluginloader"] = {
        isPluginLoaded = function() return false end,
        getPluginInstance = function(_, name)
            if name == "ankikoflash" then return {} end
        end,
    }
    assert_true(PluginPeers.is_ankikoflash_available(nil), "getPluginInstance ankikoflash")

    package.loaded["pluginloader"] = {
        isPluginLoaded = function() return false end,
        getPluginInstance = function() return nil end,
    }
    assert_true(PluginPeers.is_ankikoflash_available({ ankikoflash = {} }), "ui.ankikoflash fallback")

    package.loaded["pluginloader"] = nil
    assert_true(not PluginPeers.is_ankikoflash_available({}), "empty ui, no loader → false")

    restore_loader()
end
