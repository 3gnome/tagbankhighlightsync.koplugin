local _ = require("gettext")
local Tags = require("tags")
local VerseLayout = require("verse_layout")

local function capture_image_exists(item)
    return require("library_export").capture_image_exists(item)
end

local function format_msg(msg, value)
    value = tostring(value or "")
    if type(msg) == "table" then
        if msg.format then
            local ok, result = pcall(function()
                return msg:format(value)
            end)
            if ok and result and result ~= "" then
                return result
            end
        end
        if msg.fmt then
            return msg.fmt:gsub("%%1", value:gsub("%%", "%%%%"))
        end
    end
    local text = type(msg) == "string" and msg or tostring(msg)
    return text:gsub("%%1", value:gsub("%%", "%%%%"))
end

local Export = {}

local MONTHS = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}
local WEEKDAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

local function escape_csv(value)
    value = tostring(value or "")
    if value:find('[,"\n\r]') then
        return '"' .. value:gsub('"', '""') .. '"'
    end
    return value
end

local function get_page_label(item)
    if item.pageref then
        return tostring(item.pageref)
    end
    if item.pageno then
        return tostring(item.pageno)
    end
    local page = item.page or ""
    if page ~= "" and not page:match("^/body/") then
        return page
    end
    return ""
end

local function get_highlight_text(item)
    return item.text or ""
end

local function get_note_text(item)
    return item.note or ""
end

local function get_raw_datetime(item, metadata)
    metadata = metadata or {}
    return item.datetime_updated or item.datetime or metadata.sync_datetime or ""
end

function Export.format_circadian_datetime(raw)
    raw = tostring(raw or "")
    if raw == "" then
        return ""
    end
    local y, mo, d, h, mi, s = raw:match("^(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d):(%d%d)")
    if not y then
        return raw
    end
    y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
    h, mi = tonumber(h), tonumber(mi)
    local t = os.time({
        year = y, month = mo, day = d,
        hour = h, min = mi, sec = tonumber(s) or 0,
    })
    if not t then
        return raw
    end
    local wday = tonumber(os.date("%w", t)) or 0
    local day_name = WEEKDAYS[wday + 1] or ""
    local hour12 = h % 12
    if hour12 == 0 then
        hour12 = 12
    end
    local ampm = h >= 12 and "pm" or "am"
    return string.format(
        "%s %d %s %d, %d:%02d %s",
        day_name, d, MONTHS[mo] or "", y, hour12, mi, ampm)
end

local function get_datetime_label(item, metadata)
    return Export.format_circadian_datetime(get_raw_datetime(item, metadata))
end

local function yaml_needs_quotes(value)
    if value == "" then
        return true
    end
    if value:find("\n") or value:find("\r") then
        return true
    end
    if value:find('["\\]') then
        return true
    end
    -- YAML special chars in plain scalars (colon breaks "book: Title: Subtitle").
    if value:find("[:#{}%[%],%&%*%?|%<%>%=%!%%@]") then
        return true
    end
    if value:match("^%-") or value:match("^%s") or value:match("%s$") then
        return true
    end
    if value:match("^%-%-%-") then
        return true
    end
    return false
end

function Export.yaml_quote(value)
    value = tostring(value or "")
    if value == "" then
        return '""'
    end
    if yaml_needs_quotes(value) then
        return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
    end
    return value
end

local function yaml_quote(value)
    return Export.yaml_quote(value)
end

local function inline_field(name, value)
    if not value or value == "" then
        return nil
    end
    return name .. ":: " .. value
end

local function scholarly_title_part(metadata)
    local author = metadata.author or ""
    local book = metadata.doc_title or metadata.book_title or metadata.sidecar_name or "book"
    if author ~= "" then
        return author .. " · *" .. book .. "*"
    end
    return "*" .. book .. "*"
end

