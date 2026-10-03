return function(assert_eq, assert_true, HighlightContext)
    local page = table.concat({
        "Header",
        "",
        "A first paragraph about weather.",
        "",
        "The mind becomes quiet. Compassion grows through patient attention.",
        "",
        "Footer",
    }, "\n")
    local paragraph = HighlightContext.extract_paragraph(
        page, "Compassion grows", { max_words = 20 })
    assert_eq(paragraph,
        "The mind becomes quiet. Compassion grows through patient attention.",
        "extracts blank-line paragraph around highlight")
    assert_true(not paragraph:find("weather", 1, true),
        "paragraph excludes other visible-page blocks")

    local screen = {
        getWidth = function() return 600 end,
        getHeight = function() return 800 end,
    }
    local called_with_screen
    local document = {
        getTextFromPositions = function(_, pos0, pos1, visible)
            called_with_screen = pos0.x == 0 and pos0.y == 0
                and pos1.x == 600 and pos1.y == 800 and visible
            return { lines = { { text = page } } }
        end,
    }
    local context, source = HighlightContext.get(nil, {
        text = "Compassion grows",
    }, {
        document = document,
        screen = screen,
    })
    assert_true(called_with_screen, "reads visible screen through document positions")
    assert_eq(source, "page", "reports visible-page source")
    assert_true(context:find("patient attention", 1, true) ~= nil,
        "visible-page context includes paragraph")

    local failing_document = {
        getTextFromPositions = function() error("backend unavailable") end,
    }
    context, source = HighlightContext.get(nil, {
        text = "Fallback highlight text",
    }, {
        document = failing_document,
        screen = screen,
    })
    assert_eq(context, "Fallback highlight text", "pcall fallback uses annotation text")
    assert_eq(source, "annotation", "fallback source reported")

    context, source = HighlightContext.get(nil, {
        text = "Selection absent from page",
    }, {
        document = {
            getTextFromPositions = function() return "Unrelated visible words." end,
        },
        screen = screen,
    })
    assert_eq(context, "Selection absent from page",
        "missing selection falls back to annotation text")

    local many = {}
    for i = 1, 30 do many[i] = "word" .. i end
    local bounded = HighlightContext.bound_around(
        table.concat(many, " "), table.concat(many, " "), 10, 200)
    local count = 0
    for _ in bounded:gmatch("%S+") do count = count + 1 end
    assert_eq(count, 10, "fallback context respects word cap")
    assert_true(#bounded <= 200, "fallback context respects character cap")
end
