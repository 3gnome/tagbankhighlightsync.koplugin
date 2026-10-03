return function(assert_eq, assert_true, SyncProgress)
    local shown = {}
    local closed = {}
    local repainted = false

    package.loaded["ui/uimanager"] = {
        show = function(_, widget)
            shown[#shown + 1] = widget
        end,
        close = function(_, widget)
            closed[#closed + 1] = widget
        end,
        forceRePaint = function()
            repainted = true
        end,
    }
    package.loaded["ui/widget/infomessage"] = {
        new = function(_, args)
            return { _kind = "InfoMessage", text = args.text, timeout = args.timeout }
        end,
    }

    -- Reload so SyncProgress picks up mocks.
    package.loaded["sync_progress"] = nil
    local SP = require("sync_progress")

    local first_token = SP.show("busy one")
    assert_true(SP.is_active(), "show sets active")
    assert_true(first_token ~= nil, "show returns owner token")
    assert_eq(#shown, 1, "show displays widget")
    assert_true(repainted, "show forceRepaints")

    local second_token = SP.show("busy two")
    assert_true(second_token ~= first_token, "replacement gets a new token")
    assert_eq(#closed, 1, "show closes prior widget")
    assert_eq(#shown, 2, "show displays replacement")

    assert_true(not SP.close(first_token), "stale token cannot close replacement")
    assert_true(SP.is_active(), "replacement remains active after stale close")
    assert_eq(#closed, 1, "stale close does not close widget")

    assert_true(SP.close(second_token), "owner token closes active widget")
    assert_true(not SP.is_active(), "owned close clears active")
    assert_eq(#closed, 2, "close closes widget")

    SP.show("legacy close")
    assert_true(SP.close(), "tokenless close remains backward compatible")
    assert_true(not SP.is_active(), "tokenless close clears active")

    SP.toast("done", 4)
    assert_eq(#shown, 4, "toast shows message")
    assert_eq(shown[4].timeout, 4, "toast timeout")
end
