#!/usr/bin/env bash

set -euo pipefail

# QuickBot Installer
# Installs QuickBot and its dependencies on macOS

# Color codes for output
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

# Flags
SKIP_CONFIRMATIONS=false
NO_CONFIRM=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --yes)
            SKIP_CONFIRMATIONS=true
            shift
            ;;
        --no-confirm)
            NO_CONFIRM=true
            SKIP_CONFIRMATIONS=true
            shift
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unknown option: $1"
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

# Log to file
log_to_file() {
    local log_file="$QUICKBOT_LOG_DIR/install.log"
    mkdir -p "$QUICKBOT_LOG_DIR" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$log_file" 2>/dev/null || true
}

# Check if running on macOS
check_macos() {
    log_info "Checking operating system..."
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This installer only supports macOS."
        exit 1
    fi
    log_success "macOS detected"
}

# Check and install Homebrew
check_homebrew() {
    log_info "Checking for Homebrew..."
    
    if command -v brew &> /dev/null; then
        log_success "Homebrew is already installed"
        return 0
    fi
    
    log_warn "Homebrew is not installed"
    
    if confirm "Install Homebrew?" "Y"; then
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add Homebrew to PATH for Apple Silicon Macs
        if [[ -f "/opt/homebrew/bin/brew" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        
        if command -v brew &> /dev/null; then
            log_success "Homebrew installed successfully"
        else
            log_error "Failed to install Homebrew"
            exit 1
        fi
    else
        log_error "Homebrew is required for installation"
        exit 1
    fi
}

# Check Python version
check_python() {
    log_info "Checking for Python 3.11+..."
    
    local python_cmd=""
    local python_version=""
    
    # Check for python3
    if command -v python3 &> /dev/null; then
        python_cmd="python3"
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
    elif command -v python &> /dev/null; then
        python_cmd="python"
        python_version=$(python --version 2>&1 | awk '{print $2}')
    fi
    
    if [[ -n "$python_cmd" ]]; then
        # Extract major and minor version
        local major=$(echo "$python_version" | cut -d. -f1)
        local minor=$(echo "$python_version" | cut -d. -f2)
        
        if [[ "$major" -ge 3 ]] && [[ "$minor" -ge 11 ]]; then
            log_success "Python $python_version found"
            return 0
        else
            log_warn "Python $python_version found, but 3.11+ is required"
        fi
    else
        log_warn "Python not found"
    fi
    
    if confirm "Install Python 3.11+?" "Y"; then
        log_info "Installing Python via Homebrew..."
        brew install python@3.11
        log_success "Python installed successfully"
    else
        log_error "Python 3.11+ is required for QuickBot"
        exit 1
    fi
}

# Check and install pipx
check_pipx() {
    log_info "Checking for pipx..."
    
    if command -v pipx &> /dev/null; then
        log_success "pipx is already installed"
        return 0
    fi
    
    log_warn "pipx is not installed"
    
    if confirm "Install pipx?" "Y"; then
        log_info "Installing pipx via Homebrew..."
        brew install pipx
        pipx ensurepath
        log_success "pipx installed successfully"
    else
        log_error "pipx is required for QuickBot installation"
        exit 1
    fi
}

# Get version from pyproject.toml
get_version_from_pyproject() {
    local pyproject_file="$1"
    if [[ -f "$pyproject_file" ]]; then
        grep '^version = ' "$pyproject_file" | sed 's/version = "\(.*\)"/\1/' | tr -d '"'
    else
        echo "0.1.0d"
    fi
}

# Backup existing installation
backup_existing() {
    if [[ -d "$QUICKBOT_HOME" ]]; then
        log_warn "Existing QuickBot installation found at $QUICKBOT_HOME"
        
        if confirm "Backup and replace existing installation?" "Y"; then
            local backup_dir="$QUICKBOT_HOME.backup.$(date +%Y%m%d_%H%M%S)"
            log_info "Creating backup at $backup_dir"
            mv "$QUICKBOT_HOME" "$backup_dir"
            log_success "Backup created successfully"
            echo "$backup_dir" > /tmp/quickbot_backup_path
        else
            log_error "Installation cancelled by user"
            exit 1
        fi
    fi
}

# Setup directory structure
setup_directories() {
    log_info "Setting up directory structure..."
    
    # Check if we're in the installer directory by looking for all required files
    local has_all_files=true
    for required_file in uninstall.sh updater.sh pyproject.toml; do
        if [[ ! -f "$required_file" ]]; then
            has_all_files=false
            break
        fi
    done
    
    # If we don't have all files, we're running from curl | bash
    if [[ "$has_all_files" == "false" ]]; then
        log_info "Downloading installer files..."
        local temp_dir=$(mktemp -d)
        cd "$temp_dir"
        
        if ! curl -fsSL "https://github.com/levinismynameirl/QuickBot-Installer/archive/main.zip" -o installer.zip; then
            log_error "Failed to download installer files"
            exit 1
        fi
        
        unzip -q installer.zip
        cd QuickBot-Installer-main 2>/dev/null || cd quickbot-installer-main 2>/dev/null || {
            log_error "Failed to extract installer files"
            exit 1
        }
        log_success "Downloaded installer files"
    fi
    
    # Backup existing scripts dir if present
    backup_existing
    
    # Create scripts directory (~/.quickbot/)
    log_info "Setting up scripts directory at $QUICKBOT_HOME..."
    mkdir -p "$QUICKBOT_HOME"
    
    # Copy shell scripts into ~/.quickbot/
    log_info "Installing scripts..."
    for script in uninstall.sh updater.sh update-installer.sh; do
        if [[ -f "$script" ]]; then
            cp "$script" "$QUICKBOT_HOME/$script"
            chmod +x "$QUICKBOT_HOME/$script"
        fi
    done
    
    # Create data directory structure (~/.config/.quickbot/data/...)
    log_info "Creating data directories..."
    mkdir -p "$QUICKBOT_CONFIG_DIR"
    mkdir -p "$QUICKBOT_LOG_DIR"
    mkdir -p "$QUICKBOT_DATA_ROOT/cache"
    mkdir -p "$QUICKBOT_DATA_ROOT/plugins"
    mkdir -p "$QUICKBOT_DATA_ROOT/recipes"
    
    log_success "Directory structure created"
}

# Generate .env file
generate_env_file() {
    log_info "Generating .env file..."
    
    local version="0.1.0d"
    # Try to detect version from installed package
    if command -v pipx &> /dev/null; then
        local detected_ver=$(pipx list 2>/dev/null | grep -A1 "quickbot" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [[ -n "$detected_ver" ]] && version="$detected_ver"
    fi
    local install_date=$(date '+%Y-%m-%d')
    
    cat > "$QUICKBOT_ENV_FILE" <<EOF
# QuickBot Environment Configuration
# Generated on $install_date

QUICKBOT_SCRIPTS_DIR="$QUICKBOT_SCRIPTS_DIR"
QUICKBOT_DATA_ROOT="$QUICKBOT_DATA_ROOT"
QUICKBOT_GITHUB_REPO="$QUICKBOT_GITHUB_REPO"
QUICKBOT_VERSION="$version"
QUICKBOT_INSTALLED_AT="$install_date"
QUICKBOT_INSTALL_METHOD="installer"
EOF
    
    log_success ".env file created at $QUICKBOT_ENV_FILE"
    log_to_file "Generated .env file with version $version"
}

# Download latest release from GitHub
download_latest_release() {
    log_info "Fetching latest QuickBot release from GitHub..." >&2
    
    local max_retries=3
    local retry_count=0
    local download_url=""
    local version=""
    
    while [[ $retry_count -lt $max_retries ]]; do
        # Get latest release info
        local release_info=$(curl -s --connect-timeout 30 "https://api.github.com/repos/$QUICKBOT_GITHUB_REPO/releases/latest" 2>&1)
        
        if [[ $? -eq 0 ]] && [[ ! "$release_info" =~ "Not Found" ]]; then
            version=$(echo "$release_info" | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/')
            
            # Try to get wheel file from assets first
            download_url=$(echo "$release_info" | grep 'browser_download_url' | grep '\.whl' | head -1 | cut -d'"' -f4)
            
            # If no wheel, try tarball from assets
            if [[ -z "$download_url" ]]; then
                download_url=$(echo "$release_info" | grep 'browser_download_url' | grep '\.tar\.gz' | head -1 | cut -d'"' -f4)
            fi
            
            # If still no download, use the automatic tarball_url
            if [[ -z "$download_url" ]]; then
                download_url=$(echo "$release_info" | grep '"tarball_url"' | head -1 | cut -d'"' -f4)
            fi
            
            if [[ -n "$download_url" ]] && [[ -n "$version" ]]; then
                break
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log_warn "Failed to fetch release info, retrying... ($retry_count/$max_retries)" >&2
            sleep 2
        fi
    done
    
    # If no release found, install directly from GitHub
    if [[ -z "$download_url" ]]; then
        log_warn "No release found, installing from main branch..." >&2
        echo "git+https://github.com/$QUICKBOT_GITHUB_REPO.git"
        log_to_file "No release found, will install from main branch"
        return 0
    fi
    
    log_info "Latest version: $version" >&2
    
    if ! confirm "Download QuickBot $version from GitHub?" "Y"; then
        log_error "Installation cancelled by user" >&2
        rollback_installation
        exit 1
    fi
    
    # Download the release
    local filename=$(basename "$download_url")
    # If using tarball_url (no extension), add .tar.gz
    if [[ ! "$filename" =~ \.(whl|tar\.gz|zip)$ ]]; then
        filename="quickbot-${version}.tar.gz"
    fi
    local download_path="/tmp/$filename"
    
    log_info "Downloading $filename..." >&2
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
    rollback_installation
    exit 1
}

# Install QuickBot via pipx
install_quickbot() {
    local package_path="$1"
    
    log_info "Installing QuickBot via pipx..."
    
    if ! confirm "Install to pipx? This will make 'quick' command available globally" "Y"; then
        log_error "Installation cancelled by user"
        rollback_installation
        exit 1
    fi
    
    # Install with pipx (handle both file paths and git URLs)
    log_info "Running pipx install..."
    if pipx install "$package_path" --force 2>&1 | tee -a "$QUICKBOT_LOG_DIR/install.log"; then
        log_success "QuickBot installed to pipx"
        log_to_file "Installed QuickBot via pipx"
    else
        log_error "Failed to install QuickBot via pipx"
        rollback_installation
        exit 1
    fi
    
    # Copy .env to pipx venv
    log_info "Copying .env to pipx environment..."
    local pipx_venv="$HOME/.local/pipx/venvs/quickbot"
    
    if [[ -d "$pipx_venv" ]]; then
        cp "$QUICKBOT_ENV_FILE" "$pipx_venv/.env"
        log_success ".env copied to pipx environment"
    else
        log_warn "pipx venv not found, .env copy skipped (QuickBot may still work)"
    fi
}

# Create symlinks
create_symlinks() {
    log_info "Creating command symlinks..."
    
    mkdir -p "$LOCAL_BIN"
    
    local pipx_bin="$HOME/.local/pipx/venvs/quickbot/bin"
    
    # Create symlink for 'quick'
    if [[ -f "$pipx_bin/quick" ]]; then
        ln -sf "$pipx_bin/quick" "$LOCAL_BIN/quick"
        log_success "Created symlink: $LOCAL_BIN/quick"
    else
        log_warn "quick binary not found in pipx venv"
    fi
    
    # Create symlink for 'qw'
    if [[ -f "$pipx_bin/qw" ]]; then
        ln -sf "$pipx_bin/qw" "$LOCAL_BIN/qw"
        log_success "Created symlink: $LOCAL_BIN/qw"
    else
        log_warn "qw binary not found in pipx venv (may not be available yet)"
    fi
}

# Add to PATH
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
            echo '# QuickBot - Added by installer' >> "$shell_config"
            echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$shell_config"
            log_success "PATH updated in $shell_config"
            log_warn "Please run: source $shell_config"
        else
            log_warn "Could not determine shell config file"
            log_warn "Please add $LOCAL_BIN to your PATH manually"
        fi
    else
        log_success "$LOCAL_BIN is already in PATH"
    fi
}

# Validate installation
validate_installation() {
    log_info "Validating installation..."
    
    # Source the shell config to get updated PATH
    if [[ "$SHELL" == *"zsh"* ]] && [[ -f "$HOME/.zshrc" ]]; then
        source "$HOME/.zshrc" 2>/dev/null || true
    elif [[ "$SHELL" == *"bash"* ]] && [[ -f "$HOME/.bashrc" ]]; then
        source "$HOME/.bashrc" 2>/dev/null || true
    fi
    
    # Check if quick command exists
    if command -v quick &> /dev/null; then
        log_info "Testing 'quick help' command..."
        if quick help &> /dev/null; then
            log_success "Installation validated successfully!"
            return 0
        else
            log_warn "'quick help' command failed, but installation may still work"
        fi
    else
        log_warn "'quick' command not found in PATH yet"
        log_warn "You may need to restart your shell or run: source ~/.zshrc"
    fi
}

# Rollback installation on failure
rollback_installation() {
    log_error "Installation failed, attempting rollback..."
    
    # Restore backup if it exists
    if [[ -f /tmp/quickbot_backup_path ]]; then
        local backup_path=$(cat /tmp/quickbot_backup_path)
        if [[ -d "$backup_path" ]]; then
            log_info "Restoring backup from $backup_path"
            rm -rf "$QUICKBOT_HOME"
            mv "$backup_path" "$QUICKBOT_HOME"
            log_success "Backup restored"
        fi
        rm -f /tmp/quickbot_backup_path
    fi
    
    log_to_file "Installation failed and rolled back"
}

# Main installation flow
main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║     QuickBot Installer v0.1.0d         ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo -e "${YELLOW}⚠  Development Beta — first public build of QuickBot.${NC}"
    echo -e "${YELLOW}   Things may break. Report issues at:${NC}"
    echo -e "${YELLOW}   https://github.com/levinismynameirl/Quick-Bot/issues${NC}"
    echo ""
    
    # Create temporary log directory
    mkdir -p /tmp/quickbot_logs
    
    log_info "Starting QuickBot installation..."
    log_to_file "Installation started"
    
    # System checks
    check_macos
    check_homebrew
    check_python
    check_pipx
    
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
    echo -e "${YELLOW}⚠  Development Beta (v0.1.0d) — first public build of QuickBot.${NC}"
    echo -e "${YELLOW}   Features may be incomplete. Config files may change between releases.${NC}"
    echo -e "${YELLOW}   Things may break. Please report issues at:${NC}"
    echo -e "${YELLOW}   https://github.com/$QUICKBOT_GITHUB_REPO/issues${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Restart your terminal or run: source ~/.zshrc"
    echo "  2. Type 'quick help' to get started"
    echo "  3. Visit https://github.com/$QUICKBOT_GITHUB_REPO for documentation"
    echo ""
    echo "Update QuickBot: quick update"
    echo "Uninstall: ~/.quickbot/uninstall.sh"
    echo ""
    
    log_to_file "Installation completed successfully"
    
    # Cleanup
    rm -f /tmp/quickbot_backup_path
}

# Run main installation
main "$@"
