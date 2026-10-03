return function(assert_eq, assert_true, Suggestions)
    local bank = {
        {
            kind = "folder", id = "themes", name = "Themes", children = {
                { kind = "tag", id = "compassion", name = "Compassion" },
                { kind = "tag", id = "leadership", name = "Leadership" },
                { kind = "tag", id = "ocean", name = "Ocean" },
            },
        },
    }
    local current = {
        id = "current",
        pos0 = "/p/9.1",
        pos1 = "/p/9.8",
        text = "Patient kindness and empathy support compassionate care.",
    }
    local annotations = {
        {
            id = "c1", text = "Patient kindness and empathy require attentive care.",
            note = "A compassion practice.", datetime = "2026-07-01 10:00:00",
            highlight_sync_tags = { "compassion", "deleted_from_bank" },
        },
        {
            id = "c2", text = "Kindness and patient care develop empathy.",
            datetime_updated = "2026-07-03 10:00:00",
            highlight_sync_tags = { "compassion" },
        },
        {
            id = "l1", text = "Strategic teams need decisive governance.",
            datetime = "2026-07-04 10:00:00",
            highlight_sync_tags = { "leadership" },
        },
        {
            id = "folder1", text = "Mindful attention supports awareness.",
            datetime = "2026-07-02 10:00:00",
            highlight_sync_tags = { "themes" },
        },
        {
            id = "position-copy", pos0 = "/p/9.1", pos1 = "/p/9.8",
            text = "Ocean waves and currents.", highlight_sync_tags = { "ocean" },
        },
        current,
    }

    local result = Suggestions.suggest(current.text, annotations, bank, {
        current_annotation = current,
        current_index = 6,
    })
    assert_eq(result.suggestions[1].id, "compassion",
        "TF-IDF ranks matching history first")
    local all_ids = {}
    for _, row in ipairs(result.suggestions) do all_ids[row.id] = true end
    for _, row in ipairs(result.recent) do all_ids[row.id] = true end
    assert_true(not all_ids.deleted_from_bank, "candidate set is closed to current bank")
    assert_true(not all_ids.ocean, "same-position current copy excluded")
    assert_true(all_ids.themes, "folder/category ids remain valid candidates")

    local weak = Suggestions.suggest("patient", annotations, bank, {
        current_annotation = current,
        current_index = 6,
    })
    assert_eq(#weak.suggestions, 0, "one shared token stays below conservative threshold")

    local exact = Suggestions.suggest("A difficult Leadership decision.", annotations, bank, {
        current_annotation = current,
        current_index = 6,
    })
    assert_eq(exact.suggestions[1].id, "leadership",
        "exact display-name occurrence boosts candidate")
    assert_true(exact.suggestions[1].exact_match, "exact match is marked")
    for _, row in ipairs(exact.recent) do
        assert_true(row.id ~= "leadership", "recent list dedupes suggestions")
    end

    assert_true(Suggestions.is_current_annotation(current, 6, current, 6),
        "table identity excludes current")
    assert_true(Suggestions.is_current_annotation({ text = "copy" }, 6, current, 6),
        "annotation index excludes current")
    assert_true(Suggestions.is_current_annotation({ id = "current" }, 2, current, 6),
        "persistent identity excludes current")
    assert_true(Suggestions.is_current_annotation({
        pos0 = "/p/9.1", pos1 = "/p/9.8",
    }, 2, current, 6), "position identity excludes current")

    local recent_bank = {
        { kind = "tag", id = "alpha", name = "Alpha" },
        { kind = "tag", id = "beta", name = "Beta" },
        { kind = "tag", id = "gamma", name = "Gamma" },
    }
    local recent_annotations = {
        { text = "older alpha text", datetime = "2026-01-01 00:00:00",
            highlight_sync_tags = { "alpha" } },
        { text = "new beta one", datetime = "2026-02-01 00:00:00",
            highlight_sync_tags = { "beta" } },
        { text = "new beta two", datetime_updated = "2026-02-01 00:00:00",
            highlight_sync_tags = { "beta" } },
        { text = "new gamma", datetime = "2026-02-01 00:00:00",
            highlight_sync_tags = { "gamma" } },
    }
    local recent_result = Suggestions.suggest("unrelated vocabulary", recent_annotations, recent_bank)
    assert_eq(recent_result.recent[1].id, "beta",
        "equal recency uses frequency tie-break")
    assert_eq(recent_result.recent[2].id, "gamma", "recent unique tags remain deterministic")
    assert_eq(recent_result.recent[3].id, "alpha", "older tag follows newer tags")

    local cap_bank, cap_annotations, query_parts = {}, {}, {}
    for i = 1, 15 do
        local id = "topic" .. i
        cap_bank[#cap_bank + 1] = { kind = "tag", id = id, name = id }
        cap_annotations[#cap_annotations + 1] = {
            text = "history for " .. id,
            datetime = string.format("2026-03-%02d 00:00:00", i),
            highlight_sync_tags = { id },
        }
        if i <= 7 then query_parts[#query_parts + 1] = id end
    end
    local capped = Suggestions.suggest(table.concat(query_parts, " "), cap_annotations, cap_bank)
    assert_eq(#capped.suggestions, 5, "suggestions hard-cap at five")
    assert_true(#capped.recent <= 12, "recent tags stay within hard cap")
    local suggested = {}
    for _, row in ipairs(capped.suggestions) do suggested[row.id] = true end
    for _, row in ipairs(capped.recent) do
        assert_true(not suggested[row.id], "capped recent remains deduped from suggestions")
    end
    local recent_capped = Suggestions.suggest(
        "entirely unrelated vocabulary", cap_annotations, cap_bank)
    assert_eq(#recent_capped.recent, 12, "recent tags hard-cap at twelve")
end
