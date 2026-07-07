return function(assert_eq, assert_true, TagBank, Tags)
    local bank = {
        { kind = "folder", id = "buddhism", name = "Buddhism", children = {
            { kind = "tag", id = "aversion", name = "aversion" },
        }},
        { kind = "tag", id = "quotes", name = "quotes" },
    }

    local expanded = TagBank.expand_for_export({ "aversion" }, bank)
    assert_eq(#expanded, 2, "ancestor export count")
    assert_eq(expanded[1], "aversion", "leaf id")
    assert_eq(expanded[2], "buddhism", "folder id")

    local line = Tags.format_hashtag_line_for_export({ "aversion" }, bank)
    assert_true(line:find("#buddhism") ~= nil, "folder hashtag")
    assert_true(line:find("#aversion") ~= nil, "leaf hashtag")

    local expanded_folder = TagBank.expand_for_export({ "buddhism", "aversion" }, bank)
    assert_eq(#expanded_folder, 2, "stored folder+leaf deduped")

    local migrated = TagBank.migrate_from_presets({ "Love", "grief" })
    assert_eq(#migrated, 2, "preset migration count")
    assert_eq(migrated[1].id, "love", "preset slug")

    local default_bank = TagBank.default_bank()
    assert_eq(default_bank[1].kind, "folder", "default first node is folder")
    assert_eq(default_bank[1].id, "buddhism", "default buddhism folder")
    assert_eq(default_bank[1].children[1].id, "aversion", "default aversion tag")
    assert_true(TagBank.find_by_id(default_bank, "manuscript") ~= nil, "default manuscript folder")
    assert_true(TagBank.find_by_id(default_bank, "themes") ~= nil, "default themes folder")

    local flat_settings = {
        tag_bank = {
            { kind = "tag", id = "love", name = "love" },
            { kind = "tag", id = "grief", name = "grief" },
        },
        tag_bank_layout_version = 0,
    }
    TagBank.ensure_bank(flat_settings)
    assert_eq(flat_settings.tag_bank_layout_version, 3, "layout version bumped")
    assert_true(TagBank.find_by_id(flat_settings.tag_bank, "buddhism") ~= nil, "buddhism added")
    assert_true(TagBank.find_by_id(flat_settings.tag_bank, "general") ~= nil, "general folder")

    local buddhism_folder = TagBank.find_by_id(default_bank, "buddhism")
    assert_eq(TagBank.count_tags_in_folder(buddhism_folder), 1, "buddhism tag count")
    assert_true(TagBank.format_folder_tag_count(buddhism_folder):find("1") ~= nil, "folder count label")

    local bank2 = {}
    local buddhism = TagBank.add_folder(bank2, {}, "Buddhism")
    assert_eq(buddhism.kind, "folder", "add folder kind")
    local tag = TagBank.add_tag(bank2, { buddhism.id }, "Craving")
    assert_true(tag.id ~= nil, "add tag id")

    local nested = TagBank.add_folder_for_apply(bank2, { buddhism.id }, "  Four Noble Truths  ")
    assert_eq(nested.id, "four_noble_truths", "nested folder slug")
    assert_eq(#buddhism.children, 2, "nested folder in parent")

    local expanded_parent = TagBank.expand_for_export({ buddhism.id }, bank2)
    assert_eq(#expanded_parent, 1, "folder id alone exports as parent tag")
    assert_eq(expanded_parent[1], buddhism.id, "parent tag id")

    assert_eq(TagBank.add_folder_for_apply(bank2, {}, "  "), nil, "blank name rejected")

    local settings = { tag_presets = { "ideas" } }
    TagBank.ensure_bank(settings)
    assert_true(#settings.tag_bank >= 1, "ensure bank")
end
