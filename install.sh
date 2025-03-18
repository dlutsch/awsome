#!/bin/bash

# AWsome Installer Script
# This script downloads and installs AWsome for macOS

set -e # Exit on error

# Default configuration values
AWS_REGION="us-west-2"  # Default AWS region for both default and SSO
SSO_START_URL=""        # No default SSO URL

INSTALL_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/awsome"
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
        colorize "red" "Error: git is not installed. Please install git and try again."
        colorize "yellow" "Tip: You can install git using Homebrew: brew install git"
        exit 1
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
        # Install awsume if needed
        if ! command -v awsume &> /dev/null; then
            colorize "blue" "Installing awsume..."
            $PIP_CMD install --user awsume
            # Add pip user bin to PATH for this session
            export PATH="$HOME/Library/Python/$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')/bin:$PATH"
        else
            colorize "green" "✓ awsume is already installed"
        fi
        
        # Install aws-sso-util if needed
        if ! command -v aws-sso-util &> /dev/null; then
            colorize "blue" "Installing aws-sso-util..."
            $PIP_CMD install --user aws-sso-util
            # Path already updated above
        else
            colorize "green" "✓ aws-sso-util is already installed"
        fi
    else
        colorize "yellow" "Python package manager not found. Please install awsume and aws-sso-util manually."
    fi
}

# Create directories if they don't exist
setup_directories() {
    colorize "blue" "Setting up directories..."
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
}

# Clone or update the repository
download_awsome() {
    colorize "blue" "Downloading AWsome..."
    
    # If we're running from the awsome directory, use local files
    if [ -f "./$SCRIPT_NAME" ]; then
        colorize "green" "Using local AWsome files"
        # Create config dir and copy files there
        mkdir -p "$CONFIG_DIR"
        cp -r ./* "$CONFIG_DIR/"
        # Initialize git repo if it doesn't exist
        if [ ! -d "$CONFIG_DIR/.git" ]; then
            colorize "blue" "Initializing git repository..."
            cd "$CONFIG_DIR"
            git init
            git add .
            git commit -m "Initial commit"
            # Set the remote for future updates
            git remote add origin "$REPO_URL"
        fi
    elif [ -d "$CONFIG_DIR/.git" ]; then
        # Repository exists, update it
        cd "$CONFIG_DIR"
        git pull origin main || {
            colorize "yellow" "Git pull failed, continuing with existing files"
        }
    else
        # Clone the repository
        git clone "$REPO_URL" "$CONFIG_DIR" || {
            colorize "red" "Git clone failed. Creating empty repository."
            mkdir -p "$CONFIG_DIR"
            cd "$CONFIG_DIR"
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
    
    # Prompt for AWS Region
    gum style --foreground 4 "Please enter your preferred AWS Region"
    gum style --foreground 7 "(This will be used for both AWS operations and SSO)"
    AWS_REGION=$(gum input --placeholder "$AWS_REGION" --value "$AWS_REGION")
    # Use the default if user entered nothing
    AWS_REGION=${AWS_REGION:-"us-west-2"}
    
    # Prompt for AWS SSO Start URL
    echo ""
    gum style --foreground 4 "Please enter your AWS SSO Start URL" 
    gum style --foreground 7 "(e.g., https://mycompany.awsapps.com/start)"
    SSO_START_URL=$(gum input --placeholder "https://example.awsapps.com/start" --value "$SSO_START_URL")
    
    # Display confirmation
    echo ""
    gum style --foreground 2 --bold "Configuration confirmed:"
    gum style --foreground 6 "  AWS Region: $AWS_REGION"
    gum style --foreground 6 "  SSO Start URL: ${SSO_START_URL:-"<None>"}"
    echo ""
}

# Install the script and inject configuration
install_script() {
    colorize "blue" "Installing AWsome..."
    
    # Check if the main script exists in the expected location
    local script_path=""
    if [ -f "$CONFIG_DIR/$SCRIPT_NAME" ]; then
        script_path="$CONFIG_DIR/$SCRIPT_NAME"
    elif [ -f "./$SCRIPT_NAME" ]; then
        # If not found in config dir but exists in current dir, use that
        colorize "yellow" "Using script from current directory."
        script_path="./$SCRIPT_NAME"
    else
        colorize "red" "Could not find $SCRIPT_NAME in any expected location."
        colorize "red" "Installation failed."
        exit 1
    fi
    
    # Create a temporary file with modifications
    local temp_file=$(mktemp)
    
    # Replace configuration values in the script
    sed -e "s|DEFAULT_REGION=\".*\"|DEFAULT_REGION=\"$AWS_REGION\"|" \
        -e "s|SSO_REGION=\".*\"|SSO_REGION=\"$AWS_REGION\"|" \
        -e "s|SSO_START_URL=\".*\"|SSO_START_URL=\"$SSO_START_URL\"|" \
        "$script_path" > "$temp_file"
    
    # Copy the modified script to the install directory
    cp "$temp_file" "$INSTALL_DIR/$SCRIPT_NAME"
    
    # Clean up temporary file
    rm "$temp_file"
    
    # Make it executable
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    
    # Create update script in the install directory that preserves configuration
    cat > "$INSTALL_DIR/awsome-update" <<EOL
#!/bin/bash
# Extract current configuration values before updating
CURRENT_INSTALL="$INSTALL_DIR/$SCRIPT_NAME"
if [ -f "\$CURRENT_INSTALL" ]; then
    # Extract current configuration values
    CURRENT_AWS_REGION=\$(grep "^DEFAULT_REGION=" "\$CURRENT_INSTALL" | cut -d'"' -f2)
    CURRENT_SSO_START_URL=\$(grep "^SSO_START_URL=" "\$CURRENT_INSTALL" | cut -d'"' -f2)
    
    # Ensure we're using the same region for both
    if [ -z "\$CURRENT_AWS_REGION" ]; then
        CURRENT_AWS_REGION=\$(grep "^SSO_REGION=" "\$CURRENT_INSTALL" | cut -d'"' -f2)
    fi
else
    # Use defaults if not found
    CURRENT_AWS_REGION="${AWS_REGION}"
    CURRENT_SSO_START_URL="${SSO_START_URL}"
fi

echo "Using configuration from existing installation:"
echo "  AWS Region: \$CURRENT_AWS_REGION"
echo "  SSO Start URL: \$CURRENT_SSO_START_URL"

# Update from repository
cd "$CONFIG_DIR"
git pull origin main

# Create a temporary file with modifications
TEMP_FILE=\$(mktemp)
    
# Replace configuration values in the script
sed -e "s|DEFAULT_REGION=\".*\"|DEFAULT_REGION=\"\$CURRENT_AWS_REGION\"|" \\
    -e "s|SSO_REGION=\".*\"|SSO_REGION=\"\$CURRENT_AWS_REGION\"|" \\
    -e "s|SSO_START_URL=\".*\"|SSO_START_URL=\"\$CURRENT_SSO_START_URL\"|" \\
    "$CONFIG_DIR/$SCRIPT_NAME" > "\$TEMP_FILE"

# Copy the modified script to the install directory
cp "\$TEMP_FILE" "$INSTALL_DIR/$SCRIPT_NAME"

# Clean up temporary file
rm "\$TEMP_FILE"

chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
echo "AWsome has been updated to the latest version with your customized configuration."
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
