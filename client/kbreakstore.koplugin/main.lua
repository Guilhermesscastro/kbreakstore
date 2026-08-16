--[[
    KindleBreak Store KOReader Plugin Entry Point (main.lua)
    Integrates the KindleBreak Store into KOReader's tools menu.
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local RepoManager = require("kbreakstore_repo")
local StoreUI = require("kbreakstore_ui")

local KBreakStore = WidgetContainer:extend{
    name = "kbreakstore",
}

function KBreakStore:init()
    RepoManager:init()
    self.ui.menu:registerToMainMenu(self)
end

function KBreakStore:addToMainMenu(menu_items)
    menu_items.kbreakstore = {
        text = _("📦 KindleBreak Store"),
        help_text = _("Browse and install Kindle homebrew, tools, and KOReader plugins"),
        sub_item_table = {
            {
                text = _("Browse Store"),
                callback = function(touch_menu)
                    StoreUI:showStoreMenu(touch_menu)
                end,
            },
            {
                text = _("Installed Packages"),
                callback = function(touch_menu)
                    StoreUI.current_category = "installed"
                    StoreUI:showStoreMenu(touch_menu)
                end,
            },
            {
                text = _("Sync Online Repository"),
                callback = function(touch_menu)
                    RepoManager:fetchManifest(nil, function(success)
                        StoreUI:showStoreMenu(touch_menu)
                    end)
                end,
            },
        },
    }
end

return KBreakStore
