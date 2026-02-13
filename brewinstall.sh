#!/usr/bin/env bash

set -euo pipefail

# QuickBot Brew Installer
# Non-interactive installer for Homebrew tap installation
# This script is called by Homebrew during 'brew install' and CANNOT use interactive prompts

# Exit codes for Homebrew
EXIT_SUCCESS=0
EXIT_FAILURE=1

# Color codes for output (Homebrew captures these)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
QUICKBOT_GITHUB_REPO="levinismynameirl/Quick-Bot"
QUICKBOT_HOME="$HOME/.quickbot"
QUICKBOT_CONFIG_BASE="$HOME/.config/.quickbot"
QUICKBOT_DATA_ROOT="$QUICKBOT_CONFIG_BASE/data"
QUICKBOT_SCRIPTS_DIR="$QUICKBOT_HOME"
QUICKBOT_CONFIG_DIR="$QUICKBOT_DATA_ROOT/.config"
QUICKBOT_LOG_DIR="$QUICKBOT_DATA_ROOT/logs"
QUICKBOT_ENV_FILE="$QUICKBOT_HOME/.env"
LOCAL_BIN="$HOME/.local/bin"

# Logging functions (output to STDOUT/STDERR for Homebrew)
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&1
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&1
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&1
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Log to file
log_to_file() {
    local log_file="$QUICKBOT_LOG_DIR/brew-install.log"
    mkdir -p "$QUICKBOT_LOG_DIR" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$log_file" 2>/dev/null || true
}

# Error handler
error_exit() {
    log_error "$1"
    log_to_file "ERROR: $1"
    exit $EXIT_FAILURE
}

# Check if running on macOS
check_macos() {
    log_info "Checking operating system..."
    if [[ "$(uname)" != "Darwin" ]]; then
        error_exit "This installer only supports macOS"
    fi
    log_success "macOS detected"
}

# Check dependencies (Homebrew pre-checks these, but verify anyway)
check_dependencies() {
    log_info "Verifying dependencies..."
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        error_exit "Python 3 not found. Install with: brew install python@3.11"
    fi
    
    local python_version=$(python3 --version 2>&1 | awk '{print $2}')
    local major=$(echo "$python_version" | cut -d. -f1)
    local minor=$(echo "$python_version" | cut -d. -f2)
    
    if [[ "$major" -lt 3 ]] || { [[ "$major" -eq 3 ]] && [[ "$minor" -lt 11 ]]; }; then
        error_exit "Python 3.11+ required, found $python_version"
    fi
    
    # Check pipx
    if ! command -v pipx &> /dev/null; then
        log_warn "pipx not found, installing..."
        if ! brew install pipx; then
            error_exit "Failed to install pipx"
        fi
        pipx ensurepath
    fi
    
    log_success "All dependencies verified"
}

# Get version from pyproject.toml
get_version_from_pyproject() {
    local pyproject_file="$1"
    if [[ -f "$pyproject_file" ]]; then
        grep '^version = ' "$pyproject_file" | sed 's/version = "\(.*\)"/\1/' | tr -d '"'
    else
        echo "0.1.0.dev0"
    fi
}

# Setup directory structure (non-interactive)
setup_directories() {
    log_info "Setting up directory structure..."
    
    # Backup existing scripts dir if present
    if [[ -d "$QUICKBOT_HOME" ]]; then
        local backup_dir="$QUICKBOT_HOME.backup.$(date +%Y%m%d_%H%M%S)"
        log_warn "Existing installation found, creating backup at $backup_dir"
        mv "$QUICKBOT_HOME" "$backup_dir" || error_exit "Failed to backup existing installation"
        log_success "Backup created"
    fi
    
    # Create scripts directory (~/.quickbot/)
    log_info "Setting up scripts at $QUICKBOT_HOME..."
    mkdir -p "$QUICKBOT_HOME" || error_exit "Failed to create scripts directory"
    
    # Copy shell scripts into ~/.quickbot/
    for script in uninstall.sh updater.sh update-installer.sh; do
        if [[ -f "$script" ]]; then
            cp "$script" "$QUICKBOT_HOME/$script"
            chmod +x "$QUICKBOT_HOME/$script"
        fi
    done
    
    # Create data directory structure
    log_info "Creating data directories..."
    mkdir -p "$QUICKBOT_CONFIG_DIR" || error_exit "Failed to create config directory"
    mkdir -p "$QUICKBOT_LOG_DIR" || error_exit "Failed to create log directory"
    mkdir -p "$QUICKBOT_DATA_ROOT/cache" || error_exit "Failed to create cache directory"
    mkdir -p "$QUICKBOT_DATA_ROOT/plugins" || error_exit "Failed to create plugins directory"
    mkdir -p "$QUICKBOT_DATA_ROOT/recipes" || error_exit "Failed to create recipes directory"
    
    log_success "Directory structure created"
}

