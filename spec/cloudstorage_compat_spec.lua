return function(assert_eq, assert_true, CloudStorageCompat)
    assert_eq(CloudStorageCompat.normalizeUrl(nil), "/", "nil url → /")
    assert_eq(CloudStorageCompat.normalizeUrl(""), "/", "empty url → /")
    assert_eq(CloudStorageCompat.normalizeUrl("/books"), "/books", "path unchanged")

    local server = { name = "webdav", url = nil }
    CloudStorageCompat.normalizeSyncServer(server)
    assert_eq(server.url, "/", "sync_server url normalized")

    assert_eq(
        CloudStorageCompat.joinUploadUrl("http://example.com/", "/library/quotes/images/"),
        "http://example.com/library/quotes/images",
        "join upload url"
    )
    assert_eq(
        CloudStorageCompat.joinUploadUrl("http://example.com/library/quotes/images", "abc.png"),
        "http://example.com/library/quotes/images/abc.png",
        "join filename"
    )
    assert_eq(CloudStorageCompat.SYNC_ABORT, "tagbank_sync_abort", "sync abort sentinel")

    local push_nil = CloudStorageCompat.pushSyncFile(nil, nil, nil)
    assert_true(not push_nil.ok and not push_nil.conflict, "pushSyncFile nil args fails safely")
end
