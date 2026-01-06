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
QUICKBOT_HOME="$HOME/.quickbotScripts"
QUICKBOT_ENV_FILE="$QUICKBOT_HOME/quickbot/.env"
QUICKBOT_LOG_DIR="$QUICKBOT_HOME/quickbot/logs"
LOCAL_BIN="$HOME/.local/bin"

# Flags
FORCE_UPDATE=false
UPDATE_SCRIPTS=false
SKIP_CONFIRMATIONS=false

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
        *)
            echo -e "${RED}[ERROR]${NC} Unknown option: $1"
            echo "Usage: $0 [--force] [--update-scripts] [--yes]"
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
        echo "  https://github.com/levinismynameirl/QuickBot-Installers"
        exit 1
    fi
    
    # Source the .env file
    source "$QUICKBOT_ENV_FILE"
    
    if [[ -z "${QUICKBOT_VERSION:-}" ]]; then
        log_warn "Could not determine current version"
        QUICKBOT_VERSION="unknown"
    fi
    
    if [[ -z "${QUICKBOT_GITHUB_REPO:-}" ]]; then
        log_warn "GitHub repository not specified in .env, using default"
        QUICKBOT_GITHUB_REPO="levinismynameirl/Quick-Bot"
    fi
    
    log_success "QuickBot installation found (version: $QUICKBOT_VERSION)"
}

# Compare versions (returns 0 if v1 < v2, 1 otherwise)
version_less_than() {
    local v1="$1"
    local v2="$2"
    
    # Remove 'v' prefix if present
    v1="${v1#v}"
    v2="${v2#v}"
    
    # Simple lexicographic comparison
    if [[ "$v1" == "$v2" ]]; then
        return 1
    fi
    
    # Use sort -V for version comparison
    local sorted=$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -n1)
    
    if [[ "$sorted" == "$v1" ]]; then
        return 0
    else
        return 1
    fi
}

# Get latest release version from GitHub
get_latest_version() {
    log_info "Checking for latest version on GitHub..."
    
    local max_retries=3
    local retry_count=0
    local latest_version=""
    
    while [[ $retry_count -lt $max_retries ]]; do
        latest_version=$(curl -s --connect-timeout 30 "https://api.github.com/repos/$QUICKBOT_GITHUB_REPO/releases/latest" 2>&1 | \
            grep '"tag_name"' | head -1 | sed 's/.*"v\?\([^"]*\)".*/\1/')
        
        if [[ -n "$latest_version" ]]; then
            echo "$latest_version"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log_warn "Failed to fetch version, retrying... ($retry_count/$max_retries)"
            sleep 2
        fi
    done
    
    log_error "Failed to fetch latest version from GitHub"
    exit 1
}

# Download latest release
download_latest_release() {
    local version="$1"
    
    log_info "Downloading QuickBot $version..."
    
    local max_retries=3
    local retry_count=0
    local download_url=""
    
    while [[ $retry_count -lt $max_retries ]]; do
        local release_info=$(curl -s --connect-timeout 30 "https://api.github.com/repos/$QUICKBOT_GITHUB_REPO/releases/latest" 2>&1)
        
        if [[ $? -eq 0 ]]; then
            # Try to get wheel file first, then tarball
            download_url=$(echo "$release_info" | grep 'browser_download_url' | grep '\.whl' | head -1 | cut -d'"' -f4)
            
            if [[ -z "$download_url" ]]; then
                download_url=$(echo "$release_info" | grep 'browser_download_url' | grep '\.tar\.gz' | head -1 | cut -d'"' -f4)
            fi
            
            if [[ -n "$download_url" ]]; then
                break
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log_warn "Failed to fetch download URL, retrying... ($retry_count/$max_retries)"
            sleep 2
        fi
    done
    
    if [[ -z "$download_url" ]]; then
        log_error "Failed to get download URL from GitHub"
        exit 1
    fi
    
    # Download the release
    local filename=$(basename "$download_url")
    local download_path="/tmp/$filename"
    
    retry_count=0
    while [[ $retry_count -lt $max_retries ]]; do
        if curl -fL --progress-bar --connect-timeout 30 "$download_url" -o "$download_path"; then
            log_success "Downloaded successfully"
            echo "$download_path"
            log_to_file "Downloaded QuickBot $version from $download_url"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log_warn "Download failed, retrying... ($retry_count/$max_retries)"
            sleep 2
        fi
    done
    
    log_error "Failed to download QuickBot after $max_retries attempts"
    exit 1
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
        fi
    else
        log_warn "'quick' command not found, update may have failed"
    fi
}

