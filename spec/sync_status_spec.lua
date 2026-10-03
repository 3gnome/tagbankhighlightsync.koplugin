return function(assert_eq, assert_true, SyncStatus)
    local settings = { pending_sync = true }

    assert_true(SyncStatus.apply_outcome(settings, {
        success = true,
        phase = "complete",
    }, "2026-08-18 07:00:00"), "success transition applied")
    assert_eq(settings.last_sync_status, SyncStatus.SUCCESS, "success status persisted")
    assert_eq(settings.last_sync_time, "2026-08-18 07:00:00", "success time persisted")
    assert_true(not settings.pending_sync, "success clears pending")

    SyncStatus.apply_outcome(settings, {
        success = false,
        phase = "upload",
    }, "2026-08-18 07:01:00")
    assert_eq(settings.last_sync_status, SyncStatus.FAILED, "failure status persisted")
    assert_true(settings.pending_sync, "failure sets pending")

    SyncStatus.apply(settings, SyncStatus.DEFERRED, "2026-08-18 07:02:00")
    assert_eq(settings.last_sync_status, SyncStatus.DEFERRED, "deferred status persisted")
    assert_true(settings.pending_sync, "deferred retains pending")

    local labels = {
        [SyncStatus.SUCCESS] = "Succeeded",
        [SyncStatus.FAILED] = "Failed",
        [SyncStatus.DEFERRED] = "Deferred",
        unknown = "Unknown",
    }
    assert_eq(SyncStatus.format_last(settings, labels),
        "Deferred — 2026-08-18 07:02:00", "last outcome formatted")
    assert_eq(SyncStatus.format_last({}, labels), nil, "missing timestamp stays hidden")

    assert_eq(SyncStatus.append_pending("Cloud folder: WebDAV", true, "Sync pending"),
        "Cloud folder: WebDAV — Sync pending", "pending status appended")
    assert_eq(SyncStatus.append_pending("Cloud folder: WebDAV", false, "Sync pending"),
        "Cloud folder: WebDAV", "non-pending menu text unchanged")
end
