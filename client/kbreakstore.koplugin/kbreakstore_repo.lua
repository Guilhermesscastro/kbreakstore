--[[
    KindleBreak Store Repository Manager (kbreakstore_repo.lua)
    Fetches manifest.v2.json, caches locally, and resolves package states.
    Falls back gracefully to bundled manifest.v2.json if remote is unreachable.
--]]

local DataStorage = require("datastorage")
local logger = require("logger")
local socketutil = require("socketutil")
local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("json")

local RepoManager = {
    DEFAULT_REPO_URL = "https://raw.githubusercontent.com/Guilhermesscastro/kbreakstore/main/registry/manifest.v2.json",
    CACHE_DIR = "/mnt/us/kbreakstore",
    CACHE_FILE = "/mnt/us/kbreakstore/manifest_cache.json",
    INSTALLED_FILE = "/mnt/us/kbreakstore/installed.json",
    KOREADER_PLUGINS_DIR = "/mnt/us/koreader/plugins",
    manifest = nil,
    packages = {},
}

-- Resolve absolute directory of this plugin
function RepoManager:getPluginDir()
    local str = debug.getinfo(1, "S").source:sub(2)
    return str:match("(.*/)") or "/mnt/us/koreader/plugins/kbreakstore.koplugin/"
end

function RepoManager:init()
    os.execute("mkdir -p " .. self.CACHE_DIR)
    -- 1. Try local user cache
    local loaded = self:loadCachedManifest()
    -- 2. Fall back to bundled manifest inside plugin directory
    if not loaded then
        self:loadBundledManifest()
    end
end

function RepoManager:loadCachedManifest()
    local f = io.open(self.CACHE_FILE, "r")
    if f then
        local content = f:read("*all")
        f:close()
        local ok, data = pcall(json.decode, content)
        if ok and data and data.packages then
            self.manifest = data
            self.packages = data.packages
            logger.info("KindleBreak Store: Loaded manifest from user cache.")
            return true
        end
    end
    return false
end

function RepoManager:loadBundledManifest()
    local bundled_path = self:getPluginDir() .. "manifest.v2.json"
    local f = io.open(bundled_path, "r")
    if f then
        local content = f:read("*all")
        f:close()
        local ok, data = pcall(json.decode, content)
        if ok and data and data.packages then
            self.manifest = data
            self.packages = data.packages
            logger.info("KindleBreak Store: Loaded bundled fallback manifest (" .. bundled_path .. ")")
            return true
        end
    end
    return false
end

function RepoManager:fetchManifest(url, callback)
    url = url or self.DEFAULT_REPO_URL
    logger.info("KindleBreak Store: Fetching manifest from: " .. url)

    local response_body = {}
    socketutil:set_timeout(8, 8)

    -- Try via socket.http first
    local res, code, response_headers = http.request{
        url = url,
        sink = ltn12.sink.table(response_body),
    }

    local body_str = table.concat(response_body)

    -- Fallback to curl if socket.http failed or returned empty
    if not res or code ~= 200 or #body_str == 0 then
        logger.info("KindleBreak Store: socket.http failed, trying curl fallback...")
        local tmp_file = "/tmp/kbreak_manifest_fetch.json"
        local ret = os.execute(string.format("curl -sSL -k '%s' -o '%s'", url, tmp_file))
        if ret == 0 then
            local f = io.open(tmp_file, "r")
            if f then
                body_str = f:read("*all")
                f:close()
                code = 200
            end
        end
    end

    if code == 200 and #body_str > 0 then
        local ok, data = pcall(json.decode, body_str)
        if ok and data and data.packages then
            self.manifest = data
            self.packages = data.packages

            -- Save to cache
            local f = io.open(self.CACHE_FILE, "w")
            if f then
                f:write(body_str)
                f:close()
            end
            logger.info("KindleBreak Store: Manifest successfully updated from remote.")
            if callback then callback(true, self.packages) end
            return true
        end
    end

    -- If remote failed, make sure we have at least bundled or cached data
    if not self.manifest then
        self:loadBundledManifest()
    end

    logger.warn("KindleBreak Store: Could not reach remote repo. Using cached/bundled manifest.")
    if callback then callback(false, self.packages) end
    return false
end

function RepoManager:getInstalledPackages()
    local installed = {}

    -- Check installed.json
    local f = io.open(self.INSTALLED_FILE, "r")
    if f then
        local content = f:read("*all")
        f:close()
        local ok, data = pcall(json.decode, content)
        if ok and type(data) == "table" then
            installed = data
        end
    end

    -- Also check existing KOReader plugin folders
    for pkg_id, pkg in pairs(self.packages) do
        if pkg.package_type == "koreader_plugin" then
            local plugin_dir = self.KOREADER_PLUGINS_DIR .. "/" .. pkg_id .. ".koplugin"
            local meta_file = plugin_dir .. "/_meta.lua"
            local meta_f = io.open(meta_file, "r")
            if meta_f then
                meta_f:close()
                if not installed[pkg_id] then
                    installed[pkg_id] = {
                        version = {1, 0, 0},
                        installed_at = os.time(),
                        package_type = "koreader_plugin",
                    }
                end
            end
        end
    end

    return installed
end

-- Compare version array [major, minor, patch]
function RepoManager:compareVersions(v1, v2)
    if not v1 or not v2 then return 0 end
    for i = 1, 3 do
        local n1 = v1[i] or 0
        local n2 = v2[i] or 0
        if n1 > n2 then return 1 end
        if n1 < n2 then return -1 end
    end
    return 0
end

function RepoManager:getPackageState(pkg_id)
    local pkg = self.packages[pkg_id]
    if not pkg then return "unknown", nil end

    local installed = self:getInstalledPackages()
    local inst_info = installed[pkg_id]

    if not inst_info then
        return "not_installed", nil
    end

    local remote_version = nil
    if pkg.artifacts and #pkg.artifacts > 0 then
        remote_version = pkg.artifacts[1].version
    end

    if remote_version and inst_info.version then
        if self:compareVersions(remote_version, inst_info.version) > 0 then
            return "update_available", inst_info.version, remote_version
        end
    end

    return "installed", inst_info.version, remote_version
end

function RepoManager:recordInstall(pkg_id, version, pkg_type)
    local installed = self:getInstalledPackages()
    installed[pkg_id] = {
        version = version or {1, 0, 0},
        installed_at = os.time(),
        package_type = pkg_type or "system",
    }
    local f = io.open(self.INSTALLED_FILE, "w")
    if f then
        f:write(json.encode(installed))
        f:close()
    end
end

function RepoManager:recordUninstall(pkg_id)
    local installed = self:getInstalledPackages()
    installed[pkg_id] = nil
    local f = io.open(self.INSTALLED_FILE, "w")
    if f then
        f:write(json.encode(installed))
        f:close()
    end
end

return RepoManager
