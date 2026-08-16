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
    active_menu = nil,
}

function StoreUI:showStoreMenu()
    if not RepoManager.packages or next(RepoManager.packages) == nil then
        RepoManager:init()
    end

    -- Close any existing open store menu to prevent stacked dialogs
    if self.active_menu then
        UIManager:close(self.active_menu)
        self.active_menu = nil
    end

    local menu_items = {}

    -- Header Controls: Search & Sync & Category Switcher
    table.insert(menu_items, {
        text = _("🔍 Search Packages"),
        help_text = self.search_query ~= "" and (_("Active filter: ") .. self.search_query) or _("Filter packages by name or keyword"),
        callback = function()
            self:showSearchDialog()
        end,
    })

    table.insert(menu_items, {
        text = _("🔄 Sync Online Catalog"),
        help_text = _("Fetch latest packages from GitHub repository"),
        callback = function()
            UIManager:show(InfoMessage:new{
                text = _("Connecting to GitHub repository..."),
                timeout = 1,
            })
            RepoManager:fetchManifest(nil, function(success, pkgs)
                local count = RepoManager:getPackageCount()
                if success then
                    UIManager:show(InfoMessage:new{
                        text = string.format(_("Catalog updated! %d packages available."), count),
                        timeout = 2,
                    })
                else
                    UIManager:show(InfoMessage:new{
                        text = string.format(_("Could not reach remote repo. %d cached packages available."), count),
                        timeout = 3,
                    })
                end
                self:showStoreMenu()
            end)
        end,
    })

    local cat_names = {
        all = _("ALL (140+)"),
        plugins = _("All KOReader Plugins"),
        ai = _("🤖 AI Assistants & Tools"),
        dict = _("📖 Translation & Dictionaries"),
        sync = _("☁️ Sync & Highlights"),
        library = _("📚 Library & Catalog"),
        readers = _("👓 Readers & Manga"),
        games = _("🎮 Games & Puzzles"),
        utilities = _("🛠 Utilities & Hardware"),
        tweaks = _("⚡ Tweaks & Hacks"),
        installed = _("✅ Installed on Device"),
    }
    local cat_label = cat_names[self.current_category] or self.current_category:upper()

    table.insert(menu_items, {
        text = _("📂 Category: ") .. cat_label,
        help_text = _("Tap to filter packages by category"),
        callback = function()
            self:showCategoryPicker()
        end,
    })

    -- Populate package entries
    local packages = RepoManager.packages or {}
    local count = 0

    -- Sort package keys alphabetically by name
    local sorted_keys = {}
    for pkg_id, pkg in pairs(packages) do
        table.insert(sorted_keys, { id = pkg_id, name = (pkg.name or pkg_id):lower() })
    end
    table.sort(sorted_keys, function(a, b) return a.name < b.name end)

    for _, entry in ipairs(sorted_keys) do
        local pkg_id = entry.id
        local pkg = packages[pkg_id]

        local matches_category = (self.current_category == "all") or
            (self.current_category == "plugins" and pkg.package_type == "koreader_plugin") or
            (self.current_category == "installed" and RepoManager:getPackageState(pkg_id) ~= "not_installed") or
            (pkg.category == self.current_category)

        local matches_search = true
        if self.search_query ~= "" then
            local q = self.search_query:lower()
            local n = (pkg.name or ""):lower()
            local d = (pkg.description or ""):lower()
            local a = (pkg.author or ""):lower()
            matches_search = (n:find(q, 1, true) ~= nil) or (d:find(q, 1, true) ~= nil) or (pkg_id:lower():find(q, 1, true) ~= nil) or (a:find(q, 1, true) ~= nil)
        end

        if matches_category and matches_search then
            count = count + 1
            local state, local_v, remote_v = RepoManager:getPackageState(pkg_id)
            local badge = ""
            if state == "update_available" then
                badge = " [UPDATE]"
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
            text = _("(No packages found in this category)"),
            help_text = _("Tap 'Category' above or 'Sync Online Catalog' to refresh."),
            enabled = false,
        })
    end

    local menu_title = string.format(_("KindleBreak Store (%d)"), count)
    local store_menu = Menu:new{
        title = menu_title,
        item_table = menu_items,
        is_borderless = false,
        on_close = function()
            self.active_menu = nil
        end,
    }

    self.active_menu = store_menu
    UIManager:show(store_menu)
