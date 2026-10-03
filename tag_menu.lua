-- Tag bank navigation menus (apply tags + manage bank).

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local FFIUtil = require("ffi/util")
local T = FFIUtil.template
local _ = require("gettext")
local TagBank = require("tag_bank")
local Tags = require("tags")
local Merge = require("merge")
local FromHighlight = require("from_highlight")

local TagMenu = {}

TagMenu.FOLDER_PICKER_BROWSE = "browse"
TagMenu.FOLDER_PICKER_MOVE = "move"

--- Normalize a folder path for bank operations (tests / helpers).
function TagMenu.custom_tag_dest_path(path)
    return path or {}
end

--- At bank root, Add to bank needs a folder picker; inside a folder, use current path.
function TagMenu.should_pick_add_tag_folder(path)
    return not path or #path == 0
end

--- Inside a folder, Add tag skips Make folder / Add to bank / Apply only and saves directly.
function TagMenu.skip_add_tag_actions(path)
    return path and #path > 0
end

--- Folder picker mode for Add tag → Add to bank at root (tap folder = destination).
function TagMenu.add_tag_dest_picker_mode()
    return TagMenu.FOLDER_PICKER_MOVE
end

function TagMenu.folder_picker_mode(opts)
    if opts and opts.mode == TagMenu.FOLDER_PICKER_MOVE then
        return TagMenu.FOLDER_PICKER_MOVE
    end
    return TagMenu.FOLDER_PICKER_BROWSE
end

local CHECKMARK = "✓"
local FROM_HIGHLIGHT_SENTINEL = "__from_highlight__"

local FROM_HIGHLIGHT_HELP = _([[
Words come from this highlight only (5+ letters). Common words and words
already in your tag bank are omitted. Proper names keep their capitalization.

Hyphenated words stay hyphenated. Hyphens from line breaks are removed.

Tap to tag. Hold to add to the bank.

English-oriented; some accented letters may be skipped.
]])

local function set_menu_subtitle(menu, subtitle)
    if not menu then
        return
    end
    menu.subtitle = subtitle
    if menu.title_bar then
        menu.title_bar:setSubTitle(subtitle, true)
    end
end

local function attach_menu_hold(menu)
    function menu:onMenuHold(item)
        if item.hold_callback then
            item.hold_callback(self, item)
        end
        return true
    end
end

local function applied_subtitle(applied_ids, bank)
    local label = TagBank.format_applied_labels(applied_ids, bank)
    if label == "" then
        return _("Applied: (none)")
    end
    return T(_("Applied: %1"), label)
end

function TagMenu.persist_applied_tags(hl, ann, applied_ids, bank)
    Tags.stash_expanded_tags_for_library(ann, bank)
    Tags.set_tags(ann, applied_ids)
    ann.datetime_updated = os.date("%Y-%m-%d %H:%M:%S")
    if hl and hl.ui and hl.ui.annotation then
        hl.ui.annotation.annotations =
            Merge.dedupe_annotations(hl.ui.annotation.annotations, function(item)
                return item and item.text and item.pos0 ~= nil and item.pos1 ~= nil
            end)
    end
    if hl and hl.ui and hl.ui.doc_settings then
        hl.ui.doc_settings:saveSetting("annotations", hl.ui.annotation.annotations)
    end
    if hl and hl.ui and hl.ui.annotation then
        hl.ui.annotation:updateAnnotations(true, true)
    end
end