# Generate .env file
generate_env_file() {
    log_info "Generating .env file..."
    
    local version="0.1.0.dev0"
    if command -v pipx &> /dev/null; then
        local detected_ver=$(pipx list 2>/dev/null | grep -A1 "quickbot" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [[ -n "$detected_ver" ]] && version="$detected_ver"
    fi
    local install_date=$(date '+%Y-%m-%d')
    
    cat > "$QUICKBOT_ENV_FILE" <<EOF || error_exit "Failed to create .env file"
# QuickBot Environment Configuration
# Generated on $install_date via Homebrew

QUICKBOT_SCRIPTS_DIR="$QUICKBOT_SCRIPTS_DIR"
QUICKBOT_DATA_ROOT="$QUICKBOT_DATA_ROOT"
QUICKBOT_GITHUB_REPO="$QUICKBOT_GITHUB_REPO"
QUICKBOT_VERSION="$version"
QUICKBOT_INSTALLED_AT="$install_date"
QUICKBOT_INSTALL_METHOD="brew"
EOF
    
    log_success ".env file created"
    log_to_file "Generated .env file with version $version via Homebrew"
}

# Download latest release from GitHub
download_latest_release() {
    log_info "Fetching latest QuickBot release from GitHub..."
    
    local max_retries=3
    local retry_count=0
    local download_url=""
    local version=""
    
    while [[ $retry_count -lt $max_retries ]]; do
        # Get latest release info
        local release_info=$(curl -s --connect-timeout 30 "https://api.github.com/repos/$QUICKBOT_GITHUB_REPO/releases/latest" 2>&1)
        
        if [[ $? -eq 0 ]]; then
            version=$(echo "$release_info" | grep '"tag_name"' | head -1 | sed 's/.*"v\?\([^"]*\)".*/\1/')
            
            # Try to get wheel file first, then tarball
            download_url=$(echo "$release_info" | grep 'browser_download_url' | grep '\.whl' | head -1 | cut -d'"' -f4)
            
            if [[ -z "$download_url" ]]; then
                download_url=$(echo "$release_info" | grep 'browser_download_url' | grep '\.tar\.gz' | head -1 | cut -d'"' -f4)
            fi
            
            if [[ -n "$download_url" ]] && [[ -n "$version" ]]; then
                break
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log_warn "Failed to fetch release info, retrying... ($retry_count/$max_retries)"
            sleep 2
        fi
    done
    
    if [[ -z "$download_url" ]]; then
        error_exit "Failed to fetch latest release information from GitHub"
    fi
    
    log_info "Latest version: $version"
    
    # Download the release
    local filename=$(basename "$download_url")
    local download_path="/tmp/$filename"
    
    log_info "Downloading $filename..."
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
    
    error_exit "Failed to download QuickBot after $max_retries attempts"
}

# Install QuickBot via pipx (non-interactive)
install_quickbot() {
    local package_path="$1"
    
    log_info "Installing QuickBot via pipx..."
    
    # Install with pipx (no user prompts)
    if pipx install "$package_path" --force > "$QUICKBOT_LOG_DIR/brew-install.log" 2>&1; then
        log_success "QuickBot installed to pipx"
        log_to_file "Installed QuickBot via pipx"
    else
        log_error "pipx installation failed. Log:"
        cat "$QUICKBOT_LOG_DIR/brew-install.log" >&2
        error_exit "Failed to install QuickBot via pipx"
    fi
    
    # Copy .env to pipx venv
    log_info "Copying .env to pipx environment..."
    local pipx_venv="$HOME/.local/pipx/venvs/quickbot"
    
    if [[ -d "$pipx_venv" ]]; then
        cp "$QUICKBOT_ENV_FILE" "$pipx_venv/.env" || log_warn ".env copy failed (QuickBot may still work)"
        log_success ".env copied to pipx environment"
    else
        log_warn "pipx venv not found at expected location"
    fi
}

# Create symlinks
create_symlinks() {
    log_info "Creating command symlinks..."
    
    mkdir -p "$LOCAL_BIN" || error_exit "Failed to create $LOCAL_BIN"
    
    local pipx_bin="$HOME/.local/pipx/venvs/quickbot/bin"
    
    # Create symlink for 'quick'
    if [[ -f "$pipx_bin/quick" ]]; then
        ln -sf "$pipx_bin/quick" "$LOCAL_BIN/quick" || error_exit "Failed to create quick symlink"
        log_success "Created symlink: $LOCAL_BIN/quick"
    else
        log_warn "quick binary not found in pipx venv"
    fi
    
    # Create symlink for 'qw'
    if [[ -f "$pipx_bin/qw" ]]; then
        ln -sf "$pipx_bin/qw" "$LOCAL_BIN/qw" || log_warn "Failed to create qw symlink"
        log_success "Created symlink: $LOCAL_BIN/qw"
    else
        log_warn "qw binary not found (may not be available yet)"
    fi
}

# Add to PATH (non-interactive)
add_to_path() {
    log_info "Checking PATH configuration..."
    
    # Check if LOCAL_BIN is in PATH
    if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
        log_warn "$LOCAL_BIN is not in PATH"
        
        # Determine shell config file
        local shell_config=""
        if [[ "$SHELL" == *"zsh"* ]]; then
            shell_config="$HOME/.zshrc"
        elif [[ "$SHELL" == *"bash"* ]]; then
            shell_config="$HOME/.bashrc"
        fi
        
        if [[ -n "$shell_config" ]]; then
            log_info "Adding $LOCAL_BIN to PATH in $shell_config"
            echo '' >> "$shell_config"
            echo '# QuickBot - Added by Homebrew installer' >> "$shell_config"
            echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$shell_config"
            log_success "PATH updated in $shell_config"
        else
            log_warn "Could not determine shell config file"
        fi
    else
        log_success "$LOCAL_BIN is already in PATH"
    fi
}

# Validate installation
validate_installation() {
    log_info "Validating installation..."
    
    # Check if quick command exists
    if command -v quick &> /dev/null; then
        log_info "Testing 'quick help' command..."
        if timeout 5 quick help &> /dev/null; then
            log_success "Installation validated successfully!"
            return 0
        else
            log_warn "'quick help' command failed, but installation may still work"
        fi
    else
        log_warn "'quick' command not found in PATH yet"
        log_info "You may need to restart your shell"
    fi
}

# Main installation flow
main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  QuickBot Brew Installer v0.1.0.dev0  ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo -e "${YELLOW}⚠  Development Beta — first public build of QuickBot.${NC}"
    echo -e "${YELLOW}   Things may break. Report issues at:${NC}"
    echo -e "${YELLOW}   https://github.com/levinismynameirl/Quick-Bot/issues${NC}"
    echo ""
    
    log_info "Starting QuickBot installation via Homebrew..."
    log_to_file "Homebrew installation started"
    
    # System checks
    check_macos
    check_dependencies
    
    # Setup
    setup_directories
    generate_env_file
    
    # Download and install
    local package_path=$(download_latest_release)
    install_quickbot "$package_path"
    
    # Cleanup downloaded package
    rm -f "$package_path"
    
    # Finalize
    create_symlinks
    add_to_path
    validate_installation
    
    # Success message
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  QuickBot installed successfully! 🎉   ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    log_success "Installation complete!"
    echo ""
    echo -e "${YELLOW}⚠  Development Beta (v0.1.0.dev0) — first public build of QuickBot.${NC}"
    echo -e "${YELLOW}   Features may be incomplete. Config files may change between releases.${NC}"
    echo -e "${YELLOW}   Things may break. Please report issues at:${NC}"
    echo -e "${YELLOW}   https://github.com/levinismynameirl/Quick-Bot/issues${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Restart your terminal or run: source ~/.zshrc"
    echo "  2. Type 'quick help' to get started"
    echo ""
    echo "Update: brew upgrade quickbot"
    echo "Uninstall: brew uninstall quickbot"
    echo "           or: ~/.quickbot/uninstall.sh"
    echo ""
    
    log_to_file "Homebrew installation completed successfully"
    
    exit $EXIT_SUCCESS
}

# Run main installation
main "$@"
