return function(assert_eq, assert_true, Export, OutputSettings)
    local settings = OutputSettings.merge_defaults({})
    local fn = OutputSettings.resolve_filename(settings, { sidecar_name = "MyBook.sdr", book_title = "My Book" })
    assert_eq(fn, "MyBook.sdr", "sidecar filename")

    settings.include_page_bookmarks = false
    settings.include_highlights = true
    settings.include_notes = true
    local anns = {
        { drawer = "lighten", text = "hl" },
        { drawer = "lighten", note = "note", text = "hl2" },
        { page = 1, text = "bm" },
    }
    local filtered = OutputSettings.filter_annotations(anns, settings)
    assert_eq(#filtered, 2, "filter bookmarks out")

    local wrapped = { annotations = { { page = "a", pos0 = "a", pos1 = "b" } } }
    assert_eq(#OutputSettings.unwrap_payload(wrapped), 1, "unwrap wrapper")

    local md = Export.to_markdown({ { text = "hello", pageno = 1, datetime = "2020-01-01 10:00:00" } }, {}, settings)
    assert_true(md:find("hello") ~= nil, "markdown export")
    assert_true(md:find("type: literature") ~= nil, "book frontmatter")

    local block_settings = { library_metadata_style = "both", library_use_callouts = true }
    local block = Export.format_quote_block({
        text = "quoted",
        pageno = 3,
        datetime = "2020-01-01 10:00:00",
        chapter = "Chapter One",
        highlight_sync_tags = { "aversion" },
    }, {
        book_title = "Book",
        doc_title = "Book Title",
        author = "Author Name",
        sidecar_name = "book.sdr",
        tag_bank = {
            { kind = "folder", id = "buddhism", name = "Buddhism", children = {
                { kind = "tag", id = "aversion", name = "aversion" },
            }},
        },
    }, block_settings)
    assert_true(block:find("#buddhism") ~= nil, "inherited folder tag")
    assert_true(block:find("#aversion") ~= nil, "leaf tag")
    assert_true(block:find("quoted") ~= nil, "quote block text")
    assert_true(not block:find("hs:key"), "no inner sync marker")
    assert_true(block:find("[!quote]") ~= nil, "quote callout")
    assert_true(block:find("book::") ~= nil, "inline book field")
    assert_true(block:find("author:: Author Name") ~= nil, "inline author field")
    assert_true(block:find("Author Name") ~= nil, "scholarly heading author")
    assert_true(block:find("captured::") ~= nil, "circadian captured field")
    assert_true(not block:find("**Book:**"), "no redundant footer")

    local note_block = Export.format_quote_block({
        text = "quoted",
        pageno = 3,
        note = "my commentary",
        highlight_sync_tags = { "ideas" },
    }, { book_title = "Book", sidecar_name = "book.sdr" }, settings)
    assert_true(note_block:find("[!note]") ~= nil, "note callout")
    assert_true(note_block:find("my commentary") ~= nil, "note text")

    local circadian = Export.format_circadian_datetime("2020-01-01 10:00:00")
    assert_true(circadian:find("10:00 am") ~= nil, "circadian 12h time")
    assert_true(circadian:find("Jan") ~= nil, "circadian month name")

    local csv = Export.to_csv({ { text = "a", pageno = 1 } })
    assert_true(csv:find("page,chapter") ~= nil, "csv header")

    local NBSP = "\194\160"
    local alice_verse = table.concat({
        "I speak severely to my boy,",
        NBSP, NBSP, NBSP, NBSP,
        "I beat him when he sneezes; For he can thoroughly enjoy",
        NBSP, NBSP, NBSP, NBSP,
        "The pepper when he pleases!",
    })
    assert_true(Export.has_verse_nbsp(alice_verse), "alice has nbsp runs")
    local normalized = Export.normalize_verse_text(alice_verse)
    assert_true(normalized:find("\n") ~= nil, "normalized verse has line breaks")
    assert_true(not normalized:find(NBSP, 1, true), "nbsp removed from normalized verse")
    assert_eq(select(2, normalized:gsub("\n", "")), 3, "normalized verse has four lines")
    assert_true(normalized:find("\n  I beat", 1, true) ~= nil, "verse line 2 indented")
    assert_true(normalized:find("\n  The pepper", 1, true) ~= nil, "verse line 4 indented")
    assert_true(normalized:find("I beat him when he sneezes;") ~= nil, "verse line 2 preserved")
    assert_true(normalized:find(";\nFor he can") ~= nil, "semicolon stanza break")
    assert_true(not normalized:find("\n\n", 1, true), "nbsp verse has no stanza blank lines")

    local verse_meta = { book_title = "Alice", doc_title = "Alice", author = "Carroll", sidecar_name = "alice.sdr" }
    local verse_settings = {
        library_metadata_style = "hashtags_only",
        library_use_callouts = true,
        library_preserve_verse_layout = true,
    }
    local verse_block = Export.format_quote_block({
        text = alice_verse,
        pageno = 48,
        chapter = "CHAPTER VI. Pig and Pepper",
    }, verse_meta, verse_settings)
    assert_true(verse_block:find("boy,\\") ~= nil, "verse hard break after line 1")
    assert_true(verse_block:find("sneezes;\\") ~= nil, "verse hard break after line 2")
    assert_true(verse_block:find("enjoy\\") ~= nil, "verse hard break after line 3")
    assert_true(not verse_block:match("pleases!\\"), "no hard break after last line")
    assert_true(not verse_block:find(NBSP, 1, true), "verse block has no nbsp")

    local prose_block = Export.format_quote_block({
        text = "Normal prose highlight with single spaces only.",
        pageno = 1,
    }, verse_meta, verse_settings)
    assert_true(not prose_block:find("\\"), "prose has no hard breaks")
    assert_true(prose_block:find("Normal prose") ~= nil, "prose text unchanged")

    local multiline_block = Export.format_quote_block({
        text = "First line\nSecond line",
        pageno = 1,
    }, verse_meta, verse_settings)
    assert_true(multiline_block:find("First line\\") ~= nil, "existing newline gets hard break")
    assert_true(not multiline_block:match("Second line\\"), "last existing line has no hard break")

    local verse_off = Export.format_quote_block({
        text = alice_verse,
        pageno = 48,
    }, verse_meta, {
        library_metadata_style = "hashtags_only",
        library_use_callouts = true,
        library_preserve_verse_layout = false,
    })
    assert_true(not verse_off:find("\\"), "toggle off skips hard breaks")
    assert_true(verse_off:find(NBSP) ~= nil, "toggle off keeps nbsp padding")

    local lobster_verse
    do
        local fixture = io.open("spec/lobster_fixture.txt", "r")
        if not fixture then
            fixture = io.open("lobster_fixture.txt", "r")
        end
        if fixture then
            lobster_verse = fixture:read("*a")
            fixture:close()
        end
    end
    assert_true(lobster_verse ~= nil and lobster_verse ~= "", "lobster fixture loaded")
    assert_true(not Export.has_verse_nbsp(lobster_verse), "lobster has no nbsp")
    assert_true(Export.looks_like_verse_layout(lobster_verse), "lobster detected as verse layout")
    local lobster_normalized = Export.normalize_verse_text(lobster_verse)
    assert_true(select(2, lobster_normalized:gsub("\n", "")) >= 15, "lobster normalized to many lines")
    assert_true(lobster_normalized:find("\nBut the snail", 1, true) ~= nil, "lobster stanza break before But")
    assert_true(lobster_normalized:find("\nWhen they", 1, true) ~= nil, "lobster stanza break before When")
    assert_true(not lobster_normalized:find("sea!" .. string.char(226, 128, 157) .. " But", 1, true),
        "no merged When/But line")
    assert_eq(select(2, lobster_normalized:gsub("\n\n", "\n")), 2, "lobster has two stanza gaps")
    assert_true(lobster_normalized:find("\n\n" .. string.char(226, 128, 156) .. "You can", 1, true) ~= nil,
        "stanza gap before second stanza")
    assert_true(lobster_normalized:find("\n\n" .. string.char(226, 128, 156) .. "What matters", 1, true) ~= nil,
        "stanza gap before third stanza")
    local lobster_block = Export.format_quote_block({
        text = lobster_verse,
        pageno = 55,
        chapter = "CHAPTER X. The Lobster Quadrille",
    }, verse_meta, verse_settings)
    assert_true(lobster_block:find("snail.\\") ~= nil, "lobster hard break after first line")
    assert_true(lobster_block:find("dance?\\", 1, true) ~= nil, "lobster hard breaks in chorus")
    assert_true(lobster_block:find("sea!" .. string.char(226, 128, 157) .. "\\") ~= nil,
        "hard break after out to sea line")
    assert_true(not lobster_block:find("out to sea!" .. string.char(226, 128, 157) .. " But", 1, true),
        "lobster callout splits But onto its own line")
    assert_true(lobster_block:find("dance?\\\n> \n> " .. string.char(226, 128, 156) .. "You can", 1, true) ~= nil,
        "lobster callout blank line between stanzas")
    assert_true(not lobster_block:find("\n\n", 1, true), "lobster block uses callout blank lines not double newlines")
    assert_true(not lobster_block:find(NBSP, 1, true), "lobster block has no nbsp")

    assert_true(not Export.looks_like_verse_layout(
        "Normal prose highlight with single spaces only."), "short prose not verse layout")

    local lobster_voice
    do
        local fixture = io.open("spec/lobster_voice_fixture.txt", "r")
        if not fixture then
            fixture = io.open("lobster_voice_fixture.txt", "r")
        end
        if fixture then
            lobster_voice = fixture:read("*a")
            fixture:close()
        end
    end
    assert_true(lobster_voice ~= nil and lobster_voice ~= "", "lobster voice fixture loaded")
    assert_true(Export.looks_like_verse_layout(lobster_voice), "lobster voice detected as verse layout")
    local voice_normalized = Export.normalize_verse_text(lobster_voice)
    assert_true(select(2, voice_normalized:gsub("\n", "")) >= 7, "lobster voice normalized to many lines")
    assert_true(voice_normalized:find("\nTrims", 1, true) ~= nil, "lobster voice break before Trims")
    assert_true(not voice_normalized:find("the\nLobster", 1, true), "lobster voice keeps the Lobster together")
    assert_true(not voice_normalized:find("the\nShark", 1, true), "lobster voice keeps the Shark together")
    assert_true(voice_normalized:find("\nWhen", 1, true) ~= nil, "lobster voice break before When")
    assert_true(voice_normalized:find("\nAnd", 1, true) ~= nil, "lobster voice break before And")
    assert_eq(select(2, voice_normalized:gsub("\n\n", "\n")), 1, "lobster voice has one stanza gap")
    assert_true(voice_normalized:find("\n\n[", 1, true) ~= nil, "stanza gap before bracket block")
    local voice_block = Export.format_quote_block({
        text = lobster_voice,
        pageno = 57,
        chapter = "CHAPTER X. The Lobster Quadrille",
    }, verse_meta, verse_settings)
    assert_true(voice_block:find("toes." .. string.char(226, 128, 157) .. "\\", 1, true) ~= nil,
        "lobster voice hard break before stanza gap")
    assert_true(voice_block:find("toes." .. string.char(226, 128, 157) .. "\\\n> \n> [later", 1, true) ~= nil,
        "lobster voice callout blank line before bracket stanza")

    local verse_override = Export.format_quote_block({
        text = "First line here; For second line follows.",
        pageno = 1,
        highlight_sync_quote_layout = "verse",
    }, verse_meta, verse_settings)
    assert_true(verse_override:find("here;\\") ~= nil, "verse layout override forces normalization")

    local prose_override = Export.format_quote_block({
        text = lobster_voice,
        pageno = 57,
        highlight_sync_quote_layout = "prose",
    }, verse_meta, verse_settings)
    assert_true(not prose_override:find("\\"), "prose layout override skips hard breaks")
    assert_true(prose_override:find("nose Trims", 1, true) ~= nil, "prose override keeps flat text")

    local LibraryExport = require("library_export")
    local capture_item = {
        text = "quoted",
        pageno = 3,
        highlight_sync_tags = { "aversion" },
        highlight_sync_capture = "quotes/images/abc123.png",
    }
    local no_embed = Export.format_quote_block(capture_item, {
        book_title = "Book",
        doc_title = "Book Title",
        author = "Author Name",
        sidecar_name = "book.sdr",
        tag_bank = {},
    }, block_settings)
    assert_true(not no_embed:find("!%[%[quotes/images"), "no embed without library_embed_screenshot")

    local embed_settings = {}
    for k, v in pairs(block_settings) do embed_settings[k] = v end
    embed_settings.library_embed_screenshot = true
    embed_settings.library_include_screenshots = true
    local still_no_file = Export.format_quote_block(capture_item, {
        book_title = "Book",
        sidecar_name = "book.sdr",
        tag_bank = {},
    }, embed_settings)
    assert_true(not still_no_file:find("!%[%[quotes/images"), "no embed when png missing on disk")
    assert_true(not LibraryExport.capture_image_exists(capture_item),
        "shared capture_image_exists false when png missing")

    local off_settings = {}
    for k, v in pairs(embed_settings) do off_settings[k] = v end
    off_settings.library_include_screenshots = false
    local test_item = {
        text = "quoted",
        pageno = 3,
        pos0 = "/body/DocFragment[1]/body/div/p[1]/text().0",
        pos1 = "/body/DocFragment[1]/body/div/p[1]/text().5",
        highlight_sync_tags = { "love" },
        highlight_sync_capture = LibraryExport.get_capture_relative_path({
            pos0 = "/body/DocFragment[1]/body/div/p[1]/text().0",
            pos1 = "/body/DocFragment[1]/body/div/p[1]/text().5",
        }),
    }
    LibraryExport.ensure_local_dirs()
    local png_path = LibraryExport.get_quote_image_path(test_item)
    local f = io.open(png_path, "wb")
    if f then
        f:write("fake")
        f:close()
        local with_embed = Export.format_quote_block(test_item, {
            book_title = "Book",
            sidecar_name = "book.sdr",
            tag_bank = {},
        }, embed_settings)
        assert_true(with_embed:find("!%[%[quotes/images/") ~= nil, "embed when png exists")
        os.remove(png_path)
    end

    local book_settings = { library_include_screenshots = true }
    local book_item = {
        text = "book quote",
        pageno = 35,
        chapter = "CHAPTER VI. Pig and Pepper",
        datetime = "2026-06-30 16:16:25",
        highlight_sync_capture = LibraryExport.get_capture_relative_path({
            pos0 = "/body/DocFragment[8]/body/div/p[40]/text()[1].1",
            pos1 = "/body/DocFragment[8]/body/div/p[40]/text()[4].34",
        }),
    }
    local book_png = LibraryExport.get_quote_image_path(book_item)
    local book_md_missing = Export.to_markdown({ book_item }, {}, book_settings)
    assert_true(not book_md_missing:find("!%[%[quotes/images/"),
        "book markdown omits embed when png missing")

    local book_f = io.open(book_png, "wb")
    if book_f then
        book_f:write("fake")
        book_f:close()
        local book_md = Export.to_markdown({ book_item }, {}, book_settings)
        assert_true(book_md:find("!%[%[quotes/images/") ~= nil,
            "book markdown embeds screenshot below callout when png exists")
        assert_true(book_md:find("book quote", 1, true) ~= nil,
            "book markdown keeps callout text")
        os.remove(book_png)
    end

    local book_off = { library_include_screenshots = false }
    book_f = io.open(book_png, "wb")
    if book_f then
        book_f:write("fake")
        book_f:close()
        local book_md_off = Export.to_markdown({ book_item }, {}, book_off)
        assert_true(not book_md_off:find("!%[%[quotes/images/"),
            "book markdown omits embed when screenshots disabled")
        os.remove(book_png)
    end
end
