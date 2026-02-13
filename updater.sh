#!/usr/bin/env bash

set -euo pipefail

# QuickBot Updater
# Updates QuickBot to the latest version while preserving configuration

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
QUICKBOT_HOME="$HOME/.quickbot"
QUICKBOT_CONFIG_BASE="$HOME/.config/.quickbot"
QUICKBOT_DATA_ROOT="$QUICKBOT_CONFIG_BASE/data"
QUICKBOT_ENV_FILE="$QUICKBOT_HOME/.env"
QUICKBOT_LOG_DIR="$QUICKBOT_DATA_ROOT/logs"
LOCAL_BIN="$HOME/.local/bin"

# Flags
FORCE_UPDATE=false
UPDATE_SCRIPTS=false
SKIP_CONFIRMATIONS=false
DEV_CHANNEL=false
ROLLBACK=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_UPDATE=true
            shift
            ;;
        --update-scripts)
            UPDATE_SCRIPTS=true
            shift
            ;;
        --yes)
            SKIP_CONFIRMATIONS=true
            shift
            ;;
        --development)
            DEV_CHANNEL=true
            shift
            ;;
        --rollback)
            ROLLBACK=true
            shift
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unknown option: $1"
            echo "Usage: $0 [--force] [--update-scripts] [--yes] [--development] [--rollback]"
            exit 1
            ;;
    esac
done

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Reportable issue — safe to ignore but worth flagging
log_reportable() {
    echo -e "${BLUE}[INFO]${NC} This is safe to ignore, but if it persists please report it at:"
    echo -e "       https://github.com/levinismynameirl/QuickBot-Installer/issues"
}

# Log to file
log_to_file() {
    local log_file="$QUICKBOT_LOG_DIR/update.log"
    mkdir -p "$QUICKBOT_LOG_DIR" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$log_file" 2>/dev/null || true
}

