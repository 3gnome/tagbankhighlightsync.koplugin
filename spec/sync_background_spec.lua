return function(assert_eq, assert_true, SyncBackground)
    assert_eq(SyncBackground.OPEN_SYNC_DEFER_SEC, 3, "open sync defer seconds")
    assert_eq(SyncBackground.CLOSE_SYNC_DEFER_SEC, 1, "close sync defer seconds")
    assert_true(not SyncBackground.should_defer_library(nil), "nil opts not background")
    assert_true(not SyncBackground.should_defer_library({}), "empty opts not background")
    assert_true(not SyncBackground.should_defer_library({ background = false }),
        "background false not deferred")
    assert_true(SyncBackground.should_defer_library({ background = true }),
        "background true defers library")
    assert_true(SyncBackground.is_push_only({ push_only = true }), "push_only opts")
    assert_true(not SyncBackground.is_push_only({ background = true }), "background not push_only")
    assert_true(SyncBackground.should_queue_offline(true, {}),
        "silent auto-sync queues offline")
    assert_true(SyncBackground.should_queue_offline(false, { background = true }),
        "background auto-sync queues offline")
    assert_true(not SyncBackground.should_queue_offline(false, {}),
        "manual sync does not queue offline silently")
    assert_true(not SyncBackground.should_queue_offline(false, { background = false }),
        "non-background manual does not queue offline silently")

    local NetworkMgr = require("ui/network/manager")
    NetworkMgr.isConnected = function() return true end
    NetworkMgr.isWifiOn = function() return false end
    assert_true(SyncBackground.network_ready_for_merge_sync(), "merge sync when connected")
    assert_true(SyncBackground.network_ready_for_raw_push(), "raw push when connected")

    NetworkMgr.isConnected = function() return false end
    NetworkMgr.isWifiOn = function() return true end
    assert_true(not SyncBackground.network_ready_for_merge_sync(),
        "merge sync waits for connected route")
    assert_true(SyncBackground.network_ready_for_raw_push(), "raw push when wifi on for LAN")

    NetworkMgr.isConnected = function() return false end
    NetworkMgr.isWifiOn = function() return false end
    assert_true(not SyncBackground.network_ready_for_merge_sync(), "merge offline")
    assert_true(not SyncBackground.network_ready_for_raw_push(), "raw push offline")
end
