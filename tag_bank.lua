-- Hierarchical tag bank (folders + tags) for TagBankHighlightSync.

local TagBank = {}

function TagBank.slugify(name)
    if not name or name == "" then
        return "tag"
    end
    local slug = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
    slug = slug:gsub("[^%w%-%_]+", "_"):gsub("_+", "_")
    slug = slug:gsub("^_+", ""):gsub("_+$", "")
    if slug == "" then
        slug = "tag"
    end
    return slug
end

function TagBank.unique_id(bank, base)
    base = TagBank.slugify(base)
    if not TagBank.find_by_id(bank, base) then
        return base
    end
    local n = 2
    while TagBank.find_by_id(bank, base .. "_" .. n) do
        n = n + 1
    end
    return base .. "_" .. n
end

function TagBank.buddhism_sample_node()
    return {
        kind = "folder",
        id = "buddhism",
        name = "Buddhism",
        children = {
            { kind = "tag", id = "aversion", name = "aversion" },
        },
    }
end

function TagBank.manuscript_sample_node()
    return {
        kind = "folder",
        id = "manuscript",
        name = "Manuscript",
        children = {
            { kind = "tag", id = "draft", name = "draft" },
            { kind = "tag", id = "used", name = "used" },
            { kind = "tag", id = "cut", name = "cut" },
        },
    }
end

function TagBank.themes_sample_node()
    return {
        kind = "folder",
        id = "themes",
        name = "Themes",
        children = {},
    }
end

function TagBank.default_bank()
    return {
        TagBank.buddhism_sample_node(),
        {
            kind = "folder",
            id = "general",
            name = "General",
            children = {
                { kind = "tag", id = "love", name = "love" },
                { kind = "tag", id = "grief", name = "grief" },
                { kind = "tag", id = "leadership", name = "leadership" },
                { kind = "tag", id = "quotes", name = "quotes" },
                { kind = "tag", id = "ideas", name = "ideas" },
            },
        },
        TagBank.manuscript_sample_node(),
        TagBank.themes_sample_node(),
    }
end

function TagBank.has_folder_nodes(bank)
    for i = 1, #(bank or {}) do
        if bank[i].kind == "folder" then
            return true
        end
    end
    return false
end