# Ask for confirmation
confirm() {
    if [[ "$SKIP_CONFIRMATIONS" == "true" ]]; then
        return 0
    fi
    
    local prompt="$1"
    local default="${2:-Y}"
    
    if [[ "$default" == "Y" ]]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi
    
    read -r -p "$prompt" response
    response=${response:-$default}
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Check if QuickBot is installed
check_installation() {
    log_info "Checking QuickBot installation..."
    
    if [[ ! -f "$QUICKBOT_ENV_FILE" ]]; then
        log_error "QuickBot installation not found or corrupted"
        log_error "Missing: $QUICKBOT_ENV_FILE"
        echo ""
        log_info "To reinstall, download and run the installer:"
        echo "  https://github.com/levinismynameirl/QuickBot-Installer"
        exit 1
    fi
    
    # Source the .env file
    source "$QUICKBOT_ENV_FILE"
    
    if [[ -z "${QUICKBOT_VERSION:-}" ]]; then
        log_warn "Could not determine current version"
        log_reportable
        QUICKBOT_VERSION="unknown"
    fi
    
    if [[ -z "${QUICKBOT_GITHUB_REPO:-}" ]]; then
        log_warn "GitHub repository not specified in .env, using default"
        log_reportable
        QUICKBOT_GITHUB_REPO="levinismynameirl/Quick-Bot"
    fi
    
    log_success "QuickBot installation found (version: $QUICKBOT_VERSION)"
}

# Check if a version string is a development build (ends with 'd')
is_dev_build() {
    local ver="${1#v}"
    [[ "$ver" =~ d$ ]]
}

# Strip the development suffix for numeric comparison
strip_dev_suffix() {
    local ver="${1#v}"
    echo "${ver%d}"
}

# Compare versions (returns 0 if v1 < v2, 1 otherwise)
# Handles development builds: 0.1.0d sorts alongside 0.1.0
version_less_than() {
    local v1="$1"
    local v2="$2"
    
    # Remove 'v' prefix if present
    v1="${v1#v}"
    v2="${v2#v}"
    
    # Simple equality check
    if [[ "$v1" == "$v2" ]]; then
        return 1
    fi
    
    # Strip 'd' suffix for numeric comparison
    local v1_base=$(strip_dev_suffix "$v1")
    local v2_base=$(strip_dev_suffix "$v2")
    
    # If bases are equal, dev < stable (0.1.0d < 0.1.0)
    if [[ "$v1_base" == "$v2_base" ]]; then
        if is_dev_build "$v1" && ! is_dev_build "$v2"; then
            return 0  # dev < stable
        else
            return 1
        fi
    fi
    
    # Use sort -V for version comparison on the base versions
    local sorted=$(printf '%s\n%s\n' "$v1_base" "$v2_base" | sort -V | head -n1)
    
    if [[ "$sorted" == "$v1_base" ]]; then
        return 0
    else
        return 1
    fi
}

# Get latest release version from GitHub
# When DEV_CHANNEL is true, also considers pre-releases tagged with 'd'
get_latest_version() {
    log_info "Checking for latest version on GitHub..." >&2
    
    local max_retries=3
    local retry_count=0
    local latest_version=""
    
    while [[ $retry_count -lt $max_retries ]]; do
        if [[ "$DEV_CHANNEL" == "true" ]]; then
            # Fetch all releases (including pre-releases / dev builds)
            # Pick the first one whose tag ends with 'd', or just the first one
            local all_releases
            all_releases=$(curl -s --connect-timeout 30 \
                "https://api.github.com/repos/$QUICKBOT_GITHUB_REPO/releases?per_page=20" 2>/dev/null)
            
            # Try to find a dev build first (tag ends with 'd')
            latest_version=$(echo "$all_releases" | \
                grep '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/' | \
                grep 'd$' | head -1)
            
            # If no dev build found, fall back to latest
            if [[ -z "$latest_version" ]]; then
                latest_version=$(echo "$all_releases" | \
                    grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/')
            fi
        else
            # Standard: only look at the latest non-prerelease
            latest_version=$(curl -s --connect-timeout 30 \
                "https://api.github.com/repos/$QUICKBOT_GITHUB_REPO/releases/latest" 2>/dev/null | \
                grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/')
        fi
        
        if [[ -n "$latest_version" ]]; then
            echo "$latest_version"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log_warn "Failed to fetch version, retrying... ($retry_count/$max_retries)" >&2
            sleep 2
        fi
    done
    
    log_error "Failed to fetch latest version from GitHub" >&2
    exit 1
}

# Download a specific release version
download_release() {
    local version="$1"
    
    log_info "Downloading QuickBot $version..." >&2
    
    local max_retries=3
    local retry_count=0
    local download_url=""
    
    # Determine the API endpoint — for a specific version we search releases by tag
    local release_endpoint="https://api.github.com/repos/$QUICKBOT_GITHUB_REPO/releases/tags/v${version}"
    
    while [[ $retry_count -lt $max_retries ]]; do
        local release_info=$(curl -s --connect-timeout 30 "$release_endpoint" 2>/dev/null)
        
        if [[ $? -eq 0 ]] && [[ -n "$release_info" ]]; then
            # Try uploaded assets first: wheel, then tarball
            download_url=$(echo "$release_info" | grep 'browser_download_url' | grep '\.whl' | head -1 | cut -d'"' -f4)
            
            if [[ -z "$download_url" ]]; then
                download_url=$(echo "$release_info" | grep 'browser_download_url' | grep '\.tar\.gz' | head -1 | cut -d'"' -f4)
            fi
            
            # Fall back to the auto-generated source tarball
            if [[ -z "$download_url" ]]; then
                download_url=$(echo "$release_info" | grep '"tarball_url"' | head -1 | cut -d'"' -f4)
            fi
            
            if [[ -n "$download_url" ]]; then
                break
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log_warn "Failed to fetch download URL, retrying... ($retry_count/$max_retries)" >&2
            sleep 2
        fi
    done
    
    # If still nothing, fall back to direct git install
    if [[ -z "$download_url" ]]; then
        log_warn "No downloadable release found, will install from git" >&2
        echo "git+https://github.com/$QUICKBOT_GITHUB_REPO.git@v$version"
        return 0
    fi
    
    # Download the release
    local filename=$(basename "$download_url")
    # If using tarball_url (API URL with no extension), give it a name
    if [[ ! "$filename" =~ \.(whl|tar\.gz|zip)$ ]]; then
        filename="quickbot-${version}.tar.gz"
    fi
    local download_path="/tmp/$filename"
    
    retry_count=0
    while [[ $retry_count -lt $max_retries ]]; do
        if curl -fL --progress-bar --connect-timeout 30 "$download_url" -o "$download_path" 2>&2; then
            log_success "Downloaded successfully" >&2
            echo "$download_path"
            log_to_file "Downloaded QuickBot $version from $download_url"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log_warn "Download failed, retrying... ($retry_count/$max_retries)" >&2
            sleep 2
        fi
    done
    
    log_error "Failed to download QuickBot after $max_retries attempts" >&2
    exit 1
}

# Show development build disclaimer
show_dev_disclaimer() {
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠  DEVELOPMENT BUILD WARNING                            ║${NC}"
    echo -e "${YELLOW}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║  Development builds may:                                  ║${NC}"
    echo -e "${YELLOW}║    • Break existing configuration files                   ║${NC}"
    echo -e "${YELLOW}║    • Introduce unstable features                          ║${NC}"
    echo -e "${YELLOW}║    • Change behavior between releases                     ║${NC}"
    echo -e "${YELLOW}║                                                           ║${NC}"
    echo -e "${YELLOW}║  Back up ~/.config/.quickbot/ before proceeding.          ║${NC}"
    echo -e "${YELLOW}║  Use 'quick update --rollback' to revert if needed.       ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Save current version for rollback
save_rollback_info() {
    local current_ver="$1"
    local rollback_file="$QUICKBOT_DATA_ROOT/.rollback_version"
    echo "$current_ver" > "$rollback_file"
    log_to_file "Saved rollback version: $current_ver"
}

# Perform rollback to previous version
do_rollback() {
    local rollback_file="$QUICKBOT_DATA_ROOT/.rollback_version"
    
    if [[ ! -f "$rollback_file" ]]; then
        log_error "No rollback information found."
        log_info "Rollback is only available after a successful update."
        exit 1
    fi
    
    local previous_version
    previous_version=$(cat "$rollback_file")
    
    if [[ -z "$previous_version" ]]; then
        log_error "Rollback file is empty."
        exit 1
    fi
    
    local current_version="${QUICKBOT_VERSION#v}"
    
    echo ""
    log_info "Current version:  $current_version"
    log_info "Rollback target:  $previous_version"
    echo ""
    
    if [[ "$current_version" == "$previous_version" ]]; then
        log_warn "Already on version $previous_version, nothing to rollback."
        exit 0
    fi
    
    if [[ "$SKIP_CONFIRMATIONS" != "true" ]]; then
        if ! confirm "Rollback from $current_version to $previous_version?" "N"; then
            log_info "Rollback cancelled."
            exit 0
        fi
    fi
    
    if is_dev_build "$previous_version"; then
        show_dev_disclaimer
        if [[ "$SKIP_CONFIRMATIONS" != "true" ]]; then
            if ! confirm "The rollback target is a development build. Continue?" "N"; then
                log_info "Rollback cancelled."
                exit 0
            fi
        fi
    fi
    
    echo ""
    local package_path=$(download_release "$previous_version")
    update_quickbot "$package_path" "$previous_version"
    rm -f "$package_path"
    
    # Remove rollback file after successful rollback
    rm -f "$rollback_file"
    
    validate_update
    
    echo ""
    log_success "Rolled back from $current_version to $previous_version"
    log_to_file "Rolled back from $current_version to $previous_version"
}

# Update QuickBot via pipx
update_quickbot() {
    local package_path="$1"
    local new_version="$2"
    
    log_info "Updating QuickBot via pipx..."
    
    # Create backup of current version info
    local backup_version="$QUICKBOT_VERSION"
    
    # Update with pipx
    if pipx install "$package_path" --force 2>&1 | tee -a "$QUICKBOT_LOG_DIR/update.log"; then
        log_success "QuickBot updated via pipx"
        log_to_file "Updated QuickBot from $backup_version to $new_version"
    else
        log_error "Failed to update QuickBot via pipx"
        log_to_file "Update failed: pipx install error"
        exit 1
    fi
    
    # Update .env file with new version
    sed -i.bak "s/QUICKBOT_VERSION=\".*\"/QUICKBOT_VERSION=\"$new_version\"/" "$QUICKBOT_ENV_FILE"
    
    # Copy updated .env to pipx venv
    log_info "Updating .env in pipx environment..."
    local pipx_venv="$HOME/.local/pipx/venvs/quickbot"
    
    if [[ -d "$pipx_venv" ]]; then
        cp "$QUICKBOT_ENV_FILE" "$pipx_venv/.env"
        log_success ".env updated in pipx environment"
    else
        log_warn "pipx venv not found, .env copy skipped (QuickBot may still work)"
        log_reportable
    fi
}

# Validate update
validate_update() {
    log_info "Validating update..."
    
    if command -v quick &> /dev/null; then
        if quick help &> /dev/null; then
            log_success "Update validated successfully!"
            return 0
        else
            log_warn "'quick help' command failed, but update may still work"
            log_reportable
        fi
    else
        log_warn "'quick' command not found, update may have failed"
        log_reportable
    fi
}

# Check and update scripts
check_script_updates() {
    if [[ "$UPDATE_SCRIPTS" == "false" ]] && [[ "$FORCE_UPDATE" == "false" ]]; then
        # Only check if explicitly requested or not forcing
        return 0
    fi
    
    log_info "Checking for script updates..."
    
    local scripts_repo="levinismynameirl/QuickBot-Installer"
    
    # Get latest release tag
    local latest_tag
    latest_tag=$(curl -s --connect-timeout 30 \
        "https://api.github.com/repos/$scripts_repo/releases/latest" 2>/dev/null | \
        grep '"tag_name"' | head -1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    
    if [[ -z "$latest_tag" ]]; then
        log_warn "Could not fetch latest installer release tag"
        log_reportable
        return 0
    fi
    
    log_info "Latest installer release: $latest_tag"
    
    # Compare hash of current updater script against the tagged version
    local current_script_hash=""
    local latest_script_hash=""
    
    if [[ -f "$QUICKBOT_HOME/updater.sh" ]]; then
        current_script_hash=$(shasum -a 256 "$QUICKBOT_HOME/updater.sh" | awk '{print $1}')
    fi
    
    local latest_updater
    latest_updater=$(curl -fsSL --connect-timeout 30 \
        "https://raw.githubusercontent.com/$scripts_repo/$latest_tag/updater.sh" 2>/dev/null) || true
    
    if [[ -n "$latest_updater" ]]; then
        latest_script_hash=$(echo "$latest_updater" | shasum -a 256 | awk '{print $1}')
        
        if [[ "$current_script_hash" != "$latest_script_hash" ]]; then
            log_info "Script updates available (release $latest_tag)"
            
            if [[ "$SKIP_CONFIRMATIONS" == "true" ]] || confirm "Update installation scripts to $latest_tag?" "Y"; then
                update_scripts "$latest_tag"
            fi
        else
            log_success "Scripts are up to date ($latest_tag)"
        fi
    else
        log_warn "Could not check for script updates"
        log_reportable
    fi
}

# Update installation scripts from a tagged release
update_scripts() {
    local tag="${1:-}"
    
    log_info "Updating installation scripts to $tag..."
    
    local scripts_repo="levinismynameirl/QuickBot-Installer"
    local scripts_dir="$QUICKBOT_HOME"
    local updated=0
    
    # Backup current scripts
    local backup_dir="$scripts_dir.backup.$(date +%Y%m%d_%H%M%S)"
    cp -r "$scripts_dir" "$backup_dir"
    log_info "Backed up scripts to $backup_dir"
    
    # Update each script from the tagged release
    for script in install.sh updater.sh uninstall.sh brewinstall.sh update-installer.sh; do
        log_info "Updating $script..."
        
        if curl -fsSL --connect-timeout 30 \
            "https://raw.githubusercontent.com/$scripts_repo/$tag/$script" \
            -o "$scripts_dir/$script.new"; then
            
            mv "$scripts_dir/$script.new" "$scripts_dir/$script"
            chmod +x "$scripts_dir/$script"
            log_success "Updated $script"
            updated=$((updated + 1))
        else
            log_warn "Failed to update $script"
            log_reportable
        fi
    done
    
    if [[ $updated -gt 0 ]]; then
        log_success "Updated $updated script(s) to $tag"
        log_to_file "Updated $updated script(s) to $tag"
        log_info "New script versions will take effect on next run."
    else
        log_warn "No scripts were updated"
        log_reportable
    fi
}

# Main update flow
main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║      QuickBot Updater v0.1.0d          ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo -e "${YELLOW}⚠  Development Beta — first public build of QuickBot.${NC}"
    echo -e "${YELLOW}   Config files may change between releases. Back up before updating.${NC}"
    echo ""
    
    log_info "Starting QuickBot update process..."
    log_to_file "Update process started"
    
    # Check installation
    check_installation
    
    # Handle rollback
    if [[ "$ROLLBACK" == "true" ]]; then
        do_rollback
        exit 0
    fi
    
    # If only script update is requested, handle it and exit early
    if [[ "$UPDATE_SCRIPTS" == "true" ]] && [[ "$FORCE_UPDATE" == "false" ]]; then
        check_script_updates
        echo ""
        log_success "Script update check complete."
        exit 0
    fi
    
    # Show dev channel info
    if [[ "$DEV_CHANNEL" == "true" ]]; then
        log_info "Development channel enabled — will check for dev builds (tagged with 'd')"
    fi
    
    # Get latest version
    local latest_version=$(get_latest_version)
    local current_version="${QUICKBOT_VERSION#v}"
    latest_version="${latest_version#v}"
    
    echo ""
    log_info "Current version: $current_version"
    log_info "Latest version:  $latest_version"
    if is_dev_build "$latest_version"; then
        echo -e "                 ${YELLOW}(development build)${NC}"
    fi
    echo ""
    
    # Check if update is needed
    if [[ "$FORCE_UPDATE" == "false" ]]; then
        if [[ "$current_version" == "$latest_version" ]]; then
            log_success "QuickBot is already up to date!"
            
            # Still check for script updates
            check_script_updates
            
            echo ""
            log_info "To force update: $0 --force"
            if [[ "$DEV_CHANNEL" != "true" ]]; then
                log_info "To check for development builds: $0 --development"
            fi
            exit 0
        fi
        
        if version_less_than "$latest_version" "$current_version"; then
            log_warn "Current version ($current_version) is newer than latest release ($latest_version)"
            log_info "You may be using a development version"
            
            if ! confirm "Downgrade to latest stable release?" "N"; then
                log_info "Update cancelled"
                exit 0
            fi
        fi
    fi
    
    # Show dev build disclaimer if updating to a dev version
    if is_dev_build "$latest_version"; then
        show_dev_disclaimer
        if [[ "$SKIP_CONFIRMATIONS" != "true" ]]; then
            if ! confirm "Install development build $latest_version?" "N"; then
                log_info "Update cancelled"
                exit 0
            fi
        fi
    fi
    
    # Confirm update (for non-dev, non-force updates)
    if ! is_dev_build "$latest_version" && [[ "$FORCE_UPDATE" == "false" ]] && [[ "$SKIP_CONFIRMATIONS" == "false" ]]; then
        echo ""
        if ! confirm "QuickBot update available: $current_version → $latest_version. Install?" "Y"; then
            log_info "Update cancelled by user"
            echo ""
            log_info "To skip version check: $0 --force"
            exit 0
        fi
    fi
    
    echo ""
    
    # Save rollback info before updating
    save_rollback_info "$current_version"
    
    # Download and install update
    local package_path=$(download_release "$latest_version")
    update_quickbot "$package_path" "$latest_version"
    
    # Cleanup downloaded package
    rm -f "$package_path"
    
    # Validate
    validate_update
    
    # Check for script updates
    check_script_updates
    
    # Success message
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  QuickBot updated successfully! 🎉     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    log_success "Update complete!"
    echo ""
    echo "Updated: $current_version → $latest_version"
    if is_dev_build "$latest_version"; then
        echo ""
        echo -e "${YELLOW}This is a development build. Config files may change between releases.${NC}"
        echo -e "${YELLOW}Use 'quick update --rollback' to revert to $current_version if needed.${NC}"
    fi
    echo ""

    # Show release notes if available
    if command -v quick &> /dev/null; then
        quick help --release-notes 2>/dev/null || true
    else
        echo "Run 'quick help --release-notes' to see what's new"
    fi
    echo ""
    
    log_to_file "Update completed successfully: $current_version → $latest_version"
}

# Run main update
main "$@"
