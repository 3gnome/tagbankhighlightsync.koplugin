-- Persistent busy message + brief toasts for blocking automatic sync work.

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local notification_ok, Notification = pcall(require, "ui/widget/notification")

local SyncProgress = {}

local BUSY_TIMEOUT_SEC = 12
local active = nil

local function make_message(text, timeout)
    if notification_ok and Notification then
        return Notification:new{
            text = text,
            timeout = timeout,
        }
    end
    return InfoMessage:new{
        text = text,
        timeout = timeout,
    }
end

function SyncProgress.show(text)
    SyncProgress.close()
    local token = {}
    active = {
        token = token,
        widget = make_message(text, BUSY_TIMEOUT_SEC),
    }
    UIManager:show(active.widget)
    if UIManager.forceRePaint then
        UIManager:forceRePaint()
    end
    return token
end

function SyncProgress.close(token)
    if token ~= nil and (not active or active.token ~= token) then
        return false
    end
    if active then
        UIManager:close(active.widget)
        active = nil
        return true
    end
    return false
end

function SyncProgress.is_active()
    return active ~= nil
end

function SyncProgress.toast(text, timeout)
    UIManager:show(make_message(text, timeout or 3))
end

return SyncProgress
