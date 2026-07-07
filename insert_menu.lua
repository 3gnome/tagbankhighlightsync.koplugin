-- Menu order hooks for Tools (dev emulator + device)
require("insert_menu_cloudstorage")

-- Add Tag Bank Highlight Sync to the Tools menu after statistics
local filemanager_order = require("ui/elements/filemanager_menu_order")

local pos = 1
for index, value in ipairs(filemanager_order.tools) do
    if value == "statistics" then
        pos = index + 1
        break
    end
end
table.insert(filemanager_order.tools, pos, "tag_bank_highlight_sync")

local reader_order = require("ui/elements/reader_menu_order")

pos = 1
for index, value in ipairs(reader_order.tools) do
    if value == "statistics" then
        pos = index + 1
        break
    end
end

table.insert(reader_order.tools, pos, "tag_bank_highlight_sync")
