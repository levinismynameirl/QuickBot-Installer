# QuickBot Installer

Official installation scripts for [QuickBot](https://github.com/levinismynameirl/Quick-Bot).

## Quick Start

### Method 1: One-Click Installer (Easiest)

1. Download the latest release from [GitHub Releases](https://github.com/levinismynameirl/QuickBot-Installers/releases)
2. Extract the zip file
3. **Double-click `QuickBot Installer.app`**
4. Follow the prompts in the terminal

The .app will automatically handle permissions and run the installer for you.

### Method 2: One-Line Command

```bash
curl -fsSL https://raw.githubusercontent.com/levinismynameirl/QuickBot-Installers/main/install.sh | bash
```

### Method 3: Manual Installation

```bash
# Download the installer
curl -fL https://github.com/levinismynameirl/QuickBot-Installers/archive/main.zip -o quickbot-installer.zip

# Extract
unzip quickbot-installer.zip

# Navigate to the directory
cd quickbot-installers-main

# Make the installer executable and run it
chmod +x install.sh && ./install.sh
```

### Method 4: Homebrew (Coming Soon)

```bash
brew tap levinismynameirl/quickbot
brew install quickbot
```

## What Gets Installed

- **Scripts**: `~/.quickbotScripts/quickbot/scripts/`
  - Installer, updater, and uninstaller scripts
- **Configuration**: `~/.config/.quickbot/quickbot/data/.config/configFiles/`
  - Config files created by QuickBot CLI
- **Python Environment**: `~/.local/pipx/venvs/quickbot/`
  - Isolated Python environment managed by pipx
- **Commands**: `~/.local/bin/quick` and `~/.local/bin/qw`
  - Global command-line tools

## Available Scripts

### install.sh
Initial installation from bootstrap repository. Handles dependency checks, directory setup, and QuickBot installation via pipx.

### updater.sh
Updates QuickBot to the latest version while preserving your configuration files.

```bash
~/.quickbot/quickbot/scripts/updater.sh
# or
quick update
```

**Flags:**
- `--force`: Skip version check, update immediately
- `--update-scripts`: Update installer/updater/uninstall scripts
- `--yes`: Skip all confirmations

### uninstall.sh
Completely removes QuickBot from your system.

```bash
~/.quickbot/quickbot/scripts/uninstall.sh
```

**Flags:**
- `--force`: Skip confirmations, delete everything
- `--keep-config`: Don't delete config files
- `--yes`: Skip all prompts

### brewinstall.sh
Non-interactive installer for Homebrew tap installation. Called automatically by Homebrew.

## Requirements

- macOS (Intel or Apple Silicon)
- Python 3.11 or higher
- Homebrew (will be installed if missing)
- pipx (will be installed if missing)
- Internet connection

## Directory Structure

After installation:

```
~/.quickbotScripts/
└── quickbot/
    ├── .env
    └── scripts/
        ├── updater.sh
        ├── uninstall.sh
        └── unused/
            ├── install.sh
            ├── brewinstall.sh
            └── QuickBot Installer.app

~/.config/.quickbot/
└── quickbot/
    └── data/
        └── .config/
            └── configFiles/
                ├── config.json
                ├── plugins.json
                ├── aliases.yaml
                └── workflows.json

~/.local/pipx/venvs/quickbot/
└── [Python virtual environment with QuickBot installed]
```

## Troubleshooting

### Installation Failed

If installation fails, the installer will attempt to rollback any changes. You can try running the installer again:

```bash
./install.sh
```

### Command Not Found

If `quick` command is not found after installation, ensure `~/.local/bin` is in your PATH:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### Update Issues

If updates fail, you can force reinstall:

```bash
~/.quickbot/quickbot/scripts/updater.sh --force
```

Or reinstall from scratch:

```bash
~/.quickbot/quickbot/scripts/uninstall.sh
./install.sh
```

## Contributing

Issues and pull requests welcome at:

- Installer: https://github.com/levinismynameirl/QuickBot-Installers

- QuickBot: https://github.com/levinismynameirl/Quick-Bot

## License

MIT License - see QuickBot repository for details
