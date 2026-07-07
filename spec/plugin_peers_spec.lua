return function(assert_eq, assert_true, PluginPeers)
    local saved_loader = package.loaded["pluginloader"]

    local function restore_loader()
        package.loaded["pluginloader"] = saved_loader
    end

    assert_true(not PluginPeers.is_ankikooai_available(nil), "nil ui, no loader → false")

    package.loaded["pluginloader"] = {
        isPluginLoaded = function(_, name)
            return name == "ankikooai"
        end,
    }
    assert_true(PluginPeers.is_ankikooai_available(nil), "isPluginLoaded ankikooai")

    package.loaded["pluginloader"] = {
        isPluginLoaded = function() return false end,
        getPluginInstance = function(_, name)
            if name == "ankikooai" then return {} end
        end,
    }
    assert_true(PluginPeers.is_ankikooai_available(nil), "getPluginInstance ankikooai")

    package.loaded["pluginloader"] = {
        isPluginLoaded = function() return false end,
        getPluginInstance = function() return nil end,
    }
    assert_true(PluginPeers.is_ankikooai_available({ ankikooai = {} }), "ui.ankikooai fallback")

    package.loaded["pluginloader"] = nil
    assert_true(not PluginPeers.is_ankikooai_available({}), "empty ui, no loader → false")

    restore_loader()
end
