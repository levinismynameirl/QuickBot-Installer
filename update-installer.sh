#!/usr/bin/env bash

set -euo pipefail

# QuickBot Installer Updater
# Updates the installer scripts (install.sh, updater.sh, uninstall.sh, brewinstall.sh)
# stored in ~/.quickbot/ to the latest versions from GitHub.

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPTS_REPO="levinismynameirl/QuickBot-Installer"
QUICKBOT_HOME="$HOME/.quickbot"
QUICKBOT_CONFIG_BASE="$HOME/.config/.quickbot"
QUICKBOT_DATA_ROOT="$QUICKBOT_CONFIG_BASE/data"
QUICKBOT_LOG_DIR="$QUICKBOT_DATA_ROOT/logs"
QUICKBOT_ENV_FILE="$QUICKBOT_HOME/.env"

# Scripts to update
MANAGED_SCRIPTS=("install.sh" "updater.sh" "uninstall.sh" "brewinstall.sh" "update-installer.sh")

# Flags
FORCE_UPDATE=false
SKIP_CONFIRMATIONS=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_UPDATE=true
            shift
            ;;
        --yes)
            SKIP_CONFIRMATIONS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "QuickBot Installer Updater"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force       Force update even if scripts are up to date"
            echo "  --yes         Skip all confirmations"
            echo "  --dry-run     Check for updates without applying them"
            echo "  --help, -h    Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unknown option: $1"
            echo "Usage: $0 [--force] [--yes] [--dry-run]"
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
    local log_file="$QUICKBOT_LOG_DIR/update-installer.log"
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

    if [[ ! -d "$QUICKBOT_HOME" ]]; then
        log_error "QuickBot is not installed (missing $QUICKBOT_HOME)"
        log_info "Install QuickBot first: https://github.com/$SCRIPTS_REPO"
        exit 1
    fi

    log_success "QuickBot installation found at $QUICKBOT_HOME"
}

# Check connectivity to GitHub
check_connectivity() {
    log_info "Checking GitHub connectivity..."

    if ! curl -s --connect-timeout 10 "https://api.github.com" &>/dev/null; then
        log_error "Cannot reach GitHub. Check your internet connection."
        exit 1
    fi

    log_success "GitHub is reachable"
}

