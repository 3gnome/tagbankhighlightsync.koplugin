return function(assert_eq, assert_true, VerseLayout)
    assert_eq(VerseLayout.get_quote_layout({}), "auto", "default layout is auto")
    assert_eq(VerseLayout.get_quote_layout({ highlight_sync_quote_layout = "verse" }), "verse",
        "read verse layout")
    assert_eq(VerseLayout.get_quote_layout({ highlight_sync_quote_layout = "prose" }), "prose",
        "read prose layout")

    local ann = {}
    VerseLayout.set_quote_layout(ann, "verse")
    assert_eq(ann.highlight_sync_quote_layout, "verse", "set verse layout")
    VerseLayout.set_quote_layout(ann, "auto")
    assert_true(ann.highlight_sync_quote_layout == nil, "auto clears layout field")

    assert_true(VerseLayout.should_normalize("any text", { library_preserve_verse_layout = true }, {
        highlight_sync_quote_layout = "verse",
    }), "verse override always normalizes")
    assert_true(not VerseLayout.should_normalize("any text", { library_preserve_verse_layout = true }, {
        highlight_sync_quote_layout = "prose",
    }), "prose override skips normalization")
    assert_true(not VerseLayout.should_normalize("short prose.", { library_preserve_verse_layout = true }, {}),
        "auto skips short prose")
end
