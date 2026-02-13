# QuickBot Installer

Official installation scripts for [QuickBot](https://github.com/levinismynameirl/Quick-Bot).

> **⚠️ Development Build (v0.1.0.dev0)**
> This is the first public release of QuickBot. This version is a **development beta** — features may be incomplete, config formats may change between releases, and things may break. Please [report issues](https://github.com/levinismynameirl/QuickBot-Installer/issues) if you run into problems.

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

  (if you get permissions errors then reopen the terminal with admin privileges)

**No GitHub download, no cd, no chmod - just one command.**

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

### Homebrew

```bash
brew tap levinismynameirl/quickbot
brew install quickbot
```

## What Gets Installed

- **Scripts**: `~/.quickbot/`
  - Updater, uninstaller, and update-installer scripts
- **Configuration**: `~/.config/.quickbot/data/`
  - Config files, logs, plugins, recipes, and cache
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
~/.quickbot/updater.sh
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
~/.quickbot/uninstall.sh
```

**Flags:**
- `--force`: Skip confirmations, delete everything
- `--keep-config`: Don't delete config files
- `--yes`: Skip all prompts

### brewinstall.sh
Non-interactive installer for Homebrew tap installation. Called automatically by Homebrew.

### update-installer.sh
Updates the installer scripts themselves (install.sh, updater.sh, uninstall.sh, etc.) to the latest versions from GitHub.

```bash
~/.quickbot/update-installer.sh
```

**Flags:**
- `--force`: Re-download all scripts even if up to date
- `--yes`: Skip all confirmations
- `--dry-run`: Check for updates without applying them

## Requirements

- macOS (Intel or Apple Silicon)
- Python 3.11 or higher
- Homebrew (will be installed if missing)
- pipx (will be installed if missing)
- Internet connection

## Directory Structure

After installation:

```
~/.quickbot/
├── .env                            # Environment variables
├── updater.sh                      # Self-updater
├── uninstall.sh                    # Uninstaller
├── update-installer.sh             # Script updater
├── install.sh                      # Original installer (backup)
└── brewinstall.sh                  # Homebrew installer (backup)

~/.config/.quickbot/data/
├── .config/
│   ├── config.json                 # Settings, aliases, workflows
│   ├── plugins.json                # Installed plugins registry
│   └── aliases.yaml                # Custom command aliases
├── logs/                           # Audit logs (JSONL)
├── cache/                          # Downloaded archives
├── plugins/                        # Installed plugins (each with own venv)
└── recipes/                        # Cloned recipe registry

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
~/.quickbot/updater.sh --force
```

Or reinstall from scratch:

```bash
~/.quickbot/uninstall.sh
./install.sh
```

## Disclaimer

QuickBot v0.1.0.dev0 is a **development beta** — the first public build. Installation scripts have been tested on macOS (Intel and Apple Silicon), but edge cases may exist. Config file formats may change between development releases. Back up `~/.config/.quickbot/data/` before running updates.

## Contributing

Issues and pull requests welcome at:

- Installer: https://github.com/levinismynameirl/QuickBot-Installer

- QuickBot: https://github.com/levinismynameirl/Quick-Bot

## License

MIT License - see [LICENSE](LICENSE) for details.
