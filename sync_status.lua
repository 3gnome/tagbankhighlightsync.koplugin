local SyncStatus = {}

SyncStatus.SUCCESS = "success"
SyncStatus.FAILED = "failed"
SyncStatus.DEFERRED = "deferred"

local valid = {
    [SyncStatus.SUCCESS] = true,
    [SyncStatus.FAILED] = true,
    [SyncStatus.DEFERRED] = true,
}

function SyncStatus.from_outcome(outcome)
    if outcome and outcome.success == true then
        return SyncStatus.SUCCESS
    end
    return SyncStatus.FAILED
end

function SyncStatus.apply(settings, status, timestamp)
    if not settings or not valid[status] then
        return false
    end
    settings.last_sync_status = status
    settings.last_sync_time = timestamp
    settings.pending_sync = status ~= SyncStatus.SUCCESS
    return true
end

function SyncStatus.apply_outcome(settings, outcome, timestamp)
    return SyncStatus.apply(settings, SyncStatus.from_outcome(outcome), timestamp)
end

function SyncStatus.append_pending(text, pending, pending_label)
    if not pending then
        return text
    end
    return tostring(text or "") .. " — " .. tostring(pending_label or "")
end

function SyncStatus.format_last(settings, labels)
    if not settings or not settings.last_sync_time then
        return nil
    end
    labels = labels or {}
    local label = labels[settings.last_sync_status] or labels.unknown
        or tostring(settings.last_sync_status or "")
    if label == "" then
        return settings.last_sync_time
    end
    return tostring(label) .. " — " .. tostring(settings.last_sync_time)
end

return SyncStatus
