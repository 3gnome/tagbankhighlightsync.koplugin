return function(assert_eq, assert_true, LibraryExport, Merge, Tags)
    local Export = require("export")
    local settings = {
        library_use_callouts = true,
        library_metadata_style = "both",
    }
    LibraryExport.ensure_local_dirs()

    local item = {
        page = "p",
        pos0 = "a",
        pos1 = "b",
        text = "quote text",
        highlight_sync_tags = { "love" },
        datetime = "2026-01-01 10:00:00",
    }
    local ctx = {
        book_title = "Alice",
        doc_title = "Alice in Wonderland",
        author = "Carroll",
        sidecar_name = "alice.sdr",
        tag_bank = {},
    }
    local block = Export.format_quote_block(item, {
        book_title = "Alice",
        doc_title = "Alice in Wonderland",
        author = "Carroll",
        sidecar_name = "alice.sdr",
    }, settings)
    local heading = LibraryExport.block_heading(item, ctx)
    local legacy = LibraryExport.legacy_block_heading(item, ctx)

    local content = LibraryExport.upsert_quote_block("", item, ctx, settings)
    assert_true(content:find("quote text") ~= nil, "block written")
    assert_true(content:find("hs:key", 1, true) ~= nil, "stable anchor written")
    assert_true(content:find("#love") ~= nil, "tag in block")
    assert_true(not content:find("highlight_sync"), "no sync markers")
    assert_true(not content:find("%%"), "no obsidian comment markers")
    assert_true(content:find("Carroll") ~= nil, "scholarly author in heading")
    assert_true(content:find("captured::") ~= nil, "circadian captured field")
    assert_true(not content:find("**Book:**"), "no redundant footer")

    item.text = "quote text updated"
    local content2 = LibraryExport.upsert_quote_block(content, item, ctx, settings)
    assert_true(content2:find("quote text updated") ~= nil, "block updated")
    assert_eq(select(2, content2:gsub("hs:key", "")), 1, "single anchor after update")

    content2 = LibraryExport.remove_quote_block(content2, item, ctx)
    assert_true(not content2:find("quote text"), "block removed")

    local css = LibraryExport.build_scholarly_quotes_css()
    assert_true(css:find("pre-wrap", 1, true) ~= nil, "verse pre-wrap css in scholarly snippet")
    assert_true(css:find("is-live-preview", 1, true) ~= nil, "verse css covers live preview")

    local legacy_file = table.concat({
        "%% highlight_sync:a|b %%",
        legacy,
        "quote text",
        "%% /highlight_sync %%",
        "",
    }, "\n")
    local migrated = LibraryExport.upsert_block_by_heading(legacy_file, heading, block, legacy)
    assert_true(not migrated:find("highlight_sync"), "legacy markers stripped on upsert")
    assert_true(migrated:find("quote text") ~= nil, "legacy content preserved")
    assert_true(migrated:find("Carroll") ~= nil, "legacy upsert uses scholarly heading")

    local bank = {
        { kind = "folder", id = "buddhism", name = "Buddhism", children = {
            { kind = "tag", id = "aversion", name = "aversion" },
        }},
    }
    local tagged = {
        page = "2",
        pos0 = "c",
        pos1 = "d",
        text = "Buddhist quote",
        highlight_sync_tags = { "aversion" },
        datetime = "2026-06-01 12:00:00",
    }
    local expanded = Tags.expand_for_export(Tags.get_tags(tagged), bank)
    assert_eq(#expanded, 2, "expanded tag count for index")
    assert_true(LibraryExport.write_file(LibraryExport.get_tag_index_path("_probe"), "# probe\n"), "write_file probe")
    local tag_ctx = {
        book_title = "Alice",
        doc_title = "Alice in Wonderland",
        author = "Carroll",
        sidecar_name = "alice.sdr",
        filename = "alice.sdr",
        tag_bank = bank,
    }
    LibraryExport.update_tag_indexes_for_annotation(tagged, tag_ctx, false, settings)
    local buddhism_md = LibraryExport.read_file(LibraryExport.get_tag_index_path("buddhism"))
    local aversion_md = LibraryExport.read_file(LibraryExport.get_tag_index_path("aversion"))
    assert_true(#buddhism_md > 0, "buddhism index file written")
    assert_true(buddhism_md:find("[[quotes/", 1, true) ~= nil, "buddhism index link")
    assert_true(aversion_md:find("[[quotes/", 1, true) ~= nil, "aversion index link")
    assert_true(buddhism_md:find("#buddhism") ~= nil or buddhism_md:find("#aversion") ~= nil, "tag hashtag in index")
    assert_true(not buddhism_md:find("Buddhist quote"), "buddhism index omits quote body")
    assert_true(not buddhism_md:find("highlight_sync"), "tag index no sync markers")

    LibraryExport.update_tag_indexes_for_annotation(tagged, tag_ctx, true, settings)
    buddhism_md = LibraryExport.read_file(LibraryExport.get_tag_index_path("buddhism"))
    assert_true(not buddhism_md:find("[[quotes/", 1, true), "buddhism index cleared on remove")

    local retagged = {
        page = "2",
        pos0 = "c",
        pos1 = "d",
        text = "Buddhist quote",
        highlight_sync_tags = { "love" },
        datetime = "2026-06-01 12:00:00",
        highlight_sync_tags_prev_expanded = { "buddhism", "aversion" },
    }
    LibraryExport.update_tag_indexes_for_annotation(retagged, tag_ctx, false, settings)
    buddhism_md = LibraryExport.read_file(LibraryExport.get_tag_index_path("buddhism"))
    local love_md = LibraryExport.read_file(LibraryExport.get_tag_index_path("love"))
    assert_true(not buddhism_md:find("[[quotes/", 1, true), "stale tag index removed on tag change")
    assert_true(love_md:find("[[quotes/", 1, true) ~= nil, "new tag index upserted")

    item.datetime_updated = "2026-06-02 08:00:00"
    local content3 = LibraryExport.upsert_quote_block(content, item, ctx, settings)
    assert_eq(select(2, content3:gsub("quote text", "")), 1, "datetime change does not duplicate quote")

    settings.library_templates_version = 0
    LibraryExport.ensure_library_assets(settings)
    assert_true(#LibraryExport.read_file(LibraryExport.get_readme_path()) > 0, "library readme")
    assert_true(#LibraryExport.read_file(LibraryExport.get_templates_dir() .. "/Writing Dashboard.md") > 0, "writing dashboard")
    assert_true(LibraryExport.read_file(LibraryExport.get_templates_dir() .. "/Writing Dashboard.md"):find('FROM "quotes"') ~= nil, "dashboard quotes query")

    assert_true(LibraryExport.is_hybrid_layout({}), "always hybrid layout")

    LibraryExport.write_atomic_quote(item, ctx, settings)
    local atomic_path = LibraryExport.get_quote_path(item)
    local path_again = LibraryExport.get_quote_path(item)
    assert_eq(atomic_path, path_again, "stable atomic path")
    local atomic = LibraryExport.read_file(atomic_path)
    assert_true(atomic:find("quote text") ~= nil, "atomic quote body")
    assert_true(atomic:find("hs:key", 1, true) ~= nil, "atomic anchor")
    assert_true(atomic:find("type: quote") ~= nil, "atomic frontmatter")
    assert_true(atomic:find("Source: [[books/alice.sdr]]", 1, true) ~= nil, "atomic book backlink")

    local master_h = LibraryExport.upsert_library_entry("", item, ctx, settings)
    assert_true(master_h:find("[[quotes/", 1, true) ~= nil, "master hybrid link")
    assert_true(not master_h:find("quote text"), "master index omits quote body")

    LibraryExport.update_tag_indexes_for_annotation(tagged, tag_ctx, false, settings)
    aversion_md = LibraryExport.read_file(LibraryExport.get_tag_index_path("aversion"))
    assert_true(aversion_md:find("[[quotes/", 1, true) ~= nil, "tag index hybrid link")
    assert_true(not aversion_md:find("Buddhist quote"), "tag index omits quote body")
    assert_true(aversion_md:find("![[quotes/", 1, true) ~= nil, "tag index embeds atomic quote")

    local embed_settings = { library_tag_index_style = "link" }
    local link_line = LibraryExport.build_index_line(tagged, tag_ctx, embed_settings)
    assert_true(link_line:find("![[quotes/", 1, true) == nil, "link mode omits embed")

    assert_eq(Export.yaml_quote("Feeding Your Demons: Ancient Wisdom"), '"Feeding Your Demons: Ancient Wisdom"', "yaml quotes colons")

    local metadata = {
        book_title = "Alice",
        doc_title = "Alice in Wonderland",
        author = "Carroll",
        sidecar_name = "alice.sdr",
        sync_datetime = "2026-06-01 12:00:00",
    }

    local orange_item = {
        pos0 = "o1", pos1 = "o2", text = "pending word", color = "orange",
        datetime = "2026-06-01 12:00:00",
    }
    local filter_settings = {
        library_include_untagged = true,
        library_exclude_orange_highlights = true,
    }
    assert_true(not LibraryExport.is_library_exportable(orange_item, filter_settings), "orange excluded")
    local book_md = LibraryExport.rebuild_book_document({ orange_item }, filter_settings, metadata)
    assert_true(not book_md:find("pending word"), "orange not in book rebuild")

    local untagged_item = {
        pos0 = "u1", pos1 = "u2", text = "orphan quote",
        datetime = "2026-06-01 12:00:00",
    }
    local tagged_only_settings = { library_include_untagged = false }
    book_md = LibraryExport.rebuild_book_document({ untagged_item }, tagged_only_settings, metadata)
    assert_true(not book_md:find("orphan quote"), "untagged excluded from book")

    local atomic_doc = LibraryExport.build_atomic_quote_document(item, ctx, settings)
    assert_true(not atomic_doc:find("book::"), "atomic body skips inline book field")

    local capture_item = {
        pos0 = "cap0", pos1 = "cap1", text = "captured quote",
        highlight_sync_tags = { "love" },
        highlight_sync_capture = "quotes/images/capturehash.png",
        datetime = "2026-06-01 12:00:00",
    }
    local capture_doc = LibraryExport.build_atomic_quote_document(capture_item, ctx, settings)
    assert_true(not capture_doc:find("screenshot:", 1, true),
        "frontmatter omits screenshot when capture field set but png missing")
    assert_true(not capture_doc:find("!%[%[quotes/images", 1, true),
        "body omits embed when png missing")

    local colon_ctx = {
        book_title = "Feeding Your Demons",
        doc_title = "Feeding Your Demons: Ancient Wisdom",
        author = "Tsultrim Allione",
        sidecar_name = "feeding.sdr",
        filename = "feeding.sdr",
        tag_bank = bank,
    }
    local colon_item = {
        pos0 = "x", pos1 = "y", text = "demon quote",
        highlight_sync_tags = { "demons" },
        datetime = "2026-06-01 12:00:00",
    }
    local colon_doc = LibraryExport.build_atomic_quote_document(colon_item, colon_ctx, settings)
    assert_true(colon_doc:find('book: "Feeding Your Demons: Ancient Wisdom"', 1, true) ~= nil, "colon title quoted in yaml")

    LibraryExport.remove_library_entry(master_h, item, ctx, settings)
    LibraryExport.update_tag_indexes_for_annotation(tagged, tag_ctx, true, settings)
    assert_eq(LibraryExport.read_file(atomic_path), "", "atomic file removed on untag")

    assert_eq(settings.library_templates_version, 4, "template version bumped")

    local stale_readme = LibraryExport.get_readme_path()
    LibraryExport.write_file(stale_readme, "# stale aggregated readme\n")
    local force_settings = { library_force_reupload = true, library_templates_version = 4 }
    LibraryExport.ensure_library_assets(force_settings)
    assert_true(LibraryExport.read_file(stale_readme):find("quotes/", 1, true) ~= nil,
        "readme refreshed on force reupload")

    local util_mod = package.loaded["util"]
    package.loaded["util"] = {
        makePath = util_mod.makePath,
        partialMD5 = function() return nil end,
    }
    local tagged_a = {
        pos0 = "/pos/a",
        pos1 = "/pos/b",
        text = "tagged quote",
        highlight_sync_tags = { "ideas" },
        datetime = "2026-06-29 12:00:00",
    }
    local untagged_b = {
        pos0 = "/pos/c",
        pos1 = "/pos/d",
        text = "untagged quote",
        datetime = "2026-06-29 12:00:00",
    }
    LibraryExport.write_atomic_quote(tagged_a, ctx, settings)
    local tagged_path = LibraryExport.get_quote_path(tagged_a)
    assert_true(LibraryExport.read_file(tagged_path) ~= "", "tagged atomic file written")
    assert_true(tagged_path ~= LibraryExport.get_quote_path(untagged_b), "unique paths when MD5 fails")
    assert_true(tagged_path:match("/[%x]+%.md$") ~= nil, "fallback filename is short hex hash")
    LibraryExport.remove_atomic_quote(untagged_b)
    assert_true(LibraryExport.read_file(tagged_path) ~= "",
        "untagged remove must not delete tagged quote file")
    package.loaded["util"] = util_mod

    local untagged_sync = {
        pos0 = "us0", pos1 = "us1", text = "plain untagged verse",
        datetime = "2026-06-30 12:00:00",
    }
    local sync_ctx = {
        book_title = "Alice",
        doc_title = "Alice in Wonderland",
        author = "Carroll",
        sidecar_name = "alice.sdr",
        filename = "alice.sdr",
        tag_bank = bank,
        sync_datetime = "2026-06-30 12:00:00",
    }
    local master_before = LibraryExport.read_file(LibraryExport.get_master_path({}))
    LibraryExport.refresh_target_for_sync(
        untagged_sync, sync_ctx, { untagged_sync }, { library_include_untagged = true })
    local untagged_atomic = LibraryExport.read_file(LibraryExport.get_quote_path(untagged_sync))
    assert_true(untagged_atomic:find("plain untagged verse") ~= nil, "untagged atomic quote written")
    assert_true(not untagged_atomic:find("\ntags:", 1, true), "untagged atomic omits tags frontmatter")
    local book_path = LibraryExport.get_book_path("alice.sdr")
    assert_true(LibraryExport.read_file(book_path):find("plain untagged verse") ~= nil,
        "untagged in book when include_untagged")
    assert_eq(LibraryExport.read_file(LibraryExport.get_master_path({})), master_before,
        "untagged refresh does not change master index")

    LibraryExport.refresh_target_for_sync(
        untagged_sync, sync_ctx, { untagged_sync }, { library_include_untagged = false })
    assert_true(not LibraryExport.read_file(book_path):find("plain untagged verse"),
        "untagged excluded from book when include_untagged off")

    local tagged_sync = {
        pos0 = "ts0", pos1 = "ts1", text = "tagged verse",
        highlight_sync_tags = { "love" },
        datetime = "2026-06-30 12:00:00",
    }
    local util_mod = package.loaded["util"]
    package.loaded["util"] = {
        makePath = util_mod.makePath,
        partialMD5 = function() return nil end,
    }
    local include_settings = { library_include_untagged = true }
    LibraryExport.refresh_target_for_sync(
        untagged_sync, sync_ctx, { untagged_sync, tagged_sync }, include_settings)
    local untagged_path = LibraryExport.get_quote_path(untagged_sync)
    local tagged_path = LibraryExport.get_quote_path(tagged_sync)
    assert_true(untagged_path ~= tagged_path, "untagged and tagged use distinct quote paths")
    assert_true(LibraryExport.read_file(untagged_path):find("plain untagged verse") ~= nil,
        "untagged atomic exists before full refresh")

    LibraryExport.sync_library_quotes(
        { untagged_sync, tagged_sync }, sync_ctx, include_settings)
    assert_true(LibraryExport.read_file(untagged_path):find("plain untagged verse") ~= nil,
        "sync_library_quotes preserves untagged atomic when include_untagged")

    local keys = LibraryExport.collect_preserved_quote_keys(
        { untagged_sync, tagged_sync }, include_settings)
    assert_true(keys[LibraryExport.quote_block_key(untagged_sync)] == true,
        "preserved keys include untagged when include_untagged")
    assert_true(keys[LibraryExport.quote_block_key(tagged_sync)] == true,
        "preserved keys include tagged")

    local strict_settings = { library_include_untagged = false }
    LibraryExport.sync_library_quotes({ untagged_sync, tagged_sync }, sync_ctx, strict_settings)
    assert_eq(LibraryExport.read_file(untagged_path), "",
        "sync_library_quotes removes untagged atomic when include_untagged off")
    assert_true(LibraryExport.read_file(tagged_path):find("tagged verse") ~= nil,
        "tagged atomic survives strict refresh")
    package.loaded["util"] = util_mod
end
