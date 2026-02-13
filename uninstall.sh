#!/usr/bin/env bash

set -euo pipefail

# QuickBot Uninstaller
# Completely removes QuickBot from the system

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
LOCAL_BIN="$HOME/.local/bin"

# Flags
FORCE_UNINSTALL=false
KEEP_CONFIG=false
SKIP_CONFIRMATIONS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_UNINSTALL=true
            SKIP_CONFIRMATIONS=true
            shift
            ;;
        --keep-config)
            KEEP_CONFIG=true
            shift
            ;;
        --yes)
            SKIP_CONFIRMATIONS=true
            shift
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unknown option: $1"
            echo "Usage: $0 [--force] [--keep-config] [--yes]"
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
    log_info "Checking for QuickBot installation..."
    
    if [[ ! -f "$QUICKBOT_ENV_FILE" ]] && [[ ! -d "$QUICKBOT_HOME" ]]; then
        log_error "QuickBot does not appear to be installed"
        log_info "Checked for: $QUICKBOT_ENV_FILE"
        
        # Check if pipx has quickbot
        if command -v pipx &> /dev/null && pipx list | grep -q "quickbot"; then
            log_warn "Found QuickBot in pipx, but installation directory missing"
            log_info "Will attempt to remove pipx installation only"
            return 0
        fi
        
        exit 1
    fi
    
    log_success "QuickBot installation found"
    
    # Display installation info
    if [[ -f "$QUICKBOT_ENV_FILE" ]]; then
        echo ""
        log_info "Installation details:"
        source "$QUICKBOT_ENV_FILE" 2>/dev/null || true
        if [[ -n "${QUICKBOT_VERSION:-}" ]]; then
            echo "  Version: $QUICKBOT_VERSION"
        fi
        if [[ -n "${QUICKBOT_INSTALLED_AT:-}" ]]; then
            echo "  Installed: $QUICKBOT_INSTALLED_AT"
        fi
        if [[ -n "${QUICKBOT_INSTALL_METHOD:-}" ]]; then
            echo "  Method: $QUICKBOT_INSTALL_METHOD"
        fi
        echo ""
    fi
}

