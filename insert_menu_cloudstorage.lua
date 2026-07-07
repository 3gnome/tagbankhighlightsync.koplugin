-- Ensure Cloud storage appears in Tools on dev emulators whose menu_order omits it.
local filemanager_order = require("ui/elements/filemanager_menu_order")
local reader_order = require("ui/elements/reader_menu_order")

local function insert_after_statistics(tools_list, key)
    for _, value in ipairs(tools_list) do
        if value == key then
            return
        end
    end
    local pos = 1
    for index, value in ipairs(tools_list) do
        if value == "statistics" then
            pos = index + 1
            break
        end
    end
    table.insert(tools_list, pos, key)
end

insert_after_statistics(filemanager_order.tools, "cloudstorage")
insert_after_statistics(reader_order.tools, "cloudstorage")
