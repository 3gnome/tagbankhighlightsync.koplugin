return function(assert_eq, assert_true, FromHighlight, TagBank)
    local function ids(words)
        local out = {}
        for _, w in ipairs(words) do
            out[#out + 1] = w.id
        end
        return out
    end

    local function has_id(words, id)
        for _, w in ipairs(words) do
            if w.id == id then
                return true
            end
        end
        return false
    end

    assert_eq(#FromHighlight.extract_words("", TagBank.default_bank()), 0, "empty text")
    assert_eq(#FromHighlight.extract_words(nil, TagBank.default_bank()), 0, "nil text")

    local stop_text = "without themselves which would there really always"
    local stop_words = FromHighlight.extract_words(stop_text, TagBank.default_bank())
    assert_eq(#stop_words, 0, "stopwords only")

    local short_text = "the cat sat on a mat with dogs"
    local short_words = FromHighlight.extract_words(short_text, TagBank.default_bank())
    assert_eq(#short_words, 0, "words under 5 letters skipped")

    assert_eq(TagBank.format_display_name("government"), "Government", "title case")
    assert_eq(TagBank.format_display_name("Alice"), "Alice", "preserve casing")
    assert_eq(TagBank.format_display_name("Caucus-Race"), "Caucus-Race", "hyphenated proper")

    local hyphen_text = "They ran the Caucus-Race together."
    local hyphen_words = FromHighlight.extract_words(hyphen_text, TagBank.default_bank())
    assert_true(has_id(hyphen_words, "caucus-race"), "Caucus-Race one token")

    local linebreak_text = "He was self-\naware of it."
    local linebreak_words = FromHighlight.extract_words(linebreak_text, TagBank.default_bank())
    assert_true(has_id(linebreak_words, "selfaware"), "dehyphenated selfaware")

    local contraction_text = "Don't I'll won't"
    assert_eq(#FromHighlight.extract_words(contraction_text, TagBank.default_bank()), 0, "short contractions excluded")

    local bank = TagBank.default_bank()
    local bank_text = "She kept quotes about love and grief."
    local bank_words = FromHighlight.extract_words(bank_text, bank)
    assert_true(not has_id(bank_words, "quotes"), "bank id quotes excluded")
    assert_true(not has_id(bank_words, "love"), "bank id love excluded")

    local score_text = "Alice walked familiarly through the consultation room."
    local score_words = FromHighlight.extract_words(score_text, bank)
    local score_ids = ids(score_words)
    local alice_idx, familiarly_idx, consultation_idx
    for i, id in ipairs(score_ids) do
        if id == "alice" then alice_idx = i end
        if id == "familiarly" then familiarly_idx = i end
        if id == "consultation" then consultation_idx = i end
    end
    assert_true(alice_idx ~= nil, "alice extracted")
    assert_true(familiarly_idx ~= nil, "familiarly extracted")
    assert_true(alice_idx < familiarly_idx, "Alice beats familiarly")
    assert_true(consultation_idx ~= nil and consultation_idx < familiarly_idx, "consultation beats familiarly")

    local long_word_list = {
        "apple", "banana", "cherry", "dragon", "elephant", "falcon", "garden",
        "harbor", "island", "jungle", "kitten", "ladder", "magnum", "nectar",
        "orange", "planet", "quartz", "rocket", "silver", "temple", "unicorn",
        "velvet", "wizard", "yellow", "zephyr",
    }
    local capped = FromHighlight.extract_words(table.concat(long_word_list, " "), bank)
    assert_eq(#capped, 20, "max 20 words")

    local nineteen_parts = {}
    for i = 1, 19 do
        nineteen_parts[#nineteen_parts + 1] = long_word_list[i]
    end
    assert_eq(#FromHighlight.extract_words(table.concat(nineteen_parts, " "), bank), 19, "19 eligible shown")

    local repeat_text = "wonder wonder wonder marvelous shadow shadow"
    local repeat_words = FromHighlight.extract_words(repeat_text, bank)
    local repeat_ids = ids(repeat_words)
    local wonder_idx, shadow_idx
    for i, id in ipairs(repeat_ids) do
        if id == "wonder" then wonder_idx = i end
        if id == "shadow" then shadow_idx = i end
    end
    assert_true(wonder_idx ~= nil and shadow_idx ~= nil, "repeat test words found")
    assert_true(wonder_idx < shadow_idx, "repeated wonder ranks above shadow")

    local pad = string.rep("x ", 40)
    local position_text = "castle " .. pad .. "fortress"
    local position_words = FromHighlight.extract_words(position_text, bank)
    local position_ids = ids(position_words)
    local castle_idx, fortress_idx
    for i, id in ipairs(position_ids) do
        if id == "castle" then castle_idx = i end
        if id == "fortress" then fortress_idx = i end
    end
    assert_true(castle_idx ~= nil and fortress_idx ~= nil, "position test words found")
    assert_true(castle_idx < fortress_idx, "early castle beats late fortress")

    local alice_snippet = [[Alice was beginning to get very tired of sitting by her sister
on the bank, and of having nothing to do: once or twice she had peeped into the
book her sister was reading, but it had no pictures or conversations in it,
'and what is the use of a book,' thought Alice 'without pictures or conversation?']]

    local alice_words = FromHighlight.extract_words(alice_snippet, bank)
    assert_true(#alice_words > 0, "alice snippet yields words")
    assert_true(has_id(alice_words, "alice"), "alice in snippet")
    assert_true(not has_id(alice_words, "without"), "without stopword omitted")

    local para_text = "Melancholy\n\nConsultation"
    local para_words = FromHighlight.extract_words(para_text, bank)
    assert_true(has_id(para_words, "melancholy"), "paragraph break keeps words separate")
    assert_true(has_id(para_words, "consultation"), "second paragraph word kept")

    local collected = TagBank.collect_ids(bank)
    assert_true(collected.quotes == true, "collect_ids includes quotes")
    assert_true(collected.buddhism == true, "collect_ids includes folders")
end