end

function StoreUI:showCategoryPicker()
    local categories = {
        { id = "all", name = _("All Packages (140+)") },
        { id = "ai", name = _("🤖 AI Assistants & Language Models") },
        { id = "plugins", name = _("🔌 KOReader Plugins (All)") },
        { id = "dict", name = _("📖 Translation, Dictionaries & Anki") },
        { id = "sync", name = _("☁️ Sync, Notes & Highlights") },
        { id = "library", name = _("📚 Library, Covers & OPDS") },
        { id = "readers", name = _("👓 Readers & Manga Viewers") },
        { id = "games", name = _("🎮 Games & Puzzles") },
        { id = "utilities", name = _("🛠 Utilities & Hardware Tools") },
        { id = "tweaks", name = _("⚡ System Tweaks, Fonts & Hacks") },
        { id = "installed", name = _("✅ Installed on This Device") },
    }

    local items = {}
    for _, cat in ipairs(categories) do
        table.insert(items, {
            text = cat.name,
            checked = (self.current_category == cat.id),
            callback = function()
                self.current_category = cat.id
                self:showStoreMenu()
            end,
        })
    end

    local cat_menu = Menu:new{
        title = _("Select Category"),
        item_table = items,
    }
    UIManager:show(cat_menu)
end

function StoreUI:showSearchDialog()
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
                        self:showStoreMenu()
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
                        self:showStoreMenu()
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
        "Category: %s\n" ..
        "Type: %s\n" ..
        "Latest Version: %s\n" ..
        "Installed Version: %s\n" ..
        "Homepage: %s\n\n" ..
        "Description:\n%s",
        pkg.name or pkg_id, pkg_id,
        pkg.author or "Community",
        pkg.category or "plugins",
        pkg.package_type == "koreader_plugin" and "KOReader Plugin" or "System Homebrew",
        v_remote_str,
        v_local_str,
        pkg.homepage or "N/A",
        pkg.description or ""
    )

    local tv
    local buttons_table = {}
    local action_row = {}

    if state == "not_installed" then
        table.insert(action_row, {
            text = _("⬇ Install"),
            callback = function()
                if tv then UIManager:close(tv) end
                Installer:installPackage(pkg_id, pkg, function(success, msg)
                    UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
                    self:showStoreMenu()
                end)
            end,
        })
    elseif state == "update_available" then
        table.insert(action_row, {
            text = _("⬆ Update to v") .. v_remote_str,
            callback = function()
                if tv then UIManager:close(tv) end
                Installer:installPackage(pkg_id, pkg, function(success, msg)
                    UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
                    self:showStoreMenu()
                end)
            end,
        })
    else
        table.insert(action_row, {
            text = _("🔄 Reinstall"),
            callback = function()
                if tv then UIManager:close(tv) end
                Installer:installPackage(pkg_id, pkg, function(success, msg)
                    UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
                    self:showStoreMenu()
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
                        if tv then UIManager:close(tv) end
                        Installer:uninstallPackage(pkg_id, pkg, function(success, msg)
                            UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
                            self:showStoreMenu()
                        end)
                    end,
                })
            end,
        })
    end

    table.insert(action_row, {
        text = _("Close"),
        callback = function()
            if tv then UIManager:close(tv) end
        end,
    })

    table.insert(buttons_table, action_row)

    tv = TextViewer:new{
        title = pkg.name or pkg_id,
        text = detail_text,
        buttons_table = buttons_table,
    }
    UIManager:show(tv)
end

return StoreUI
