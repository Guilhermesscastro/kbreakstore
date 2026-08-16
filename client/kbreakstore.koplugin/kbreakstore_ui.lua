--[[
    KindleBreak Store UI Interface (kbreakstore_ui.lua)
    Provides an E-Ink optimized catalog browser, search, and package detail dialogs.
--]]

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local TextViewer = require("ui/widget/textviewer")
local RepoManager = require("kbreakstore_repo")
local Installer = require("kbreakstore_installer")

local StoreUI = {
    current_category = "all",
    search_query = "",
}

function StoreUI:showStoreMenu(caller_menu)
    local menu_items = {}

    -- Header Controls: Refresh & Search & Category Switcher
    table.insert(menu_items, {
        text = _("🔍 Search Packages"),
        help_text = self.search_query ~= "" and (_("Active filter: ") .. self.search_query) or _("Filter packages by name or keyword"),
        callback = function(touch_menu)
            self:showSearchDialog(touch_menu)
        end,
    })

    table.insert(menu_items, {
        text = _("🔄 Refresh Online Catalog"),
        help_text = _("Sync latest releases from GitHub"),
        callback = function(touch_menu)
            UIManager:show(InfoMessage:new{
                text = _("Refreshing catalog from online repository..."),
                timeout = 1,
            })
            RepoManager:fetchManifest(nil, function(success)
                if success then
                    UIManager:show(InfoMessage:new{
                        text = _("Catalog updated successfully!"),
                        timeout = 2,
                    })
                else
                    UIManager:show(InfoMessage:new{
                        text = _("Could not reach repository. Using cached catalog."),
                        timeout = 3,
                    })
                end
                self:showStoreMenu(caller_menu)
            end)
        end,
    })

    table.insert(menu_items, {
        text = _("📂 Filter Category: ") .. self.current_category:upper(),
        callback = function(touch_menu)
            self:showCategoryPicker(touch_menu)
        end,
    })

    table.insert(menu_items, {
        text = "----------------------------------------",
        enabled = false,
    })

    -- Populate package entries
    local packages = RepoManager.packages or {}
    local count = 0

    for pkg_id, pkg in pairs(packages) do
        local matches_category = (self.current_category == "all") or
            (self.current_category == "plugins" and pkg.package_type == "koreader_plugin") or
            (self.current_category == "installed" and RepoManager:getPackageState(pkg_id) ~= "not_installed") or
            (pkg.category == self.current_category)

        local matches_search = true
        if self.search_query ~= "" then
            local q = self.search_query:lower()
            local n = (pkg.name or ""):lower()
            local d = (pkg.description or ""):lower()
            matches_search = (n:find(q, 1, true) ~= nil) or (d:find(q, 1, true) ~= nil) or (pkg_id:lower():find(q, 1, true) ~= nil)
        end

        if matches_category and matches_search then
            count = count + 1
            local state, local_v, remote_v = RepoManager:getPackageState(pkg_id)
            local badge = ""
            if state == "update_available" then
                badge = " [UPDATE AVAILABLE]"
            elseif state == "installed" then
                badge = " [INSTALLED]"
            end

            local v_str = remote_v and string.format("v%d.%d.%d", remote_v[1], remote_v[2], remote_v[3]) or ""
            local display_title = string.format("%s %s%s", pkg.name or pkg_id, v_str, badge)
            local display_subtitle = string.format("by %s • %s", pkg.author or "Community", pkg.description or "")

            table.insert(menu_items, {
                text = display_title,
                help_text = display_subtitle,
                callback = function()
                    self:showPackageDetails(pkg_id, pkg)
                end,
            })
        end
    end

    if count == 0 then
        table.insert(menu_items, {
            text = _("(No packages found matching criteria)"),
            enabled = false,
        })
    end

    local store_menu = Menu:new{
        title = _("KindleBreak Store"),
        item_table = menu_items,
        is_borderless = false,
        show_parent = caller_menu,
    }

    UIManager:show(store_menu)
