return function(assert_eq, assert_true, BatchSync)
    local succeeded, failed = BatchSync.summary_counts(7, 2)
    assert_eq(succeeded, 5, "batch summary success count")
    assert_eq(failed, 2, "batch summary failure count")

    succeeded, failed = BatchSync.summary_counts(3, 9)
    assert_eq(succeeded, 0, "batch failures clamped to total")
    assert_eq(failed, 3, "batch failure clamp")
end
