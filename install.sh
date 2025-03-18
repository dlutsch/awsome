#!/bin/bash

# AWsome Installer Script
# This script downloads and installs AWsome for macOS
#
# MIT License
# Copyright (c) 2025 dlutsch
# See LICENSE file for full license text

set -e # Exit on error

# Default configuration values
AWS_REGION="us-west-2"  # Default AWS region for both default and SSO
SSO_START_URL=""        # No default SSO URL

INSTALL_DIR="$HOME/.local/bin"
REPO_DIR="$HOME/.local/share/awsome"  # Repository/code files directory
AWSOME_CONFIG_DIR="$HOME/.config/awsome"  # User configuration directory
AWSOME_CONFIG_FILE="$AWSOME_CONFIG_DIR/config"
REPO_URL="https://github.com/dlutsch/awsome"
SCRIPT_NAME="awsome.sh"

# Function to display colored output
colorize() {
    local color=$1
    local text=$2
    
    case $color in
        "green") echo -e "\033[0;32m$text\033[0m" ;;
        "yellow") echo -e "\033[0;33m$text\033[0m" ;;
        "red") echo -e "\033[0;31m$text\033[0m" ;;
        "blue") echo -e "\033[0;34m$text\033[0m" ;;
        *) echo "$text" ;;
    esac
}