# Get the latest release tag from GitHub
LATEST_TAG=""
get_latest_tag() {
    if [[ -n "$LATEST_TAG" ]]; then
        echo "$LATEST_TAG"
        return
    fi

    local tag
    tag=$(curl -s --connect-timeout 30 \
        "https://api.github.com/repos/$SCRIPTS_REPO/releases/latest" 2>/dev/null | \
        grep '"tag_name"' | head -1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    if [[ -z "$tag" ]]; then
        log_error "Could not determine latest release tag from $SCRIPTS_REPO"
        exit 1
    fi

    LATEST_TAG="$tag"
    echo "$tag"
}

# Get the local hash of a script
get_local_hash() {
    local script="$1"
    local script_path="$QUICKBOT_HOME/$script"

    if [[ -f "$script_path" ]]; then
        shasum -a 256 "$script_path" | awk '{print $1}'
    else
        echo "missing"
    fi
}

# Get the remote hash of a script from the latest release tag
get_remote_hash() {
    local script="$1"
    local tag
    tag=$(get_latest_tag)
    local content

    content=$(curl -fsSL --connect-timeout 30 \
        "https://raw.githubusercontent.com/$SCRIPTS_REPO/$tag/$script" 2>/dev/null) || {
        echo "fetch_failed"
        return
    }

    echo "$content" | shasum -a 256 | awk '{print $1}'
}

# Download a script from the latest release tag
download_script() {
    local script="$1"
    local dest="$2"
    local tag
    tag=$(get_latest_tag)

    if curl -fsSL --connect-timeout 30 \
        "https://raw.githubusercontent.com/$SCRIPTS_REPO/$tag/$script" \
        -o "$dest"; then
        chmod +x "$dest"
        return 0
    else
        return 1
    fi
}

# Check which scripts need updates
check_for_updates() {
    log_info "Checking for installer script updates..."

    local updates_available=()
    local new_scripts=()

    for script in "${MANAGED_SCRIPTS[@]}"; do
        local local_hash
        local remote_hash

        local_hash=$(get_local_hash "$script")
        remote_hash=$(get_remote_hash "$script")

        if [[ "$remote_hash" == "fetch_failed" ]]; then
            log_warn "Could not fetch remote version of $script"
            continue
        fi

        if [[ "$local_hash" == "missing" ]]; then
            new_scripts+=("$script")
            log_info "  NEW: $script (not installed locally)"
        elif [[ "$local_hash" != "$remote_hash" ]]; then
            updates_available+=("$script")
            log_info "  UPDATE: $script (changed)"
        else
            log_success "  OK: $script (up to date)"
        fi
    done

    # Export results via global vars
    SCRIPTS_TO_UPDATE=("${updates_available[@]}" "${new_scripts[@]}")
    SCRIPTS_NEW=("${new_scripts[@]}")
}

# Create backup of current scripts
create_backup() {
    local backup_dir="$QUICKBOT_HOME/.backup.$(date +%Y%m%d_%H%M%S)"

    log_info "Backing up current scripts to $backup_dir..."
    mkdir -p "$backup_dir"

    for script in "${MANAGED_SCRIPTS[@]}"; do
        if [[ -f "$QUICKBOT_HOME/$script" ]]; then
            cp "$QUICKBOT_HOME/$script" "$backup_dir/$script"
        fi
    done

    log_success "Backup created"
    echo "$backup_dir"
}

# Apply updates
apply_updates() {
    local updated=0
    local failed=0

    for script in "${SCRIPTS_TO_UPDATE[@]}"; do
        log_info "Updating $script..."

        local temp_file="$QUICKBOT_HOME/$script.new"

        if download_script "$script" "$temp_file"; then
            mv "$temp_file" "$QUICKBOT_HOME/$script"
            chmod +x "$QUICKBOT_HOME/$script"
            log_success "Updated $script"
            log_to_file "Updated $script from $SCRIPTS_REPO @ $(get_latest_tag)"
            updated=$((updated + 1))
        else
            log_error "Failed to update $script"
            rm -f "$temp_file"
            failed=$((failed + 1))
        fi
    done

    echo ""
    if [[ $updated -gt 0 ]]; then
        log_success "Updated $updated script(s)"
    fi
    if [[ $failed -gt 0 ]]; then
        log_warn "Failed to update $failed script(s)"
    fi
}

# Rollback from backup
rollback() {
    local backup_dir="$1"

    if [[ -d "$backup_dir" ]]; then
        log_warn "Rolling back to backup..."
        for script in "${MANAGED_SCRIPTS[@]}"; do
            if [[ -f "$backup_dir/$script" ]]; then
                cp "$backup_dir/$script" "$QUICKBOT_HOME/$script"
                chmod +x "$QUICKBOT_HOME/$script"
            fi
        done
        log_success "Rollback complete"
    else
        log_error "Backup directory not found, cannot rollback"
    fi
}

# Cleanup old backups (keep last 3)
cleanup_old_backups() {
    local backup_dirs
    backup_dirs=$(find "$QUICKBOT_HOME" -maxdepth 1 -name ".backup.*" -type d 2>/dev/null | sort -r | tail -n +4)

    if [[ -n "$backup_dirs" ]]; then
        log_info "Cleaning up old backups..."
        echo "$backup_dirs" | while IFS= read -r dir; do
            rm -rf "$dir"
        done
        log_success "Old backups cleaned up"
    fi
}

# Main flow
main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║   QuickBot Installer Updater v0.1.0d   ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo -e "${YELLOW}⚠  Development Beta — first public build of QuickBot.${NC}"
    echo ""

    log_info "Checking for installer script updates..."
    log_to_file "Installer update check started"

    # Preflight checks
    check_installation
    check_connectivity

    # Resolve latest release tag
    local tag
    tag=$(get_latest_tag)
    log_info "Latest installer release: $tag"

    echo ""

    # Initialise arrays
    SCRIPTS_TO_UPDATE=()
    SCRIPTS_NEW=()

    # Check what needs updating
    check_for_updates

    echo ""

    # Nothing to do?
    if [[ ${#SCRIPTS_TO_UPDATE[@]} -eq 0 ]] && [[ "$FORCE_UPDATE" == "false" ]]; then
        log_success "All installer scripts are up to date!"
        log_to_file "No updates needed"
        cleanup_old_backups
        exit 0
    fi

    # Force mode: re-download everything
    if [[ "$FORCE_UPDATE" == "true" ]] && [[ ${#SCRIPTS_TO_UPDATE[@]} -eq 0 ]]; then
        log_info "Force mode: re-downloading all scripts"
        SCRIPTS_TO_UPDATE=("${MANAGED_SCRIPTS[@]}")
    fi

    # Dry run?
    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        log_info "Dry run — the following scripts would be updated:"
        for script in "${SCRIPTS_TO_UPDATE[@]}"; do
            echo "  - $script"
        done
        exit 0
    fi

    # Confirm
    echo ""
    log_info "The following scripts will be updated:"
    for script in "${SCRIPTS_TO_UPDATE[@]}"; do
        echo "  - $script"
    done
    echo ""

    if ! confirm "Proceed with update?" "Y"; then
        log_info "Update cancelled by user"
        exit 0
    fi

    echo ""

    # Backup, then apply
    local backup_dir
    backup_dir=$(create_backup)

    apply_updates

    # Cleanup old backups
    cleanup_old_backups

    # Done
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  Installer scripts updated! ✅          ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    log_info "Backup saved at: $backup_dir"
    log_info "To rollback: cp $backup_dir/* $QUICKBOT_HOME/"
    echo ""

    log_to_file "Installer scripts updated successfully"
}

# Run
main "$@"