# Check and update scripts
check_script_updates() {
    if [[ "$UPDATE_SCRIPTS" == "false" ]] && [[ "$FORCE_UPDATE" == "false" ]]; then
        # Only check if explicitly requested or not forcing
        return 0
    fi
    
    log_info "Checking for script updates..."
    
    # Get the latest commit hash for scripts from GitHub
    local scripts_repo="levinismynameirl/QuickBot-Installers"
    local current_script_hash=""
    local latest_script_hash=""
    
    # Calculate hash of current updater script
    if [[ -f "$QUICKBOT_HOME/quickbot/scripts/updater.sh" ]]; then
        current_script_hash=$(shasum -a 256 "$QUICKBOT_HOME/quickbot/scripts/updater.sh" | awk '{print $1}')
    fi
    
    # Try to get latest updater script hash from GitHub
    local latest_updater=$(curl -s --connect-timeout 30 \
        "https://raw.githubusercontent.com/$scripts_repo/main/updater.sh" 2>&1)
    
    if [[ -n "$latest_updater" ]]; then
        latest_script_hash=$(echo "$latest_updater" | shasum -a 256 | awk '{print $1}')
        
        if [[ "$current_script_hash" != "$latest_script_hash" ]]; then
            log_info "Script updates available"
            
            if [[ "$SKIP_CONFIRMATIONS" == "true" ]] || confirm "Update installation scripts?" "Y"; then
                update_scripts
            fi
        else
            log_success "Scripts are up to date"
        fi
    else
        log_warn "Could not check for script updates"
    fi
}

# Update installation scripts
update_scripts() {
    log_info "Updating installation scripts..."
    
    local scripts_repo="levinismynameirl/QuickBot-Installers"
    local scripts_dir="$QUICKBOT_HOME/quickbot/scripts"
    local updated=0
    
    # Backup current scripts
    local backup_dir="$scripts_dir.backup.$(date +%Y%m%d_%H%M%S)"
    cp -r "$scripts_dir" "$backup_dir"
    log_info "Backed up scripts to $backup_dir"
    
    # Update each script
    for script in installer.sh updater.sh uninstall.sh brewinstall.sh; do
        log_info "Updating $script..."
        
        if curl -fsSL --connect-timeout 30 \
            "https://raw.githubusercontent.com/$scripts_repo/main/$script" \
            -o "$scripts_dir/$script.new"; then
            
            mv "$scripts_dir/$script.new" "$scripts_dir/$script"
            chmod +x "$scripts_dir/$script"
            log_success "Updated $script"
            updated=$((updated + 1))
        else
            log_warn "Failed to update $script"
        fi
    done
    
    if [[ $updated -gt 0 ]]; then
        log_success "Updated $updated script(s)"
        
        # If updater was updated, re-exec it
        if [[ -f "$scripts_dir/updater.sh.new" ]] || [[ $updated -gt 0 ]]; then
            log_info "Restarting updater with new version..."
            exec bash "$scripts_dir/updater.sh" "$@"
        fi
    else
        log_warn "No scripts were updated"
    fi
}

# Main update flow
main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║      QuickBot Updater v1.0.0           ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    log_info "Starting QuickBot update process..."
    log_to_file "Update process started"
    
    # Check installation
    check_installation
    
    # Get latest version
    local latest_version=$(get_latest_version)
    local current_version="${QUICKBOT_VERSION#v}"
    latest_version="${latest_version#v}"
    
    echo ""
    log_info "Current version: $current_version"
    log_info "Latest version:  $latest_version"
    echo ""
    
    # Check if update is needed
    if [[ "$FORCE_UPDATE" == "false" ]]; then
        if [[ "$current_version" == "$latest_version" ]]; then
            log_success "QuickBot is already up to date!"
            
            # Still check for script updates
            check_script_updates
            
            echo ""
            log_info "To force update: $0 --force"
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
    
    # Confirm update
    if [[ "$FORCE_UPDATE" == "false" ]] && [[ "$SKIP_CONFIRMATIONS" == "false" ]]; then
        echo ""
        if ! confirm "QuickBot update available: $current_version → $latest_version. Install?" "Y"; then
            log_info "Update cancelled by user"
            echo ""
            log_info "To skip version check: $0 --force"
            exit 0
        fi
    fi
    
    echo ""
    
    # Download and install update
    local package_path=$(download_latest_release "$latest_version")
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
    echo ""
    echo "Use 'quick help' to see what's new"
    echo ""
    
    log_to_file "Update completed successfully: $current_version → $latest_version"
}

# Run main update
main "$@"