# Check and install required dependencies
check_requirements() {
    colorize "blue" "Checking and installing requirements..."
    
    # Check git
    if ! command -v git &> /dev/null; then
        colorize "yellow" "Git is not installed. Git is required for update functionality."
        
        # Ask if user wants to install git
        read -p "Would you like to install git now? (y/n): " install_git
        if [[ $install_git == "y" || $install_git == "Y" ]]; then
            if command -v brew &> /dev/null; then
                colorize "blue" "Installing git using Homebrew..."
                brew install git
                if ! command -v git &> /dev/null; then
                    colorize "red" "Git installation failed. Please install git manually."
                    colorize "yellow" "Continuing installation without git. Update functionality will be limited."
                fi
            else
                colorize "yellow" "Homebrew is not installed. Cannot install git automatically."
                colorize "yellow" "Continuing installation without git. Update functionality will be limited."
            fi
        else
            colorize "yellow" "Continuing without git. Update functionality will be limited."
        fi
    fi
    
    # Check and install Homebrew if needed
    if ! command -v brew &> /dev/null; then
        colorize "yellow" "Homebrew is not installed. We recommend installing it for package management."
        colorize "yellow" "Visit https://brew.sh to install Homebrew"
        
        # Ask if user wants to install Homebrew
        read -p "Would you like to install Homebrew now? (y/n): " install_brew
        if [[ $install_brew == "y" || $install_brew == "Y" ]]; then
            colorize "blue" "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            
            # Add Homebrew to PATH for the current session
            if [[ -f /opt/homebrew/bin/brew ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [[ -f /usr/local/bin/brew ]]; then
                eval "$(/usr/local/bin/brew shellenv)"
            else
                colorize "red" "Homebrew installation appears to have failed. Please install it manually."
                exit 1
            fi
        else
            colorize "yellow" "Continuing without Homebrew. Some dependencies may need to be installed manually."
        fi
    fi
    
    # Install gum using Homebrew if available
    if command -v brew &> /dev/null; then
        if ! command -v gum &> /dev/null; then
            colorize "blue" "Installing gum using Homebrew..."
            brew install gum
        else
            colorize "green" "✓ gum is already installed"
        fi
    else
        if ! command -v gum &> /dev/null; then
            colorize "red" "gum is not installed and Homebrew is not available. Please install gum manually."
            colorize "yellow" "Visit https://github.com/charmbracelet/gum#installation for installation instructions."
        fi
    fi
    
    # Check for pip/pip3
    PIP_CMD=""
    if command -v pip3 &> /dev/null; then
        PIP_CMD="pip3"
    elif command -v pip &> /dev/null; then
        PIP_CMD="pip"
    else
        colorize "yellow" "pip is not installed. We'll try to install it using easy_install..."
        if command -v easy_install &> /dev/null; then
            sudo easy_install pip
            PIP_CMD="pip"
        else
            colorize "red" "Could not install pip. Please install pip manually."
        fi
    fi
    
    # Install Python packages if pip is available
    if [ -n "$PIP_CMD" ]; then
        # Determine Python user bin path
        PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
        PYTHON_USER_BIN="$HOME/Library/Python/$PYTHON_VERSION/bin"
        
        # Install awsume if needed
        if ! command -v awsume &> /dev/null; then
            colorize "blue" "Installing awsume..."
            $PIP_CMD install --user awsume
            
            # Add pip user bin to PATH for this session
            export PATH="$PYTHON_USER_BIN:$PATH"
        else
            colorize "green" "✓ awsume is already installed"
        fi
        
        # Install aws-sso-util if needed
        if ! command -v aws-sso-util &> /dev/null; then
            colorize "blue" "Installing aws-sso-util..."
            $PIP_CMD install --user aws-sso-util
            
            # Add pip user bin to PATH for this session if not done already
            export PATH="$PYTHON_USER_BIN:$PATH"
        else
            colorize "green" "✓ aws-sso-util is already installed"
        fi
        
        # Ensure PATH is properly set for future sessions
        colorize "blue" "Ensuring Python packages are in PATH..."
        
        # Detect the user's shell by checking the SHELL environment variable
        USER_SHELL=$(basename "$SHELL")
        
        # Determine the appropriate RC file based on the detected shell
        if [ "$USER_SHELL" = "zsh" ]; then
            SHELL_RC="$HOME/.zshrc"
        elif [ "$USER_SHELL" = "bash" ]; then
            SHELL_RC="$HOME/.bashrc"
        else
            # Default to zsh on macOS
            SHELL_RC="$HOME/.zshrc"
        fi
        
        # Add Python user bin to PATH in shell config if not already there
        if ! grep -q "PATH.*$PYTHON_USER_BIN" "$SHELL_RC"; then
            colorize "blue" "Adding Python user bin to PATH in $SHELL_RC"
            echo "" >> "$SHELL_RC"
            echo "# Python user bin path (added by AWsome installer)" >> "$SHELL_RC"
            echo "export PATH=\"$PYTHON_USER_BIN:\$PATH\"" >> "$SHELL_RC"
            
            colorize "yellow" "PATH has been updated. Please restart your terminal or run:"
            colorize "yellow" "source $SHELL_RC"
        fi
    else
        colorize "yellow" "Python package manager not found. Please install awsume and aws-sso-util manually."
    fi
}

# Create directories if they don't exist
setup_directories() {
    colorize "blue" "Setting up directories..."
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$REPO_DIR"
    mkdir -p "$AWSOME_CONFIG_DIR"
}

# Clone or update the repository
download_awsome() {
    colorize "blue" "Downloading AWsome..."
    
    # If we're running from the awsome directory, use local files
    if [ -f "./$SCRIPT_NAME" ]; then
        colorize "green" "Using local AWsome files"
        # Create repo dir and copy files there
        mkdir -p "$REPO_DIR"
        cp -r ./* "$REPO_DIR/"
        # Initialize git repo if it doesn't exist
        if [ ! -d "$REPO_DIR/.git" ]; then
            colorize "blue" "Initializing git repository..."
            cd "$REPO_DIR"
            git init
            git add .
            git commit -m "Initial commit"
            # Set the remote for future updates
            git remote add origin "$REPO_URL"
        fi
    elif [ -d "$REPO_DIR/.git" ]; then
        # Repository exists, update it
        cd "$REPO_DIR"
        # Check for local modifications before pulling
        if [ -n "$(git status --porcelain)" ]; then
            colorize "yellow" "Local modifications detected in $REPO_DIR"
            # Backup local changes
            BACKUP_DIR="$REPO_DIR.backup.$(date +%Y%m%d%H%M%S)"
            colorize "blue" "Creating backup of local files at $BACKUP_DIR"
            cp -r "$REPO_DIR" "$BACKUP_DIR"
            
            # Try to stash changes - for tracked files
            if git diff --quiet HEAD; then
                # No changes to tracked files
                colorize "blue" "No changes to tracked files"
            else
                colorize "blue" "Stashing tracked changes before pull"
                git stash || colorize "yellow" "Could not stash changes"
            fi
            
            # Handle untracked files that would be overwritten by pull
            UNTRACKED_FILES=$(git ls-files --others --exclude-standard)
            if [ -n "$UNTRACKED_FILES" ]; then
                colorize "blue" "Moving untracked files temporarily"
                mkdir -p "$REPO_DIR/.untracked_backup"
                for file in $UNTRACKED_FILES; do
                    mv "$file" "$REPO_DIR/.untracked_backup/" 2>/dev/null || true
                done
            fi
        fi
        
        # Now pull from remote
        git pull origin main || {
            colorize "yellow" "Git pull failed, continuing with existing files"
        }
        
        # Restore stashed changes if any
        git stash list | grep -q 'stash@{0}' && {
            colorize "blue" "Restoring stashed changes"
            git stash pop || colorize "yellow" "Could not restore stashed changes"
        }
        
        # Restore untracked files if any
        if [ -d "$REPO_DIR/.untracked_backup" ] && [ -n "$(ls -A "$REPO_DIR/.untracked_backup" 2>/dev/null)" ]; then
            colorize "blue" "Restoring untracked files"
            cp -r "$REPO_DIR/.untracked_backup/"* "$REPO_DIR/" 2>/dev/null || true
            rm -rf "$REPO_DIR/.untracked_backup" 2>/dev/null || true
        fi
    else
        # Clone the repository 
        git clone "$REPO_URL" "$REPO_DIR" || {
            colorize "red" "Git clone failed. Creating empty repository."
            mkdir -p "$REPO_DIR"
            cd "$REPO_DIR"
            # If clone fails, create a basic repo with the current script
            git init
            if [ -f "../$SCRIPT_NAME" ]; then
                cp "../$SCRIPT_NAME" .
            elif [ -f "../../$SCRIPT_NAME" ]; then
                cp "../../$SCRIPT_NAME" .
            fi
            git add .
            git commit -m "Initial commit"
            # Set the remote for future updates
            git remote add origin "$REPO_URL"
        }
    fi
}

# Prompt for configuration values
get_configuration() {
    colorize "blue" "Configuring AWsome..."
    
    echo ""
    gum style --foreground 6 --bold "AWS Configuration"
    echo ""
    
    # Prompt for Default AWS Region
    gum style --foreground 4 "Please enter your preferred Default AWS Region"
    gum style --foreground 7 "(Used for standard AWS CLI operations)"
    DEFAULT_AWS_REGION=$(gum input --placeholder "us-west-2" --value "$DEFAULT_AWS_REGION")
    # Use the default if user entered nothing
    DEFAULT_AWS_REGION=${DEFAULT_AWS_REGION:-"us-west-2"}
    
    # Prompt for SSO AWS Region
    echo ""
    gum style --foreground 4 "Please enter your AWS SSO Region"
    gum style --foreground 7 "(Used for SSO login operations, often the same as default region)"
    SSO_AWS_REGION=$(gum input --placeholder "$DEFAULT_AWS_REGION" --value "$SSO_AWS_REGION")
    # Use the default region if user entered nothing
    SSO_AWS_REGION=${SSO_AWS_REGION:-"$DEFAULT_AWS_REGION"}
    
    # Prompt for AWS SSO Start URL (required)
    echo ""
    gum style --foreground 4 "Please enter your AWS SSO Start URL (REQUIRED)" 
    gum style --foreground 7 "(e.g., https://mycompany.awsapps.com/start)"
    
    # Keep prompting until a non-empty value is provided
    while [ -z "$SSO_START_URL" ]; do
        SSO_START_URL=$(gum input --placeholder "https://example.awsapps.com/start" --value "$SSO_START_URL")
        
        if [ -z "$SSO_START_URL" ]; then
            gum style --foreground 1 "SSO Start URL is required. Please enter a valid URL."
        fi
    done
    
    # Display confirmation
    echo ""
    gum style --foreground 2 --bold "Configuration confirmed:"
    gum style --foreground 6 "  Default AWS Region: $DEFAULT_AWS_REGION"
    gum style --foreground 6 "  SSO AWS Region: $SSO_AWS_REGION"
    gum style --foreground 6 "  SSO Start URL: $SSO_START_URL"
    echo ""
    
    # Save the configuration to the config file
    colorize "blue" "Saving configuration to $AWSOME_CONFIG_FILE..."
    mkdir -p "$AWSOME_CONFIG_DIR"
    cat > "$AWSOME_CONFIG_FILE" <<EOL
# AWsome Configuration
# Generated on $(date)

# AWS Default Region (used for standard AWS CLI operations)
DEFAULT_AWS_REGION="$DEFAULT_AWS_REGION"

# AWS SSO Region (used for SSO login)
SSO_AWS_REGION="$SSO_AWS_REGION"

# AWS SSO Start URL (REQUIRED)
SSO_START_URL="$SSO_START_URL"
EOL
}

# Install the script and inject configuration
install_script() {
    colorize "blue" "Installing AWsome..."
    
    # Check if the main script exists in the expected location
    local script_path=""
    if [ -f "$REPO_DIR/$SCRIPT_NAME" ]; then
        script_path="$REPO_DIR/$SCRIPT_NAME"
    elif [ -f "./$SCRIPT_NAME" ]; then
        # If not found in repo dir but exists in current dir, use that
        colorize "yellow" "Using script from current directory."
        script_path="./$SCRIPT_NAME"
    else
        colorize "red" "Could not find $SCRIPT_NAME in any expected location."
        colorize "red" "Installation failed."
        exit 1
    fi
    
    # Copy the script to the install directory without modification
    # (it will now read from config file)
    cp "$script_path" "$INSTALL_DIR/$SCRIPT_NAME"
    
    # Make it executable
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    
    # Create update script in the install directory that preserves configuration
    cat > "$INSTALL_DIR/awsome-update" <<EOL
#!/bin/bash
# Check for existing configuration
AWSOME_CONFIG_DIR="$AWSOME_CONFIG_DIR"
AWSOME_CONFIG_FILE="$AWSOME_CONFIG_FILE"

# Update from repository
cd "$REPO_DIR"
git pull origin main > /dev/null 2>&1 || {
    echo "Git pull failed, continuing with existing files"
}

# Copy the script to the install directory
cp "$REPO_DIR/$SCRIPT_NAME" "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

echo "AWsome has been updated to the latest version."
echo "Your configuration at \$AWSOME_CONFIG_FILE is preserved."
EOL
    
    # Make update script executable
    chmod +x "$INSTALL_DIR/awsome-update"
}

# Setup shell aliases
setup_aliases() {
    colorize "blue" "Setting up shell aliases..."
    
    # Detect the user's shell by checking the SHELL environment variable
    USER_SHELL=$(basename "$SHELL")
    
    # Determine the appropriate RC file based on the detected shell
    if [ "$USER_SHELL" = "zsh" ]; then
        SHELL_RC="$HOME/.zshrc"
        colorize "green" "Detected zsh shell, using $SHELL_RC"
    elif [ "$USER_SHELL" = "bash" ]; then
        SHELL_RC="$HOME/.bashrc"
        colorize "green" "Detected bash shell, using $SHELL_RC"
    else
        # Default to zsh on macOS if we can't determine the shell
        colorize "yellow" "Could not confidently detect shell type, defaulting to zsh."
        SHELL_RC="$HOME/.zshrc"
    fi
    
    # Check if aliases already exist in the shell config
    if grep -q "alias awsm=" "$SHELL_RC"; then
        colorize "yellow" "AWsome aliases already exist in $SHELL_RC. Skipping alias setup."
    else
        colorize "green" "Adding aliases to $SHELL_RC"
        cat >> "$SHELL_RC" <<EOL

# AWsome aliases
alias awsm="source $INSTALL_DIR/$SCRIPT_NAME menu"
alias awp="source $INSTALL_DIR/$SCRIPT_NAME profile"
alias awl="source $INSTALL_DIR/$SCRIPT_NAME login"
alias awr="source $INSTALL_DIR/$SCRIPT_NAME repopulate"
alias awu="source $INSTALL_DIR/$SCRIPT_NAME update"
EOL
    fi
}

# Main installation process
main() {
    colorize "green" "Starting AWsome installation for macOS..."
    check_requirements
    setup_directories
    download_awsome
    get_configuration
    install_script
    setup_aliases
    
    colorize "green" "AWsome installation complete!"
    colorize "green" "To update AWsome in the future, run: awsome-update"
    colorize "yellow" "Please restart your terminal or run 'source $SHELL_RC' to use the aliases."
}

# Execute main function
main