# Confirm uninstallation
confirm_uninstall() {
    if [[ "$FORCE_UNINSTALL" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warn "This will remove QuickBot completely from your system"
    echo ""
    
    if ! confirm "Are you sure you want to uninstall QuickBot?" "N"; then
        log_info "Uninstallation cancelled by user"
        exit 0
    fi
    
    # Ask about config files if not already specified
    if [[ "$KEEP_CONFIG" == "false" ]] && [[ -d "$QUICKBOT_CONFIG_BASE" ]]; then
        echo ""
        if confirm "Delete configuration files too?" "N"; then
            KEEP_CONFIG=false
        else
            KEEP_CONFIG=true
        fi
    fi
    
    echo ""
    if ! confirm "Final confirmation: Proceed with uninstallation?" "N"; then
        log_info "Uninstallation cancelled by user"
        exit 0
    fi
    
    echo ""
}

# Remove pipx installation
remove_pipx_installation() {
    log_info "Removing QuickBot from pipx..."
    
    if command -v pipx &> /dev/null; then
        if pipx list 2>/dev/null | grep -q "quickbot"; then
            if pipx uninstall quickbot; then
                log_success "Removed QuickBot from pipx"
            else
                log_warn "Failed to remove QuickBot from pipx (may already be uninstalled)"
            fi
        else
            log_info "QuickBot not found in pipx"
        fi
    else
        log_info "pipx not found, skipping pipx uninstallation"
    fi
}

# Remove symlinks
remove_symlinks() {
    log_info "Removing command symlinks..."
    
    local removed=0
    
    if [[ -L "$LOCAL_BIN/quick" ]] || [[ -f "$LOCAL_BIN/quick" ]]; then
        rm -f "$LOCAL_BIN/quick"
        log_success "Removed: $LOCAL_BIN/quick"
        removed=$((removed + 1))
    fi
    
    if [[ -L "$LOCAL_BIN/qw" ]] || [[ -f "$LOCAL_BIN/qw" ]]; then
        rm -f "$LOCAL_BIN/qw"
        log_success "Removed: $LOCAL_BIN/qw"
        removed=$((removed + 1))
    fi
    
    if [[ $removed -eq 0 ]]; then
        log_info "No symlinks found to remove"
    fi
}

# Remove configuration files
remove_config_files() {
    if [[ "$KEEP_CONFIG" == "true" ]]; then
        log_info "Keeping configuration files at: $QUICKBOT_CONFIG_BASE"
        return 0
    fi
    
    log_info "Removing configuration files..."
    
    if [[ -d "$QUICKBOT_CONFIG_BASE" ]]; then
        rm -rf "$QUICKBOT_CONFIG_BASE"
        log_success "Removed configuration directory: $QUICKBOT_CONFIG_BASE"
    else
        log_info "No configuration directory found"
    fi
}

# Remove QuickBot directory
remove_quickbot_directory() {
    log_info "Removing QuickBot directory..."
    
    if [[ -d "$QUICKBOT_HOME" ]]; then
        # Ask if user wants to keep scripts for reference
        if [[ "$FORCE_UNINSTALL" == "false" ]] && [[ "$SKIP_CONFIRMATIONS" == "false" ]]; then
            if confirm "Keep installation scripts in $QUICKBOT_HOME for reference?" "N"; then
                log_info "Keeping $QUICKBOT_HOME directory"
                return 0
            fi
        fi
        
        rm -rf "$QUICKBOT_HOME"
        log_success "Removed QuickBot directory: $QUICKBOT_HOME"
    else
        log_info "No QuickBot directory found"
    fi
}

# Clean up PATH modifications
cleanup_path() {
    log_info "Checking for PATH modifications..."
    
    local cleaned=false
    
    # Check zshrc
    if [[ -f "$HOME/.zshrc" ]]; then
        if grep -q "# QuickBot - Added by installer" "$HOME/.zshrc"; then
            log_info "Found QuickBot PATH entry in ~/.zshrc"
            
            if [[ "$SKIP_CONFIRMATIONS" == "true" ]] || confirm "Remove QuickBot PATH entry from ~/.zshrc?" "Y"; then
                # Remove the QuickBot section
                sed -i.bak '/# QuickBot - Added by installer/d' "$HOME/.zshrc"
                sed -i.bak '/export PATH="\$HOME\/.local\/bin:\$PATH"/d' "$HOME/.zshrc"
                log_success "Removed PATH entry from ~/.zshrc"
                cleaned=true
            fi
        fi
    fi
    
    # Check bashrc
    if [[ -f "$HOME/.bashrc" ]]; then
        if grep -q "# QuickBot - Added by installer" "$HOME/.bashrc"; then
            log_info "Found QuickBot PATH entry in ~/.bashrc"
            
            if [[ "$SKIP_CONFIRMATIONS" == "true" ]] || confirm "Remove QuickBot PATH entry from ~/.bashrc?" "Y"; then
                # Remove the QuickBot section
                sed -i.bak '/# QuickBot - Added by installer/d' "$HOME/.bashrc"
                sed -i.bak '/export PATH="\$HOME\/.local\/bin:\$PATH"/d' "$HOME/.bashrc"
                log_success "Removed PATH entry from ~/.bashrc"
                cleaned=true
            fi
        fi
    fi
    
    if [[ "$cleaned" == "true" ]]; then
        log_warn "Shell configuration updated. Restart your terminal for changes to take effect"
    else
        log_info "No PATH modifications found"
    fi
}

# Main uninstallation flow
main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║      QuickBot Uninstaller v0.1.0d      ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo -e "${YELLOW}⚠  Development Beta — this will remove QuickBot v0.1.0d.${NC}"
    echo ""
    
    check_installation
    confirm_uninstall
    
    log_info "Starting QuickBot uninstallation..."
    echo ""
    
    # Remove components
    remove_pipx_installation
    remove_symlinks
    remove_config_files
    remove_quickbot_directory
    cleanup_path
    
    # Success message
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  QuickBot uninstalled successfully! 👋  ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    log_success "Uninstallation complete!"
    echo ""
    
    if [[ "$KEEP_CONFIG" == "true" ]]; then
        echo "Configuration files preserved at:"
        echo "  $QUICKBOT_CONFIG_BASE"
        echo ""
        echo "To remove them later:"
        echo "  rm -rf $QUICKBOT_CONFIG_BASE"
        echo ""
    fi
    
    if [[ -d "$QUICKBOT_HOME" ]]; then
        echo "Installation scripts preserved at:"
        echo "  $QUICKBOT_HOME"
        echo ""
        echo "To remove them:"
        echo "  rm -rf $QUICKBOT_HOME"
        echo ""
    fi
    
    echo "Thank you for using QuickBot!"
    echo "To reinstall: https://github.com/levinismynameirl/QuickBot-Installer"
    echo ""
}

# Run main uninstallation
main "$@"
