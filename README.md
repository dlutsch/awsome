# AWsome: AWS Session Manager

AWsome is an elegant and powerful CLI tool for managing AWS credentials, profiles, and SSO sessions on macOS. It provides a modern terminal UI with a streamlined workflow for common AWS authentication tasks.

![AWS Session Manager](https://github.com/charmbracelet/gum/raw/main/examples/demo.gif)

## Features

- **Modern TUI** with [Charm's Gum library](https://github.com/charmbracelet/gum)
- **Quick Profile Switching** with fuzzy filtering for fast selection
- **SSO Login Management** with session validity checking
- **AWS Config Repopulation** to refresh available profiles
- **Interactive Menu Interface** with clear visual feedback
- **Command Line Shortcuts** for common operations
- **Confirmation Dialogs** and spinners for clear user feedback
- **Beautiful Styling** with consistent visual design
- **Configuration System** for easy customization without modifying the script

## Requirements

1. [aws-sso-util](https://github.com/benkehoe/aws-sso-util) - Utility for AWS SSO
2. [awsume](https://github.com/trek10inc/awsume) - A utility for using AWS IAM credentials
3. [gum](https://github.com/charmbracelet/gum) - A tool for glamorous shell scripts

## Installation

### Option 1: One-Line Installer (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/dlutsch/awsome/main/install.sh | bash
```

This will:
- Check for and install required dependencies (Homebrew, gum, awsume, aws-sso-util)
- Install AWsome to `~/.local/bin/awsome.sh`
- Set up aliases in your shell configuration
- Create an update mechanism

### Option 2: Manual Installation

#### 1. Install Prerequisites

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install gum
brew install gum

# Install aws-sso-util
pip3 install --user aws-sso-util

# Install awsume
pip3 install --user awsume
```

#### 2. Install AWsome

```bash
# Clone the repository
git clone https://github.com/dlutsch/awsome.git
cd awsome

# Make the script executable
chmod +x awsome.sh

# Move to a permanent location
mkdir -p ~/.local/bin
cp awsome.sh ~/.local/bin/awsome.sh
```

#### 3. Set Up Aliases

Add these lines to your `~/.zshrc` (or `~/.bashrc` if you're using bash):

```bash
# Main command - shows the menu
alias awsm="source ~/.local/bin/awsome.sh menu"

# Quick commands for common operations
alias awp="source ~/.local/bin/awsome.sh profile"  # Switch profiles
alias awl="source ~/.local/bin/awsome.sh login"    # Login to SSO
alias awr="source ~/.local/bin/awsome.sh repopulate" # Repopulate config
alias awc="source ~/.local/bin/awsome.sh config"   # Configure settings
```

*Important:* Reload your shell configuration after adding aliases:

```bash
source ~/.zshrc  # or ~/.bashrc if using bash
```

## Updating AWsome

There are multiple ways to update AWsome:

1. **From the menu**: Select "Update AWsome" from the main menu
2. **Using the command shortcut**: `awu` (if you set up the alias)
3. **Direct command**: `source ~/.local/bin/awsome.sh update` or `awsome-update`

Each method will pull the latest version from the repository and update your local installation.

## Usage

### Command Shortcuts

- `awsm` - Show the interactive menu
- `awp` - Switch AWS profiles
- `awl` - Login to AWS SSO
- `awr` - Repopulate AWS config with all available profiles
- `awc` - Configure AWsome settings
- `awu` - Update AWsome to the latest version

### Interactive Menu

1. Run `awsm` to start the AWS Session Manager menu
2. Choose from the available operations:
   - Switch AWS Profile
   - Login to AWS SSO
   - Repopulate AWS Config
   - Configure Settings
   - Update AWsome

### Direct Script Usage

```bash
# Show the menu
./awsome.sh

# Run with arguments
./awsome.sh profile     # or p - Switch profiles
./awsome.sh login       # or l - Login to SSO
./awsome.sh repopulate  # or r - Repopulate config
./awsome.sh config      # or c - Configure settings
./awsome.sh menu        # or m - Show menu
./awsome.sh help        # or h - Show help
```

## Configuration

AWsome will interactively prompt for configuration during installation and preserve settings across updates.

### Configuration options:

1. **AWS Region** - Used for both AWS operations and SSO (default: us-west-2)
2. **SSO Start URL** - Your organization's AWS SSO URL (e.g., https://mycompany.awsapps.com/start)

### How it works:

1. During installation, you'll be prompted to enter these values
2. The values are baked into your local AWsome installation
3. When updating, your existing configuration is automatically preserved

You can view your current configuration any time by running `awsm config` or selecting "View Configuration" from the menu.

## How It Works

1. **Profile Switching** - Uses the `awsume` command to assume AWS roles after an interactive profile selection
2. **SSO Login** - Manages AWS SSO session login and validation with feedback about current session status
3. **Config Repopulation** - Refreshes your AWS config file with all available profiles using `aws-sso-util`

## Notes

- The script must be **sourced** (not executed) to ensure AWS credentials are exported to your current shell
- When switching profiles, the script automatically checks if you're logged in to SSO
- Config repopulation can be followed by profile switching in a single workflow
- All operations provide clear visual feedback about their progress and status

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

[MIT License](LICENSE)
