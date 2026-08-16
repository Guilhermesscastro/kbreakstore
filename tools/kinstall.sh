#!/bin/sh
# ==============================================================================
# KindleBreak Installer & KPM Bridge (kinstall.sh)
# Lightweight POSIX shell package manager & KOReader plugin installer for Kindle
# ==============================================================================

set -e

STORE_DIR="/mnt/us/kbreakstore"
INSTALLED_DB="${STORE_DIR}/installed.json"
CACHE_DIR="/tmp/kbreak_cache"
DEFAULT_REPO_URL="https://raw.githubusercontent.com/Guilhermesscastro/kbreakstore/main/registry/manifest.v2.json"
KOREADER_PLUGINS_DIR="/mnt/us/koreader/plugins"

log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARN] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

init_dirs() {
    mkdir -p "${STORE_DIR}" "${CACHE_DIR}" "${KOREADER_PLUGINS_DIR}"
    if [ ! -f "${INSTALLED_DB}" ]; then
        echo "{}" > "${INSTALLED_DB}"
    fi
}

detect_platform() {
    # Detect hard-float vs soft-float on Kindle
    ARCH=$(uname -m 2>/dev/null || echo "armv7l")
    if [ -f /etc/version.txt ]; then
        FW_VER=$(awk -F- '{print $2}' /etc/version.txt 2>/dev/null || echo "")
    else
        FW_VER=""
    fi

    # Kindles running FW >= 5.16.3 or modern 32-bit HF kernels
    if [ -f /lib/ld-linux-armhf.so.3 ] || [ -f /usr/lib/arm-linux-gnueabihf ]; then
        echo "kindlehf"
    elif [ -f /lib/ld-linux.so.3 ]; then
        echo "kindlepw2"
    else
        echo "kindlehf" # Default modern assumption
    fi
}

fetch_manifest() {
    REPO_URL="${1:-$DEFAULT_REPO_URL}"
    MANIFEST_CACHE="${CACHE_DIR}/manifest.json"
    log_info "Fetching manifest from ${REPO_URL}..."
    
    if command -v curl >/dev/null 2>&1; then
        curl -sSL -k "${REPO_URL}" -o "${MANIFEST_CACHE}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --no-check-certificate "${REPO_URL}" -O "${MANIFEST_CACHE}"
    else
        log_error "Neither curl nor wget found on device."
        return 1
    fi
    echo "${MANIFEST_CACHE}"
}

download_file() {
    URL="$1"
    DEST="$2"
    log_info "Downloading ${URL}..."
    if command -v curl >/dev/null 2>&1; then
        curl -sSL -k "${URL}" -o "${DEST}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --no-check-certificate "${URL}" -O "${DEST}"
    else
        log_error "Neither curl nor wget found."
        return 1
    fi
}

# Install KOReader Plugin (.zip or folder)
install_koreader_plugin() {
    PKG_ID="$1"
    ARCHIVE_PATH="$2"
    TARGET_DIR="${KOREADER_PLUGINS_DIR}/${PKG_ID}.koplugin"

    log_info "Installing KOReader plugin '${PKG_ID}' to ${TARGET_DIR}..."
    TMP_EXTRACT="${CACHE_DIR}/ext_${PKG_ID}"
    rm -rf "${TMP_EXTRACT}"
    mkdir -p "${TMP_EXTRACT}"

    # Extract based on file type
    case "${ARCHIVE_PATH}" in
        *.zip)
            if command -v unzip >/dev/null 2>&1; then
                unzip -q "${ARCHIVE_PATH}" -d "${TMP_EXTRACT}"
            else
                log_error "unzip command not found."
                return 1
            fi
            ;;
        *.tar.gz|*.tgz)
            tar -xzf "${ARCHIVE_PATH}" -C "${TMP_EXTRACT}"
            ;;
        *.tar.xz)
            tar -xJf "${ARCHIVE_PATH}" -C "${TMP_EXTRACT}"
            ;;
        *)
            log_error "Unsupported archive extension: ${ARCHIVE_PATH}"
            return 1
            ;;
    esac

    # Locate plugin directory or copy extracted files
    mkdir -p "${TARGET_DIR}"
    if [ -d "${TMP_EXTRACT}/${PKG_ID}.koplugin" ]; then
        cp -r "${TMP_EXTRACT}/${PKG_ID}.koplugin/"* "${TARGET_DIR}/"
    else
        cp -r "${TMP_EXTRACT}/"* "${TARGET_DIR}/"
    fi

    rm -rf "${TMP_EXTRACT}"
    log_info "Successfully installed KOReader plugin '${PKG_ID}'!"
}