local function collect_applied_ids(selected_map)
    local out = {}
    for id, on in pairs(selected_map) do
        if on then
            out[#out + 1] = id
        end
    end
    return Tags.normalize_list(out)
end

local function init_selected_from_ann(ann)
    local selected = {}
    for idx, id in ipairs(Tags.get_tags(ann)) do
        selected[id] = true
    end
    return selected
end

local function add_back_row(items, path, on_back_in, on_back_root)
    items[#items + 1] = {
        text = "← " .. _("Back"),
        keep_menu_open = true,
        callback = function()
            if #path > 0 then
                on_back_in()
            else
                on_back_root()
            end
        end,
    }
end

local function from_highlight_help_row()
    return {
        text = _("About From Highlight"),
        dim = true,
        keep_menu_open = true,
        callback = function()
            UIManager:show(InfoMessage:new{
                text = FROM_HIGHLIGHT_HELP,
                timeout = 10,
            })
        end,
    }
end

local function prompt_new_tag(plugin, bank, path, save, on_done)
    local dlg
    dlg = InputDialog:new{
        title = _("New tag"),
        input_hint = _("aversion"),
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Add"), is_enter_default = true, callback = function()
                local name = dlg:getInputText()
                UIManager:close(dlg)
                if name and not name:match("^%s*$") then
                    TagBank.add_tag(bank, path, name)
                    save()
                    if on_done then on_done() end
                end
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

local function prompt_new_folder(plugin, bank, path, save, on_done)
    local dlg
    dlg = InputDialog:new{
        title = _("New folder"),
        input_hint = _("Buddhism"),
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Add"), is_enter_default = true, callback = function()
                local name = dlg:getInputText()
                UIManager:close(dlg)
                if name and not name:match("^%s*$") then
                    TagBank.add_folder(bank, path, name)
                    save()
                    if on_done then on_done() end
                end
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

local function show_add_menu(plugin, bank, path, save, on_done)
    local dlg
    dlg = ButtonDialog:new{
        title = _("Add"),
        buttons = {
            {
                {
                    text = _("Add tag…"),
                    callback = function()
                        UIManager:close(dlg)
                        prompt_new_tag(plugin, bank, path, save, on_done)
                    end,
                },
                {
                    text = _("Add subfolder…"),
                    callback = function()
                        UIManager:close(dlg)
                        prompt_new_folder(plugin, bank, path, save, on_done)
                    end,
                },
            },
        },
    }
    UIManager:show(dlg)
end

local function show_node_edit_dialog(plugin, bank, node, save, on_done)
    if not node then
        return
    end
    local node_id = node.id
    local is_folder = node.kind == "folder"
    local dlg
    dlg = ButtonDialog:new{
        title = node.name,
        buttons = {
            {
                {
                    text = _("Rename…"),
                    callback = function()
                        UIManager:close(dlg)
                        local rename_dlg
                        rename_dlg = InputDialog:new{
                            title = is_folder and _("Rename folder") or _("Rename tag"),
                            input = node.name,
                            buttons = {{
                                { text = _("Cancel"), callback = function() UIManager:close(rename_dlg) end },
                                { text = _("Save"), is_enter_default = true, callback = function()
                                    TagBank.rename_node(bank, node_id, rename_dlg:getInputText())
                                    save()
                                    UIManager:close(rename_dlg)
                                    if on_done then on_done() end
                                end },
                            }},
                        }
                        UIManager:show(rename_dlg)
                        rename_dlg:onShowKeyboard()
                    end,
                },
                {
                    text = _("Move to…"),
                    callback = function()
                        UIManager:close(dlg)
                        TagMenu.show_folder_picker(plugin, _("Move to"), function(dest)
                            if TagBank.move_node(bank, node_id, dest) then
                                save()
                                if on_done then on_done() end
                            elseif is_folder then
                                UIManager:show(InfoMessage:new{
                                    text = _("Could not move folder."),
                                    timeout = 2,
                                })
                            end
                        end, { mode = TagMenu.FOLDER_PICKER_MOVE })
                    end,
                },
            },
            {
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:close(dlg)
                        UIManager:show(ConfirmBox:new{
                            text = is_folder
                                and _("Delete this folder and everything inside it?")
                                or _("Delete this tag from the bank?"),
                            ok_text = _("Delete"),
                            ok_callback = function()
                                TagBank.delete_node(bank, node_id)
                                save()
                                if on_done then on_done() end
                            end,
                        })
                    end,
                },
            },
        },
    }
    UIManager:show(dlg)
end

function TagMenu.show_folder_picker(plugin, title, on_pick, opts)
    opts = opts or {}
    local mode = TagMenu.folder_picker_mode(opts)
    local bank = TagBank.ensure_bank(plugin.settings)
    local path = {}
    local menu

    local function rebuild()
        UIManager:close(menu)
        local items = {}

        if #path > 0 then
            items[#items + 1] = {
                text = "← " .. _("Back"),
                keep_menu_open = true,
                callback = function()
                    table.remove(path)
                    rebuild()
                end,
            }
        end

        if mode == TagMenu.FOLDER_PICKER_BROWSE then
            if #path == 0 then
                items[#items + 1] = {
                    text = _("Choose here (root)"),
                    keep_menu_open = true,
                    callback = function()
                        UIManager:close(menu)
                        on_pick({})
                    end,
                }
            else
                items[#items + 1] = {
                    text = _("Choose this folder"),
                    keep_menu_open = true,
                    callback = function()
                        UIManager:close(menu)
                        on_pick(path)
                    end,
                }
            end
        elseif #path == 0 then
            items[#items + 1] = {
                text = _("Choose here (root)"),
                keep_menu_open = true,
                callback = function()
                    UIManager:close(menu)
                    on_pick({})
                end,
            }
        end

        local children = TagBank.get_node_at_path(bank, path) or {}
        for idx, node in ipairs(children) do
            if node.kind == "folder" then
                local folder_id = node.id
                local dest_path = {}
                for _, id in ipairs(path) do
                    dest_path[#dest_path + 1] = id
                end
                dest_path[#dest_path + 1] = folder_id
                if mode == TagMenu.FOLDER_PICKER_MOVE then
                    items[#items + 1] = {
                        text = node.name,
                        keep_menu_open = true,
                        callback = function()
                            UIManager:close(menu)
                            on_pick(dest_path)
                        end,
                        hold_callback = function()
                            path[#path + 1] = folder_id
                            rebuild()
                        end,
                    }
                else
                    items[#items + 1] = {
                        text = "▶ " .. node.name,
                        keep_menu_open = true,
                        callback = function()
                            path[#path + 1] = folder_id
                            rebuild()
                        end,
                    }
                end
            end
        end

        menu = Menu:new{
            title = title,
            subtitle = TagBank.path_label(bank, path),
            item_table = items,
        }
        if mode == TagMenu.FOLDER_PICKER_MOVE then
            attach_menu_hold(menu)
        end
        UIManager:show(menu)
    end

    rebuild()
end

function TagMenu.show_apply(plugin, hl, resolved_index, ann, opts)
    opts = opts or {}
    local bank = TagBank.ensure_bank(plugin.settings)
    local selected = init_selected_from_ann(ann)
    local path = {}
    local menu

    local function save_now()
        TagMenu.persist_applied_tags(hl, ann, collect_applied_ids(selected), bank)
    end

    local function applied_label()
        return applied_subtitle(collect_applied_ids(selected), bank)
    end

    local function refresh()
        if menu then
            set_menu_subtitle(menu, applied_label())
            menu:updateItems()
        end
    end

    local function toggle_tag(tag_id)
        selected[tag_id] = not selected[tag_id]
        save_now()
        refresh()
    end

    local function go_back_root()
        UIManager:close(menu)
        if opts.on_back then
            opts.on_back()
        end
    end

    local build_items

    local function rebuild_apply_menu()
        if not menu then
            return
        end
        menu.item_table = build_items()
        set_menu_subtitle(menu, applied_label())
        menu:updateItems()
    end

    local function save_bank()
        plugin:saveSettings()
    end

    local function go_back_in()
        table.remove(path)
        rebuild_apply_menu()
    end

    local function add_new_tag(name, add_to_bank)
        name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then
            return
        end
        local function apply_id(tag_id)
            selected[tag_id] = true
            save_now()
            refresh()
        end
        if add_to_bank then
            local function finish_add_to_bank(dest_path, reset_to_root)
                local node = TagBank.add_tag(bank, dest_path, name)
                if node then
                    save_bank()
                    apply_id(node.id)
                    if reset_to_root then
                        while #path > 0 do
                            table.remove(path)
                        end
                    end
                    rebuild_apply_menu()
                else
                    UIManager:show(InfoMessage:new{
                        text = _("Could not add tag to the bank."),
                        timeout = 2,
                    })
                end
            end
            if TagMenu.should_pick_add_tag_folder(path) then
                TagMenu.show_folder_picker(plugin, _("Add tag to"), function(dest_path)
                    finish_add_to_bank(dest_path, true)
                end, { mode = TagMenu.add_tag_dest_picker_mode() })
            else
                finish_add_to_bank(TagMenu.custom_tag_dest_path(path), false)
            end
        else
            local id = TagBank.unique_id(bank, name)
            apply_id(id)
        end
    end

    local function make_custom_folder(name)
        local folder = TagBank.add_folder_for_apply(bank, path, name)
        if not folder then
            UIManager:show(InfoMessage:new{
                text = _("Could not create folder."),
                timeout = 2,
            })
            return
        end
        plugin:saveSettings()
        selected[folder.id] = true
        save_now()
        path[#path + 1] = folder.id
        rebuild_apply_menu()
        UIManager:show(InfoMessage:new{
            text = _("Folder created; parent tag applied."),
            timeout = 2,
        })
    end

    local function show_new_tag_actions(name)
        name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then
            return
        end
        local choice
        choice = ButtonDialog:new{
            title = _("Add this tag to the bank for reuse?")
                .. "\n\n"
                .. _("Make folder creates a category here. The folder name is also a parent tag (#folder-id), like Buddhism."),
            buttons = {
                {
                    {
                        text = _("Make folder"),
                        callback = function()
                            UIManager:close(choice)
                            make_custom_folder(name)
                        end,
                    },
                },
                {
                    {
                        text = _("Add to bank"),
                        callback = function()
                            UIManager:close(choice)
                            add_new_tag(name, true)
                        end,
                    },
                    {
                        text = _("Apply only"),
                        callback = function()
                            UIManager:close(choice)
                            add_new_tag(name, false)
                        end,
                    },
                },
            },
        }
        UIManager:show(choice)
    end

    local function prompt_add_tag()
        local dlg
        local subtitle = #path > 0 and TagBank.path_label(bank, path) or nil
        dlg = InputDialog:new{
            title = _("Add tag"),
            input_hint = _("aversion"),
            description = subtitle,
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        callback = function() UIManager:close(dlg) end,
                    },
                    {
                        text = _("Add"),
                        is_enter_default = true,
                        callback = function()
                            local name = dlg:getInputText()
                            UIManager:close(dlg)
                            if TagMenu.skip_add_tag_actions(path) then
                                add_new_tag(name, true)
                            else
                                show_new_tag_actions(name)
                            end
                        end,
                    },
                },
            },
        }
        UIManager:show(dlg)
        dlg:onShowKeyboard()
    end

    build_items = function()
        local items = {}

        add_back_row(items, path, go_back_in, go_back_root)

        if path[1] == FROM_HIGHLIGHT_SENTINEL then
            items[#items + 1] = from_highlight_help_row()
            local words = FromHighlight.extract_words(ann.text, bank)
            if #words == 0 then
                items[#items + 1] = {
                    text = _("No new words in this highlight."),
                    dim = true,
                    enabled = false,
                    keep_menu_open = true,
                }
            else
                for _, word in ipairs(words) do
                    local tag_id = word.id
                    local display = word.display
                    items[#items + 1] = {
                        text = display,
                        mandatory_func = function()
                            return selected[tag_id] and CHECKMARK or ""
                        end,
                        keep_menu_open = true,
                        callback = function()
                            toggle_tag(tag_id)
                        end,
                        hold_callback = function()
                            show_new_tag_actions(display)
                        end,
                    }
                end
            end
            return items
        end

        local children = TagBank.get_node_at_path(bank, path) or {}
        for idx, node in ipairs(children) do
            if node.kind == "folder" then
                local folder_id = node.id
                items[#items + 1] = {
                    text = "▶ " .. node.name,
                    mandatory_func = function()
                        return TagBank.format_folder_tag_count(node)
                    end,
                    keep_menu_open = true,
                    callback = function()
                        path[#path + 1] = folder_id
                        selected[folder_id] = true
                        save_now()
                        rebuild_apply_menu()
                    end,
                    hold_callback = function()
                        show_node_edit_dialog(plugin, bank, node, save_bank, rebuild_apply_menu)
                    end,
                }
            elseif node.kind == "tag" then
                local tag_id = node.id
                items[#items + 1] = {
                    text = node.name,
                    mandatory_func = function()
                        return selected[tag_id] and CHECKMARK or ""
                    end,
                    keep_menu_open = true,
                    callback = function()
                        toggle_tag(tag_id)
                    end,
                    hold_callback = function()
                        show_node_edit_dialog(plugin, bank, node, save_bank, rebuild_apply_menu)
                    end,
                }
            end
        end

        if #path > 0 then
            local folder_id = path[#path]
            local folder_node = TagBank.find_by_id(bank, folder_id)
            if folder_node then
                items[#items + 1] = {
                    text = folder_node.name,
                    mandatory_func = function()
                        return selected[folder_id] and CHECKMARK or ""
                    end,
                    keep_menu_open = true,
                    callback = function()
                        toggle_tag(folder_id)
                    end,
                }
            end
        end

        items[#items + 1] = {
            text = _("Add folder…"),
            keep_menu_open = true,
            callback = function()
                prompt_new_folder(plugin, bank, path, save_bank, rebuild_apply_menu)
            end,
        }
        items[#items + 1] = {
            text = _("Add tag…"),
            keep_menu_open = true,
            callback = prompt_add_tag,
        }

        items[#items + 1] = {
            text = _("Hold a tag or folder to rename, move, or delete."),
            dim = true,
            enabled = false,
            keep_menu_open = true,
        }

        if #path == 0 then
            local words = FromHighlight.extract_words(ann.text, bank)
            items[#items + 1] = {
                text = T(_("▶ From Highlight (%1)"), #words),
                keep_menu_open = true,
                callback = function()
                    path[#path + 1] = FROM_HIGHLIGHT_SENTINEL
                    rebuild_apply_menu()
                end,
            }
        end

        return items
    end

    menu = Menu:new{
        title = _("Tag highlight"),
        subtitle = applied_label(),
        item_table = build_items(),
    }
    attach_menu_hold(menu)
    UIManager:show(menu)
end

function TagMenu.show_manage(plugin, opts)
    opts = opts or {}
    local bank = TagBank.ensure_bank(plugin.settings)
    local save = function() plugin:saveSettings() end
    local path = {}
    local menu

    local function go_back_root()
        UIManager:close(menu)
        if opts.on_back then
            opts.on_back()
        end
    end

    local function rebuild()
        UIManager:close(menu)
        local items = {}

        add_back_row(items, path, function()
            table.remove(path)
            rebuild()
        end, go_back_root)

        items[#items + 1] = {
            text = _("Add…"),
            keep_menu_open = true,
            callback = function()
                show_add_menu(plugin, bank, path, save, rebuild)
            end,
        }

        if #path > 0 then
            local folder_node = TagBank.find_by_id(bank, path[#path])
            if folder_node then
                items[#items + 1] = {
                    text = _("Edit category…"),
                    keep_menu_open = true,
                    callback = function()
                        show_node_edit_dialog(plugin, bank, folder_node, save, rebuild)
                    end,
                }
            end
        end

        local children = TagBank.get_node_at_path(bank, path) or {}
        for idx, node in ipairs(children) do
            if node.kind == "folder" then
                local folder_id = node.id
                items[#items + 1] = {
                    text = "▶ " .. node.name,
                    mandatory_func = function()
                        return TagBank.format_folder_tag_count(node)
                    end,
                    keep_menu_open = true,
                    callback = function()
                        path[#path + 1] = folder_id
                        rebuild()
                    end,
                    hold_callback = function()
                        show_node_edit_dialog(plugin, bank, node, save, rebuild)
                    end,
                }
            else
                local tag_id = node.id
                items[#items + 1] = {
                    text = node.name,
                    keep_menu_open = true,
                    callback = function()
                        show_node_edit_dialog(plugin, bank, node, save, rebuild)
                    end,
                }
            end
        end

        items[#items + 1] = {
            text = _("Hold a folder for options. Tap a tag to edit."),
            dim = true,
            enabled = false,
            keep_menu_open = true,
        }

        menu = Menu:new{
            title = _("Manage tag bank"),
            subtitle = TagBank.path_label(bank, path),
            item_table = items,
        }
        attach_menu_hold(menu)
        UIManager:show(menu)
    end

    rebuild()
end

return TagMenu
