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

    local CloudStorageCompat = require("cloudstorage_compat")
    local SyncProgress = require("sync_progress")
    local SyncStatus = require("sync_status")
    local original_push = CloudStorageCompat.pushSyncFile
    local original_queue = CloudStorageCompat.pushFileQueue
    local snapshot = {
        sync_path = "/tmp/book.sdr.json",
        base_server = { address = "http://example.com/" },
        server = { url = "/highlights" },
        library_jobs = {
            { path = "/tmp/book.md", server = { url = "/library" } },
        },
    }

    local function reset_settings()
        G_reader_settings._store.tag_bank_highlight_sync = { pending_sync = false }
    end

    NetworkMgr.isConnected = function() return true end
    NetworkMgr.isWifiOn = function() return true end

    reset_settings()
    CloudStorageCompat.pushSyncFile = function()
        return { ok = false, conflict = true }
    end
    SyncBackground.schedule_close_push(snapshot)
    assert_true(G_reader_settings._store.tag_bank_highlight_sync.pending_sync,
        "close conflict queues pending sync")
    assert_eq(G_reader_settings._store.tag_bank_highlight_sync.last_sync_status,
        SyncStatus.DEFERRED, "close conflict records deferred")
    assert_true(not SyncProgress.is_active(), "close conflict clears progress")

    reset_settings()
    CloudStorageCompat.pushSyncFile = function()
        return { ok = false, conflict = false }
    end
    SyncBackground.schedule_close_push(snapshot)
    assert_true(G_reader_settings._store.tag_bank_highlight_sync.pending_sync,
        "close network failure queues pending sync")
    assert_eq(G_reader_settings._store.tag_bank_highlight_sync.last_sync_status,
        SyncStatus.FAILED, "close failure records failed")
    assert_true(not SyncProgress.is_active(), "close failure clears progress")

    reset_settings()
    CloudStorageCompat.pushSyncFile = function()
        error("push exploded")
    end
    SyncBackground.schedule_close_push(snapshot)
    assert_true(G_reader_settings._store.tag_bank_highlight_sync.pending_sync,
        "close exception queues pending sync")
    assert_true(not SyncProgress.is_active(), "close exception clears progress")

    reset_settings()
    CloudStorageCompat.pushSyncFile = function()
        return { ok = true, conflict = false }
    end
    CloudStorageCompat.pushFileQueue = function()
        return false
    end
    SyncBackground.schedule_close_push(snapshot)
    assert_true(G_reader_settings._store.tag_bank_highlight_sync.pending_sync,
        "close library failure queues pending sync")
    assert_true(not SyncProgress.is_active(), "close library failure clears progress")

    reset_settings()
    CloudStorageCompat.pushFileQueue = function()
        return true
    end
    SyncBackground.schedule_close_push(snapshot)
    assert_true(not G_reader_settings._store.tag_bank_highlight_sync.pending_sync,
        "successful close push leaves sync clear")
    assert_eq(G_reader_settings._store.tag_bank_highlight_sync.last_sync_status,
        SyncStatus.SUCCESS, "successful close push records success")
    assert_true(not SyncProgress.is_active(), "successful close push clears progress")

    CloudStorageCompat.pushSyncFile = original_push
    CloudStorageCompat.pushFileQueue = original_queue
end