function TagBank.migrate_layout_v2(settings)
    local bank = settings.tag_bank
    if type(bank) ~= "table" then
        return
    end

    if not TagBank.has_folder_nodes(bank) then
        local root_tags = {}
        for i = 1, #bank do
            local node = bank[i]
            if node.kind == "tag" then
                root_tags[#root_tags + 1] = node
            end
        end
        local new_bank = {
            TagBank.buddhism_sample_node(),
            {
                kind = "folder",
                id = "general",
                name = "General",
                children = root_tags,
            },
        }
        for k in pairs(bank) do
            bank[k] = nil
        end
        for i, node in ipairs(new_bank) do
            bank[i] = node
        end
    elseif not TagBank.find_by_id(bank, "buddhism") then
        table.insert(bank, 1, TagBank.buddhism_sample_node())
    end
end

function TagBank.migrate_layout_v3(settings)
    local bank = settings.tag_bank
    if type(bank) ~= "table" then
        return
    end
    if not TagBank.find_by_id(bank, "manuscript") then
        bank[#bank + 1] = TagBank.manuscript_sample_node()
    end
    if not TagBank.find_by_id(bank, "themes") then
        bank[#bank + 1] = TagBank.themes_sample_node()
    end
end

function TagBank.ensure_bank(settings)
    settings = settings or {}
    if type(settings.tag_bank) ~= "table" or #settings.tag_bank == 0 then
        if settings.tag_presets and #settings.tag_presets > 0 then
            settings.tag_bank = TagBank.migrate_from_presets(settings.tag_presets)
        else
            settings.tag_bank = TagBank.default_bank()
        end
    end
    if not settings.tag_bank_migrated then
        TagBank.merge_presets_into_bank(settings)
        settings.tag_bank_migrated = true
    end
    local did_migrate = false
    if (settings.tag_bank_layout_version or 0) < 2 then
        TagBank.migrate_layout_v2(settings)
        settings.tag_bank_layout_version = 2
        did_migrate = true
    end
    if (settings.tag_bank_layout_version or 0) < 3 then
        TagBank.migrate_layout_v3(settings)
        settings.tag_bank_layout_version = 3
        did_migrate = true
    end
    return settings.tag_bank, did_migrate
end

function TagBank.migrate_from_presets(presets)
    local bank = {}
    for _, preset in ipairs(presets or {}) do
        local id = TagBank.unique_id(bank, preset)
        bank[#bank + 1] = { kind = "tag", id = id, name = preset }
    end
    return bank
end

function TagBank.merge_presets_into_bank(settings)
    if type(settings.tag_bank) ~= "table" then
        return
    end
    for _, preset in ipairs(settings.tag_presets or {}) do
        local id = TagBank.slugify(preset)
        if not TagBank.find_by_id(settings.tag_bank, id) then
            settings.tag_bank[#settings.tag_bank + 1] = {
                kind = "tag", id = id, name = preset,
            }
        end
    end
end

local function walk_nodes(nodes, fn, ancestors)
    ancestors = ancestors or {}
    for i, node in ipairs(nodes or {}) do
        local stop = fn(node, nodes, i, ancestors)
        if stop then
            return true
        end
        if node.kind == "folder" and node.children then
            local next_ancestors = {}
            for _, a in ipairs(ancestors) do
                next_ancestors[#next_ancestors + 1] = a
            end
            next_ancestors[#next_ancestors + 1] = node
            if walk_nodes(node.children, fn, next_ancestors) then
                return true
            end
        end
    end
    return false
end

function TagBank.find_by_id(bank, id)
    local found
    walk_nodes(bank, function(node)
        if node.id == id then
            found = node
            return true
        end
    end)
    return found
end

function TagBank.find_parent_list(bank, id)
    local parent_list
    local parent_index
    walk_nodes(bank, function(node, list, index, ancestors)
        if node.id == id then
            if #ancestors == 0 then
                parent_list = bank
            else
                parent_list = ancestors[#ancestors].children
            end
            parent_index = index
            return true
        end
    end)
    return parent_list, parent_index
end

function TagBank.get_node_at_path(bank, path)
    local nodes = bank
    for _, folder_id in ipairs(path or {}) do
        local folder = TagBank.find_by_id(bank, folder_id)
        if not folder or folder.kind ~= "folder" then
            return nil
        end
        folder.children = folder.children or {}
        nodes = folder.children
    end
    return nodes
end

function TagBank.get_ancestor_chain(bank, id)
    local chain
    walk_nodes(bank, function(node, _, _, ancestors)
        if node.id == id then
            chain = {}
            for _, a in ipairs(ancestors) do
                chain[#chain + 1] = a.id
            end
            chain[#chain + 1] = node.id
            return true
        end
    end)
    return chain or {}
end

function TagBank.expand_for_export(leaf_ids, bank)
    bank = bank or {}
    local out = {}
    local seen = {}
    for _, leaf_id in ipairs(leaf_ids or {}) do
        local chain = TagBank.get_ancestor_chain(bank, leaf_id)
        if #chain == 0 then
            chain = { leaf_id }
        end
        for _, id in ipairs(chain) do
            if not seen[id] then
                seen[id] = true
                out[#out + 1] = id
            end
        end
    end
    table.sort(out)
    return out
end

function TagBank.get_display_name(bank, id)
    local node = TagBank.find_by_id(bank, id)
    return (node and node.name) or id
end

--- All tag and folder ids in the bank (for From Highlight exclusion).
function TagBank.collect_ids(bank)
    local ids = {}
    walk_nodes(bank, function(node)
        if node.id then
            ids[node.id] = true
        end
    end)
    return ids
end

--- Title Case for all-lowercase tokens; preserve highlight casing otherwise.
function TagBank.format_display_name(token)
    if not token or token == "" then
        return token
    end
    if token:match("[A-Z]") then
        return token
    end
    return token:sub(1, 1):upper() .. token:sub(2)
end

function TagBank.format_applied_labels(leaf_ids, bank)
    local labels = {}
    for _, id in ipairs(leaf_ids or {}) do
        labels[#labels + 1] = TagBank.get_display_name(bank, id)
    end
    table.sort(labels)
    return table.concat(labels, ", ")
end

function TagBank.count_tags_in_folder(node)
    if not node or node.kind ~= "folder" or not node.children then
        return 0
    end
    local n = 0
    for _, child in ipairs(node.children) do
        if child.kind == "tag" then
            n = n + 1
        end
    end
    return n
end

function TagBank.format_folder_tag_count(node)
    local n = TagBank.count_tags_in_folder(node)
    if n == 0 then
        return ""
    end
    if n == 1 then
        return "1 tag"
    end
    return n .. " tags"
end

function TagBank.add_tag(bank, path, name)
    local list = TagBank.get_node_at_path(bank, path)
    if not list then
        return nil
    end
    local id = TagBank.unique_id(bank, name)
    local node = { kind = "tag", id = id, name = name }
    list[#list + 1] = node
    return node
end

function TagBank.add_folder(bank, path, name)
    local list = TagBank.get_node_at_path(bank, path)
    if not list then
        return nil
    end
    local id = TagBank.unique_id(bank, name)
    local node = { kind = "folder", id = id, name = name, children = {} }
    list[#list + 1] = node
    return node
end

--- Create a folder at path during Tag highlight apply (Add tag → Make folder).
--- Returns the new folder node, or nil when name/path is invalid.
function TagBank.add_folder_for_apply(bank, path, name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        return nil
    end
    return TagBank.add_folder(bank, path, name)
end

function TagBank.delete_node(bank, id)
    local list, index = TagBank.find_parent_list(bank, id)
    if list and index then
        table.remove(list, index)
        return true
    end
    return false
end

function TagBank.rename_node(bank, id, new_name)
    local node = TagBank.find_by_id(bank, id)
    if not node or not new_name or new_name == "" then
        return false
    end
    node.name = new_name
    return true
end

local function contains_folder(node, folder_id)
    if node.id == folder_id then
        return true
    end
    if node.kind == "folder" and node.children then
        for _, child in ipairs(node.children) do
            if contains_folder(child, folder_id) then
                return true
            end
        end
    end
    return false
end

function TagBank.move_node(bank, id, dest_path)
    local node = TagBank.find_by_id(bank, id)
    if not node then
        return false
    end
    if node.kind == "folder" then
        for _, folder_id in ipairs(dest_path or {}) do
            if folder_id == id or contains_folder(node, folder_id) then
                return false
            end
        end
    end
    local src_list, src_index = TagBank.find_parent_list(bank, id)
    local dest_list = TagBank.get_node_at_path(bank, dest_path)
    if not src_list or not src_index or not dest_list then
        return false
    end
    local moving = table.remove(src_list, src_index)
    dest_list[#dest_list + 1] = moving
    return true
end

function TagBank.path_label(bank, path)
    if not path or #path == 0 then
        return "/"
    end
    local parts = {}
    for _, id in ipairs(path) do
        parts[#parts + 1] = TagBank.get_display_name(bank, id)
    end
    return table.concat(parts, " / ")
end

return TagBank
