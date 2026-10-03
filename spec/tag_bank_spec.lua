return function(assert_eq, assert_true, TagBank, Tags)
    local function assert_ids(nodes, expected, label)
        assert_eq(#nodes, #expected, label .. " count")
        for i, id in ipairs(expected) do
            assert_eq(nodes[i].id, id, label .. " item " .. i)
        end
    end

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
    assert_eq(flat_settings.tag_bank_layout_version, 4, "layout version bumped")
    assert_true(TagBank.find_by_id(flat_settings.tag_bank, "buddhism") ~= nil, "buddhism added")
    assert_true(TagBank.find_by_id(flat_settings.tag_bank, "general") ~= nil, "general folder")

    local nested_folder = {
        kind = "folder", id = "folder_b", name = "Beta", children = {
            { kind = "tag", id = "nested_z", name = "same" },
            { kind = "folder", id = "nested_folder_b", name = "beta", children = {
                { kind = "tag", id = "deep_z", name = "ALPHA" },
                { kind = "tag", id = "deep_a", name = "alpha" },
            }},
            { kind = "folder", id = "nested_folder_a", name = "Alpha", children = {} },
            { kind = "tag", id = "nested_a", name = "Same" },
        },
    }
    local sortable = {
        { kind = "tag", id = "tag_z", name = "zulu" },
        { kind = "folder", id = "folder_z", name = "alpha", children = {} },
        { kind = "tag", id = "tag_b", name = "Beta" },
        nested_folder,
        { kind = "folder", id = "folder_a", name = "Alpha", children = {} },
        { kind = "tag", id = "tag_a", name = "alpha" },
    }
    local sorted = TagBank.sort_bank(sortable)
    assert_eq(sorted, sortable, "sort keeps original bank table")
    assert_ids(sortable,
        { "folder_a", "folder_z", "folder_b", "tag_a", "tag_b", "tag_z" },
        "mixed root siblings")
    assert_eq(sortable[3], nested_folder, "sort preserves nested folder node")
    assert_ids(nested_folder.children,
        { "nested_folder_a", "nested_folder_b", "nested_a", "nested_z" },
        "mixed nested siblings")
    assert_ids(nested_folder.children[2].children,
        { "deep_a", "deep_z" },
        "case-tied deep siblings")

    local legacy_folder = {
        kind = "folder", id = "legacy_folder", name = "Legacy", children = {
            { kind = "tag", id = "legacy_z", name = "Zulu" },
            { kind = "tag", id = "legacy_a", name = "alpha" },
        },
    }
    local legacy_settings = {
        tag_bank = {
            { kind = "tag", id = "root_z", name = "Zulu" },
            legacy_folder,
            { kind = "folder", id = "alpha_folder", name = "alpha", children = {} },
            { kind = "tag", id = "root_a", name = "alpha" },
        },
        tag_bank_migrated = true,
        tag_bank_layout_version = 3,
    }
    local ensured_legacy, legacy_migrated = TagBank.ensure_bank(legacy_settings)
    assert_true(legacy_migrated, "legacy ordering migration reported")
    assert_eq(legacy_settings.tag_bank_layout_version, 4, "sort migration version persisted")
    assert_ids(ensured_legacy,
        { "alpha_folder", "legacy_folder", "root_a", "root_z" },
        "legacy root ordering")
    assert_ids(legacy_folder.children,
        { "legacy_a", "legacy_z" },
        "legacy nested ordering")
    local _, legacy_migrated_again = TagBank.ensure_bank(legacy_settings)
    assert_eq(legacy_migrated_again, false, "sort migration is idempotent")

    local ensured_defaults = TagBank.ensure_bank({})
    local default_general = TagBank.find_by_id(ensured_defaults, "general")
    assert_ids(default_general.children,
        { "grief", "ideas", "leadership", "love", "quotes" },
        "default children ordering")

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

    local mutation_bank = {
        { kind = "folder", id = "middle_folder", name = "Middle", children = {
            { kind = "tag", id = "nested_zulu", name = "Zulu" },
        }},
        { kind = "folder", id = "zulu_folder", name = "Zulu", children = {
            { kind = "tag", id = "dest_beta", name = "Beta" },
        }},
        { kind = "tag", id = "middle_tag", name = "Middle" },
    }
    local added_tag = TagBank.add_tag(mutation_bank, {}, "alpha")
    assert_ids(mutation_bank,
        { "middle_folder", "zulu_folder", added_tag.id, "middle_tag" },
        "add tag reorder")
    local added_folder = TagBank.add_folder(mutation_bank, {}, "beta")
    assert_ids(mutation_bank,
        { added_folder.id, "middle_folder", "zulu_folder", added_tag.id, "middle_tag" },
        "add folder reorder")
    local added_nested_folder = TagBank.add_folder(
        mutation_bank, { "middle_folder" }, "zz Folder")
    assert_ids(TagBank.find_by_id(mutation_bank, "middle_folder").children,
        { added_nested_folder.id, "nested_zulu" },
        "nested add folders first")

    assert_true(TagBank.rename_node(mutation_bank, added_folder.id, "Omega"),
        "rename succeeds")
    assert_ids(mutation_bank,
        { "middle_folder", added_folder.id, "zulu_folder", added_tag.id, "middle_tag" },
        "rename reorder")

    assert_true(TagBank.move_node(mutation_bank, added_tag.id, { "zulu_folder" }),
        "move succeeds")
    assert_ids(mutation_bank,
        { "middle_folder", added_folder.id, "zulu_folder", "middle_tag" },
        "move source reorder")
    local moved_tag = TagBank.find_by_id(mutation_bank, added_tag.id)
    assert_eq(moved_tag, added_tag, "move preserves node identity")
    assert_eq(moved_tag.id, added_tag.id, "move preserves node id")
    assert_ids(TagBank.find_by_id(mutation_bank, "zulu_folder").children,
        { added_tag.id, "dest_beta" },
        "move destination reorder")
end
