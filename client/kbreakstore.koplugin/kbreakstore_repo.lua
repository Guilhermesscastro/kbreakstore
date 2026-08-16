--[[
    KindleBreak Store Repository Manager (kbreakstore_repo.lua)
    Fetches manifest.v2.json, caches locally, and resolves package states.
--]]

local DataStorage = require("datastorage")
local logger = require("logger")
local socketutil = require("socketutil")
local json = require("json")

-- Try loading ssl.https for TLS, fallback to socket.http
local has_ssl, https = pcall(require, "ssl.https")
local has_http, http = pcall(require, "socket.http")
local ltn12 = require("ltn12")

local RepoManager = {
    DEFAULT_REPO_URL = "https://raw.githubusercontent.com/Guilhermesscastro/kbreakstore/main/registry/manifest.v2.json",
    CACHE_DIR = "/mnt/us/kbreakstore",
    CACHE_FILE = "/mnt/us/kbreakstore/manifest_cache.json",
    INSTALLED_FILE = "/mnt/us/kbreakstore/installed.json",
    KOREADER_PLUGINS_DIR = "/mnt/us/koreader/plugins",
    manifest = nil,
    packages = {},
}

function RepoManager:getPluginDir()
    local str = debug.getinfo(1, "S").source:sub(2)
    return str:match("(.*/)") or "/mnt/us/koreader/plugins/kbreakstore.koplugin/"
end

function RepoManager:init()
    os.execute("mkdir -p " .. self.CACHE_DIR)
    -- 1. Try local user cache
    local loaded = self:loadCachedManifest()
    -- 2. Fall back to bundled manifest inside plugin directory
    if not loaded or not self.packages or next(self.packages) == nil then
        self:loadBundledManifest()
    end
end

function RepoManager:loadCachedManifest()
    local f = io.open(self.CACHE_FILE, "r")
    if f then
        local content = f:read("*all")
        f:close()
        if content and #content > 0 then
            local ok, data = pcall(json.decode, content)
            if ok and data and data.packages and next(data.packages) ~= nil then
                self.manifest = data
                self.packages = data.packages
                logger.info("KindleBreak Store: Loaded manifest from cache with " .. self:getPackageCount() .. " package(s).")
                return true
            end
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
        if content and #content > 0 then
            local ok, data = pcall(json.decode, content)
            if ok and data and data.packages then
                self.manifest = data
                self.packages = data.packages
                logger.info("KindleBreak Store: Loaded bundled fallback manifest with " .. self:getPackageCount() .. " package(s).")
                return true
            end
        end
    end
    logger.warn("KindleBreak Store: Could not load bundled manifest.")
    return false
end

function RepoManager:getPackageCount()
    local c = 0
    if self.packages then
        for _ in pairs(self.packages) do c = c + 1 end
    end
    return c
end

function RepoManager:fetchManifest(url, callback)
    url = url or self.DEFAULT_REPO_URL
    logger.info("KindleBreak Store: Fetching manifest from: " .. url)

    local body_str = ""
    local response_body = {}
    local code = 0

    socketutil:set_timeout(10, 10)

    -- 1. Try ssl.https or socket.http
    local http_mod = (url:sub(1, 5) == "https" and has_ssl) and https or (has_http and http)
    if http_mod then
        local res, c, _ = http_mod.request{
            url = url,
            sink = ltn12.sink.table(response_body),
        }
        if res and c == 200 then
            code = 200
            body_str = table.concat(response_body)
        end
    end

    -- 2. Fallback to curl on Kindle
    if code ~= 200 or #body_str == 0 then
        logger.info("KindleBreak Store: HTTP module failed/unavailable, executing curl fallback...")
        local tmp_file = "/tmp/kbreak_manifest_fetch.json"
        local ret = os.execute(string.format("curl -sSL -k '%s' -o '%s'", url, tmp_file))
        if ret == 0 or ret == true then
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
        if ok and data and data.packages and next(data.packages) ~= nil then
            self.manifest = data
            self.packages = data.packages

            -- Save to cache
            local f = io.open(self.CACHE_FILE, "w")
            if f then
                f:write(body_str)
                f:close()
            end
            logger.info("KindleBreak Store: Manifest successfully updated with " .. self:getPackageCount() .. " package(s).")
            if callback then callback(true, self.packages) end
            return true
        else
            logger.warn("KindleBreak Store: Decoded JSON has no packages or invalid structure.")
        end
    end

    -- If remote fetch failed, preserve existing packages or fallback to bundled
    if not self.packages or next(self.packages) == nil then
        self:loadBundledManifest()
    end

    logger.warn("KindleBreak Store: Failed to fetch remote manifest. Total packages available: " .. self:getPackageCount())
    if callback then callback(false, self.packages) end
    return false
end

function RepoManager:getInstalledPackages()
    local installed = {}

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
    if self.packages then
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
    end

    return installed
end

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
    local pkg = self.packages and self.packages[pkg_id]
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
