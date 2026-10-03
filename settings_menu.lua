-- TagBankHighlightSync settings menus (Tools → Tag Bank Highlight Sync → Settings).

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local PathChooser = require("ui/widget/pathchooser")
local FFIUtil = require("ffi/util")
local T = FFIUtil.template
local _ = require("gettext")

local SettingsMenu = {}

local TagMenu = require("tag_menu")
local PluginPeers = require("plugin_peers")

local HELP_SUBTITLE = _("Tap gray rows for help.")

local HELP = {
    about = _([[
Recommended setup:
1. Tools → Tag Bank Highlight Sync → Cloud folder — tap your WebDAV server, then long-press "Long-press here to choose current folder" and tap Choose.
2. Settings → When to sync → Turn on Tag Bank Highlight Sync.
3. Settings → Cloud file name — keep "KOReader sidecar name" on all devices.
4. Sync Highlights (or enable sync when you open a book).

JSON sync files are the source of truth. Advanced options are optional.]]),

    filename = _([[
Every device must use the same cloud file naming choice, or they will write different filenames and not see each other's highlights.

"KOReader sidecar name" matches KOReader's default metadata folder and is recommended for most users.]]),

    layout = _([[
Choose how JSON files are organized inside your cloud folder:
• One folder — all books together (default).
• Folder per book title — separate subfolder per book.
• Folder per date — subfolder by sync date.
• Custom prefix — subfolder named from the prefix setting (default name: highlights).]]),

    json_strip = _([[
These options remove extra fields from sync JSON to make files smaller. They do not change which highlights are synced.

Omit positions, PDF extras, page references, or colors only if you know you do not need them on other devices.]]),

    advanced = _([[
Optional tuning for JSON size, extra export formats (Markdown, plain text, CSV), cloud subfolders, local copies, and backups.

Defaults work for most users. Change these only if you know you need them.]]),

    categories = _([[
Folders organize tags in the highlight picker (e.g. Buddhism → aversion). Inside a folder, the folder name is also a parent tag (#buddhism), like selecting Buddhism in the default bank.

Add tag… opens a name prompt, then Make folder / Add to bank / Apply only. Add folder… creates structure at the current path. Hold a tag or folder to rename, move, or delete.

Folders appear first and tags are alphabetized at every level.

Suggest tags from this book compares the current visible paragraph with highlights you already tagged in this book. Suggested tags are preselected; recent tags remain available below them. Nothing changes until you tap Apply selected. This works locally without AI or a network connection.

Tags sync in JSON and in the quote library Markdown files.]]),

    quote_library = [=[
Two layers on your cloud folder:

1. JSON (*.sdr.json) — syncs highlights and tags across KOReader devices (source of truth).
2. Markdown (library/) — human-readable browsing on PC; regenerated on Sync now.

When quote library is ON, Sync now uploads:
• library/books/{book}.md — literature note per book (all highlights; Apple Notes import)
• library/quotes/{key}.md — one atomic note per tagged highlight (link with [[quotes/…]])
• library/quotes/images/{key}.png — optional highlight screenshots (Capture with screenshot in Tag & sync)
• library/master-quotes.md — cross-book index linking to quotes/
• library/tags/{tag}.md — theme index linking to quotes/
• library/templates/ — Obsidian Writing Dashboard and Manuscript MOC

Writer workflow: tag on device → Sync now → open library/ in Obsidian → link [[quotes/…]] from drafts.

Manuscript folder tags (draft, used, cut) mark quotes for your book-in-progress.

Per-book files include all highlights when enabled below; master, tags, and quotes include tagged quotes only.

First sync after a plugin upgrade re-uploads the library even when highlights are unchanged.

Tags save to the sidecar immediately; Markdown uploads only when you press Sync now.

Capture with screenshot: crops the highlight while you are on that page (tagging optional). PNG uploads on Sync now; embed appears in library/quotes/ notes. Tagged highlights also appear in master and tags indexes. Change font or theme after capture and the image still shows the layout at capture time.

After capture, use Sync now (not just open-book sync) for fastest PNG delivery.

If an embed is broken in Obsidian (image missing): open Tag & sync for that highlight → Capture with screenshot again → Sync now with WiFi on. Confirm the PNG exists at library/quotes/images/ on your WebDAV folder (same vault root as library/). Delete any stale note with wrong paths (e.g. flat .jpg embeds not from this plugin).]=],

    open_sync = _([[
Sync when I open a book waits a few seconds after the book appears so you can turn pages immediately. JSON highlight sync runs first; quote library Markdown is regenerated and uploaded in the background afterward.

Sync when device wakes waits until Wi-Fi is actually connected (or uses KOReader’s “Restore Wi-Fi connection on resume” + onNetworkConnected) so it does not fight the system reconnect or show connection errors.

When you are offline (Wi-Fi off), automatic sync (open, close, wake) queues work as pending sync — no join-Wi-Fi popup. Sync runs when Wi-Fi is on or when you reconnect at home. Manual Sync now (Tag & sync hub or Sync Highlights menu) still offers to turn on Wi-Fi when needed.]]),

    close_sync = _([[
Sync when I close a book writes your local highlights (including deletions) to the sidecar JSON, then uploads that file to WebDAV after you return to the file browser.

When quote library is ON, it also regenerates library Markdown (per-book file, quotes, tag indexes) and uploads changed files to library/ on WebDAV for Obsidian.

It does not merge remote changes or reload the book on close — that keeps closing fast and avoids freezes. The upload stops after the first failure instead of retrying every library file. Full two-way JSON merge still runs when you open the book or press Sync now.

If the cloud copy changed elsewhere, the upload may queue pending sync and merge on the next open. Cloud folder shows pending state and the last completed outcome.]]),
}

local function show_help(text)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = 10,
    })
end

local function help_row(label, body)
    return {
        text = label,
        dim = true,
        keep_menu_open = true,
        callback = function()
            show_help(body)
        end,
    }
end

local function toggle_row(label, checked_fn, on_toggle)
    return {
        text = label,
        checked_func = checked_fn,
        keep_menu_open = true,
        callback = on_toggle,
    }
end

local function radio_row(label, mode, get_mode, set_mode, save_fn)
    return {
        text = label,
        checked_func = function() return get_mode() == mode end,
        keep_menu_open = true,
        callback = function()
            set_mode(mode)
            save_fn()
        end,
    }
end

function SettingsMenu.genSettingsMenu(plugin)
    return {
        help_row(_("About Tag Bank Highlight Sync settings"), HELP.about),
        {
            text = _("When to sync"),
            sub_item_table_func = function()
                return SettingsMenu.genWhenToSyncMenu(plugin)
            end,
        },
        {
            text = _("What to sync"),
            sub_item_table_func = function()
                return SettingsMenu.genWhatToSyncMenu(plugin)
            end,
        },
        {
            text = _("Cloud file name"),
            sub_item_table_func = function()
                return SettingsMenu.genCloudFilenameMenu(plugin)
            end,
        },
        {
            text = _("Categories"),
            sub_item_table_func = function()
                return SettingsMenu.genCategoriesMenu(plugin)
            end,
        },
        {
            text = _("Quote library"),
            sub_item_table_func = function()
                return SettingsMenu.genQuoteLibraryMenu(plugin)
            end,
        },
        {
            text = _("Advanced…"),
            sub_item_table_func = function()
                return SettingsMenu.genAdvancedMenu(plugin)
            end,
        },
        subtitle = HELP_SUBTITLE,
    }
end

function SettingsMenu.genWhenToSyncMenu(plugin)
    local s = plugin.settings
    local toggle = function(key)
        return function()
            plugin:toggleSetting(key)
        end
    end

    return {
        toggle_row(_("Turn on Tag Bank Highlight Sync"), function() return s.is_enabled end, toggle("is_enabled")),
        toggle_row(_("Sync when I open a book"), function() return s.sync_on_open end, toggle("sync_on_open")),
        toggle_row(_("Sync when I close a book"), function() return s.sync_on_close end, toggle("sync_on_close")),
        help_row(_("Close-book sync"), HELP.close_sync),
        toggle_row(_("Sync when device wakes"), function() return s.sync_on_resume end, toggle("sync_on_resume")),
        help_row(_("Open-book sync timing"), HELP.open_sync),
        {
            text = _("Skip this book"),
            enabled_func = function() return plugin:is_doc() end,
            checked_func = function() return plugin:isSyncDisabledForDoc() end,
            keep_menu_open = true,
            callback = function()
                if plugin.ui.doc_settings then
                    local disabled = plugin:isSyncDisabledForDoc()
                    plugin.ui.doc_settings:saveSetting("highlight_sync_disabled", not disabled)
                end
            end,
        },
    }
end

function SettingsMenu.genWhatToSyncMenu(plugin)
    local s = plugin.settings
    local save = function() plugin:saveSettings() end
    local flip = function(key)
        return function()
            s[key] = not s[key]
            save()
        end
    end

    return {
        toggle_row(_("Sync highlighted text"), function() return s.include_highlights end, flip("include_highlights")),
        toggle_row(_("Sync notes on highlights"), function() return s.include_notes end, flip("include_notes")),
        toggle_row(_("Sync page bookmarks"), function() return s.include_page_bookmarks end, flip("include_page_bookmarks")),
    }
end

function SettingsMenu.genCloudFilenameMenu(plugin)
    local s = plugin.settings
    local save = function() plugin:saveSettings() end
    local get_mode = function() return s.filename_mode end
    local set_mode = function(mode) s.filename_mode = mode end

    return {
        help_row(_("Must match on all devices"), HELP.filename),
        radio_row(_("Recommended: KOReader sidecar name"), "sidecar", get_mode, set_mode, save),
        radio_row(_("Use book title"), "title", get_mode, set_mode, save),
        radio_row(_("Use metadata hash"), "hash", get_mode, set_mode, save),
    }
end

function SettingsMenu.genCategoriesMenu(plugin)
    return {
        help_row(_("About category presets"), HELP.categories),
        {
            text = _("Advanced: manage structure…"),
            keep_menu_open = true,
            callback = function()
                TagMenu.show_manage(plugin)
            end,
        },
    }
end

function SettingsMenu.genQuoteLibraryMenu(plugin)
    local s = plugin.settings
    local save = function() plugin:saveSettings() end
    local flip = function(key)
        return function()
            s[key] = not s[key]
            save()
        end
    end
    local anki_peer = PluginPeers.is_ankikoflash_available(plugin.ui)
    local orange_label = anki_peer
        and _("Exclude Anki pending highlights (orange)")
        or _("Exclude orange highlights")
    local green_label = anki_peer
        and _("Exclude Anki sent highlights (green)")
        or _("Exclude green highlights")
    local color_help_label = anki_peer and _("Anki highlight colors") or _("Highlight colors")
    local color_help_body = anki_peer and _([[
Orange = AnkiKoFlash pending queue. Green = sent card kept on device.

These filters affect library Markdown only, not JSON sync.]]) or _([[
These filters affect library Markdown only, not JSON sync.]])

    return {
        help_row(_("About quote library Markdown"), HELP.quote_library),
        toggle_row(_("Turn on quote library (Markdown)"), function()
            return s.tagged_library_enabled
        end, flip("tagged_library_enabled")),
        toggle_row(_("Include untagged highlights in book files"), function()
            return s.library_include_untagged ~= false
        end, flip("library_include_untagged")),
        help_row(_("Untagged in book files only"), _([[
Per-book library/books/*.md can include every highlight (literature notes).

Master and tags/*.md always include tagged quotes only.]])),
        toggle_row(orange_label, function()
            return s.library_exclude_orange_highlights ~= false
        end, flip("library_exclude_orange_highlights")),
        toggle_row(green_label, function()
            return s.library_exclude_green_highlights == true
        end, flip("library_exclude_green_highlights")),
        help_row(color_help_label, color_help_body),
        toggle_row(_("Embed quotes on tag index pages"), function()
            return (s.library_tag_index_style or "embed") == "embed"
        end, function()
            if (s.library_tag_index_style or "embed") == "embed" then
                s.library_tag_index_style = "link"
            else
                s.library_tag_index_style = "embed"
            end
            save()
        end),
        toggle_row(_("Obsidian quote callouts"), function()
            return s.library_use_callouts ~= false
        end, flip("library_use_callouts")),
        toggle_row(_("Preserve verse line breaks"), function()
            return s.library_preserve_verse_layout ~= false
        end, flip("library_preserve_verse_layout")),
        help_row(_("Verse layout"), _([[
Recover poetry line breaks from EPUB highlights: NBSP padding,
automatic flat-verse detection, and hard breaks in Obsidian callouts.

Per highlight: Tag & sync → Quote layout (Auto, Verse, or Prose).]])),
        toggle_row(_("Inline metadata for Dataview"), function()
            return s.library_metadata_style == "both" or s.library_metadata_style == "inline"
        end, function()
            if s.library_metadata_style == "hashtags_only" then
                s.library_metadata_style = "both"
            elseif s.library_metadata_style == "both" then
                s.library_metadata_style = "hashtags_only"
            else
                s.library_metadata_style = "both"
            end
            save()
        end),
        {
            text_func = function()
                return T(_("Master document: %1"), s.master_doc_filename or "master-quotes.md")
            end,
            enabled_func = function() return s.tagged_library_enabled end,
            keep_menu_open = true,
            callback = function()
                local dlg
                dlg = InputDialog:new{
                    title = _("Master document filename"),
                    input = s.master_doc_filename or "master-quotes.md",
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                callback = function() UIManager:close(dlg) end,
                            },
                            {
                                text = _("Save"),
                                is_enter_default = true,
                                callback = function()
                                    local name = dlg:getInputText()
                                    if name and name ~= "" then
                                        s.master_doc_filename = name
                                        save()
                                    end
                                    UIManager:close(dlg)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dlg)
                dlg:onShowKeyboard()
            end,
        },
        {
            text_func = function()
                return T(_("Cloud subfolder: %1"), s.library_subpath or "library")
            end,
            enabled_func = function() return s.tagged_library_enabled end,
            keep_menu_open = true,
            callback = function()
                local dlg
                dlg = InputDialog:new{
                    title = _("Library subfolder"),
                    input = s.library_subpath or "library",
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                callback = function() UIManager:close(dlg) end,
                            },
                            {
                                text = _("Save"),
                                is_enter_default = true,
                                callback = function()
                                    local name = dlg:getInputText()
                                    if name and name ~= "" then
                                        s.library_subpath = name
                                        save()
                                    end
                                    UIManager:close(dlg)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dlg)
                dlg:onShowKeyboard()
            end,
        },
    }
end

function SettingsMenu.genAdvancedMenu(plugin)
    return {
        help_row(_("JSON & exports — optional tuning"), HELP.advanced),
        {
            text = _("JSON & file size"),
            sub_item_table_func = function()
                return SettingsMenu.genJsonMenu(plugin)
            end,
        },
        {
            text = _("Extra export formats"),
            sub_item_table_func = function()
                return SettingsMenu.genExportMenu(plugin)
            end,
        },
        {
            text = _("Cloud folder layout"),
            sub_item_table_func = function()
                return SettingsMenu.genCloudLayoutMenu(plugin)
            end,
        },
        {
            text = _("Local copy on device"),
            sub_item_table_func = function()
                return SettingsMenu.genMirrorMenu(plugin)
            end,
        },
        toggle_row(
            _("Keep backup before merge"),
            function() return plugin.settings.backup_before_sync end,
            function()
                plugin.settings.backup_before_sync = not plugin.settings.backup_before_sync
                plugin:saveSettings()
            end
        ),
    }
end

function SettingsMenu.genJsonMenu(plugin)
    local s = plugin.settings
    local save = function() plugin:saveSettings() end
    local flip = function(key)
        return function()
            s[key] = not s[key]
            save()
        end
    end

    return {
        help_row(_("About omitting JSON fields"), HELP.json_strip),
        toggle_row(_("Readable JSON (larger files)"), function() return s.json_pretty end, flip("json_pretty")),
        toggle_row(_("Wrap with book metadata"), function() return s.json_wrapper end, flip("json_wrapper")),
        toggle_row(_("Omit highlight positions"), function() return s.json_strip_pboxes end, flip("json_strip_pboxes")),
        toggle_row(_("Omit extra PDF fields"), function() return s.json_strip_ext end, flip("json_strip_ext")),
        toggle_row(_("Omit page references"), function() return s.json_strip_pageref end, flip("json_strip_pageref")),
        toggle_row(_("Omit highlight colors"), function() return s.json_strip_color end, flip("json_strip_color")),
    }
end

local function export_format_toggled(formats, fmt)
    for _, f in ipairs(formats or {}) do
        if f == fmt then return true end
    end
    return false
end

local function toggle_export_format(s, fmt, save_fn)
    s.export_formats = s.export_formats or {}
    local found, idx
    for i, f in ipairs(s.export_formats) do
        if f == fmt then found, idx = true, i break end
    end
    if found then
        table.remove(s.export_formats, idx)
    else
        table.insert(s.export_formats, fmt)
    end
    save_fn()
end

function SettingsMenu.genExportMenu(plugin)
    local s = plugin.settings
    local save = function() plugin:saveSettings() end
    local exports_on = function() return s.export_enabled end

    local function fmt_row(label, fmt)
        return {
            text = label,
            enabled_func = exports_on,
            checked_func = function() return export_format_toggled(s.export_formats, fmt) end,
            keep_menu_open = true,
            callback = function()
                toggle_export_format(s, fmt, save)
            end,
        }
    end

    return {
        toggle_row(_("Also save Markdown/TXT/CSV"), function() return s.export_enabled end, function()
            s.export_enabled = not s.export_enabled
            save()
        end),
        fmt_row(_("Markdown"), "markdown"),
        fmt_row(_("Plain text"), "txt"),
        fmt_row(_("CSV"), "csv"),
    }
end

function SettingsMenu.genCloudLayoutMenu(plugin)
    local s = plugin.settings
    local save = function() plugin:saveSettings() end
    local get_layout = function() return s.remote_layout end
    local set_layout = function(layout) s.remote_layout = layout end

    return {
        help_row(_("About cloud folder layout"), HELP.layout),
        radio_row(_("All books in one folder"), "flat", get_layout, set_layout, save),
        radio_row(_("Folder per book title"), "by_title", get_layout, set_layout, save),
        radio_row(_("Folder per date"), "by_date", get_layout, set_layout, save),
        radio_row(_("Custom prefix folder"), "prefix", get_layout, set_layout, save),
    }
end

function SettingsMenu.genMirrorMenu(plugin)
    local s = plugin.settings
    local save = function() plugin:saveSettings() end

    return {
        toggle_row(_("Copy synced files locally"), function() return s.mirror_enabled end, function()
            s.mirror_enabled = not s.mirror_enabled
            save()
        end),
        {
            text_func = function()
                local path = s.mirror_path
                if path == "" then path = _("not set") end
                return T(_("Local folder: %1"), path)
            end,
            enabled_func = function() return s.mirror_enabled end,
            keep_menu_open = true,
            callback = function()
                UIManager:show(PathChooser:new{
                    select_file = false,
                    path = s.mirror_path ~= "" and s.mirror_path or nil,
                    onConfirm = function(path)
                        s.mirror_path = path
                        save()
                    end,
                })
            end,
        },
    }
end

return SettingsMenu