function Export.build_book_frontmatter(metadata, settings)
    metadata = metadata or {}
    settings = settings or {}
    if settings.library_metadata_style == "hashtags_only" then
        return ""
    end
    local title = metadata.doc_title or metadata.book_title or "book"
    local author = metadata.author or ""
    local sidecar = metadata.sidecar_name or ""
    local synced = Export.format_circadian_datetime(metadata.sync_datetime)
    if synced == "" then
        synced = Export.format_circadian_datetime(os.date("%Y-%m-%d %H:%M:%S"))
    end
    local lines = {
        "---",
        "type: literature",
        "title: " .. yaml_quote(title),
        "source: koreader",
    }
    if author ~= "" then
        lines[#lines + 1] = "author: " .. yaml_quote(author)
    end
    if sidecar ~= "" then
        lines[#lines + 1] = "sidecar: " .. yaml_quote(sidecar)
    end
    if metadata.series and metadata.series ~= "" then
        lines[#lines + 1] = "series: " .. yaml_quote(metadata.series)
    end
    lines[#lines + 1] = "synced: " .. yaml_quote(synced)
    lines[#lines + 1] = "tags: [reading, quotes]"
    lines[#lines + 1] = "---"
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end

function Export.format_quote_heading_legacy(item, metadata)
    metadata = metadata or {}
    local sidecar = metadata.sidecar_name or metadata.book_title or "book"
    local page = get_page_label(item)
    local when = get_raw_datetime(item, metadata)
    local heading_page = page ~= "" and page or "?"
    return string.format("### %s · p.%s · %s", sidecar, heading_page, when)
end

function Export.format_quote_heading(item, metadata)
    metadata = metadata or {}
    local page = get_page_label(item)
    local heading_page = page ~= "" and page or "?"
    local when_display = get_datetime_label(item, metadata)
    local title_part = scholarly_title_part(metadata)
    if when_display ~= "" then
        return string.format("### %s · p. %s · %s", title_part, heading_page, when_display)
    end
    return string.format("### %s · p. %s", title_part, heading_page)
end

function Export.has_verse_nbsp(text)
    return VerseLayout.has_verse_nbsp(text)
end

function Export.looks_like_flat_verse(text)
    return VerseLayout.looks_like_verse_layout(text)
end

function Export.looks_like_verse_layout(text)
    return VerseLayout.looks_like_verse_layout(text)
end

function Export.normalize_verse_text(text)
    return VerseLayout.normalize(text)
end

local function prepare_quote_text(text, settings, item)
    settings = settings or {}
    text = text or ""
    if not VerseLayout.should_normalize(text, settings, item) then
        return text
    end
    return VerseLayout.normalize(text)
end

local function split_lines(text)
    local lines = {}
    local pos = 1
    while pos <= #text do
        local nl = text:find("\n", pos, true)
        if nl then
            lines[#lines + 1] = text:sub(pos, nl - 1)
            pos = nl + 1
        else
            lines[#lines + 1] = text:sub(pos)
            break
        end
    end
    return lines
end

local function format_blockquote_lines(text, quote_prefix)
    quote_prefix = quote_prefix or "> "
    text = text or ""
    if text == "" then
        return ""
    end
    if not text:find("\n") then
        return quote_prefix .. text
    end
    local lines = split_lines(text)
    local out = {}
    for i, line in ipairs(lines) do
        if line == "" then
            out[#out + 1] = quote_prefix
        elseif i < #lines then
            out[#out + 1] = quote_prefix .. line .. "\\"
        else
            out[#out + 1] = quote_prefix .. line
        end
    end
    return table.concat(out, "\n")
end

function Export.format_quote_block(item, metadata, settings)
    metadata = metadata or {}
    settings = settings or {}
    local meta_style = settings.library_metadata_style or "both"
    local use_callouts = settings.library_use_callouts ~= false
    local page = get_page_label(item)
    local tag_bank = metadata.tag_bank
    local leaf = Tags.get_tags(item)
    local tag_line = Tags.format_hashtag_line_for_export(leaf, tag_bank)
    local book = metadata.doc_title or metadata.book_title or metadata.sidecar_name or "book"
    local author = metadata.author or ""
    local chapter = item.chapter or ""
    local expanded = Tags.expand_for_export(leaf, tag_bank)
    local raw_when = get_raw_datetime(item, metadata)
    local when_display = get_datetime_label(item, metadata)

    local lines = {}
    local heading_page = page ~= "" and page or "?"
    lines[#lines + 1] = Export.format_quote_heading(item, metadata)

    if meta_style == "inline" or meta_style == "both" then
        local book_link = inline_field("book", "[[" .. book .. "]]")
        if book_link then
            lines[#lines + 1] = book_link
        end
        if author ~= "" then
            lines[#lines + 1] = inline_field("author", author)
        end
        if chapter ~= "" then
            lines[#lines + 1] = inline_field("chapter", yaml_quote(chapter))
        end
        if page ~= "" then
            lines[#lines + 1] = inline_field("page", page)
        end
        if when_display ~= "" then
            lines[#lines + 1] = inline_field("captured", when_display)
        end
        if raw_when ~= "" then
            lines[#lines + 1] = inline_field("captured_at", raw_when)
        end
        if #expanded > 0 then
            lines[#lines + 1] = "tags:: [" .. table.concat(expanded, ", ") .. "]"
        end
        lines[#lines + 1] = ""
    end

    if (meta_style == "hashtags_only" or meta_style == "both") and tag_line ~= "" then
        lines[#lines + 1] = tag_line
        lines[#lines + 1] = ""
    end

    local text = prepare_quote_text(item.text or "", settings, item)
    if text ~= "" then
        if use_callouts then
            local callout_title = "p. " .. heading_page
            if chapter ~= "" then
                callout_title = callout_title .. " · " .. chapter
            end
            lines[#lines + 1] = "> [!quote] " .. callout_title
            lines[#lines + 1] = format_blockquote_lines(text)
        else
            lines[#lines + 1] = format_blockquote_lines(text)
        end
    end

    if settings.library_embed_screenshot
        and settings.library_include_screenshots ~= false
        and capture_image_exists(item) then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "![[" .. item[Tags.CAPTURE_FIELD] .. "]]"
    end

    local note = item.note or ""
    if note ~= "" then
        lines[#lines + 1] = ""
        if use_callouts then
            lines[#lines + 1] = "> [!note] Commentary"
            lines[#lines + 1] = "> " .. note:gsub("\n", "\n> ")
        else
            lines[#lines + 1] = format_msg(_("Note: %1"), note)
        end
    end

    return table.concat(lines, "\n")
end

function Export.to_markdown(annotations, metadata, settings)
    settings = settings or {}
    metadata = metadata or {}
    local lines = {}
    local frontmatter = Export.build_book_frontmatter(metadata, settings)
    if frontmatter ~= "" then
        lines[#lines + 1] = frontmatter
    end
    local title = metadata.doc_title or metadata.book_title
    if title and title ~= "" and frontmatter == "" then
        lines[#lines + 1] = "# " .. title
        lines[#lines + 1] = ""
    end
    if metadata.sync_datetime then
        local synced = Export.format_circadian_datetime(metadata.sync_datetime)
        lines[#lines + 1] = format_msg(_("Last sync: %1"), synced)
        lines[#lines + 1] = ""
    end
    for i, item in ipairs(annotations or {}) do
        local chapter = item.chapter
        if chapter and chapter ~= "" then
            lines[#lines + 1] = "## " .. chapter
            lines[#lines + 1] = ""
        end
        local page = get_page_label(item)
        local when = get_datetime_label(item, metadata)
        if page ~= "" or when ~= "" then
            lines[#lines + 1] = string.format("*p. %s* · %s", page ~= "" and page or "?", when)
            lines[#lines + 1] = ""
        end
        local text = prepare_quote_text(get_highlight_text(item), settings, item)
        if text ~= "" then
            if settings.library_use_callouts ~= false then
                lines[#lines + 1] = "> [!quote]"
                lines[#lines + 1] = format_blockquote_lines(text)
            else
                lines[#lines + 1] = format_blockquote_lines(text)
            end
        end
        if settings.library_include_screenshots ~= false
            and capture_image_exists(item) then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "![[" .. item[Tags.CAPTURE_FIELD] .. "]]"
        end
        local note = get_note_text(item)
        if note ~= "" then
            lines[#lines + 1] = ""
            if settings.library_use_callouts ~= false then
                lines[#lines + 1] = "> [!note] Commentary"
                lines[#lines + 1] = "> " .. note:gsub("\n", "\n> ")
            else
                lines[#lines + 1] = format_msg(_("Note: %1"), note)
            end
        end
        lines[#lines + 1] = ""
    end
    return table.concat(lines, "\n")
end

function Export.to_txt(annotations, metadata)
    metadata = metadata or {}
    local lines = {}
    local title = metadata.book_title
    if title and title ~= "" then
        lines[#lines + 1] = title
        lines[#lines + 1] = string.rep("-", #title)
        lines[#lines + 1] = ""
    end
    for i, item in ipairs(annotations or {}) do
        if item.chapter and item.chapter ~= "" then
            lines[#lines + 1] = item.chapter
        end
        lines[#lines + 1] = string.format(
            "p. %s — %s",
            get_page_label(item),
            get_datetime_label(item, metadata))
        local text = get_highlight_text(item)
        if text ~= "" then
            lines[#lines + 1] = text
        end
        local note = get_note_text(item)
        if note ~= "" then
            lines[#lines + 1] = format_msg(_("Note: %1"), note)
        end
        lines[#lines + 1] = ""
    end
    return table.concat(lines, "\n")
end

function Export.to_csv(annotations)
    local lines = { "page,chapter,text,note,datetime" }
    for i, item in ipairs(annotations or {}) do
        lines[#lines + 1] = table.concat({
            escape_csv(get_page_label(item)),
            escape_csv(item.chapter or ""),
            escape_csv(get_highlight_text(item)),
            escape_csv(get_note_text(item)),
            escape_csv(item.datetime_updated or item.datetime or ""),
        }, ",")
    end
    return table.concat(lines, "\n")
end

function Export.generate(annotations, format, metadata, settings)
    if format == "markdown" or format == "md" then
        return Export.to_markdown(annotations, metadata, settings), "md"
    elseif format == "txt" then
        return Export.to_txt(annotations, metadata), "txt"
    elseif format == "csv" then
        return Export.to_csv(annotations), "csv"
    end
    return nil, nil
end

function Export.write_exports(base_path, annotations, settings, metadata)
    if not settings.export_enabled then
        return
    end
    local formats = settings.export_formats or { "markdown" }
    for i, fmt in ipairs(formats) do
        local content, ext = Export.generate(annotations, fmt, metadata, settings)
        if content and ext then
            local path = base_path .. "." .. ext
            local file = io.open(path, "w")
            if file then
                file:write(content)
                file:close()
            end
        end
    end
end

return Export