end

function StoreUI:showCategoryPicker(parent_menu)
    local categories = {
        { id = "all", name = _("All Packages") },
        { id = "plugins", name = _("KOReader Plugins") },
        { id = "readers", name = _("Readers & Document Viewers") },
        { id = "utilities", name = _("Utilities & Tools") },
        { id = "tweaks", name = _("Tweaks & Customization") },
        { id = "installed", name = _("Installed on this Device") },
    }

    local items = {}
    for _, cat in ipairs(categories) do
        table.insert(items, {
            text = cat.name,
            checked = (self.current_category == cat.id),
            callback = function()
                self.current_category = cat.id
                self:showStoreMenu(parent_menu)
            end,
        })
    end

    UIManager:show(Menu:new{
        title = _("Select Category"),
        item_table = items,
    })
end

function StoreUI:showSearchDialog(parent_menu)
    local input_dlg
    input_dlg = InputDialog:new{
        title = _("Search Packages"),
        input = self.search_query,
        buttons = {
            {
                {
                    text = _("Clear"),
                    callback = function()
                        self.search_query = ""
                        UIManager:close(input_dlg)
                        self:showStoreMenu(parent_menu)
                    end,
                },
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dlg)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        self.search_query = input_dlg:getInputText()
                        UIManager:close(input_dlg)
                        self:showStoreMenu(parent_menu)
                    end,
                },
            }
        },
    }
    UIManager:show(input_dlg)
    input_dlg:onShowKeyboard()
end

function StoreUI:showPackageDetails(pkg_id, pkg)
    local state, local_v, remote_v = RepoManager:getPackageState(pkg_id)
    local v_remote_str = remote_v and string.format("%d.%d.%d", remote_v[1], remote_v[2], remote_v[3]) or "N/A"
    local v_local_str = local_v and string.format("%d.%d.%d", local_v[1], local_v[2], local_v[3]) or _("Not Installed")

    local detail_text = string.format(
        "Package: %s (%s)\n" ..
        "Author: %s\n" ..
        "Type: %s\n" ..
        "Latest Version: %s\n" ..
        "Installed Version: %s\n" ..
        "Homepage: %s\n\n" ..
        "Description:\n%s",
        pkg.name or pkg_id, pkg_id,
        pkg.author or "Community",
        pkg.package_type == "koreader_plugin" and "KOReader Plugin" or "System Homebrew",
        v_remote_str,
        v_local_str,
        pkg.homepage or "N/A",
        pkg.description or ""
    )

    local buttons = {}
    local action_row = {}

    if state == "not_installed" then
        table.insert(action_row, {
            text = _("⬇ Install"),
            callback = function()
                Installer:installPackage(pkg_id, pkg, function(success, msg)
                    UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
                end)
            end,
        })
    elseif state == "update_available" then
        table.insert(action_row, {
            text = _("⬆ Update to v") .. v_remote_str,
            callback = function()
                Installer:installPackage(pkg_id, pkg, function(success, msg)
                    UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
                end)
            end,
        })
    else
        table.insert(action_row, {
            text = _("🔄 Reinstall"),
            callback = function()
                Installer:installPackage(pkg_id, pkg, function(success, msg)
                    UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
                end)
            end,
        })
    end

    if state ~= "not_installed" then
        table.insert(action_row, {
            text = _("🗑 Uninstall"),
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("Are you sure you want to uninstall ") .. (pkg.name or pkg_id) .. "?",
                    ok_text = _("Uninstall"),
                    ok_callback = function()
                        Installer:uninstallPackage(pkg_id, pkg, function(success, msg)
                            UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
                        end)
                    end,
                })
            end,
        })
    end

    table.insert(action_row, {
        text = _("Close"),
    })

    table.insert(buttons, action_row)

    local tv = TextViewer:new{
        title = pkg.name or pkg_id,
        text = detail_text,
        buttons = buttons,
    }
    UIManager:show(tv)
end

return StoreUI
