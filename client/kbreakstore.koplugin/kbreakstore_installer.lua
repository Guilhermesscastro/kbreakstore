--[[
    KindleBreak Store Installer Bridge (kbreakstore_installer.lua)
    Handles asynchronous downloads and unzips packages/plugins safely.
--]]

local logger = require("logger")
local socketutil = require("socketutil")
local http = require("socket.http")
local ltn12 = require("ltn12")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local RepoManager = require("kbreakstore_repo")

local Installer = {
    DOWNLOAD_TMP_DIR = "/tmp/kbreak_download",
    KOREADER_PLUGINS_DIR = "/mnt/us/koreader/plugins",
}

function Installer:downloadFile(url, target_path)
    os.execute("mkdir -p " .. self.DOWNLOAD_TMP_DIR)
    logger.info("KindleBreak Installer: Downloading " .. url .. " -> " .. target_path)

    -- Try via curl for reliability with large binaries/archives
    local cmd = string.format("curl -sSL -k '%s' -o '%s'", url, target_path)
    local ret = os.execute(cmd)
    if ret == 0 then
        return true
    end

    -- Fallback via socket.http / ltn12
    local f = io.open(target_path, "wb")
    if not f then return false end

    socketutil:set_timeout(30, 30)
    local res, code = http.request{
        url = url,
        sink = ltn12.sink.file(f),
    }

    if res and code == 200 then
        return true
    end

    return false
end

function Installer:installPackage(pkg_id, pkg_data, on_complete)
    if not pkg_data or not pkg_data.artifacts or #pkg_data.artifacts == 0 then
        if on_complete then on_complete(false, "No artifact available for this device.") end
        return
    end

    local artifact = pkg_data.artifacts[1]
    local url = artifact.url
    local ext = url:match("^.+%.(%w+)$") or "zip"
    local download_path = string.format("%s/%s.%s", self.DOWNLOAD_TMP_DIR, pkg_id, ext)

    UIManager:show(InfoMessage:new{
        text = "Downloading " .. (pkg_data.name or pkg_id) .. "...",
        timeout = 1,
    })

    -- Run download
    local dl_ok = self:downloadFile(url, download_path)
    if not dl_ok then
        if on_complete then on_complete(false, "Download failed. Check Wi-Fi connection.") end
        return
    end

    UIManager:show(InfoMessage:new{
        text = "Installing " .. (pkg_data.name or pkg_id) .. "...",
        timeout = 1,
    })

    local install_ok = false
    local error_msg = nil

    if pkg_data.package_type == "koreader_plugin" then
        -- Extract plugin
        local target_dir = string.format("%s/%s.koplugin", self.KOREADER_PLUGINS_DIR, pkg_id)
        local tmp_ext = self.DOWNLOAD_TMP_DIR .. "/ext_" .. pkg_id
        os.execute("rm -rf " .. tmp_ext .. " && mkdir -p " .. tmp_ext)

        local unpack_cmd = ""
        if ext == "zip" then
            unpack_cmd = string.format("unzip -q -o '%s' -d '%s'", download_path, tmp_ext)
        else
            unpack_cmd = string.format("tar -xzf '%s' -C '%s'", download_path, tmp_ext)
        end

        local res = os.execute(unpack_cmd)
        if res == 0 then
            os.execute(string.format("mkdir -p '%s'", target_dir))
            -- Check if inner directory exists or flat files
            if os.execute(string.format("[ -d '%s/%s.koplugin' ]", tmp_ext, pkg_id)) == 0 then
                os.execute(string.format("cp -rf '%s/%s.koplugin/'* '%s/'", tmp_ext, pkg_id, target_dir))
            else
                os.execute(string.format("cp -rf '%s/'* '%s/'", tmp_ext, target_dir))
            end
            os.execute("rm -rf " .. tmp_ext)
            install_ok = true
        else
            error_msg = "Extraction failed."
        end
    else
        -- System package installation
        local target_dir = "/mnt/us/kbreakstore/packages/" .. pkg_id
        os.execute("mkdir -p " .. target_dir)
        local unpack_cmd = string.format("tar -xzf '%s' -C '%s' 2>/dev/null || unzip -q -o '%s' -d '%s'", download_path, target_dir, download_path, target_dir)
        local res = os.execute(unpack_cmd)
        if res == 0 then
            -- Run install hook if present
            local hook = target_dir .. "/install.sh"
            if os.execute(string.format("[ -f '%s' ]", hook)) == 0 then
                os.execute(string.format("chmod +x '%s' && (cd '%s' && ./%s)", hook, target_dir, "install.sh"))
            end
            install_ok = true
        else
            error_msg = "Package extraction failed."
        end
    end

    -- Cleanup download
    os.execute("rm -f " .. download_path)

    if install_ok then
        RepoManager:recordInstall(pkg_id, artifact.version, pkg_data.package_type)
        if on_complete then on_complete(true, "Installation completed successfully!") end
    else
        if on_complete then on_complete(false, error_msg or "Installation failed.") end
    end
end

function Installer:uninstallPackage(pkg_id, pkg_data, on_complete)
    if pkg_data and pkg_data.package_type == "koreader_plugin" then
        local target_dir = string.format("%s/%s.koplugin", self.KOREADER_PLUGINS_DIR, pkg_id)
        os.execute("rm -rf " .. target_dir)
    else
        local target_dir = "/mnt/us/kbreakstore/packages/" .. pkg_id
        local unhook = target_dir .. "/uninstall.sh"
        if os.execute(string.format("[ -f '%s' ]", unhook)) == 0 then
            os.execute(string.format("chmod +x '%s' && (cd '%s' && ./uninstall.sh)", unhook, target_dir))
        end
        os.execute("rm -rf " .. target_dir)
    end

    RepoManager:recordUninstall(pkg_id)
    if on_complete then on_complete(true, "Package uninstalled successfully.") end
end

return Installer