# Install standard package (.kpkg or tar archive with hooks)
install_system_package() {
    PKG_ID="$1"
    ARCHIVE_PATH="$2"

    # Check if native KPM CLI is available
    if command -v kpm >/dev/null 2>&1; then
        log_info "Found native kpm CLI, delegating install..."
        kpm install "${PKG_ID}"
        return $?
    fi

    log_info "Performing standalone extraction for '${PKG_ID}'..."
    EXT_DIR="${STORE_DIR}/packages/${PKG_ID}"
    rm -rf "${EXT_DIR}"
    mkdir -p "${EXT_DIR}"

    tar -xzf "${ARCHIVE_PATH}" -C "${EXT_DIR}" 2>/dev/null || tar -xf "${ARCHIVE_PATH}" -C "${EXT_DIR}"

    # Run post-install hook if present
    if [ -f "${EXT_DIR}/install.sh" ]; then
        log_info "Executing post-install hook for '${PKG_ID}'..."
        chmod +x "${EXT_DIR}/install.sh"
        (cd "${EXT_DIR}" && ./install.sh)
    fi

    log_info "Successfully installed system package '${PKG_ID}'!"
}

cmd_install() {
    PKG_ID="$1"
    if [ -z "${PKG_ID}" ]; then
        log_error "Usage: $0 install <package_id> [manifest_url]"
        return 1
    fi

    init_dirs
    MANIFEST_FILE=$(fetch_manifest "$2")
    if [ ! -f "${MANIFEST_FILE}" ]; then
        log_error "Failed to retrieve manifest."
        return 1
    fi

    PLATFORM=$(detect_platform)
    log_info "Target platform detected: ${PLATFORM}"

    # Parse download URL and package_type via Python if present, or basic grep/awk
    if command -v python3 >/dev/null 2>&1; then
        PKG_INFO=$(python3 -c "
import json, sys
with open('${MANIFEST_FILE}') as f:
    d = json.load(f)
p = d.get('packages', {}).get('${PKG_ID}')
if not p:
    print('NOT_FOUND')
    sys.exit(0)
ptype = p.get('package_type', 'system')
url = None
for art in p.get('artifacts', []):
    if '${PLATFORM}' in art.get('supported_platforms', []) or 'kindle' in art.get('supported_platforms', []):
        url = art.get('url')
        break
if not url and p.get('artifacts'):
    url = p['artifacts'][0].get('url')
print(f'{ptype}|{url}')
")
    else
        # Fallback minimal string search
        PKG_INFO="system|"
    fi

    if [ "${PKG_INFO}" = "NOT_FOUND" ] || [ -z "${PKG_INFO}" ]; then
        log_error "Package '${PKG_ID}' not found in repository."
        return 1
    fi

    PKG_TYPE=$(echo "${PKG_INFO}" | cut -d'|' -f1)
    DOWNLOAD_URL=$(echo "${PKG_INFO}" | cut -d'|' -f2)

    if [ -z "${DOWNLOAD_URL}" ]; then
        log_error "No valid artifact found for package '${PKG_ID}' on platform '${PLATFORM}'."
        return 1
    fi

    EXT="${DOWNLOAD_URL##*.}"
    ARCHIVE_FILE="${CACHE_DIR}/${PKG_ID}.${EXT}"
    download_file "${DOWNLOAD_URL}" "${ARCHIVE_FILE}"

    if [ "${PKG_TYPE}" = "koreader_plugin" ]; then
        install_koreader_plugin "${PKG_ID}" "${ARCHIVE_FILE}"
    else
        install_system_package "${PKG_ID}" "${ARCHIVE_FILE}"
    fi

    rm -f "${ARCHIVE_FILE}"
}

cmd_list() {
    init_dirs
    log_info "Installed packages in ${STORE_DIR}:"
    if [ -d "${KOREADER_PLUGINS_DIR}" ]; then
        echo "KOReader Plugins:"
        ls -d "${KOREADER_PLUGINS_DIR}"/*.koplugin 2>/dev/null || echo "  (None)"
    fi
}

case "$1" in
    install)
        cmd_install "$2" "$3"
        ;;
    list)
        cmd_list
        ;;
    detect)
        detect_platform
        ;;
    *)
        echo "KindleBreak Store Installer (kinstall)"
        echo "Usage: $0 {install <package_id> [repo_url]|list|detect}"
        exit 1
        ;;
esac
