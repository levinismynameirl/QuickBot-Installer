# QuickBot Installer

Official installation scripts for [QuickBot](https://github.com/levinismynameirl/Quick-Bot).

## Quick Start

### One-Line Installation

**Just paste this into Terminal and press Enter:**

```bash
curl -fsSL https://raw.githubusercontent.com/levinismynameirl/QuickBot-Installer/main/install.sh | bash
```

That's it! No downloads, no files, no extra steps. The command automatically:
- Downloads the installer from GitHub
- Checks and installs dependencies (Homebrew, Python, pipx)
- Installs QuickBot via pipx
- Sets up the `quick` command globally

✨ **No GitHub download, no cd, no chmod - just one command.**

### Alternative: Download and Run

If you prefer to review the script first:

```bash
# Download the installer
curl -fL https://github.com/levinismynameirl/QuickBot-Installer/archive/main.zip -o quickbot-installer.zip

# Extract
unzip quickbot-installer.zip

# Navigate to the directory
cd quickbot-installer-main

# Make executable and run
chmod +x install.sh && ./install.sh
```

### Homebrew (Coming Soon)

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
